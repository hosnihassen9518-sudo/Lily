from sqlalchemy import create_engine, inspect, select
from app.db.session import Base
from app.models.device import Device

def test_upgrade_preserves_existing_inventory(tmp_path):
    from app.db.migrations import upgrade_database
    engine = create_engine('sqlite:///' + str(tmp_path / 'existing.db'))
    Base.metadata.create_all(engine)
    with engine.begin() as conn:
        conn.execute(Device.__table__.insert().values(serial_number='OLD-1', secret_hash='original-hash', model='UNKNOWN'))
    upgrade_database(engine)
    upgrade_database(engine)
    assert {'device_models', 'app_settings', 'mobile_sessions', 'device_operations', 'device_identities', 'alembic_version'} <= set(inspect(engine).get_table_names())
    with engine.connect() as conn:
        row = conn.execute(select(Device.serial_number, Device.secret_hash, Device.model)).one()
        assert tuple(row) == ('OLD-1', 'original-hash', 'UNKNOWN')

def test_catalog_seeds_only_supported_models(db):
    from app.services.device_inventory import seed_models
    from app.models.device_lifecycle import DeviceModel
    seed_models(db); seed_models(db)
    assert set(db.scalars(select(DeviceModel.key))) == {'lily_v1', 'lily_test_light', 'lily_led_strip'}
