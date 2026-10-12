import os
os.environ['DATABASE_URL'] = 'sqlite://'
os.environ['MQTT_ENABLED'] = 'false'
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool
from fastapi.testclient import TestClient
from app.db.session import Base, get_db
import app.models
from app.main import app
from app.models.user import User
from app.core.security import create_access_token

@pytest.fixture
def db():
    postgres=os.environ.get('LILY_TEST_DATABASE_URL')
    if postgres:
        import secrets
        schema='lily_test_'+secrets.token_hex(6)
        control=create_engine(postgres)
        with control.begin() as conn: conn.exec_driver_sql(f'CREATE SCHEMA "{schema}"')
        engine=create_engine(postgres,connect_args={'options':f'-csearch_path={schema}'})
    else:
        engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session
    engine.dispose()
    if postgres:
        with control.begin() as conn: conn.exec_driver_sql(f'DROP SCHEMA "{schema}" CASCADE')
        control.dispose()

@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as value:
        yield value
    app.dependency_overrides.clear()

@pytest.fixture
def admin(db):
    user = User(email='admin@test.org', password_hash='unused', is_admin=True, is_active=True)
    db.add(user); db.commit()
    return {'Authorization': 'Bearer ' + create_access_token(str(user.id))}

@pytest.fixture
def owner(db):
    user = User(email='owner@test.org', password_hash='unused', is_active=True)
    db.add(user); db.commit()
    return user, {'Authorization': 'Bearer ' + create_access_token(str(user.id))}
