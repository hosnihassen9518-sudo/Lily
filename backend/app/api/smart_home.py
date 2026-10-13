from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, require_admin
from app.db.session import get_db
from app.models.device import Device
from app.models.home import Home, Room
from app.models.smart_device import (
    DeviceProfile, DeviceState, DeviceTelemetry, DeviceType, DeviceTypeCapability,
)
from app.models.user import User
from app.schemas.smart_home import (
    DeviceProfileUpdate, DeviceStateUpdate, DeviceTypeCreate, GenericCommand,
    HomeCreate, HomeUpdate, RoomCreate, RoomUpdate, TelemetryIn,
)
from app.services.mqtt_service import mqtt_service
from app.services.device_features import associated_model, validate_state, validate_command, light_payload

router = APIRouter(tags=["smart-home"])


def _home_for_user(db: Session, home_id: int, user_id: int) -> Home:
    home = db.scalar(select(Home).where(Home.id == home_id, Home.owner_id == user_id))
    if not home:
        raise HTTPException(status_code=404, detail="Home not found")
    return home


def _owned_device(db: Session, device_id: int, user_id: int) -> Device:
    from app.api.device_operations import locked_device
    device = locked_device(db,device_id=device_id)
    if not device or device.owner_id != user_id:
        raise HTTPException(status_code=404, detail="Device not found")
    from app.api.device_operations import require_mutable
    require_mutable(device)
    return device


def _serialize_home(home: Home):
    return {"id": home.id, "owner_id": home.owner_id, "name": home.name, "timezone": home.timezone, "created_at": home.created_at}


def _serialize_room(room: Room):
    return {"id": room.id, "home_id": room.home_id, "name": room.name, "icon": room.icon, "created_at": room.created_at}


