from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from app.core.security import decode_token
from app.db.session import get_db
from app.models.user import User

bearer = HTTPBearer()

def get_current_user(
    creds: HTTPAuthorizationCredentials = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    try:
        payload = decode_token(creds.credentials)
        if payload.get('type') != 'access':
            raise ValueError('Access token required')
        user_id = int(payload["sub"])
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")

    user = db.get(User, user_id)
    if payload.get('sid'):
        from app.models.device_lifecycle import MobileSession
        from app.services.mobile_sessions import utc
        from datetime import datetime, timezone
        session = db.get(MobileSession, payload['sid'])
        if not session or session.user_id != user_id or session.revoked_at or utc(session.expires_at) <= datetime.now(timezone.utc):
            raise HTTPException(401, 'Session expired')
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="Inactive or missing user")
    return user

def require_admin(user: User = Depends(get_current_user)) -> User:
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin required")
    return user
