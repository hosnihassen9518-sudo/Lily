import calendar
import hashlib
import hmac
import secrets
from datetime import datetime, timezone, timedelta
from jose import jwt
from sqlalchemy import select, update
from fastapi import HTTPException
from app.core.config import settings
from app.core.security import ALGORITHM
from app.models.device_lifecycle import MobileSession, AppSetting
from app.models.user import User

def utc(value):
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)

def calendar_expiry(now: datetime, months: int) -> datetime:
    now = utc(now)
    total = now.year * 12 + now.month - 1 + months
    year, month = divmod(total, 12); month += 1
    return now.replace(year=year, month=month, day=min(now.day, calendar.monthrange(year, month)[1]))

def digest(token):
    return hashlib.sha256(token.encode()).hexdigest()

def months_policy(db):
    row = db.get(AppSetting, 'mobile_session_months')
    return row.value_json['months'] if row else 3

def response(session, refresh, now):
    expires = min(utc(session.expires_at), now + timedelta(minutes=15))
    access = jwt.encode({'sub': str(session.user_id), 'sid':session.id, 'exp':expires, 'type':'access'}, settings.secret_key, algorithm=ALGORITHM)
    return {'access_token':access, 'refresh_token':refresh, 'token_type':'bearer', 'access_expires_at':expires,
            'session_expires_at':utc(session.expires_at), 'session_id':session.id}

def issue_mobile_session(db, user, now=None):
    now = utc(now or datetime.now(timezone.utc))
    refresh = secrets.token_urlsafe(48)
    session = MobileSession(id=secrets.token_hex(16), user_id=user.id, current_refresh_hash=digest(refresh), expires_at=calendar_expiry(now, months_policy(db)))
    db.add(session); db.commit()
    return response(session, refresh, now)

def rotated_token(session_id, request_id):
    return hmac.new(settings.secret_key.encode(), ('lily-refresh-v1:'+session_id+':'+request_id).encode(), hashlib.sha256).hexdigest()

def rotate_mobile_session(db, refresh_token, request_id, now=None):
    now = utc(now or datetime.now(timezone.utc))
    hashed = digest(refresh_token)
    row = db.scalar(select(MobileSession).where((MobileSession.current_refresh_hash == hashed) | (MobileSession.previous_refresh_hash == hashed)))
    if not row or row.revoked_at or utc(row.expires_at) <= now:
        raise HTTPException(401, 'Session expired. Sign in again.')
    user = db.get(User, row.user_id)
    if not user or not user.is_active:
        raise HTTPException(401, 'Inactive user')
    if row.previous_refresh_hash == hashed:
        if row.rotation_request_id != request_id or not row.rotated_at:
            raise HTTPException(401, 'Refresh credential has already been used')
        return response(row, rotated_token(row.id, request_id), now)
    replacement = rotated_token(row.id, request_id)
    if row.rotation_request_id == request_id:
        raise HTTPException(409, 'Use a new refresh request ID')
    changed = db.execute(update(MobileSession).where(MobileSession.id == row.id, MobileSession.current_refresh_hash == hashed, MobileSession.revoked_at.is_(None)).values(previous_refresh_hash=hashed, current_refresh_hash=digest(replacement), rotation_request_id=request_id, rotated_at=now))
    if changed.rowcount != 1:
        db.rollback()
        return rotate_mobile_session(db, refresh_token, request_id, now)
    db.commit(); db.refresh(row)
    return response(row, replacement, now)
