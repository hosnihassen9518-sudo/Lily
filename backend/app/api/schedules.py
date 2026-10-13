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
from app.services.device_features import schedule_action

router = APIRouter(prefix="/schedules", tags=["schedules"])

def sync_device_schedule(
    db: Session,
    device: Device,
):
    from app.api.device_operations import require_mutable, device_generation
    require_mutable(device)
    schedules = db.scalars(
        select(Schedule).where(
            Schedule.device_id == device.id,
            Schedule.enabled == True,
        )
    ).all()

    actions = {}
    for schedule in schedules:
        try:
            action = schedule_action(db, device, schedule.action)
        except HTTPException:
            continue
        actions[schedule.id] = action
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
                "action": actions[schedule.id],
            }
            for schedule in schedules if schedule.id in actions
        ],
    }

    return mqtt_service.publish_schedule(
        device.serial_number,
        payload,
        generation=device_generation(db,device),
    )

@router.get("/device/{device_id}")
def list_schedules(
    device_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from app.api.device_operations import locked_device
    device = locked_device(db,device_id=device_id)

    if not device or device.owner_id != user.id:
        raise HTTPException(
            status_code=404,
            detail="Device not found",
        )

    from app.api.device_operations import require_mutable
    require_mutable(device)
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
    from app.api.device_operations import locked_device
    device = locked_device(db,device_id=device_id)

    if not device or device.owner_id != user.id:
        raise HTTPException(
            status_code=404,
            detail="Device not found",
        )

    from app.api.device_operations import require_mutable
    require_mutable(device)
    schedule_action(db, device, payload.action)
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
    db.flush()
    sync_device_schedule(db, device)
    db.commit()
    db.refresh(schedule)

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

    from app.api.device_operations import locked_device
    device = locked_device(db,device_id=schedule.device_id)

    from app.api.device_operations import require_mutable
    if device: require_mutable(device)
    if not device or device.owner_id!=user.id:
        raise HTTPException(404,"Device not found")
    db.delete(schedule)
    db.flush()
    sync_device_schedule(db, device)
    db.commit()

    return {"ok": True}
