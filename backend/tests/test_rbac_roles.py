import pytest
from fastapi import HTTPException
from app.models.user import User


def test_predefined_roles_and_single_assignment(db):
    from app.services.rbac import (
        seed_access_control,
        effective_permissions,
        assign_roles,
    )
    from app.models.access_control import Role

    seed_access_control(db)
    user = User(email="rbac@test.org", password_hash="unused")
    db.add(user)
    db.flush()
    with pytest.raises(HTTPException) as error:
        assign_roles(db, user.id, ["read_only", "operator"])
    assert error.value.status_code == 422
    assign_roles(db, user.id, ["operator"])
    assert "devices.control" in effective_permissions(db, user.id)
    assert "api_roles.create" not in effective_permissions(db, user.id)
    assert db.get(Role, "superuser").predefined


def test_builtin_and_unknown_grants_are_rejected(db):
    from app.services.rbac import seed_access_control, validate_permissions, edit_role

    seed_access_control(db)
    with pytest.raises(HTTPException):
        validate_permissions(["unknown.write"])
    with pytest.raises(HTTPException):
        edit_role(db, "operator", {"permissions": []})


def test_role_payloads_reject_multiple_roles():
    from pydantic import ValidationError
    from app.schemas.access_control import Assignment, UserInput
    with pytest.raises(ValidationError):
        Assignment(roles=["operator", "read_only"])
    with pytest.raises(ValidationError):
        UserInput(email="one@test.org", password="test-password-123", roles=["operator", "read_only"])


def test_legacy_multi_role_sessions_are_revoked_and_login_blocked(db):
    from app.services.rbac import seed_access_control, assign_roles
    from app.models.access_control import RoleAssignment
    from app.services.access_sessions import issue_session, validate_session
    seed_access_control(db)
    user = User(email="legacyroles@test.org", password_hash="unused")
    db.add(user); db.flush()
    assign_roles(db, user.id, ["operator"]); db.commit()
    token = issue_session(db, user)["access_token"]
    db.add(RoleAssignment(user_id=user.id, role_key="read_only")); db.commit()
    seed_access_control(db); db.commit()
    with pytest.raises(HTTPException): validate_session(db, token)
    with pytest.raises(HTTPException): issue_session(db, user)
    assign_roles(db, user.id, ["read_only"]); db.commit()
    assert issue_session(db, user)["access_token"]
