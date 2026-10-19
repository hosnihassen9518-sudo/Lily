from datetime import datetime, timezone
from fastapi import HTTPException
from sqlalchemy import select, update, delete
from app.models.access_control import (
    Role,
    RoleAssignment,
    GrantCeiling,
    AccessSession,
    ServicePrincipal,
)
from app.models.device_lifecycle import AppSetting, MobileSession
from app.models.user import User
from app.services.permission_catalog import PERMISSIONS, PREDEFINED_ROLES


def validate_permissions(values):
    if not set(values) <= PERMISSIONS:
        raise HTTPException(422, "Unknown permission")
    return sorted(set(values))


def roles_for(db, user_id):
    return db.scalars(
        select(Role)
        .join(RoleAssignment, RoleAssignment.role_key == Role.key)
        .where(RoleAssignment.user_id == user_id)
    ).all()


def effective_permissions(db, user_id):
    roles = roles_for(db, user_id)
    if any(r.key == "superuser" for r in roles):
        return set(PERMISSIONS)
    return set().union(*(set(r.permissions) for r in roles)) if roles else set()


def superuser(db, user_id):
    return db.get(RoleAssignment, (user_id, "superuser")) is not None


def seed_access_control(db):
    for key, (name, permissions) in PREDEFINED_ROLES.items():
        if not db.get(Role, key):
            db.add(
                Role(
                    key=key,
                    name=name,
                    predefined=True,
                    permissions=permissions,
                    audience="portal",
                )
            )
        else:
            role = db.get(Role, key)
            if set(role.permissions) != set(permissions):
                role.permissions = permissions
                role.revision += 1
                for uid in list(db.scalars(select(RoleAssignment.user_id).where(RoleAssignment.role_key == key))):
                    revoke_principal_sessions(db, uid)
    if not db.get(AppSetting, "rbac_lock"):
        db.add(AppSetting(key="rbac_lock", value_json={}))
    db.flush()
    from sqlalchemy import func
    conflicts = list(db.scalars(select(RoleAssignment.user_id).group_by(RoleAssignment.user_id).having(func.count() > 1)))
    for uid in conflicts:
        # Superuser already includes every grant; removing extra assignments
        # preserves existing authority while satisfying the single-role rule.
        if superuser(db, uid) and not db.get(ServicePrincipal, uid):
            db.execute(delete(RoleAssignment).where(
                RoleAssignment.user_id == uid, RoleAssignment.role_key != "superuser"))
            from app.services.access_audit import audit
            audit(db, uid, "roles.single_role_upgrade", uid)
        revoke_principal_sessions(db, uid)
    db.flush()


def edit_role(db, key, values):
    role = db.get(Role, key)
    if not role:
        raise HTTPException(404, "Role not found")
    if role.predefined:
        raise HTTPException(409, "Predefined roles are immutable")
    if "permissions" in values:
        role.permissions = validate_permissions(values["permissions"])
    if "name" in values:
        role.name = values["name"]
    role.revision += 1
    for uid in db.scalars(
        select(RoleAssignment.user_id).where(RoleAssignment.role_key == key)
    ):
        revoke_principal_sessions(db, uid)
    return role


def lock_security(db):
    db.flush()
    # Atomic update serializes security mutations on SQLite as well as PostgreSQL.
    row = db.get(AppSetting, "rbac_lock")
    if not row:
        db.add(AppSetting(key="rbac_lock", value_json={}))
        db.flush()
    db.execute(
        update(AppSetting).where(AppSetting.key == "rbac_lock").values(value_json={})
    )
    db.expire_all()


def protect_last_superuser(db, user_id):
    if not superuser(db, user_id):
        return
    active = list(
        db.scalars(
            select(User.id)
            .join(RoleAssignment, User.id == RoleAssignment.user_id)
            .where(RoleAssignment.role_key == "superuser", User.is_active.is_(True))
        )
    )
    if user_id in active and len(active) <= 1:
        raise HTTPException(409, "Cannot remove the last active superuser")


def revoke_principal_sessions(db, user_id):
    now = datetime.now(timezone.utc)
    principals = {user_id}
    frontier = {user_id}
    while frontier:
        children = (
            set(
                db.scalars(
                    select(ServicePrincipal.user_id).where(
                        ServicePrincipal.issuer_id.in_(frontier)
                    )
                )
            )
            - principals
        )
        principals.update(children)
        frontier = children
    ids = sorted(principals)
    db.execute(
        update(AccessSession)
        .where(AccessSession.user_id.in_(ids), AccessSession.revoked_at.is_(None))
        .values(revoked_at=now)
    )
    db.execute(
        update(MobileSession)
        .where(MobileSession.user_id.in_(ids), MobileSession.revoked_at.is_(None))
        .values(revoked_at=now)
    )


def assign_roles(db, user_id, keys, audience="portal"):
    if len(keys) > 1:
        raise HTTPException(422, "Only one role may be assigned at a time")
    roles = [db.get(Role, k) for k in set(keys)]
    if any(r is None or r.audience != audience for r in roles):
        raise HTTPException(422, "Invalid role audience")
    if superuser(db, user_id) and "superuser" not in keys:
        protect_last_superuser(db, user_id)
    db.execute(delete(RoleAssignment).where(RoleAssignment.user_id == user_id))
    for key in set(keys):
        db.add(RoleAssignment(user_id=user_id, role_key=key))
    revoke_principal_sessions(db, user_id)
    db.flush()


def authorize_grant(db, actor, permissions, target=None):
    if superuser(db, actor.id):
        return
    ceiling = db.get(GrantCeiling, actor.id)
    if target is not None and target != actor.id and ceiling is None:
        raise HTTPException(403, "No delegation ceiling for managing other principals")
    allowed = effective_permissions(db, actor.id) & set(
        ceiling.permissions if ceiling else []
    )
    context = getattr(actor, "_access", None)
    if context:
        allowed &= set(context.permissions)
    if not set(permissions) <= allowed:
        raise HTTPException(403, "Grant exceeds delegated permissions")
    if target is not None and (
        superuser(db, target) or not effective_permissions(db, target) <= allowed
    ):
        raise HTTPException(403, "Cannot manage a higher-privileged principal")


def bootstrap_access(db, email):
    seed_access_control(db)
    if db.get(AppSetting, "rbac_migrated"):
        return
    lock_security(db)
    for user in db.scalars(select(User).where(User.is_admin.is_(True))):
        if not roles_for(db, user.id):
            db.add(RoleAssignment(user_id=user.id, role_key="administrator"))
    user = db.scalar(
        select(User).where(
            User.email == email.lower(),
            User.is_active.is_(True),
            User.is_admin.is_(True),
        )
    )
    if not user:
        raise RuntimeError(
            "RBAC bootstrap administrator not found; run python -m app.services.rbac_recovery --email <existing-active-admin>"
        )
    if not db.get(RoleAssignment, (user.id, "superuser")):
        db.add(RoleAssignment(user_id=user.id, role_key="superuser"))
    db.add(AppSetting(key="rbac_migrated", value_json={"version": "0.9.0"}))
    db.commit()
