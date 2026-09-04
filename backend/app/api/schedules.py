from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.device import Device
from app.models.schedule import Schedule
from app.models.user import User
from app.schemas.schedule import ScheduleCreate
from app.services.mqtt_service import mqtt_service

router = APIRouter(prefix="/schedules", tags=["schedules"])

def sync_device_schedule(
    db: Session,
    device: Device,
):
    schedules = db.scalars(
        select(Schedule).where(
            Schedule.device_id == device.id,
            Schedule.enabled == True,
        )
    ).all()

    payload = {
        "timezone": "Europe/Paris",
        "schedules": [
            {
                "id": schedule.id,
                "name": schedule.name,
                "time": schedule.time_of_day.isoformat(
                    timespec="minutes"
                ),
                "days": schedule.days_of_week,
                "action": schedule.action,
            }
            for schedule in schedules
        ],
    }

    mqtt_service.publish_schedule(
        device.serial_number,
        payload,
    )

@router.get("/device/{device_id}")
def list_schedules(
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

    schedules = db.scalars(
        select(Schedule).where(
            Schedule.device_id == device.id
        )
    ).all()

    return [
        {
            "id": s.id,
            "name": s.name,
            "time_of_day": s.time_of_day,
            "days_of_week": s.days_of_week,
            "action": s.action,
            "enabled": s.enabled,
        }
        for s in schedules
    ]

@router.post("/device/{device_id}")
def create_schedule(
    device_id: int,
    payload: ScheduleCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    device = db.get(Device, device_id)

    if not device or device.owner_id != user.id:
        raise HTTPException(
            status_code=404,
            detail="Device not found",
        )

    schedule = Schedule(
        device_id=device.id,
        user_id=user.id,
        name=payload.name,
        time_of_day=payload.time_of_day,
        days_of_week=payload.days_of_week,
        action=payload.action,
        enabled=payload.enabled,
    )

    db.add(schedule)
    db.commit()
    db.refresh(schedule)

    sync_device_schedule(db, device)

    return {
        "id": schedule.id,
        "name": schedule.name,
        "time_of_day": schedule.time_of_day,
        "days_of_week": schedule.days_of_week,
        "action": schedule.action,
        "enabled": schedule.enabled,
    }

@router.delete("/{schedule_id}")
def delete_schedule(
    schedule_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    schedule = db.get(Schedule, schedule_id)

    if not schedule or schedule.user_id != user.id:
        raise HTTPException(
            status_code=404,
            detail="Schedule not found",
        )

    device = db.get(Device, schedule.device_id)

    db.delete(schedule)
    db.commit()

    if device:
        sync_device_schedule(db, device)

    return {"ok": True}
