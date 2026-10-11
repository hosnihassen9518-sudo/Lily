from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, require_admin
from app.core.security import hash_password, verify_password, create_pairing_token, decode_token
from app.db.session import get_db
from app.models.device import Device
from app.models.user import User
from app.models.home import Home
from app.models.smart_device import DeviceProfile, DeviceType, DeviceTypeCapability, DeviceState
from app.schemas.admin import DisabledUpdate
from app.schemas.device import (
    DeviceActivate,
    DeviceClaim,
    DeviceCreate,
    DeviceRename,
    LightCommand,
    VolumeCommand,
)
from app.services.mqtt_service import mqtt_service

router = APIRouter(prefix="/devices", tags=["devices"])


def ensure_smart_profile(db: Session, device: Device, user_id: int):
    home = db.scalar(select(Home).where(Home.owner_id == user_id).order_by(Home.id))
    if not home:
        home = Home(owner_id=user_id, name="My Home", timezone="Europe/Paris")
        db.add(home)
        db.flush()

    profile = db.get(DeviceProfile, device.id)
    if not profile:
        dtype = db.scalar(select(DeviceType).where(DeviceType.key == "lily_audio_light"))
        profile = DeviceProfile(
            device_id=device.id,
            home_id=home.id,
            device_type_id=dtype.id if dtype else None,
        )
        db.add(profile)
    elif profile.home_id is None:
        profile.home_id = home.id
    return profile

def serialize_device(device: Device, db: Session | None = None):
    if device.lifecycle_status == "DISABLED":
        display_status = "DISABLED"
    elif device.owner_id is None:
        display_status = "INVENTORY"
    elif device.is_online:
        display_status = "ONLINE"
    else:
        display_status = "OFFLINE"

    smart_home = {
        "home_id": None,
        "room_id": None,
        "device_type_id": None,
        "device_type_key": None,
        "device_type_name": None,
        "capabilities": [],
    }
    generic_state = {}
    if db is not None:
        state_row = db.get(DeviceState, device.id)
        if state_row:
            generic_state = state_row.state or {}
        profile = db.get(DeviceProfile, device.id)
        if profile:
            smart_home["home_id"] = profile.home_id
            smart_home["room_id"] = profile.room_id
            smart_home["device_type_id"] = profile.device_type_id
            if profile.device_type_id:
                dtype = db.get(DeviceType, profile.device_type_id)
                if dtype:
                    smart_home["device_type_key"] = dtype.key
                    smart_home["device_type_name"] = dtype.name
                    smart_home["capabilities"] = list(
                        db.scalars(
                            select(DeviceTypeCapability.capability).where(
                                DeviceTypeCapability.device_type_id == dtype.id
                            )
                        ).all()
                    )

    return {
        "id": device.id,
        "serial_number": device.serial_number,
        "name": device.name,
        "model": device.model,
        "status": display_status,
        "online": device.is_online,
        "last_seen": device.last_seen,
        "last_connected_at": device.last_connected_at,
        "last_disconnected_at": device.last_disconnected_at,
        "firmware_version": device.firmware_version,
        "wifi_rssi": device.wifi_rssi,
        "free_storage": device.free_storage,
        "light": {
            "enabled": device.light_on,
            "brightness": device.brightness,
            "r": device.color_r,
            "g": device.color_g,
            "b": device.color_b,
        },
        "audio": {
            "loaded": device.audio_loaded,
            "playing": device.audio_playing,
            "volume": device.volume,
        },
        "smart_home": smart_home,
        "generic_state": generic_state,
    }


@router.post("/pairing-session")
def create_pairing_session(
    user: User = Depends(get_current_user),
):
    return {
        "pairing_token": create_pairing_token(user.id),
        "expires_in_seconds": 600,
    }

