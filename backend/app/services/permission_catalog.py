"""Single explicit permission catalog shared by API policies and the portal."""

RESOURCE_ACTIONS = {
    "dashboard": ["read"],
    "users": ["read", "create", "change"],
    "devices": ["read", "change", "delete", "control", "export"],
    "inventory": ["read", "create", "change", "export_secrets"],
    "models": ["read", "create", "change", "delete"],
    "device_types": ["read", "create"],
    "homes": ["read", "create", "change", "delete"],
    "rooms": ["read", "create", "change", "delete"],
    "music": ["read", "create", "change", "delete", "export"],
    "schedules": ["read", "create", "change", "delete"],
    "settings": ["read", "change"],
    "roles": ["read", "create", "change", "delete", "assign"],
    "api_roles": ["read", "create", "change", "delete", "assign"],
    "api_credentials": ["read", "create", "revoke"],
    "sessions": ["read", "revoke"],
    "audit": ["read"],
    "delegation": ["change"],
    "resources": ["all"],
}
PERMISSIONS = frozenset(
    f"{resource}.{action}"
    for resource, actions in RESOURCE_ACTIONS.items()
    for action in actions
)
SECURITY_RESOURCES = {
    "roles",
    "api_roles",
    "api_credentials",
    "sessions",
    "delegation",
    "audit",
    "resources",
}
OPERATIONAL = {
    p
    for p in PERMISSIONS
    if p.split(".")[0] not in SECURITY_RESOURCES and not p.endswith("export_secrets")
}
MOBILE_PERMISSIONS = frozenset(
    {
        p
        for p in OPERATIONAL
        if p.split(".")[0]
        in {"devices", "homes", "rooms", "music", "schedules", "device_types"}
    }
)
PREDEFINED_ROLES = {
    "superuser": ("Superuser", sorted(PERMISSIONS)),
    "administrator": ("Administrator", sorted(OPERATIONAL)),
    "operator": (
        "Operator",
        sorted(
            {
                p
                for p in OPERATIONAL
                if p.endswith(".read") and p.split(".")[0] not in {"users", "settings"}
            }
            | {
                "devices.control",
                "schedules.create",
                "schedules.change",
                "schedules.delete",
            }
        ),
    ),
    "read_only": (
        "Read-only",
        sorted(
            p
            for p in OPERATIONAL
            if p.endswith(".read") and p.split(".")[0] not in {"users", "settings"}
        ),
    ),
}
