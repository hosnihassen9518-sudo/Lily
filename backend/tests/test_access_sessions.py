import pytest
from fastapi import HTTPException
from app.models.user import User
from app.services.rbac import (
    seed_access_control,
    assign_roles,
    revoke_principal_sessions,
)


def test_snapshot_and_immediate_revocation(db):
    from app.services.access_sessions import issue_session, validate_session

    seed_access_control(db)
    user = User(email="session@test.org", password_hash="unused")
    db.add(user)
    db.flush()
    assign_roles(db, user.id, ["operator"])
    db.commit()
    result = issue_session(db, user)
    context = validate_session(db, result["access_token"])
    assert "devices.control" in context.permissions
    revoke_principal_sessions(db, user.id)
    db.commit()
    with pytest.raises(HTTPException) as error:
        validate_session(db, result["access_token"])
    assert error.value.status_code == 401


def test_legacy_token_requires_fresh_login(db):
    from app.services.access_sessions import validate_session
    from app.core.security import create_access_token

    user = User(email="legacy@test.org", password_hash="unused")
    db.add(user)
    db.commit()
    with pytest.raises(HTTPException):
        validate_session(db, create_access_token(str(user.id)))


def test_superuser_can_control_all_resources_with_explicit_global_scope(db):
    from app.services.access_sessions import (
        issue_session,
        validate_session,
        can_access_device,
    )
    from app.models.device import Device

    seed_access_control(db)
    user = User(email="global@test.org", password_hash="unused")
    db.add(user)
    db.flush()
    assign_roles(db, user.id, ["superuser"])
    db.commit()
    user._access = validate_session(db, issue_session(db, user)["access_token"])
    assert can_access_device(
        db, user, Device(owner_id=999, serial_number="GLOBAL", secret_hash="unused")
    )
