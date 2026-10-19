import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from app.db.session import Base
from app.models.user import User
from app.models.device_lifecycle import AppSetting
from app.models.access_control import Role, RoleAssignment
from app.services.rbac import bootstrap_access, seed_access_control


def test_bootstrap_promotes_only_configured_admin_once(db):
    configured = User(email="bootstrap@test.org", password_hash="unused", is_admin=True)
    other = User(email="older@test.org", password_hash="unused", is_admin=True)
    db.add_all([configured, other])
    db.commit()
    bootstrap_access(db, configured.email)
    assert db.get(RoleAssignment, (configured.id, "superuser"))
    assert not db.get(RoleAssignment, (other.id, "superuser"))
    assert db.get(RoleAssignment, (other.id, "administrator"))
    configured.is_active = False
    db.commit()
    bootstrap_access(db, configured.email)
    assert not configured.is_active


def test_bootstrap_missing_admin_requires_recovery(db):
    with pytest.raises(RuntimeError, match="rbac_recovery"):
        bootstrap_access(db, "missing@test.org")


def test_migration_is_additive_and_repeatable(tmp_path):
    from app.db.migrations import upgrade_database
    from sqlalchemy import inspect

    engine = create_engine("sqlite:///" + str(tmp_path / "upgrade.db"))
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add(User(email="preserved@test.org", password_hash="preserved"))
        db.commit()
    upgrade_database(engine)
    upgrade_database(engine)
    assert {"access_roles", "access_sessions", "access_api_credentials"} <= set(
        inspect(engine).get_table_names()
    )
    with Session(engine) as db:
        assert db.scalar(select(User.password_hash)) == "preserved"
