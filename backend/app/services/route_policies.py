"""Explicit route policy registry. Unlisted authenticated routes fail closed."""

POLICIES = {
    "admin": {
        "inventory_list": "inventory.read",
        "device_models": "models.read",
        "device_features": "models.read",
        "create_model": "models.create",
        "update_model": "models.change",
        "delete_model": "models.delete",
        "factory_public_key": "inventory.read",
        "generated_inventory": "inventory.create",
        "session_policy": "settings.read",
        "update_session_policy": "settings.change",
        "dashboard": "dashboard.read",
        "users": "users.read",
        "set_user_active": "users.change",
        "homes": "homes.read",
        "inventory_credentials": "inventory.export_secrets",
        "inventory_config": "inventory.export_secrets",
        "export_devices": "devices.export",
        "resync_device": "inventory.change",
    },
    "devices": {
        "create_pairing_session": "devices.change",
        "my_devices": "devices.read",
        "rename_device": "devices.change",
        "claim_device": "devices.change",
        "activate_device": "device",
        "set_light": "devices.control",
        "audio_play": "devices.control",
        "audio_stop": "devices.control",
        "set_volume": "devices.control",
        "admin_create_device": "inventory.create",
        "admin_list_devices": "devices.read",
        "admin_set_device_disabled": "devices.change",
        "admin_delete_device": "devices.delete",
    },
    "device_operations": {
        "wifi_session": "devices.change",
        "remove_device": "devices.delete",
        "progress": "devices.read",
        "reset_authorization": "devices.delete",
        "completion_authorization": "devices.delete",
        "register_identity": "device",
        "runtime_operations": "device",
        "reset_complete": "device",
    },
    "music": {
        "list_music": "music.read",
        "download_music": "music.export",
        "upload_music": "music.create",
        "admin_list_music": "music.read",
        "admin_set_music_enabled": "music.change",
        "admin_delete_music": "music.delete",
    },
    "schedules": {
        "list_schedules": "schedules.read",
        "create_schedule": "schedules.create",
        "delete_schedule": "schedules.delete",
        "update_schedule": "schedules.change",
    },
    "smart_home": {
        "list_homes": "homes.read",
        "create_home": "homes.create",
        "update_home": "homes.change",
        "delete_home": "homes.delete",
        "list_rooms": "rooms.read",
        "create_room": "rooms.create",
        "update_room": "rooms.change",
        "delete_room": "rooms.delete",
        "list_device_types": "device_types.read",
        "create_device_type": "device_types.create",
        "get_profile": "devices.read",
        "update_profile": "devices.change",
        "get_state": "devices.read",
        "set_state": "devices.change",
        "generic_command": "devices.control",
        "add_telemetry": "devices.change",
        "get_telemetry": "devices.read",
    },
    "widgets": {
        "issue_widget": "devices.read",
        "list_widget_devices": "devices.read",
        "widget_power": "devices.control",
    },
    "auth": {
        "mobile_login": "public",
        "mobile_register": "public",
        "mobile_refresh": "public",
        "mobile_logout": "public",
        "register": "public",
        "login": "public",
        "me": "authenticated",
    },
    "access_control": {
        "catalog": "authenticated",
        "rate_settings": "settings.read",
        "set_rate_settings": "settings.change",
        "list_roles": "roles.read",
        "list_api_roles": "api_roles.read",
        "add_role": "roles.create",
        "add_api_role": "api_roles.create",
        "change_role": "roles.change",
        "change_api_role": "api_roles.change",
        "delete_role": "roles.delete",
        "delete_api_role": "api_roles.delete",
        "users": "users.read",
        "create_user": "users.create",
        "user_roles": "roles.assign",
        "ceiling": "delegation.change",
        "user_active": "users.change",
        "reset_user_password": "users.change",
        "credentials": "api_credentials.read",
        "new_credential": "api_credentials.create",
        "credential_roles": "api_roles.assign",
        "delete_credential": "api_credentials.revoke",
        "sessions": "authenticated",
        "revoke_all": "authenticated",
        "revoke_session": "authenticated",
        "audit_events": "audit.read",
        "exchange": "public",
    },
    "main": {"root": "public", "health": "public"},
}


def policy_for(endpoint):
    return POLICIES.get(endpoint.__module__.split(".")[-1], {}).get(endpoint.__name__)


def enforce_policy(request, context):
    from fastapi import HTTPException

    endpoint = request.scope.get("endpoint")
    policy = policy_for(endpoint) if endpoint else None
    if policy is None:
        raise HTTPException(403, "No authorization policy")
    if (
        policy not in ("authenticated", "public", "device")
        and policy not in context.permissions
    ):
        raise HTTPException(403, "Permission required: " + policy)
    module = endpoint.__module__.split(".")[-1]
    # Administrative bulk data/secret exports require explicitly global API scope.
    if (
        context.auth_method == "api"
        and (module == "admin" or endpoint.__name__.startswith("admin_"))
        and not context.scope.get("all")
    ):
        raise HTTPException(403, "Global API resource scope required")
    if context.auth_method == "api" and endpoint.__name__ in {
        "create_pairing_session",
        "claim_device",
        "wifi_session",
        "remove_device",
        "reset_authorization",
        "completion_authorization",
        "issue_widget",
        "create_home",
        "create_room",
    }:
        raise HTTPException(403, "Interactive owner session required")


def iter_api_routes(routes):
    from fastapi.routing import APIRoute

    for route in routes:
        if isinstance(route, APIRoute):
            yield route
        elif getattr(route, "original_router", None) is not None:
            yield from iter_api_routes(route.original_router.routes)
        elif getattr(route, "routes", None) is not None:
            yield from iter_api_routes(route.routes)


def verify_route_policies(app):
    for route in iter_api_routes(app.routes):
        policy = policy_for(route.endpoint)
        if policy is None:
            raise RuntimeError("Missing authorization policy: " + route.path)
        route.openapi_extra = {
            **(route.openapi_extra or {}),
            "x-lily-permission": policy,
        }
