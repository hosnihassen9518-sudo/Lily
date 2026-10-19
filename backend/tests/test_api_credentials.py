from datetime import datetime, timedelta, timezone
import pytest
from fastapi import HTTPException
from app.models.user import User
from app.services.rbac import seed_access_control, assign_roles
from app.models.access_control import Role, ApiCredential


def test_credential_shown_once_and_revocable(db):
    from app.services.api_credentials import (
        create_credential,
        exchange_credential,
        revoke_credential,
    )
    from app.services.access_sessions import validate_session

    seed_access_control(db)
    issuer = User(email="issuer@test.org", password_hash="unused")
    db.add(issuer)
    db.flush()
    assign_roles(db, issuer.id, ["superuser"])
    db.add(
        Role(
            key="api_reader",
            name="API Reader",
            audience="api",
            permissions=["devices.read"],
        )
    )
    db.commit()
    result = create_credential(
        db,
        issuer,
        "Integration",
        ["api_reader"],
        {"devices": [42]},
        datetime.now(timezone.utc) + timedelta(days=1),
        120,
    )
    assert result["secret"] not in db.get(ApiCredential, result["id"]).secret_hash
    token = exchange_credential(db, result["secret"])["access_token"]
    context = validate_session(db, token)
    assert context.permissions == {"devices.read"} and context.scope == {
        "devices": [42]
    }
    revoke_credential(db, result["id"])
    db.commit()
    with pytest.raises(HTTPException):
        validate_session(db, token)
    with pytest.raises(HTTPException):
        exchange_credential(db, result["secret"])
