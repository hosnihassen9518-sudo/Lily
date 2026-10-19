import pytest
from fastapi import HTTPException
from app.models.user import User


def test_predefined_roles_and_union(db):
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
    assign_roles(db, user.id, ["read_only", "operator"])
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
