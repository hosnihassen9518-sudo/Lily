from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import require_admin
from app.db.session import get_db
from app.models.device import Device
from app.models.music import Music
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
