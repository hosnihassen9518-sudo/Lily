from app.models.user import User
from app.core.security import hash_password


def test_account_lists_are_separate_and_admin_cannot_use_mobile_login(client, db, admin):
    consumer = User(email="hassen@example.com", password_hash=hash_password("consumer-password"), is_admin=False)
    db.add(consumer); db.commit()
    admins = client.get("/api/v1/access/users", headers=admin).json()
    users = client.get("/api/v1/admin/users", headers=admin).json()
    assert consumer.email not in [u["email"] for u in admins]
    assert [u["email"] for u in users] == [consumer.email]
    assert client.post("/api/v1/auth/login", json={"email":consumer.email,"password":"consumer-password"}).status_code == 401
    assert client.post("/api/v1/auth/mobile/login", json={"email":consumer.email,"password":"consumer-password"}).status_code == 200
    account = db.query(User).filter_by(email="admin@test.org").one()
    account.password_hash = hash_password("admin-password"); db.commit()
    assert client.post("/api/v1/auth/mobile/login", json={"email":account.email,"password":"admin-password"}).status_code == 401


def test_administrator_can_manage_users_but_not_administrator_accounts(client, db):
    from app.services.rbac import seed_access_control, assign_roles
    from app.services.access_sessions import issue_session
    seed_access_control(db)
    actor = User(email="operatoradmin@test.org", password_hash="unused", is_admin=True)
    consumer = User(email="consumer@test.org", password_hash="unused")
    db.add_all([actor,consumer]); db.flush(); assign_roles(db,actor.id,["administrator"]); db.commit()
    headers = {"Authorization":"Bearer "+issue_session(db,actor)["access_token"]}
    assert client.get("/api/v1/admin/users", headers=headers).status_code == 200
    assert client.get("/api/v1/access/users", headers=headers).status_code == 403
    assert client.patch(f"/api/v1/admin/users/{consumer.id}/active", headers=headers,json={"active":False}).status_code == 200
    assert client.patch(f"/api/v1/admin/users/{actor.id}/active", headers=headers,json={"active":False}).status_code == 404


def test_classification_preserves_password_and_device_owner(db):
    from app.models.device import Device
    from app.services.account_classification import classify
    from app.services.rbac import seed_access_control, assign_roles, roles_for
    seed_access_control(db)
    user = User(email="hassen@example.com", password_hash="original", is_admin=True)
    admin = User(email="admin@example.com", password_hash="admin-original", is_admin=True)
    codex = User(email="codex@example.com", password_hash="codex-original", is_admin=True)
    db.add_all([user,admin,codex]); db.flush()
    assign_roles(db,admin.id,["superuser"])
    assign_roles(db,user.id,["administrator"])
    device = Device(serial_number="ACCOUNT-TEST",secret_hash="unused",owner_id=user.id)
    db.add(device); db.commit()
    classify(db,[user.email],[admin.email,codex.email]); db.commit()
    assert not user.is_admin and not roles_for(db,user.id)
    assert user.password_hash == "original" and device.owner_id == user.id
    assert [r.key for r in roles_for(db,admin.id)] == ["superuser"]
    assert [r.key for r in roles_for(db,codex.id)] == ["administrator"]


def test_old_custom_account_grants_keep_their_administrator_meaning(db):
    from app.models.access_control import Role
    from app.models.device_lifecycle import AppSetting
    from app.services.rbac import seed_access_control
    seed_access_control(db)
    db.delete(db.get(AppSetting,"separate_account_permissions_v1"))
    role = Role(key="old_account_manager",name="Old manager",audience="portal",permissions=["users.read","devices.read"])
    db.add(role); db.flush()
    seed_access_control(db)
    assert set(role.permissions) == {"administrators.read","devices.read"}
    role.permissions = ["users.read"]
    seed_access_control(db)
    assert role.permissions == ["users.read"]


def test_permission_migration_translates_delegation_ceilings(db):
    from app.models.access_control import GrantCeiling
    from app.models.device_lifecycle import AppSetting
    from app.services.rbac import seed_access_control
    seed_access_control(db)
    db.delete(db.get(AppSetting,"separate_account_permissions_v1"))
    user = User(email="delegated@test.org",password_hash="unused",is_admin=True)
    db.add(user); db.flush()
    ceiling = GrantCeiling(user_id=user.id,permissions=["users.change","devices.read"])
    db.add(ceiling); db.flush()
    seed_access_control(db)
    assert set(ceiling.permissions) == {"administrators.change","devices.read"}


def test_startup_persists_permission_upgrade_on_existing_installation(tmp_path, monkeypatch):
    from sqlalchemy import create_engine
    from sqlalchemy.orm import Session
    from app.db.session import Base
    from app.models.device_lifecycle import AppSetting
    from app.models.access_control import Role
    from app.core.config import settings
    import app.main as main
    engine = create_engine("sqlite:///" + str(tmp_path / "accounts.db"))
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add(User(email="admin@example.com",password_hash="preserved",is_admin=True))
        db.add(AppSetting(key="rbac_migrated",value_json={"version":"0.9.0"}))
        db.add(Role(key="legacy_manager",name="Legacy",audience="portal",permissions=["users.read"]))
        db.commit()
    monkeypatch.setattr(main,"engine",engine)
    monkeypatch.setattr(main,"SessionLocal",lambda:Session(engine))
    monkeypatch.setattr(settings,"admin_email","admin@example.com")
    monkeypatch.setattr(settings,"music_dir",str(tmp_path / "music"))
    main.bootstrap()
    with Session(engine) as db:
        assert db.get(AppSetting,"separate_account_permissions_v1") is not None
        assert db.get(Role,"legacy_manager").permissions == ["administrators.read"]
    engine.dispose()