@router.get("")
def my_devices(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    devices = db.scalars(
        select(Device).where(Device.owner_id == user.id)
    ).all()

    return [serialize_device(d, db) for d in devices]

@router.patch("/{device_id}")
def rename_device(
    device_id: int,
    payload: DeviceRename,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    device = db.get(Device, device_id)
    if not device or device.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Device not found")
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="Device name cannot be empty")
    device.name = name
    db.commit()
    db.refresh(device)
    return serialize_device(device, db)


@router.post("/claim")
def claim_device(
    payload: DeviceClaim,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    device = db.scalar(
        select(Device).where(
            Device.serial_number == payload.serial_number
        )
    )

    if not device:
        raise HTTPException(
            status_code=404,
            detail="Device not found",
        )

    if device.lifecycle_status == "DISABLED":
        raise HTTPException(
            status_code=403,
            detail="Device disabled",
        )

    if device.owner_id and device.owner_id != user.id:
        raise HTTPException(
            status_code=409,
            detail="Device already assigned",
        )

    device.owner_id = user.id
    device.name = payload.name or device.name

    if not device.activated_at:
        device.activated_at = datetime.now(timezone.utc)

    ensure_smart_profile(db, device, user.id)
    db.commit()
    db.refresh(device)
    return serialize_device(device, db)


@router.post("/activate")
def activate_device(
    payload: DeviceActivate,
    db: Session = Depends(get_db),
):
    device = db.scalar(
        select(Device).where(
            Device.serial_number == payload.serial_number
        )
    )

    if not device or not verify_password(
        payload.device_secret,
        device.secret_hash,
    ):
        raise HTTPException(
            status_code=401,
            detail="Invalid device credentials",
        )

    if device.lifecycle_status == "DISABLED":
        raise HTTPException(
            status_code=403,
            detail="Device disabled",
        )

    try:
        pairing = decode_token(payload.pairing_token)
        if pairing.get("type") != "device_pairing":
            raise ValueError("Wrong token type")
        pairing_user_id = int(pairing["sub"])
    except Exception:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired pairing token",
        )

    if device.owner_id is not None and device.owner_id != pairing_user_id:
        raise HTTPException(
            status_code=409,
            detail="Device is already associated with another user",
        )

    user = db.get(User, pairing_user_id)
    if not user or not user.is_active:
        raise HTTPException(
            status_code=404,
            detail="Pairing user not found",
        )

    device.owner_id = pairing_user_id
    device.lifecycle_status = "ACTIVE"
    device.firmware_version = (
        payload.firmware_version or device.firmware_version
    )
    device.last_seen = datetime.now(timezone.utc)

    if not device.activated_at:
        device.activated_at = datetime.now(timezone.utc)

    profile = ensure_smart_profile(db, device, pairing_user_id)
    if payload.device_type_key:
        requested_type = db.scalar(select(DeviceType).where(DeviceType.key == payload.device_type_key))
        if requested_type:
            profile.device_type_id = requested_type.id
    db.commit()
    db.refresh(device)

    return {
        "id": device.id,
        "serial_number": device.serial_number,
        "owner_id": device.owner_id,
        "home_id": profile.home_id,
        "device_type_id": profile.device_type_id,
        "mqtt": {
            "topics": {
                "command": f"devices/{device.serial_number}/command",
                "status": f"devices/{device.serial_number}/status",
                "heartbeat": f"devices/{device.serial_number}/heartbeat",
                "state": f"devices/{device.serial_number}/state",
                "schedule": f"devices/{device.serial_number}/schedule",
            },
        },
    }

@router.put("/{device_id}/light")
def set_light(
    device_id: int,
    payload: LightCommand,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    device = db.get(Device, device_id)

    if not device or device.owner_id != user.id:
        raise HTTPException(
            status_code=404,
            detail="Device not found",
        )

    device.light_on = payload.enabled
    device.brightness = payload.brightness
    device.color_r = payload.r
    device.color_g = payload.g
    device.color_b = payload.b
    db.commit()

    delivered = mqtt_service.publish_command(
        device.serial_number,
        {
            "type": "light",
            "payload": payload.model_dump(),
        },
    )

    return {
        "device": serialize_device(device, db),
        "mqtt_published": delivered,
    }

@router.post("/{device_id}/audio/play")
def audio_play(
    device_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    device = db.get(Device, device_id)

    if not device or device.owner_id != user.id:
        raise HTTPException(
            status_code=404,
            detail="Device not found",
        )

    delivered = mqtt_service.publish_command(
        device.serial_number,
        {"type": "audio_play"},
    )

    return {"ok": True, "mqtt_published": delivered}

@router.post("/{device_id}/audio/stop")
def audio_stop(
    device_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    device = db.get(Device, device_id)

    if not device or device.owner_id != user.id:
        raise HTTPException(
            status_code=404,
            detail="Device not found",
        )

    delivered = mqtt_service.publish_command(
        device.serial_number,
        {"type": "audio_stop"},
    )

    return {"ok": True, "mqtt_published": delivered}

@router.put("/{device_id}/audio/volume")
def set_volume(
    device_id: int,
    payload: VolumeCommand,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    device = db.get(Device, device_id)

    if not device or device.owner_id != user.id:
        raise HTTPException(
            status_code=404,
            detail="Device not found",
        )

    device.volume = payload.volume
    db.commit()

    delivered = mqtt_service.publish_command(
        device.serial_number,
        {
            "type": "volume",
            "payload": {"volume": payload.volume},
        },
    )

    return {
        "ok": True,
        "mqtt_published": delivered,
    }

@router.post("/admin")
def admin_create_device(
    payload: DeviceCreate,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    existing = db.scalar(
        select(Device).where(
            Device.serial_number == payload.serial_number
        )
    )

    if existing:
        raise HTTPException(
            status_code=409,
            detail="Serial already exists",
        )

    device = Device(
        serial_number=payload.serial_number,
        secret_hash=hash_password(payload.device_secret),
        model=payload.model,
        hardware_version=payload.hardware_version,
        lifecycle_status="INVENTORY",
    )

    db.add(device)
    db.commit()
    db.refresh(device)

    return serialize_device(device, db)

@router.get("/admin/all")
def admin_list_devices(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    devices = db.scalars(
        select(Device).order_by(Device.id.desc())
    ).all()

    return [serialize_device(d, db) for d in devices]


@router.patch("/admin/{device_id}/disabled")
def admin_set_device_disabled(
    device_id: int,
    payload: DisabledUpdate,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    device = db.get(Device, device_id)
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    device.lifecycle_status = "DISABLED" if payload.disabled else "ACTIVE"
    if payload.disabled:
        device.is_online = False

    db.commit()
    db.refresh(device)
    return serialize_device(device, db)

@router.delete("/admin/{device_id}")
def admin_delete_device(
    device_id: int,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    device = db.get(Device, device_id)
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    db.delete(device)
    db.commit()
    return {"ok": True}
