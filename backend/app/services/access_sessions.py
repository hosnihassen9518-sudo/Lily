from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import secrets
from fastapi import HTTPException
from jose import jwt
from sqlalchemy import select
from app.core.security import decode_token, ALGORITHM
from app.core.config import settings
from app.models.access_control import AccessSession, ServicePrincipal
from app.models.device_lifecycle import MobileSession
from app.models.user import User
from app.services.rbac import effective_permissions, roles_for, lock_security
from app.services.permission_catalog import MOBILE_PERMISSIONS
from app.services.mobile_sessions import utc


@dataclass
class AuthContext:
    principal: User
    session_id: str
    permissions: frozenset
    scope: dict
    auth_method: str
    portal_roles: tuple = ()


def issue_session(
    db,
    user,
    auth_method="portal",
    scope=None,
    ttl=None,
    session_id=None,
    credential_id=None,
    permissions=None,
    expires_at=None,
    commit=True,
):
    lock_security(db)
    now = datetime.now(timezone.utc)
    roles = roles_for(db, user.id)
    grants = effective_permissions(db, user.id)
    if auth_method == "mobile":
        grants = (grants & MOBILE_PERMISSIONS) if roles else set(MOBILE_PERMISSIONS)
    if permissions is not None:
        grants = set(permissions)
    expiry = expires_at or now + timedelta(
        minutes=ttl
        or (15 if auth_method == "api" else settings.access_token_expire_minutes)
    )
    row = AccessSession(
        id=session_id or secrets.token_hex(24),
        user_id=user.id,
        permissions=sorted(grants),
        role_revisions={r.key: r.revision for r in roles},
        scope=(
            scope
            if scope is not None
            else (
                {"all": True}
                if auth_method == "portal" and "resources.all" in grants
                else {"owned": True}
            )
        ),
        auth_method=auth_method,
        credential_id=credential_id,
        expires_at=expiry,
    )
    db.add(row)
    if commit:
        db.commit()
    else:
        db.flush()
    token = jwt.encode(
        {"sub": str(user.id), "sid": row.id, "exp": expiry, "type": "access"},
        settings.secret_key,
        algorithm=ALGORITHM,
    )
    return {
        "access_token": token,
        "token_type": "bearer",
        "session_id": row.id,
        "expires_at": expiry,
    }


def validate_session(db, token):
    try:
        payload = decode_token(token)
        if payload.get("type") != "access" or not payload.get("sid"):
            raise ValueError()
        row = db.scalar(
            select(AccessSession)
            .where(AccessSession.id == payload["sid"])
            .execution_options(populate_existing=True)
        )
        user = db.get(User, int(payload["sub"]))
        if (
            not row
            or row.user_id != int(payload["sub"])
            or row.revoked_at
            or utc(row.expires_at) <= datetime.now(timezone.utc)
            or not user
            or not user.is_active
        ):
            raise ValueError()
        if row.auth_method == "mobile":
            parent = db.get(MobileSession, row.id)
            if (
                not parent
                or parent.revoked_at
                or utc(parent.expires_at) <= datetime.now(timezone.utc)
            ):
                raise ValueError()
        return AuthContext(
            user,
            row.id,
            frozenset(row.permissions),
            row.scope,
            row.auth_method,
            tuple(row.role_revisions),
        )
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(401, "Session expired or revoked. Sign in again.")


def can_access_device(db, user, device):
    if device is None:
        return False
    context = getattr(user, "_access", None)
    if context and context.auth_method == "portal" and context.scope.get("all"):
        return True
    if not context or context.auth_method != "api":
        return device.owner_id == user.id
    scope = context.scope
    if scope.get("delegated_owner") and device.owner_id != scope["delegated_owner"]:
        return False
    if scope.get("all"):
        return True
    if device.id in scope.get("devices", []):
        return True
    from app.models.smart_device import DeviceProfile

    profile = db.get(DeviceProfile, device.id)
    return bool(profile and profile.home_id in scope.get("homes", []))


def can_access_home(user, home):
    context = getattr(user, "_access", None)
    if context and context.auth_method == "portal" and context.scope.get("all"):
        return True
    if not context or context.auth_method != "api":
        return home.owner_id == user.id
    if (
        context.scope.get("delegated_owner")
        and home.owner_id != context.scope["delegated_owner"]
    ):
        return False
    return bool(context.scope.get("all") or home.id in context.scope.get("homes", []))


def can_manage_device(db, user, device, inventory_permission="inventory.read"):
    if device is None:
        return False
    if can_access_device(db, user, device):
        return True
    context = getattr(user, "_access", None)
    return bool(
        device.owner_id is None
        and context
        and context.auth_method == "portal"
        and inventory_permission in context.permissions
    )
