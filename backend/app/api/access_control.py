from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from sqlalchemy import select, delete, update
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.api.deps import get_current_user, require_permission
from app.models.user import User
from app.models.access_control import (
    Role,
    RoleAssignment,
    GrantCeiling,
    AccessSession,
    ServicePrincipal,
    ApiCredential,
    AuditEvent,
)
from app.models.device_lifecycle import MobileSession
from app.schemas.access_control import (
    RoleInput,
    RoleEdit,
    Assignment,
    Ceiling,
    UserInput,
    UserStatus,
    CredentialInput,
    Exchange,
)
from app.services.rbac import (
    seed_access_control,
    validate_permissions,
    edit_role,
    assign_roles,
    roles_for,
    authorize_grant,
    superuser,
    lock_security,
    protect_last_superuser,
    revoke_principal_sessions,
    effective_permissions,
)
from app.services.access_audit import audit
from app.services.api_credentials import (
    create_credential,
    exchange_credential,
    revoke_credential,
)
from app.services.permission_catalog import RESOURCE_ACTIONS
from app.schemas.access_control import PasswordReset
from app.core.security import hash_password

router = APIRouter(prefix="/access", tags=["access control"])
auth_router = APIRouter(prefix="/auth", tags=["API authentication"])


def role_data(role):
    return {
        "key": role.key,
        "name": role.name,
        "audience": role.audience,
        "predefined": role.predefined,
        "permissions": role.permissions,
        "revision": role.revision,
    }


def gate(actor, permission):
    if permission not in actor._access.permissions:
        raise HTTPException(403, "Permission required: " + permission)


@router.get("/permissions")
def catalog(user: User = Depends(get_current_user)):
    return {
        "resources": RESOURCE_ACTIONS,
        "grantable": sorted(user._access.permissions),
    }


@router.get("/roles")
def list_roles(
    user: User = Depends(require_permission("roles.read")),
    db: Session = Depends(get_db),
):
    return [
        role_data(r)
        for r in db.scalars(
            select(Role).where(Role.audience == "portal").order_by(Role.name)
        )
    ]


@router.get("/api-roles")
def list_api_roles(
    user: User = Depends(require_permission("api_roles.read")),
    db: Session = Depends(get_db),
):
    return [
        role_data(r)
        for r in db.scalars(
            select(Role).where(Role.audience == "api").order_by(Role.name)
        )
    ]


def create_role(db, user, payload, audience):
    lock_security(db)
    validate_permissions(payload.permissions)
    authorize_grant(db, user, payload.permissions)
    if db.get(Role, payload.key):
        raise HTTPException(409, "Role key exists")
    role = Role(
        key=payload.key,
        name=payload.name,
        audience=audience,
        permissions=sorted(set(payload.permissions)),
    )
    db.add(role)
    audit(db, user.id, audience + "_roles.create", payload.key)
    db.commit()
    return role_data(role)


@router.post("/roles")
def add_role(
    payload: RoleInput,
    user: User = Depends(require_permission("roles.create")),
    db: Session = Depends(get_db),
):
    return create_role(db, user, payload, "portal")


@router.post("/api-roles")
def add_api_role(
    payload: RoleInput,
    user: User = Depends(require_permission("api_roles.create")),
    db: Session = Depends(get_db),
):
    return create_role(db, user, payload, "api")


def mutate_role(db, user, key, payload, audience):
    lock_security(db)
    role = db.get(Role, key)
    if not role or role.audience != audience:
        raise HTTPException(404, "Role not found")
    authorize_grant(db, user, set(role.permissions) | set(payload.permissions))
    for uid in db.scalars(
        select(RoleAssignment.user_id).where(RoleAssignment.role_key == key)
    ):
        authorize_grant(db, user, effective_permissions(db, uid), uid)
    role = edit_role(db, key, payload.model_dump())
    audit(db, user.id, audience + "_roles.change", key)
    db.commit()
    return role_data(role)


@router.patch("/roles/{key}")
def change_role(
    key: str,
    payload: RoleEdit,
    user: User = Depends(require_permission("roles.change")),
    db: Session = Depends(get_db),
):
    return mutate_role(db, user, key, payload, "portal")


@router.patch("/api-roles/{key}")
def change_api_role(
    key: str,
    payload: RoleEdit,
    user: User = Depends(require_permission("api_roles.change")),
    db: Session = Depends(get_db),
):
    return mutate_role(db, user, key, payload, "api")


