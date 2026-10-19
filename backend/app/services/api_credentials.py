import hashlib, hmac, secrets
from datetime import datetime, timezone
from fastapi import HTTPException
from sqlalchemy import select, update
from app.models.user import User
from app.models.access_control import (
    ApiCredential,
    ServicePrincipal,
    AccessSession,
    Role,
    GrantCeiling,
)
from app.services.rbac import (
    effective_permissions,
    assign_roles,
    authorize_grant,
    superuser,
    revoke_principal_sessions,
    lock_security,
)
from app.services.mobile_sessions import utc
from app.services.access_sessions import issue_session
from app.services.access_audit import audit
from app.services.permission_catalog import PERMISSIONS


def issuer_ceiling(db, user, seen=None):
    if not user or not user.is_active:
        return set()
    seen = set() if seen is None else seen
    if user.id in seen:
        return set()
    seen.add(user.id)
    if superuser(db, user.id):
        return set(PERMISSIONS)
    ceiling = db.get(GrantCeiling, user.id)
    grants = effective_permissions(db, user.id)
    if "api_credentials.create" not in grants:
        return set()
    allowed = grants & set(ceiling.permissions if ceiling else [])
    principal = db.get(ServicePrincipal, user.id)
    if principal:
        credential = db.scalar(
            select(ApiCredential).where(ApiCredential.user_id == user.id)
        )
        if (
            not credential
            or credential.revoked_at
            or utc(credential.expires_at) <= datetime.now(timezone.utc)
        ):
            return set()
        allowed &= issuer_ceiling(db, db.get(User, principal.issuer_id), seen)
    return allowed


def create_credential(db, actor, name, role_keys, scope, expires_at, rate_limit=120):
    lock_security(db)
    if utc(expires_at) <= datetime.now(timezone.utc):
        raise HTTPException(422, "Expiry must be in the future")
    if not role_keys:
        raise HTTPException(422, "Select at least one API role")
    roles = [db.get(Role, k) for k in set(role_keys)]
    if any(r is None or r.audience != "api" for r in roles):
        raise HTTPException(422, "API roles required")
    grants = set().union(*(set(r.permissions) for r in roles))
    authorize_grant(db, actor, grants)
    context = getattr(actor, "_access", None)
    if context and context.auth_method == "api":
        from app.services.access_sessions import can_access_device, can_access_home
        from app.models.device import Device
        from app.models.home import Home

        if scope.get("all") and not context.scope.get("all"):
            raise HTTPException(403, "Child scope exceeds issuer scope")
        for did in scope.get("devices", []):
            if not can_access_device(db, actor, db.get(Device, did)):
                raise HTTPException(403, "Child device scope exceeds issuer scope")
        for hid in scope.get("homes", []):
            home = db.get(Home, hid)
            if not home or not can_access_home(actor, home):
                raise HTTPException(403, "Child home scope exceeds issuer scope")
    if scope.get("all") and "resources.all" not in issuer_ceiling(db, actor):
        raise HTTPException(403, "Global resource delegation required")
    # Resource-scoped delegation also requires ownership of each selected resource.
    from app.models.device import Device
    from app.models.home import Home

    if not superuser(db, actor.id) and "resources.all" not in effective_permissions(
        db, actor.id
    ):
        for did in scope.get("devices", []):
            d = db.get(Device, did)
            if not d or d.owner_id != actor.id:
                raise HTTPException(403, "Device is outside issuer scope")
        for hid in scope.get("homes", []):
            h = db.get(Home, hid)
            if not h or h.owner_id != actor.id:
                raise HTTPException(403, "Home is outside issuer scope")
    uid = secrets.token_hex(16)
    user = User(
        email="service-" + uid + "@lily.invalid",
        password_hash="!api-only!",
        is_active=True,
        is_admin=False,
    )
    db.add(user)
    db.flush()
    db.add(
        ServicePrincipal(user_id=user.id, issuer_id=actor.id, name=name, scope=scope)
    )
    db.flush()
    assign_roles(db, user.id, role_keys, audience="api")
    identifier = secrets.token_hex(12)
    secret = "lily_api_" + identifier + "." + secrets.token_urlsafe(32)
    db.add(
        ApiCredential(
            id=identifier,
            user_id=user.id,
            name=name,
            secret_hash=hashlib.sha256(secret.encode()).hexdigest(),
            expires_at=expires_at,
            rate_limit=rate_limit,
        )
    )
    audit(db, actor.id, "api_credentials.create", identifier)
    db.commit()
    return {"id": identifier, "secret": secret, "name": name, "expires_at": expires_at}


def revoke_credential(db, identifier):
    row = db.get(ApiCredential, identifier)
    if not row:
        raise HTTPException(404, "Credential not found")
    row.revoked_at = datetime.now(timezone.utc)
    revoke_principal_sessions(db, row.user_id)
    db.execute(
        update(AccessSession)
        .where(AccessSession.credential_id == identifier)
        .values(revoked_at=row.revoked_at)
    )


def exchange_credential(db, secret):
    lock_security(db)
    identifier = secret.removeprefix("lily_api_").split(".")[0]
    row = db.get(ApiCredential, identifier)
    now = datetime.now(timezone.utc)
    if (
        not row
        or row.revoked_at
        or utc(row.expires_at) <= now
        or not hmac.compare_digest(
            row.secret_hash, hashlib.sha256(secret.encode()).hexdigest()
        )
    ):
        raise HTTPException(401, "Invalid API credential")
    principal = db.get(ServicePrincipal, row.user_id)
    user = db.get(User, row.user_id)
    issuer = db.get(User, principal.issuer_id)
    grants = effective_permissions(db, user.id) & issuer_ceiling(db, issuer)
    if not user.is_active or not grants:
        raise HTTPException(401, "API access is inactive")
    if principal.scope.get("all") and "resources.all" not in issuer_ceiling(db, issuer):
        raise HTTPException(401, "Issuer scope withdrawn")
    row.last_used_at = now
    from datetime import timedelta

    expires = min(utc(row.expires_at), now + timedelta(minutes=15))
    session_scope = dict(principal.scope)
    if "resources.all" not in issuer_ceiling(db, issuer):
        session_scope["delegated_owner"] = issuer.id
    result = issue_session(
        db,
        user,
        auth_method="api",
        scope=session_scope,
        permissions=grants,
        credential_id=row.id,
        expires_at=expires,
        commit=False,
    )
    audit(db, user.id, "api.exchange", row.id)
    db.commit()
    return result
