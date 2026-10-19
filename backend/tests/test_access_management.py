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
