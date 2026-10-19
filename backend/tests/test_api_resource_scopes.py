from datetime import datetime, timedelta, timezone
import pytest
from fastapi import HTTPException
from sqlalchemy import select
from app.models.user import User
from app.models.device import Device
from app.models.access_control import Role, GrantCeiling, ServicePrincipal
from app.services.rbac import (
    seed_access_control,
    assign_roles,
    revoke_principal_sessions,
)
from app.services.api_credentials import create_credential, exchange_credential
from app.services.access_sessions import validate_session


def setup(db):
    seed_access_control(db)
    issuer = User(email="api_issuer@test.org", password_hash="unused")
    other = User(email="other@test.org", password_hash="unused")
    db.add_all([issuer, other])
    db.flush()
    assign_roles(db, issuer.id, ["superuser"])
    db.add(
        Role(
            key="api_scoped",
            name="Scoped",
            audience="api",
            permissions=["devices.read", "devices.control"],
        )
    )
    d1 = Device(
        serial_number="SCOPE1", secret_hash="unused", owner_id=other.id, model="unknown"
    )
    d2 = Device(
        serial_number="SCOPE2", secret_hash="unused", owner_id=other.id, model="unknown"
    )
    db.add_all([d1, d2])
    db.commit()
    result = create_credential(
        db,
        issuer,
        "Scoped",
        ["api_scoped"],
        {"devices": [d1.id]},
        datetime.now(timezone.utc) + timedelta(days=1),
    )
    token = exchange_credential(db, result["secret"])["access_token"]
    return issuer, d1, d2, result, {"Authorization": "Bearer " + token}


def test_api_scope_filters_lists_and_denies_other_devices(client, db):
    issuer, d1, d2, result, headers = setup(db)
    response = client.get("/api/v1/devices", headers=headers)
    assert response.status_code == 200 and [d["id"] for d in response.json()] == [d1.id]
    assert (
        client.get(f"/api/v1/devices/{d1.id}/profile", headers=headers).status_code
        == 200
    )
    assert (
        client.get(f"/api/v1/devices/{d2.id}/profile", headers=headers).status_code
        == 404
    )
    assert client.get("/api/v1/devices/admin/all", headers=headers).status_code == 403
    assert (
        client.post("/api/v1/devices/pairing-session", headers=headers).status_code
        == 403
    )


def test_issuer_disable_revokes_api_sessions_and_exchange(db):
    issuer, d1, d2, result, headers = setup(db)
    issuer.is_active = False
    revoke_principal_sessions(db, issuer.id)
    db.commit()
    with pytest.raises(HTTPException):
        validate_session(db, headers["Authorization"].split()[1])
    with pytest.raises(HTTPException):
        exchange_credential(db, result["secret"])


def test_issuer_role_reduction_caps_future_exchange(db):
    issuer, d1, d2, result, headers = setup(db)
    other = User(email="other_super@test.org", password_hash="unused")
    db.add(other)
    db.flush()
    assign_roles(db, other.id, ["superuser"])
    grants = ["devices.read", "api_credentials.create", "api_roles.assign"]
    db.add(
        Role(
            key="issuer_reduced", name="Reduced", audience="portal", permissions=grants
        )
    )
    db.flush()
    db.add(GrantCeiling(user_id=issuer.id, permissions=grants))
    assign_roles(db, issuer.id, ["issuer_reduced"])
    db.commit()
    with pytest.raises(HTTPException):
        validate_session(db, headers["Authorization"].split()[1])
    context = validate_session(
        db, exchange_credential(db, result["secret"])["access_token"]
    )
    assert context.permissions == {"devices.read"}


def test_owner_delegation_does_not_survive_device_transfer(db):
    from app.services.access_sessions import can_access_device

    seed_access_control(db)
    grants = ["devices.read", "api_credentials.create", "api_roles.assign"]
    db.add(
        Role(key="owner_issuer", name="Owner", audience="portal", permissions=grants)
    )
    db.add(
        Role(key="owner_api", name="API", audience="api", permissions=["devices.read"])
    )
    issuer = User(email="owner_issuer@test.org", password_hash="unused")
    db.add(issuer)
    db.flush()
    assign_roles(db, issuer.id, ["owner_issuer"])
    db.add(GrantCeiling(user_id=issuer.id, permissions=grants))
    device = Device(serial_number="TRANSFER", secret_hash="unused", owner_id=issuer.id)
    db.add(device)
    db.commit()
    created = create_credential(
        db,
        issuer,
        "Owner integration",
        ["owner_api"],
        {"devices": [device.id]},
        datetime.now(timezone.utc) + timedelta(days=1),
    )
    context = validate_session(
        db, exchange_credential(db, created["secret"])["access_token"]
    )
    context.principal._access = context
    assert can_access_device(db, context.principal, device)
    device.owner_id = None
    db.commit()
    assert not can_access_device(db, context.principal, device)


def test_issuer_revocation_reaches_descendant_service_sessions(db):
    from app.models.access_control import ServicePrincipal
    from app.services.access_sessions import issue_session

    root = User(email="root-chain@test.org", password_hash="unused")
    first = User(email="first-chain@test.org", password_hash="unused")
    second = User(email="second-chain@test.org", password_hash="unused")
    db.add_all([root, first, second])
    db.flush()
    db.add_all(
        [
            ServicePrincipal(
                user_id=first.id, issuer_id=root.id, name="First", scope={}
            ),
            ServicePrincipal(
                user_id=second.id, issuer_id=first.id, name="Second", scope={}
            ),
        ]
    )
    db.commit()
    token = issue_session(db, second, auth_method="api", permissions=["devices.read"])[
        "access_token"
    ]
    revoke_principal_sessions(db, root.id)
    db.commit()
    with pytest.raises(HTTPException):
        validate_session(db, token)


def test_api_issuer_cannot_broaden_its_resource_scope(db):
    issuer, d1, d2, result, headers = setup(db)
    grants = [
        "devices.read",
        "resources.all",
        "api_credentials.create",
        "api_roles.assign",
    ]
    db.add(Role(key="nested_issuer", name="Nested", audience="api", permissions=grants))
    db.commit()
    parent = create_credential(
        db,
        issuer,
        "Parent",
        ["nested_issuer"],
        {"devices": [d1.id]},
        datetime.now(timezone.utc) + timedelta(days=1),
    )
    context = validate_session(
        db, exchange_credential(db, parent["secret"])["access_token"]
    )
    actor = context.principal
    actor._access = context
    db.add(GrantCeiling(user_id=actor.id, permissions=grants))
    db.commit()
    with pytest.raises(HTTPException):
        create_credential(
            db,
            actor,
            "Overbroad child",
            ["nested_issuer"],
            {"all": True},
            datetime.now(timezone.utc) + timedelta(days=1),
        )