def remove_role(db, user, key, audience):
    lock_security(db)
    role = db.get(Role, key)
    if not role or role.audience != audience:
        raise HTTPException(404, "Role not found")
    if role.predefined:
        raise HTTPException(409, "Predefined roles are immutable")
    authorize_grant(db, user, role.permissions)
    if db.scalar(
        select(RoleAssignment.user_id).where(RoleAssignment.role_key == key).limit(1)
    ):
        raise HTTPException(409, "Unassign this role first")
    db.delete(role)
    audit(db, user.id, audience + "_roles.delete", key)
    db.commit()
    return {"ok": True}


@router.delete("/roles/{key}")
def delete_role(
    key: str,
    user: User = Depends(require_permission("roles.delete")),
    db: Session = Depends(get_db),
):
    return remove_role(db, user, key, "portal")


@router.delete("/api-roles/{key}")
def delete_api_role(
    key: str,
    user: User = Depends(require_permission("api_roles.delete")),
    db: Session = Depends(get_db),
):
    return remove_role(db, user, key, "api")


@router.get("/users")
def users(
    user: User = Depends(require_permission("users.read")),
    db: Session = Depends(get_db),
):
    service_ids = select(ServicePrincipal.user_id)
    return [
        {
            "id": u.id,
            "email": u.email,
            "active": u.is_active,
            "roles": [r.key for r in roles_for(db, u.id)],
            "ceiling": (
                db.get(GrantCeiling, u.id).permissions
                if db.get(GrantCeiling, u.id)
                else []
            ),
        }
        for u in db.scalars(
            select(User).where(User.id.not_in(service_ids)).order_by(User.id)
        )
    ]


@router.post("/users")
def create_user(
    payload: UserInput,
    user: User = Depends(require_permission("users.create")),
    db: Session = Depends(get_db),
):
    lock_security(db)
    if payload.roles:
        gate(user, "roles.assign")
    roles = [db.get(Role, k) for k in payload.roles]
    if any(r is None or r.audience != "portal" for r in roles):
        raise HTTPException(422, "Invalid role")
    if "superuser" in payload.roles and not superuser(db, user.id):
        raise HTTPException(403, "Superuser required")
    authorize_grant(db, user, set().union(*(set(r.permissions) for r in roles)))
    if db.scalar(select(User.id).where(User.email == payload.email.lower())):
        raise HTTPException(409, "Email exists")
    row = User(
        email=payload.email.lower(),
        password_hash=hash_password(payload.password),
        is_active=True,
        is_admin=bool(payload.roles),
    )
    db.add(row)
    db.flush()
    assign_roles(db, row.id, payload.roles)
    audit(db, user.id, "users.create", row.id)
    db.commit()
    return {"id": row.id, "email": row.email}


@router.put("/users/{user_id}/roles")
def user_roles(
    user_id: int,
    payload: Assignment,
    user: User = Depends(require_permission("roles.assign")),
    db: Session = Depends(get_db),
):
    lock_security(db)
    target = db.get(User, user_id)
    if not target or db.get(ServicePrincipal, user_id):
        raise HTTPException(404, "User not found")
    roles = [db.get(Role, k) for k in payload.roles]
    if any(r is None or r.audience != "portal" for r in roles):
        raise HTTPException(422, "Invalid role")
    if ("superuser" in payload.roles or superuser(db, user_id)) and not superuser(
        db, user.id
    ):
        raise HTTPException(403, "Superuser required")
    authorize_grant(
        db, user, set().union(*(set(r.permissions) for r in roles)), user_id
    )
    assign_roles(db, user_id, payload.roles)
    target.is_admin = bool(payload.roles)
    audit(db, user.id, "roles.assign", user_id)
    db.commit()
    return {"ok": True}


@router.put("/users/{user_id}/ceiling")
def ceiling(
    user_id: int,
    payload: Ceiling,
    user: User = Depends(require_permission("delegation.change")),
    db: Session = Depends(get_db),
):
    lock_security(db)
    if not superuser(db, user.id):
        raise HTTPException(403, "Superuser required")
    if not db.get(User, user_id):
        raise HTTPException(404, "User not found")
    values = validate_permissions(payload.permissions)
    row = db.get(GrantCeiling, user_id)
    if row:
        row.permissions = values
    else:
        db.add(GrantCeiling(user_id=user_id, permissions=values))
    revoke_principal_sessions(db, user_id)
    audit(db, user.id, "delegation.change", user_id)
    db.commit()
    return {"ok": True}


