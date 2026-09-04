from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select

from app.api import admin, auth, devices, music, schedules
from app.core.config import settings
from app.core.security import hash_password
from app.db.session import Base, SessionLocal, engine
from app.models.user import User
from app.services.mqtt_service import mqtt_service

def bootstrap():
    Path(settings.music_dir).mkdir(
        parents=True,
        exist_ok=True,
    )

    Base.metadata.create_all(bind=engine)

    with SessionLocal() as db:
        admin_user = db.scalar(
            select(User).where(
                User.email == settings.admin_email.lower()
            )
        )

        if not admin_user:
            db.add(
                User(
                    email=settings.admin_email.lower(),
                    password_hash=hash_password(
                        settings.admin_password
                    ),
                    is_admin=True,
                    is_active=True,
                )
            )
            db.commit()

@asynccontextmanager
async def lifespan(app: FastAPI):
    bootstrap()
    mqtt_service.start()
    yield
    mqtt_service.stop()

app = FastAPI(
    title=settings.app_name,
    version="0.2.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/v1")
app.include_router(devices.router, prefix="/api/v1")
app.include_router(music.router, prefix="/api/v1")
app.include_router(schedules.router, prefix="/api/v1")
app.include_router(admin.router, prefix="/api/v1")

@app.get("/")
def root():
    return {
        "name": settings.app_name,
        "version": "0.2.0",
        "docs": "/docs",
    }

@app.get("/health")
def health():
    return {
        "status": "ok",
        "mqtt_enabled": settings.mqtt_enabled,
    }
