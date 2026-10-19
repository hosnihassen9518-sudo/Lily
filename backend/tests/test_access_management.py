from datetime import datetime, timedelta, timezone
import pytest
from fastapi import HTTPException
from sqlalchemy import select
from app.models.user import User
from app.models.access_control import (
    Role,
    GrantCeiling,
    ApiCredential,
    AccessSession,
    AuditEvent,
)
from app.services.rbac import (
    seed_access_control,
    assign_roles,
    effective_permissions,
    authorize_grant,
    lock_security,
    protect_last_superuser,
)
from app.services.access_sessions import issue_session, validate_session


def identity(db, key, permissions):
    seed_access_control(db)
    db.add(Role(key=key, name=key, permissions=permissions, audience="portal"))
    user = User(email=key + "@test.org", password_hash="unused")
    db.add(user)
    db.flush()
    assign_roles(db, user.id, [key])
    db.commit()
    return user, {"Authorization": "Bearer " + issue_session(db, user)["access_token"]}


def test_delegated_api_roles_require_independent_permission(client, db):
    user, headers = identity(db, "role_editor", ["roles.create"])
    response = client.post(
        "/api/v1/access/api-roles",
        headers=headers,
        json={
            "key": "integration",
            "name": "Integration",
            "permissions": ["devices.read"],
        },
    )
    assert response.status_code == 403
    assert (
        client.post(
            "/api/v1/access/roles",
            headers=headers,
            json={
                "key": "elevated",
                "name": "Elevated",
                "permissions": ["devices.control"],
            },
        ).status_code
        == 403
    )


def test_custom_role_edit_revokes_assigned_sessions(client, db, admin):
    user, headers = identity(db, "limited_editor", ["devices.read"])
    response = client.patch(
        "/api/v1/access/roles/limited_editor",
        headers=admin,
        json={"name": "Limited", "permissions": ["devices.read", "devices.control"]},
    )
    assert response.status_code == 200
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401


def test_predefined_roles_are_immutable_over_api(client, admin):
    assert (
        client.patch(
            "/api/v1/access/roles/read_only",
            headers=admin,
            json={"name": "Changed", "permissions": []},
        ).status_code
        == 409
    )
    assert (
        client.delete("/api/v1/access/roles/read_only", headers=admin).status_code
        == 409
    )


def test_delegation_ceiling_prevents_self_escalation(client, db):
    user, headers = identity(db, "delegated", ["roles.create", "devices.read"])
    db.add(GrantCeiling(user_id=user.id, permissions=["devices.read"]))
    db.commit()
    assert (
        client.post(
            "/api/v1/access/roles",
            headers=headers,
            json={
                "key": "safe_reader",
                "name": "Safe",
                "permissions": ["devices.read"],
            },
        ).status_code
        == 200
    )
    assert (
        client.post(
            "/api/v1/access/roles",
            headers=headers,
            json={
                "key": "bad_writer",
                "name": "Bad",
                "permissions": ["devices.control"],
            },
        ).status_code
        == 403
    )


def test_last_superuser_cannot_be_disabled_or_demoted(client, db, admin):
    from app.core.security import decode_token

    actor_id = int(decode_token(admin["Authorization"].split()[1])["sub"])
    assert (
        client.patch(
            f"/api/v1/access/users/{actor_id}/active",
            headers=admin,
            json={"active": False},
        ).status_code
        == 409
    )
    assert (
        client.put(
            f"/api/v1/access/users/{actor_id}/roles",
            headers=admin,
            json={"roles": ["read_only"]},
        ).status_code
        == 409
    )


def test_session_revocation_and_target_protection(client, db, admin):
    user, headers = identity(db, "restricted", ["sessions.read", "sessions.revoke"])
    assert (
        client.get("/api/v1/access/sessions?user_id=1", headers=headers).status_code
        == 403
    )
    own = client.get("/api/v1/access/sessions", headers=headers).json()
    assert len(own) == 1
    assert (
        client.delete(
            "/api/v1/access/sessions/" + own[0]["id"], headers=headers
        ).status_code
        == 200
    )
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401


def test_secret_csv_export_requires_separate_permission(client, db):
    user, headers = identity(db, "exporter", ["devices.export"])
    assert (
        client.get(
            "/api/v1/admin/devices/export.csv?fields=id", headers=headers
        ).status_code
        == 200
    )
    assert (
        client.get(
            "/api/v1/admin/devices/export.csv?fields=id,device_secret", headers=headers
        ).status_code
        == 403
    )


def test_snapshot_does_not_rebuild_role_grants(db, monkeypatch):
    user, headers = identity(db, "snapshot_reader", ["devices.read"])

    def forbidden(*a, **k):
        raise AssertionError("Roles reconstructed during request")

    monkeypatch.setattr("app.services.access_sessions.effective_permissions", forbidden)
    assert validate_session(db, headers["Authorization"].split()[1]).permissions == {
        "devices.read"
    }


def test_denied_mutation_is_audited_without_secrets(client, db):
    user, headers = identity(db, "audited_reader", ["devices.read"])
    response = client.post(
        "/api/v1/access/api-roles",
        headers=headers,
        json={"key": "secretvalue", "name": "secretvalue", "permissions": []},
    )
    assert response.status_code == 403
    events = list(db.scalars(select(AuditEvent).where(AuditEvent.actor_id == user.id)))
    assert events and events[-1].result == "denied"
    assert "secretvalue" not in str([(e.action, e.target, e.details) for e in events])


