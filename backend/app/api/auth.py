from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.models.access_control import ServicePrincipal
from app.services.access_sessions import issue_session
from app.core.security import (
    create_access_token,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.models.user import User
from app.models.home import Home
from app.schemas.auth import (
    LoginRequest,
    RegisterRequest,
    TokenResponse,
)

router = APIRouter(prefix="/auth", tags=["auth"])

from pydantic import BaseModel, Field
from datetime import datetime, timezone
from app.models.device_lifecycle import MobileSession
from app.services.mobile_sessions import (
    issue_mobile_session,
    rotate_mobile_session,
    digest,
)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=256)
    request_id: str = Field(min_length=8, max_length=64)


class LogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=256)


@router.post("/mobile/login")
def mobile_login(
    payload: LoginRequest, request: Request, db: Session = Depends(get_db)
):
    from app.services.rate_limits import login_limit, failed_account

    login_limit(db, request, payload.email)
    user = db.scalar(select(User).where(User.email == payload.email.lower()))
    if (
        not user
        or user.is_admin
        or db.get(ServicePrincipal, user.id)
        or not user.is_active
        or not verify_password(payload.password, user.password_hash)
    ):
        failed_account(db, payload.email)
        raise HTTPException(401, "Invalid credentials")
    return issue_mobile_session(db, user)


@router.post("/mobile/register")
def mobile_register(
    payload: RegisterRequest, request: Request, db: Session = Depends(get_db)
):
    register(payload, request, db)
    user = db.scalar(select(User).where(User.email == payload.email.lower()))
    return issue_mobile_session(db, user)


@router.post("/mobile/refresh")
def mobile_refresh(
    payload: RefreshRequest, request: Request, db: Session = Depends(get_db)
):
    from app.services.rate_limits import public_auth_limit

    public_auth_limit(db, request)
    return rotate_mobile_session(db, payload.refresh_token, payload.request_id)


@router.post("/mobile/logout")
def mobile_logout(
    payload: LogoutRequest, request: Request, db: Session = Depends(get_db)
):
    from app.services.rate_limits import public_auth_limit

    public_auth_limit(db, request)
    hashed = digest(payload.refresh_token)
    row = db.scalar(
        select(MobileSession).where(
            (MobileSession.current_refresh_hash == hashed)
            | (MobileSession.previous_refresh_hash == hashed)
        )
    )
    if row:
        row.revoked_at = datetime.now(timezone.utc)
        db.commit()
    return {"ok": True}


@router.post("/register", response_model=TokenResponse)
def register(
    payload: RegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    from app.services.rate_limits import public_auth_limit

    public_auth_limit(db, request)
    email = payload.email.lower()

    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(
            status_code=409,
            detail="Email already registered",
        )

    user = User(
        email=email,
        password_hash=hash_password(payload.password),
        first_name=payload.first_name,
        last_name=payload.last_name,
    )

    db.add(user)
    db.flush()
    db.add(Home(owner_id=user.id, name="My Home", timezone="Europe/Paris"))
    db.commit()
    db.refresh(user)

    return TokenResponse(access_token=issue_mobile_session(db, user)["access_token"])


@router.post("/login", response_model=TokenResponse)
def login(
    payload: LoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    from app.services.rate_limits import login_limit, failed_account

    login_limit(db, request, payload.email)
    user = db.scalar(select(User).where(User.email == payload.email.lower()))

    if (
        not user
        or not user.is_admin
        or not user.is_active
        or db.get(ServicePrincipal, user.id)
        or not verify_password(
            payload.password,
            user.password_hash,
        )
    ):
        failed_account(db, payload.email)
        raise HTTPException(
            status_code=401,
            detail="Invalid credentials",
        )

    return TokenResponse(access_token=issue_session(db, user)["access_token"])


@router.get("/me")
def me(user: User = Depends(get_current_user)):
    return {
        "id": user.id,
        "email": user.email,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "is_admin": user._access.auth_method == "portal" and bool(db_role_keys(user)),
        "permissions": sorted(user._access.permissions),
        "roles": list(db_role_keys(user)),
        "session_id": user._access.session_id,
        "auth_method": user._access.auth_method,
    }


def db_role_keys(user):
    return getattr(user._access, "portal_roles", ())
