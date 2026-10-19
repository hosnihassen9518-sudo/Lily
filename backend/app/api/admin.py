from app.services.access_sessions import can_manage_device, can_access_home
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import require_admin, get_current_user
from app.db.session import get_db
from app.models.device import Device
from app.models.music import Music
from app.models.home import Home, Room
from app.models.smart_device import DeviceTelemetry, DeviceType
from app.models.user import User
from app.models.access_control import ServicePrincipal
from app.schemas.admin import ActiveUpdate
from pydantic import BaseModel, Field
from app.models.device_lifecycle import DeviceModel
from app.services.device_features import (
    FEATURES,
    model_capabilities,
    validate_capabilities,
)
from pydantic import ConfigDict


class ModelCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    key: str = Field(min_length=1, max_length=80, pattern=r"^[a-z0-9_\-]+$")
    name: str = Field(min_length=1, max_length=80)
    device_type_id: int
    hardware_version: str = Field(default="1.0", min_length=1, max_length=50)
    firmware_target: str
    capabilities: list[str] | None = None


class ModelUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = Field(default=None, min_length=1, max_length=80)
    hardware_version: str | None = Field(default=None, min_length=1, max_length=50)
    device_type_id: int | None = None
    firmware_target: str | None = None
    capabilities: list[str] | None = None


def serialize_model(db, model):
    return {
        **{
            key: getattr(model, key)
            for key in (
                "key",
                "name",
                "device_type_id",
                "hardware_version",
                "firmware_target",
            )
        },
        "capabilities": model_capabilities(db, model),
    }


def validate_model(db, dtype_id, target):
    dtype = db.get(DeviceType, dtype_id)
    if not dtype:
        raise HTTPException(422, "Unknown device type")
    expected = {"lily_audio_light": "esp32_device", "test_light": "esp32_test_light"}
    if target not in expected.values() or (
        dtype.key in expected and target != expected[dtype.key]
    ):
        raise HTTPException(422, "Firmware target does not match device type")


def model_in_use(db, model):
    from app.models.smart_device import DeviceProfile

    return any(
        (p.metadata_json or {}).get("model_key") == model.key
        for p in db.scalars(select(DeviceProfile))
    ) or bool(
        db.scalar(
            select(Device.id).where(Device.model.in_([model.key, model.name])).limit(1)
        )
    )


class InventoryCreate(BaseModel):
    device_type_id: int
    model_key: str
    name: str | None = None


from pydantic import Field


class SessionPolicy(BaseModel):
    months: int = Field(strict=True, ge=1, le=12)


router = APIRouter(
    prefix="/admin",
    tags=["admin"],
    dependencies=[Depends(require_admin)],
)


@router.get("/device-models")
def device_models(device_type_id: int | None = None, db: Session = Depends(get_db)):
    query = select(DeviceModel)
    if device_type_id is not None:
        query = query.where(DeviceModel.device_type_id == device_type_id)
    return [serialize_model(db, m) for m in db.scalars(query)]


@router.get("/device-features")
def device_features():
    return FEATURES


@router.post("/device-models")
def create_model(payload: ModelCreate, db: Session = Depends(get_db)):
    if db.get(DeviceModel, payload.key):
        raise HTTPException(409, "Model key already exists")
    validate_model(db, payload.device_type_id, payload.firmware_target)
    values = payload.model_dump()
    values["capabilities"] = validate_capabilities(payload.capabilities)
    model = DeviceModel(**values)
    db.add(model)
    db.commit()
    return serialize_model(db, model)


@router.patch("/device-models/{key}")
def update_model(key: str, payload: ModelUpdate, db: Session = Depends(get_db)):
    model = db.scalar(
        select(DeviceModel).where(DeviceModel.key == key).with_for_update()
    )
    if not model:
        raise HTTPException(404, "Model not found")
    values = payload.model_dump(exclude_unset=True)
    if any(value is None for field, value in values.items() if field != "capabilities"):
        raise HTTPException(422, "Model fields cannot be null")
    if model_in_use(db, model) and any(
        field in values and values[field] != getattr(model, field)
        for field in ("device_type_id", "hardware_version", "firmware_target")
    ):
        raise HTTPException(
            409, "Factory associations cannot change for a model in use"
        )
    validate_model(
        db,
        values.get("device_type_id", model.device_type_id),
        values.get("firmware_target", model.firmware_target),
    )
    if "capabilities" in values:
        values["capabilities"] = validate_capabilities(values["capabilities"])
    from app.services.device_features import associated_model
    from app.models.smart_device import DeviceProfile

    linked_devices = []
    for device in db.scalars(
        select(Device).order_by(Device.id).with_for_update()
    ).all():
        linked = associated_model(db, device)
        if linked is None or linked.key != model.key:
            continue
        linked_devices.append(device)
        profile = db.get(DeviceProfile, device.id)
        if profile is None:
            profile = DeviceProfile(
                device_id=device.id, device_type_id=model.device_type_id
            )
            db.add(profile)
        profile.metadata_json = {
            **(profile.metadata_json or {}),
            "model_key": model.key,
        }
    for field, value in values.items():
        setattr(model, field, value)
    pending = []
    if "capabilities" in values:
        from app.services.feature_schedule_sync import mark_pending, flush_pending

        for device in linked_devices:
            mark_pending(db, device)
            if not flush_pending(db, device):
                pending.append(device.id)
    db.commit()
    return {**serialize_model(db, model), "schedule_sync_pending": pending}