def test_parallel_demotion_preserves_one_superuser(tmp_path):
    from concurrent.futures import ThreadPoolExecutor
    from sqlalchemy import create_engine
    from sqlalchemy.orm import Session
    from app.db.session import Base

    engine = create_engine(
        "sqlite:///" + str(tmp_path / "super.db"),
        connect_args={"check_same_thread": False, "timeout": 10},
    )
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        seed_access_control(session)
        people = [
            User(email=f"parallel{i}@test.org", password_hash="unused")
            for i in range(2)
        ]
        session.add_all(people)
        session.flush()
        for person in people:
            assign_roles(session, person.id, ["superuser"])
        session.commit()
        ids = [person.id for person in people]

    def demote(uid):
        with Session(engine) as session:
            try:
                lock_security(session)
                assign_roles(session, uid, ["read_only"])
                session.commit()
                return 200
            except HTTPException as error:
                session.rollback()
                return error.status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(demote, ids))
    assert sorted(results) == [200, 409]


def test_audit_survives_real_dependency_session_cleanup(client, db):
    from app.main import app
    from app.db.session import get_db
    from sqlalchemy.orm import Session

    user, headers = identity(db, "closing_reader", ["devices.read"])

    def closing_db():
        with Session(db.bind) as session:
            yield session

    original = app.dependency_overrides[get_db]
    app.dependency_overrides[get_db] = closing_db
    try:
        result = client.post(
            "/api/v1/access/api-roles",
            headers=headers,
            json={"key": "denied_closing", "name": "Denied", "permissions": []},
        )
        assert result.status_code == 403
    finally:
        app.dependency_overrides[get_db] = original


def test_device_admin_route_cannot_bypass_owned_scope(client, db):
    from app.models.device import Device

    actor, headers = identity(
        db, "device_editor", ["devices.change", "devices.delete", "devices.read"]
    )
    other = User(email="another-owner@test.org", password_hash="unused")
    db.add(other)
    db.flush()
    device = Device(
        serial_number="OTHER-OWNER", secret_hash="unused", owner_id=other.id
    )
    db.add(device)
    db.commit()
    assert (
        client.patch(
            f"/api/v1/devices/admin/{device.id}/disabled",
            headers=headers,
            json={"disabled": True},
        ).status_code
        == 404
    )
    assert (
        client.delete(f"/api/v1/devices/admin/{device.id}", headers=headers).status_code
        == 404
    )
    assert client.get("/api/v1/devices/admin/all", headers=headers).json() == []


def test_inventory_create_does_not_grant_secret_export(
    client, db, tmp_path, monkeypatch
):
    from app.models.device_lifecycle import DeviceModel
    from app.services.device_inventory import seed_models
    from app.core.config import settings

    seed_models(db)
    monkeypatch.setattr(settings, "device_signing_key_file", str(tmp_path / "key.pem"))
    actor, headers = identity(db, "inventory_creator", ["inventory.create"])
    model = db.get(DeviceModel, "lily_test_light")
    result = client.post(
        "/api/v1/admin/device-inventory",
        headers=headers,
        json={"device_type_id": model.device_type_id, "model_key": model.key},
    )
    assert result.status_code == 200
    assert "device_secret" not in result.json() and "config_header" not in result.json()


def test_predefined_operator_excludes_accounts_and_security_settings(db):
    from app.services.permission_catalog import PREDEFINED_ROLES

    for key in ("operator", "read_only"):
        assert "users.read" not in PREDEFINED_ROLES[key][1]
        assert "settings.read" not in PREDEFINED_ROLES[key][1]


def test_pairing_token_is_revoked_with_its_parent_session(client, db, owner):
    from app.models.device import Device
    from app.core.security import hash_password

    token = client.post("/api/v1/devices/pairing-session", headers=owner[1]).json()[
        "pairing_token"
    ]
    device = Device(
        serial_number="PARENT-PAIR", secret_hash=hash_password("factory-secret")
    )
    db.add(device)
    db.commit()
    assert (
        client.post(
            f"/api/v1/access/users/{owner[0].id}/revoke-sessions", headers=owner[1]
        ).status_code
        == 200
    )
    response = client.post(
        "/api/v1/devices/activate",
        json={
            "serial_number": device.serial_number,
            "device_secret": "factory-secret",
            "pairing_token": token,
        },
    )
    assert response.status_code == 401


def test_mobile_users_cannot_manage_each_others_sessions(client, db):
    from app.services.mobile_sessions import issue_mobile_session

    alice = User(email="alice-mobile@test.org", password_hash="unused")
    bob = User(email="bob-mobile@test.org", password_hash="unused")
    db.add_all([alice, bob])
    db.commit()
    a = issue_mobile_session(db, alice)
    b = issue_mobile_session(db, bob)
    headers = {"Authorization": "Bearer " + a["access_token"]}
    assert (
        client.get(
            f"/api/v1/access/sessions?user_id={bob.id}", headers=headers
        ).status_code
        == 403
    )
    assert (
        client.post(
            f"/api/v1/access/users/{bob.id}/revoke-sessions", headers=headers
        ).status_code
        == 403
    )
    assert (
        client.delete(
            f"/api/v1/access/sessions/{b['session_id']}", headers=headers
        ).status_code
        == 403
    )
    assert client.get("/api/v1/access/sessions", headers=headers).status_code == 200
    assert validate_session(db, b["access_token"])
