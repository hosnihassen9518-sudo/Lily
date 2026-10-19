from app.models.user import User
from app.models.access_control import Role
from app.services.rbac import seed_access_control, assign_roles
from app.services.access_sessions import issue_session


def reader(db):
    seed_access_control(db)
    user = User(email="reader@test.org", password_hash="unused", is_admin=True)
    db.add(user)
    db.flush()
    assign_roles(db, user.id, ["read_only"])
    db.commit()
    return {"Authorization": "Bearer " + issue_session(db, user)["access_token"]}


def test_read_only_cannot_change_models(client, db):
    headers = reader(db)
    assert client.get("/api/v1/admin/device-models", headers=headers).status_code == 200
    response = client.post(
        "/api/v1/admin/device-models",
        headers=headers,
        json={
            "key": "bad_model",
            "name": "Bad",
            "device_type_id": 1,
            "firmware_target": "esp32_device",
        },
    )
    assert response.status_code == 403


def test_all_routes_have_explicit_policy():
    from app.main import app
    from app.services.route_policies import policy_for, iter_api_routes
    from fastapi.routing import APIRoute

    routes = list(iter_api_routes(app.routes))
    assert len(routes) > 90

    def dependencies(dep):
        yield getattr(dep.call, "__name__", "")
        for child in dep.dependencies:
            yield from dependencies(child)

    for route in routes:
        policy = policy_for(route.endpoint)
        assert policy is not None, route.path
        if policy not in ("public", "device"):
            assert {"get_current_user", "widget_user"} & set(
                dependencies(route.dependant)
            ), route.path
