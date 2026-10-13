"""Persist schedule refreshes until model changes can reach a device/broker."""
from fastapi import HTTPException
from app.models.device_lifecycle import AppSetting

def pending_key(device):
    return f'device_schedule_features:{device.id}'

def mark_pending(db, device):
    if db.get(AppSetting, pending_key(device)) is None:
        db.add(AppSetting(key=pending_key(device), value_json={'device_id': device.id}))
    db.flush()

def flush_pending(db, device, force=False):
    pending = db.get(AppSetting, pending_key(device))
    if pending is None and not force: return True
    if device.owner_id is None or device.lifecycle_status in ('DISABLED', 'RESET_PENDING', 'INVENTORY'): return False
    from app.api.schedules import sync_device_schedule
    try:
        sent = sync_device_schedule(db, device)
    except (HTTPException, RuntimeError, ValueError):
        sent = False
    if sent and pending is not None: db.delete(pending)
    return bool(sent)
