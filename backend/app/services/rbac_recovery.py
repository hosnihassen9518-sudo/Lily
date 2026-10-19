"""Explicit offline recovery; requires access to the server database configuration."""

import argparse
from sqlalchemy import select
from app.db.session import SessionLocal
from app.models.user import User
from app.services.rbac import seed_access_control, lock_security, assign_roles


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--email", required=True)
    args = parser.parse_args()
    with SessionLocal() as db:
        seed_access_control(db)
        lock_security(db)
        user = db.scalar(
            select(User).where(
                User.email == args.email.lower(), User.is_active.is_(True)
            )
        )
        if not user:
            raise SystemExit("An existing active account is required")
        assign_roles(db, user.id, ["superuser"])
        user.is_admin = True
        from app.models.device_lifecycle import AppSetting
        from app.services.access_audit import audit

        if not db.get(AppSetting, "rbac_migrated"):
            db.add(
                AppSetting(
                    key="rbac_migrated",
                    value_json={"version": "0.9.0", "recovered": True},
                )
            )
        audit(db, user.id, "delegation.recovery", user.id)
        db.commit()
        print("Superuser access restored. Sign in again.")


if __name__ == "__main__":
    main()
