from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
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
from app.services.mobile_sessions import issue_mobile_session, rotate_mobile_session, digest

class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=256)
    request_id: str = Field(min_length=8, max_length=64)

class LogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=256)

@router.post('/mobile/login')
def mobile_login(payload: LoginRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == payload.email.lower()))
    if not user or not user.is_active or not verify_password(payload.password, user.password_hash):
        raise HTTPException(401, 'Invalid credentials')
    return issue_mobile_session(db, user)

@router.post('/mobile/register')
def mobile_register(payload: RegisterRequest, db: Session = Depends(get_db)):
    register(payload, db)
    user = db.scalar(select(User).where(User.email == payload.email.lower()))
    return issue_mobile_session(db, user)

@router.post('/mobile/refresh')
def mobile_refresh(payload: RefreshRequest, db: Session = Depends(get_db)):
    return rotate_mobile_session(db, payload.refresh_token, payload.request_id)

@router.post('/mobile/logout')
def mobile_logout(payload: LogoutRequest, db: Session = Depends(get_db)):
    hashed = digest(payload.refresh_token)
    row = db.scalar(select(MobileSession).where((MobileSession.current_refresh_hash == hashed) | (MobileSession.previous_refresh_hash == hashed)))
    if row:
        row.revoked_at = datetime.now(timezone.utc); db.commit()
    return {'ok':True}

@router.post("/register", response_model=TokenResponse)
def register(
    payload: RegisterRequest,
    db: Session = Depends(get_db),
):
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

    return TokenResponse(
        access_token=create_access_token(str(user.id))
    )

@router.post("/login", response_model=TokenResponse)
def login(
    payload: LoginRequest,
    db: Session = Depends(get_db),
):
    user = db.scalar(
        select(User).where(User.email == payload.email.lower())
    )

    if not user or not verify_password(
        payload.password,
        user.password_hash,
    ):
        raise HTTPException(
            status_code=401,
            detail="Invalid credentials",
        )

    return TokenResponse(
        access_token=create_access_token(str(user.id))
    )

@router.get("/me")
def me(user: User = Depends(get_current_user)):
    return {
        "id": user.id,
        "email": user.email,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "is_admin": user.is_admin,
    }