@router.get("/homes")
def list_homes(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    homes = db.scalars(select(Home).where(Home.owner_id == user.id).order_by(Home.id)).all()
    return [_serialize_home(h) for h in homes]


@router.post("/homes")
def create_home(payload: HomeCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    home = Home(owner_id=user.id, name=payload.name, timezone=payload.timezone)
    db.add(home); db.commit(); db.refresh(home)
    return _serialize_home(home)


@router.patch("/homes/{home_id}")
def update_home(home_id: int, payload: HomeUpdate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    home = _home_for_user(db, home_id, user.id)
    if payload.name is not None: home.name = payload.name
    if payload.timezone is not None: home.timezone = payload.timezone
    db.commit(); db.refresh(home)
    return _serialize_home(home)


@router.delete("/homes/{home_id}")
def delete_home(home_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    home = _home_for_user(db, home_id, user.id)
    profiles = db.scalars(select(DeviceProfile).where(DeviceProfile.home_id == home.id)).all()
    for p in profiles:
        p.home_id = None; p.room_id = None
    db.delete(home); db.commit()
    return {"ok": True}


@router.get("/homes/{home_id}/rooms")
def list_rooms(home_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _home_for_user(db, home_id, user.id)
    rooms = db.scalars(select(Room).where(Room.home_id == home_id).order_by(Room.name)).all()
    return [_serialize_room(r) for r in rooms]


@router.post("/homes/{home_id}/rooms")
def create_room(home_id: int, payload: RoomCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _home_for_user(db, home_id, user.id)
    existing = db.scalar(select(Room).where(Room.home_id == home_id, Room.name == payload.name))
    if existing: raise HTTPException(status_code=409, detail="Room name already exists in this home")
    room = Room(home_id=home_id, name=payload.name, icon=payload.icon)
    db.add(room); db.commit(); db.refresh(room)
    return _serialize_room(room)


@router.patch("/rooms/{room_id}")
def update_room(room_id: int, payload: RoomUpdate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    room = db.get(Room, room_id)
    if not room: raise HTTPException(status_code=404, detail="Room not found")
    _home_for_user(db, room.home_id, user.id)
    if payload.name is not None: room.name = payload.name
    if payload.icon is not None: room.icon = payload.icon
    db.commit(); db.refresh(room)
    return _serialize_room(room)


@router.delete("/rooms/{room_id}")
def delete_room(room_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    room = db.get(Room, room_id)
    if not room: raise HTTPException(status_code=404, detail="Room not found")
    _home_for_user(db, room.home_id, user.id)
    profiles = db.scalars(select(DeviceProfile).where(DeviceProfile.room_id == room.id)).all()
    for p in profiles: p.room_id = None
    db.delete(room); db.commit()
    return {"ok": True}


@router.get("/device-types")
def list_device_types(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    types = db.scalars(select(DeviceType).order_by(DeviceType.name)).all()
    result = []
    for t in types:
        caps = db.scalars(select(DeviceTypeCapability.capability).where(DeviceTypeCapability.device_type_id == t.id)).all()
        result.append({"id": t.id, "key": t.key, "name": t.name, "description": t.description, "capabilities": list(caps)})
    return result


@router.post("/admin/device-types")
def create_device_type(payload: DeviceTypeCreate, admin: User = Depends(require_admin), db: Session = Depends(get_db)):
    if db.scalar(select(DeviceType).where(DeviceType.key == payload.key)):
        raise HTTPException(status_code=409, detail="Device type key already exists")
    item = DeviceType(key=payload.key, name=payload.name, description=payload.description)
    db.add(item); db.flush()
    for capability in sorted(set(payload.capabilities)):
        db.add(DeviceTypeCapability(device_type_id=item.id, capability=capability))
    db.commit(); db.refresh(item)
    return {"id": item.id, "key": item.key, "name": item.name, "capabilities": sorted(set(payload.capabilities))}


@router.get("/devices/{device_id}/profile")
def get_profile(device_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    device = _owned_device(db, device_id, user.id)
    p = db.get(DeviceProfile, device_id)
    return {"device_id": device_id, "home_id": p.home_id if p else None, "room_id": p.room_id if p else None, "device_type_id": p.device_type_id if p else None, "metadata": p.metadata_json if p else {}}


@router.put("/devices/{device_id}/profile")
def update_profile(device_id: int, payload: DeviceProfileUpdate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    device = _owned_device(db, device_id, user.id)
    if payload.home_id is not None: _home_for_user(db, payload.home_id, user.id)
    if payload.room_id is not None:
        room = db.get(Room, payload.room_id)
        if not room: raise HTTPException(status_code=404, detail="Room not found")
        _home_for_user(db, room.home_id, user.id)
        if payload.home_id is not None and room.home_id != payload.home_id:
            raise HTTPException(status_code=400, detail="Room does not belong to selected home")
    if payload.device_type_id is not None and not db.get(DeviceType, payload.device_type_id):
        raise HTTPException(status_code=404, detail="Device type not found")
    p = db.get(DeviceProfile, device_id) or DeviceProfile(device_id=device_id)
    model = associated_model(db, device)
    factory_key = (p.metadata_json or {}).get('model_key') or (model.key if model else None)
    if payload.metadata is not None and 'model_key' in payload.metadata and payload.metadata['model_key'] != factory_key:
        raise HTTPException(409, 'Factory model identity cannot change')
    if model and 'device_type_id' in payload.model_fields_set and payload.device_type_id != model.device_type_id:
        raise HTTPException(409, 'Factory device type cannot change')
    if p not in db: db.add(p)
    # model_fields_set lets explicit null detach a device from a room/home/type.
    if "home_id" in payload.model_fields_set: p.home_id = payload.home_id
    if "room_id" in payload.model_fields_set: p.room_id = payload.room_id
    if "device_type_id" in payload.model_fields_set: p.device_type_id = payload.device_type_id
    if payload.metadata is not None:
        p.metadata_json = {**payload.metadata, **({'model_key':factory_key} if factory_key else {})}
    db.commit(); db.refresh(p)
    return {"device_id": device_id, "home_id": p.home_id, "room_id": p.room_id, "device_type_id": p.device_type_id, "metadata": p.metadata_json}


@router.get("/devices/{device_id}/state")
def get_state(device_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _owned_device(db, device_id, user.id)
    state = db.get(DeviceState, device_id)
    return {"device_id": device_id, "state": state.state if state else {}, "updated_at": state.updated_at if state else None}


@router.put("/devices/{device_id}/state")
def set_state(device_id: int, payload: DeviceStateUpdate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    device = _owned_device(db, device_id, user.id)
    validate_state(db, device, payload.state)
    state = db.get(DeviceState, device_id) or DeviceState(device_id=device_id)
    if state not in db: db.add(state)
    state.state = payload.state
    state.updated_at = datetime.now(timezone.utc)
    db.commit(); db.refresh(state)
    return {"device_id": device_id, "state": state.state, "updated_at": state.updated_at}


@router.post("/devices/{device_id}/command")
def generic_command(device_id: int, payload: GenericCommand, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    device = _owned_device(db, device_id, user.id)
    validate_command(db, device, payload.model_dump())
    if payload.type == 'light': payload.payload = light_payload(db, device, payload.payload)
    from app.api.device_operations import device_generation
    delivered = mqtt_service.publish_command(device.serial_number, {"type": payload.type, "payload": payload.payload}, generation=device_generation(db,device))
    db.commit()
    return {"ok": True, "mqtt_published": delivered}


@router.post("/devices/{device_id}/telemetry")
def add_telemetry(device_id: int, payload: TelemetryIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _owned_device(db, device_id, user.id)
    numeric = None; text = None
    if isinstance(payload.value, bool): text = str(payload.value).lower()
    elif isinstance(payload.value, (int, float)): numeric = float(payload.value)
    elif payload.value is not None: text = str(payload.value)
    row = DeviceTelemetry(device_id=device_id, metric=payload.metric, numeric_value=numeric, text_value=text, extra=payload.extra, recorded_at=payload.recorded_at or datetime.now(timezone.utc))
    db.add(row); db.commit(); db.refresh(row)
    return {"id": row.id, "device_id": row.device_id, "metric": row.metric, "value": row.numeric_value if row.numeric_value is not None else row.text_value, "recorded_at": row.recorded_at}


@router.get("/devices/{device_id}/telemetry")
def get_telemetry(device_id: int, metric: str | None = None, limit: int = Query(100, ge=1, le=1000), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _owned_device(db, device_id, user.id)
    q = select(DeviceTelemetry).where(DeviceTelemetry.device_id == device_id)
    if metric: q = q.where(DeviceTelemetry.metric == metric)
    rows = db.scalars(q.order_by(DeviceTelemetry.recorded_at.desc()).limit(limit)).all()
    return [{"id": r.id, "metric": r.metric, "value": r.numeric_value if r.numeric_value is not None else r.text_value, "extra": r.extra, "recorded_at": r.recorded_at} for r in rows]