@router.patch("/users/{user_id}/active")
def user_active(
    user_id: int,
    payload: UserStatus,
    user: User = Depends(require_permission("users.change")),
    db: Session = Depends(get_db),
):
    lock_security(db)
    target = db.get(User, user_id)
    if not target:
        raise HTTPException(404, "User not found")
    authorize_grant(db, user, [], user_id)
    if not payload.active:
        protect_last_superuser(db, user_id)
    target.is_active = payload.active
    revoke_principal_sessions(db, user_id)
    audit(db, user.id, "users.change", user_id)
    db.commit()
    return {"ok": True}


@router.get("/api-credentials")
def credentials(
    user: User = Depends(require_permission("api_credentials.read")),
    db: Session = Depends(get_db),
):
    rows = db.scalars(
        select(ApiCredential).order_by(ApiCredential.created_at.desc())
    ).all()
    return [
        {
            "id": r.id,
            "name": r.name,
            "user_id": r.user_id,
            "roles": [x.key for x in roles_for(db, r.user_id)],
            "scope": db.get(ServicePrincipal, r.user_id).scope,
            "expires_at": r.expires_at,
            "revoked_at": r.revoked_at,
            "last_used_at": r.last_used_at,
            "rate_limit": r.rate_limit,
        }
        for r in rows
        if superuser(db, user.id)
        or db.get(ServicePrincipal, r.user_id).issuer_id == user.id
    ]


@router.post("/api-credentials")
def new_credential(
    payload: CredentialInput,
    user: User = Depends(require_permission("api_credentials.create")),
    db: Session = Depends(get_db),
):
    gate(user, "api_roles.assign")
    lock_security(db)
    from app.services.rate_limits import policies

    if payload.rate_limit > policies(db)["api_principal"]:
        raise HTTPException(422, "Rate exceeds the configured API ceiling")
    return create_credential(
        db,
        user,
        payload.name,
        payload.roles,
        payload.scope.model_dump(),
        payload.expires_at,
        payload.rate_limit,
    )


@router.put("/api-credentials/{identifier}/roles")
def credential_roles(
    identifier: str,
    payload: Assignment,
    user: User = Depends(require_permission("api_roles.assign")),
    db: Session = Depends(get_db),
):
    lock_security(db)
    row = db.get(ApiCredential, identifier)
    if not row:
        raise HTTPException(404, "Credential not found")
    principal = db.get(ServicePrincipal, row.user_id)
    if not superuser(db, user.id) and principal.issuer_id != user.id:
        raise HTTPException(403, "Credential belongs to another issuer")
    roles = [db.get(Role, k) for k in payload.roles]
    if any(r is None or r.audience != "api" for r in roles):
        raise HTTPException(422, "API roles required")
    authorize_grant(db, user, set().union(*(set(r.permissions) for r in roles)))
    assign_roles(db, row.user_id, payload.roles, audience="api")
    audit(db, user.id, "api_roles.assign", identifier)
    db.commit()
    return {"ok": True}


@router.delete("/api-credentials/{identifier}")
def delete_credential(
    identifier: str,
    user: User = Depends(require_permission("api_credentials.revoke")),
    db: Session = Depends(get_db),
):
    lock_security(db)
    row = db.get(ApiCredential, identifier)
    if not row:
        raise HTTPException(404, "Credential not found")
    if (
        not superuser(db, user.id)
        and db.get(ServicePrincipal, row.user_id).issuer_id != user.id
    ):
        raise HTTPException(403, "Credential belongs to another issuer")
    revoke_credential(db, identifier)
    audit(db, user.id, "api_credentials.revoke", identifier)
    db.commit()
    return {"ok": True}


