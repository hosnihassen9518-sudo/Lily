"""Explicit offline account classification; preserves passwords and device ownership."""
import argparse
from sqlalchemy import select
from app.db.session import SessionLocal
from app.models.user import User
from app.models.access_control import ServicePrincipal
from app.services.rbac import seed_access_control, lock_security, assign_roles, roles_for, protect_last_superuser, revoke_principal_sessions
from app.services.access_audit import audit


def classify(db, mobile_emails, admin_emails):
    mobile_emails = [email.strip().lower() for email in mobile_emails]
    admin_emails = [email.strip().lower() for email in admin_emails]
    if set(mobile_emails) & set(admin_emails):
        raise ValueError("An account cannot have both types")
    seed_access_control(db)
    lock_security(db)
    # Existing administrators retain their assigned role; never promote to Superuser.
    for email in admin_emails:
        user = db.scalar(select(User).where(User.email == email.lower()))
        if not user or db.get(ServicePrincipal, user.id):
            raise ValueError(f"Existing account required: {email}")
        user.is_admin = True
        if not roles_for(db, user.id):
            assign_roles(db, user.id, ["administrator"])
        revoke_principal_sessions(db, user.id)
        audit(db, user.id, "accounts.classify_admin", user.id)
    for email in mobile_emails:
        user = db.scalar(select(User).where(User.email == email.lower()))
        if not user or db.get(ServicePrincipal, user.id):
            raise ValueError(f"Existing account required: {email}")
        protect_last_superuser(db, user.id)
        assign_roles(db, user.id, [])
        user.is_admin = False
        revoke_principal_sessions(db, user.id)
        audit(db, user.id, "accounts.classify_mobile", user.id)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mobile", action="append", default=[])
    parser.add_argument("--administrator", action="append", default=[])
    args = parser.parse_args()
    with SessionLocal() as db:
        classify(db, args.mobile, args.administrator)
        db.commit()
    print("Account types saved. Affected accounts must sign in again.")


if __name__ == "__main__":
    main()
