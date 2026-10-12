import os
import pytest
from sqlalchemy import inspect

@pytest.mark.skipif(not os.environ.get('LILY_TEST_DATABASE_URL'),reason='Disposable PostgreSQL test service is not configured')
def test_postgres_baseline_and_idempotent_upgrade(db):
    from app.db.migrations import upgrade_database
    engine=db.get_bind()
    db.close()
    from app.db.session import Base
    Base.metadata.drop_all(engine)
    upgrade_database(engine);upgrade_database(engine)
    assert {'devices','device_identities','device_operations','mobile_sessions','alembic_version'}<=set(inspect(engine).get_table_names())