@router.get("/sessions")
def sessions(
    user_id: int | None = None,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    target = user.id if user_id is None else user_id
    if target != user.id:
        gate(user, "sessions.read")
        authorize_grant(db, user, [], target)
    return [
        {
            "id": s.id,
            "user_id": s.user_id,
            "auth_method": s.auth_method,
            "created_at": s.created_at,
            "expires_at": s.expires_at,
            "revoked_at": s.revoked_at,
            "last_activity": s.last_activity,
        }
        for s in db.scalars(
            select(AccessSession)
            .where(AccessSession.user_id == target)
            .order_by(AccessSession.created_at.desc())
            .limit(500)
        )
    ]


@router.post("/users/{user_id}/revoke-sessions")
def revoke_all(
    user_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    lock_security(db)
    if user_id != user.id:
        gate(user, "sessions.revoke")
        authorize_grant(db, user, [], user_id)
    revoke_principal_sessions(db, user_id)
    audit(db, user.id, "sessions.revoke_all", user_id)
    db.commit()
    return {"ok": True}


@router.delete("/sessions/{session_id}")
def revoke_session(
    session_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = db.get(AccessSession, session_id)
    if not row:
        raise HTTPException(404, "Session not found")
    if row.user_id != user.id:
        gate(user, "sessions.revoke")
        authorize_grant(db, user, [], row.user_id)
    row.revoked_at = datetime.now(timezone.utc)
    parent = db.get(MobileSession, row.id)
    if parent:
        parent.revoked_at = row.revoked_at
    audit(db, user.id, "sessions.revoke", row.id)
    db.commit()
    return {"ok": True}


@router.get("/audit")
def audit_events(
    limit: int = Query(100, ge=1, le=500),
    user: User = Depends(require_permission("audit.read")),
    db: Session = Depends(get_db),
):
    return [
        {
            "id": r.id,
            "actor_id": r.actor_id,
            "action": r.action,
            "target": r.target,
            "result": r.result,
            "created_at": r.created_at,
        }
        for r in db.scalars(
            select(AuditEvent).order_by(AuditEvent.id.desc()).limit(limit)
        )
    ]


@auth_router.post("/api/exchange")
def exchange(payload: Exchange, request: Request, db: Session = Depends(get_db)):
    from app.services.rate_limits import (
        require_https,
        consume_limit,
        client_ip,
        policies,
    )

    require_https(request)
    values = policies(db)
    consume_limit(db, "exchange-ip:" + client_ip(request), values["exchange_ip"], 60)
    identifier = payload.credential.removeprefix("lily_api_").split(".")[0]
    if db.get(ApiCredential, identifier):
        consume_limit(
            db, "exchange-key:" + identifier, values["exchange_credential"], 60
        )
    return exchange_credential(db, payload.credential)


@router.get("/rate-limits")
def rate_settings(
    user: User = Depends(require_permission("settings.read")),
    db: Session = Depends(get_db),
):
    from app.services.rate_limits import policies

    return policies(db)


@router.put("/rate-limits")
def set_rate_settings(
    payload: dict,
    user: User = Depends(require_permission("settings.change")),
    db: Session = Depends(get_db),
):
    from app.services.rate_limits import DEFAULTS, policies
    from app.models.device_lifecycle import AppSetting

    current = policies(db)
    if set(payload) != set(DEFAULTS) or any(
        type(v) is not int or not 1 <= v <= 100000 for v in payload.values()
    ):
        raise HTTPException(422, "Provide valid limits for every category")
    if not superuser(db, user.id):
        authorize_grant(db, user, ["settings.change"])
        if any(payload[k] > current[k] for k in current):
            raise HTTPException(403, "Only superusers can increase rate ceilings")
    row = db.get(AppSetting, "access_rate_limits")
    if row:
        row.value_json = payload
    else:
        db.add(AppSetting(key="access_rate_limits", value_json=payload))
    audit(db, user.id, "settings.change", "rate-limits")
    db.commit()
    return payload


@router.post("/users/{user_id}/password")
def reset_user_password(
    user_id: int,
    payload: PasswordReset,
    user: User = Depends(require_permission("users.change")),
    db: Session = Depends(get_db),
):
    lock_security(db)
    if not superuser(db, user.id):
        raise HTTPException(403, "Superuser required")
    target = db.get(User, user_id)
    if not target or db.get(ServicePrincipal, user_id):
        raise HTTPException(404, "Account not found")
    if len(payload.password.encode("utf-8")) > 72:
        raise HTTPException(422, "Password must not exceed 72 UTF-8 bytes")
    target.password_hash = hash_password(payload.password)
    revoke_principal_sessions(db, user_id)
    audit(db, user.id, "users.password_reset", user_id)
    db.commit()
    return {"ok": True}
