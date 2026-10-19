from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.models.user import User
from app.services.access_sessions import validate_session

bearer = HTTPBearer()


def get_current_user(
    request: Request,
    creds: HTTPAuthorizationCredentials = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    context = validate_session(db, creds.credentials)
    request.state.access = context
    request.state.access_db = db
    request.state.audit_actor_id = context.principal.id
    request.state.audit_bind = db.get_bind()
    from app.services.route_policies import enforce_policy
    from app.services.rate_limits import session_limit

    session_limit(db, request, context)
    enforce_policy(request, context)
    request.state.access = context
    context.principal._access = context
    return context.principal


def require_permission(permission):
    def check(user: User = Depends(get_current_user)):
        if permission not in user._access.permissions:
            raise HTTPException(403, "Permission required: " + permission)
        return user

    return check


def require_admin(user: User = Depends(get_current_user)) -> User:
    if user._access.auth_method == "mobile" or not user._access.permissions:
        raise HTTPException(403, "Portal permission required")
    return user