@router.delete("/device-models/{key}")
def delete_model(key: str, db: Session = Depends(get_db)):
    model = db.scalar(
        select(DeviceModel).where(DeviceModel.key == key).with_for_update()
    )
    if not model:
        raise HTTPException(404, "Model not found")
    if model_in_use(db, model):
        raise HTTPException(409, "Model is in use")
    db.delete(model)
    db.commit()
    return {"ok": True}


@router.get("/device-factory-public-key")
def factory_public_key(db: Session = Depends(get_db)):
    from app.services.device_authorization import prepare_signing_key, public_pem

    return {"public_key": public_pem(prepare_signing_key(db).public_key())}


@router.post("/device-inventory")
def generated_inventory(
    payload: InventoryCreate,
    actor: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from app.services.device_inventory import create_inventory

    result = create_inventory(db, payload.device_type_id, payload.model_key, name=payload.name)
    if "inventory.export_secrets" not in actor._access.permissions:
        result = {
            k: v
            for k, v in result.items()
            if k not in {"device_secret", "config_header"}
        }
    return result


@router.get("/mobile-session-policy")
def session_policy(db: Session = Depends(get_db)):
    from app.services.mobile_sessions import months_policy

    return {"months": months_policy(db)}


@router.patch("/mobile-session-policy")
def update_session_policy(payload: SessionPolicy, db: Session = Depends(get_db)):
    from app.models.device_lifecycle import AppSetting

    row = db.get(AppSetting, "mobile_session_months")
    if row is None:
        row = AppSetting(key="mobile_session_months", value_json={})
        db.add(row)
    row.value_json = {"months": payload.months}
    db.commit()
    return row.value_json


@router.get("/dashboard")
def dashboard(db: Session = Depends(get_db)):
    return {
        "users": db.scalar(select(func.count()).select_from(User).where(User.is_admin.is_(False), User.id.not_in(select(ServicePrincipal.user_id)))),
        "devices_total": db.scalar(select(func.count()).select_from(Device)),
        "devices_online": db.scalar(
            select(func.count()).select_from(Device).where(Device.is_online == True)
        ),
        "devices_inventory": db.scalar(
            select(func.count()).select_from(Device).where(Device.owner_id == None)
        ),
        "music_tracks": db.scalar(select(func.count()).select_from(Music)),
        "homes": db.scalar(select(func.count()).select_from(Home)),
        "rooms": db.scalar(select(func.count()).select_from(Room)),
        "device_types": db.scalar(select(func.count()).select_from(DeviceType)),
        "telemetry_points": db.scalar(
            select(func.count()).select_from(DeviceTelemetry)
        ),
    }


@router.get("/users")
def users(db: Session = Depends(get_db)):
    from app.models.access_control import ServicePrincipal
    rows = db.scalars(select(User).where(User.is_admin.is_(False), User.id.not_in(select(ServicePrincipal.user_id))).order_by(User.created_at.desc())).all()
    return [
        {
            "id": user.id,
            "email": user.email,
            "first_name": user.first_name,
            "last_name": user.last_name,
            "active": user.is_active,
            "admin": user.is_admin,
            "created_at": user.created_at,
        }
        for user in rows
    ]


@router.patch("/users/{user_id}/active")
def set_user_active(
    user_id: int,
    payload: ActiveUpdate,
    actor: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from app.models.access_control import ServicePrincipal
    from app.services.rbac import lock_security, revoke_principal_sessions
    from app.services.access_audit import audit
    lock_security(db)
    target = db.get(User, user_id)
    if not target or target.is_admin or db.get(ServicePrincipal, user_id):
        raise HTTPException(404, "User not found")
    target.is_active = payload.active
    revoke_principal_sessions(db, user_id)
    audit(db, actor.id, "users.change", user_id)
    db.commit()
    return {"ok": True}


@router.get("/homes")
def homes(actor: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.scalars(select(Home).order_by(Home.created_at.desc())).all()
    result = []
    for home in rows:
        if not can_access_home(actor, home):
            continue
        owner = db.get(User, home.owner_id)
        room_count = (
            db.scalar(
                select(func.count()).select_from(Room).where(Room.home_id == home.id)
            )
            or 0
        )
        from app.models.smart_device import DeviceProfile

        device_count = (
            db.scalar(
                select(func.count())
                .select_from(DeviceProfile)
                .where(DeviceProfile.home_id == home.id)
            )
            or 0
        )
        result.append(
            {
                "id": home.id,
                "name": home.name,
                "timezone": home.timezone,
                "owner_id": home.owner_id,
                "owner_email": owner.email if owner else None,
                "rooms": room_count,
                "devices": device_count,
                "created_at": home.created_at,
            }
        )
    return result


@router.get("/device-inventory/{device_id}/credentials")
def inventory_credentials(
    device_id: int,
    actor: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not can_manage_device(
        db, actor, db.get(Device, device_id), "inventory.export_secrets"
    ):
        raise HTTPException(404, "Device not found")
    from app.services.provisioning_archive import stored_config
    from fastapi.responses import JSONResponse

    data = stored_config(db, device_id)
    return JSONResponse(
        {
            "serial_number": data["serial_number"],
            "device_secret": data["device_secret"],
        },
        headers={"Cache-Control": "no-store"},
    )


@router.get("/device-inventory/{device_id}/config")
def inventory_config(
    device_id: int,
    actor: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not can_manage_device(
        db, actor, db.get(Device, device_id), "inventory.export_secrets"
    ):
        raise HTTPException(404, "Device not found")
    from app.services.provisioning_archive import stored_config
    from fastapi.responses import Response

    data = stored_config(db, device_id)
    return Response(
        data["config_header"],
        media_type="text/plain",
        headers={
            "Content-Disposition": 'attachment; filename="' + data["filename"] + '"',
            "Cache-Control": "no-store",
        },
    )


EXPORT_FIELDS = [
    "id",
    "serial_number",
    "name",
    "model",
    "hardware_version",
    "status",
    "owner_id",
    "device_type",
    "home_id",
    "room_id",
    "firmware_version",
    "online",
    "last_seen",
    "last_connected_at",
    "last_disconnected_at",
    "activated_at",
    "created_at",
    "wifi_rssi",
    "free_heap",
    "free_storage",
    "light_enabled",
    "brightness",
    "color_r",
    "color_g",
    "color_b",
    "audio_loaded",
    "audio_playing",
    "volume",
]


@router.get("/devices/export.csv")
def export_devices(
    fields: str | None = None,
    actor: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    import csv, io
    from app.api.devices import serialize_device
    from app.services.provisioning_archive import stored_config
    from fastapi.responses import Response

    columns = fields.split(",") if fields is not None else EXPORT_FIELDS
    if (
        not columns
        or len(columns) != len(set(columns))
        or any(c not in EXPORT_FIELDS + ["device_secret"] for c in columns)
    ):
        raise HTTPException(422, "Select valid, distinct export fields.")
    if (
        "device_secret" in columns
        and "inventory.export_secrets" not in actor._access.permissions
    ):
        raise HTTPException(403, "Secret export permission required")
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(columns)
    for d in db.scalars(select(Device).order_by(Device.id)):
        if not can_manage_device(db, actor, d):
            continue
        data = serialize_device(d, db)
        row = {c: getattr(d, c, None) for c in EXPORT_FIELDS}
        row.update(
            status=data["status"],
            online=data["online"],
            device_type=data["smart_home"]["device_type_name"],
            home_id=data["smart_home"]["home_id"],
            room_id=data["smart_home"]["room_id"],
            light_enabled=d.light_on,
        )
        if "device_secret" in columns:
            try:
                row["device_secret"] = stored_config(db, d.id)["device_secret"]
            except HTTPException as error:
                if error.status_code != 409:
                    raise
                row["device_secret"] = ""
        values = []
        for c in columns:
            value = row.get(c)
            if isinstance(value, str) and value.lstrip().startswith(
                ("=", "+", "-", "@")
            ):
                value = "'" + value
            values.append(value)
        writer.writerow(values)
    return Response(
        output.getvalue(),
        media_type="text/csv",
        headers={
            "Content-Disposition": 'attachment; filename="lily-devices.csv"',
            "Cache-Control": "no-store",
        },
    )


@router.post("/device-inventory/{device_id}/resync")
def resync_device(
    device_id: int,
    actor: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from app.api.device_operations import (
        locked_device,
        require_mutable,
        device_generation,
    )
    from app.api.schedules import sync_device_schedule
    from app.services.mqtt_service import mqtt_service

    device = locked_device(db, device_id=device_id)
    if not can_manage_device(db, actor, device, "inventory.change"):
        raise HTTPException(404, "Device not found")
    require_mutable(device)
    if not device.is_online:
        raise HTTPException(409, "Device is offline. Reconnect it before resyncing.")
    if not sync_device_schedule(db, device):
        raise HTTPException(503, "Broker unavailable. Schedules were not resent.")
    sent = mqtt_service.publish_command(
        device.serial_number,
        {"type": "status_request"},
        generation=device_generation(db, device),
    )
    if not sent:
        raise HTTPException(503, "Broker unavailable. Resync was not sent.")
    db.commit()
    return {
        "ok": True,
        "detail": "State refresh requested and schedules resent. Credentials unchanged.",
    }


@router.get("/inventory")
def inventory_list(db: Session = Depends(get_db)):
    from app.api.devices import serialize_device

    return [
        serialize_device(d, db)
        for d in db.scalars(
            select(Device).where(Device.owner_id.is_(None)).order_by(Device.id)
        )
    ]
