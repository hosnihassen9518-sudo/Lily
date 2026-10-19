import pytest
from fastapi import HTTPException


def test_exact_limit_and_reset(db):
    from app.services.rate_limits import consume_limit

    consume_limit(db, "test", 2, 60, now=100)
    consume_limit(db, "test", 2, 60, now=100)
    with pytest.raises(HTTPException) as error:
        consume_limit(db, "test", 2, 60, now=100)
    assert (
        error.value.status_code == 429 and int(error.value.headers["Retry-After"]) == 60
    )
    consume_limit(db, "test", 2, 60, now=160)


def test_buckets_are_shared_between_calls(db):
    from app.services.rate_limits import consume_limit

    consume_limit(db, "shared", 1, 60, now=100)
    db.expire_all()
    with pytest.raises(HTTPException):
        consume_limit(db, "shared", 1, 60, now=101)


def test_untrusted_forwarded_https_is_rejected(client, db, admin, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "environment", "production")
    assert (
        client.get(
            "/api/v1/auth/me", headers={**admin, "X-Forwarded-Proto": "https"}
        ).status_code
        == 400
    )


def test_registration_is_throttled(client):
    for i in range(10):
        response = client.post(
            "/api/v1/auth/register",
            json={"email": f"invalid{i}@test.org", "password": "a-long-test-password"},
        )
        assert response.status_code == 200
    assert (
        client.post(
            "/api/v1/auth/register",
            json={"email": "extra@test.org", "password": "a-long-test-password"},
        ).status_code
        == 429
    )


def test_parallel_workers_share_one_atomic_bucket(tmp_path):
    from concurrent.futures import ThreadPoolExecutor
    from sqlalchemy import create_engine
    from sqlalchemy.orm import Session
    from app.db.session import Base
    from app.services.rate_limits import consume_limit

    engine = create_engine(
        "sqlite:///" + str(tmp_path / "rate.db"),
        connect_args={"check_same_thread": False, "timeout": 10},
    )
    Base.metadata.create_all(engine)

    def hit(i):
        with Session(engine) as db:
            try:
                consume_limit(db, "parallel", 3, 60, now=100)
                return 200
            except HTTPException as error:
                return error.status_code

    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(hit, range(12)))
    assert results.count(200) == 3 and results.count(429) == 9


def test_production_http_can_be_explicitly_enabled(client, admin, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "environment", "production")
    monkeypatch.setattr(settings, "require_https", False)
    assert client.get("/api/v1/auth/me", headers=admin).status_code == 200


def test_mobile_light_drag_has_its_own_bounded_budget(db, monkeypatch):
    monkeypatch.setattr("app.services.rate_limits.time.time", lambda: 1000)
    from types import SimpleNamespace
    from starlette.requests import Request
    from app.services.rate_limits import session_limit
    from app.api.devices import set_light
    from app.models.user import User
    user = User(email="smooth@test.org",password_hash="unused")
    db.add(user); db.commit()
    # A direct context suffices: authentication and ownership are tested separately.
    context = SimpleNamespace(session_id="smooth-session",auth_method="mobile",principal=user)
    request = Request({"type":"http","method":"PUT","path":"/api/v1/devices/1/light","scheme":"http","headers":[],"endpoint":set_light,"client":("127.0.0.1",123)})
    for _ in range(10): session_limit(db,request,context)
    with pytest.raises(HTTPException) as error: session_limit(db,request,context)
    assert error.value.status_code == 429


def test_mobile_light_drag_exceeds_sensitive_write_budget_but_remains_limited(db, monkeypatch):
    from types import SimpleNamespace
    from starlette.requests import Request
    from app.services.rate_limits import session_limit
    from app.api.devices import set_light
    from app.models.user import User
    from app.models.device_lifecycle import AppSetting
    clock = [1000]
    monkeypatch.setattr("app.services.rate_limits.time.time",lambda:clock[0])
    user = User(email="dragbudget@test.org",password_hash="unused")
    db.add(user); db.add(AppSetting(key="access_rate_limits",value_json={"light_controls":35})); db.commit()
    context = SimpleNamespace(session_id="drag-session",auth_method="mobile",principal=user)
    request = Request({"type":"http","method":"PUT","path":"/api/v1/devices/1/light","scheme":"http","headers":[],"endpoint":set_light,"client":("127.0.0.1",123)})
    for i in range(35):
        clock[0] = 1000 + i // 4
        session_limit(db,request,context)
    with pytest.raises(HTTPException) as error: session_limit(db,request,context)
    assert error.value.status_code == 429
    # Other mobile writes still use the sensitive limit.
    request.scope['endpoint'] = lambda: None
    for _ in range(30): session_limit(db,request,context)
    with pytest.raises(HTTPException): session_limit(db,request,context)
