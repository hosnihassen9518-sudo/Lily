from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import require_admin
from app.db.session import get_db
from app.models.device import Device
from app.models.music import Music
from app.models.home import Home, Room
from app.models.smart_device import DeviceTelemetry, DeviceType
from app.models.user import User
from app.schemas.admin import ActiveUpdate

router = APIRouter(
    prefix="/admin",
    tags=["admin"],
    dependencies=[Depends(require_admin)],
)

@router.get("/dashboard")
def dashboard(db: Session = Depends(get_db)):
    return {
        "users": db.scalar(select(func.count()).select_from(User)),
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
        "telemetry_points": db.scalar(select(func.count()).select_from(DeviceTelemetry)),
    }

@router.get("/users")
def users(db: Session = Depends(get_db)):
    rows = db.scalars(select(User).order_by(User.created_at.desc())).all()
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
    db: Session = Depends(get_db),
):
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user.is_admin and not payload.active:
        raise HTTPException(
            status_code=400,
            detail="Administrator accounts cannot be disabled here",
        )
    user.is_active = payload.active
    db.commit()
    return {"id": user.id, "active": user.is_active}


@router.get("/homes")
def homes(db: Session = Depends(get_db)):
    rows = db.scalars(select(Home).order_by(Home.created_at.desc())).all()
    result = []
    for home in rows:
        owner = db.get(User, home.owner_id)
        room_count = db.scalar(select(func.count()).select_from(Room).where(Room.home_id == home.id)) or 0
        from app.models.smart_device import DeviceProfile
        device_count = db.scalar(select(func.count()).select_from(DeviceProfile).where(DeviceProfile.home_id == home.id)) or 0
        result.append({
            "id": home.id,
            "name": home.name,
            "timezone": home.timezone,
            "owner_id": home.owner_id,
            "owner_email": owner.email if owner else None,
            "rooms": room_count,
            "devices": device_count,
            "created_at": home.created_at,
        })
    return result
