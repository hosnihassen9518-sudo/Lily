from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select

from app.api import admin, auth, devices, music, schedules, smart_home
from app.api import device_operations, widgets
from app.core.config import settings
from app.core.security import hash_password
from app.db.session import Base, SessionLocal, engine
from app.models.user import User
from app.models.home import Home
from app.models.smart_device import DeviceType, DeviceTypeCapability
from app.services.mqtt_service import mqtt_service


def bootstrap():
    if settings.environment == "production" and (
        settings.secret_key == "change-me" or len(settings.secret_key) < 32
    ):
        raise RuntimeError(
            "Production SECRET_KEY must contain at least 32 characters of strong random data"
        )
    Path(settings.music_dir).mkdir(parents=True, exist_ok=True)
    from app.db.migrations import upgrade_database

    upgrade_database(engine)

    with SessionLocal() as db:
        admin_user = db.scalar(
            select(User).where(User.email == settings.admin_email.lower())
        )
        from app.models.device_lifecycle import AppSetting

        if not admin_user and db.scalar(select(User.id).limit(1)) is not None:
            if not db.get(AppSetting, "rbac_migrated"):
                raise RuntimeError(
                    "Existing installation has no matching bootstrap administrator; run python -m app.services.rbac_recovery --email <existing-active-admin>"
                )
        elif not admin_user:
            admin_user = User(
                email=settings.admin_email.lower(),
                password_hash=hash_password(settings.admin_password),
                is_admin=True,
                is_active=True,
            )
            db.add(admin_user)
            db.flush()

        if admin_user and not db.scalar(
            select(Home).where(Home.owner_id == admin_user.id)
        ):
            db.add(
                Home(owner_id=admin_user.id, name="Admin Home", timezone="Europe/Paris")
            )

        defaults = [
            (
                "lily_audio_light",
                "Lily Audio Light",
                ["power", "light", "brightness", "rgb", "audio", "volume"],
            ),
            ("test_light", "Lily Test Light", ["power", "light"]),
            ("smart_light", "Smart Light", ["power", "brightness", "rgb"]),
            (
                "environment_sensor",
                "Environment Sensor",
                ["temperature", "humidity", "battery"],
            ),
            (
                "plant_sensor",
                "Plant Sensor",
                ["temperature", "humidity", "soil_moisture", "battery"],
            ),
            ("smart_plug", "Smart Plug", ["power", "energy"]),
        ]
        for key, name, capabilities in defaults:
            dtype = db.scalar(select(DeviceType).where(DeviceType.key == key))
            if not dtype:
                dtype = DeviceType(key=key, name=name)
                db.add(dtype)
                db.flush()
                for capability in capabilities:
                    db.add(
                        DeviceTypeCapability(
                            device_type_id=dtype.id, capability=capability
                        )
                    )
        db.commit()
        from app.services.device_inventory import seed_models

        seed_models(db)
        from app.services.rbac import bootstrap_access

        bootstrap_access(db, settings.admin_email)


@asynccontextmanager
async def lifespan(app: FastAPI):
    from app.services.route_policies import verify_route_policies

    verify_route_policies(app)
    bootstrap()
    mqtt_service.start()
    yield
    mqtt_service.stop()


app = FastAPI(
    title=settings.app_name,
    version="0.9.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()
    ],
    # Flutter Web uses a random localhost port during development.
    # Explicit production origins remain controlled by CORS_ORIGINS.
    allow_origin_regex=(
        r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
        if settings.environment != "production"
        else None
    ),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from app.api import access_control

app.include_router(access_control.router, prefix="/api/v1")
app.include_router(access_control.auth_router, prefix="/api/v1")
app.include_router(auth.router, prefix="/api/v1")
app.include_router(devices.router, prefix="/api/v1")
app.include_router(music.router, prefix="/api/v1")
app.include_router(schedules.router, prefix="/api/v1")
app.include_router(smart_home.router, prefix="/api/v1")
app.include_router(admin.router, prefix="/api/v1")
app.include_router(device_operations.router, prefix="/api/v1")
app.include_router(widgets.router, prefix="/api/v1")


@app.get("/")
def root():
    return {
        "name": settings.app_name,
        "version": "0.9.0",
        "docs": "/docs",
    }


@app.get("/health")
def health():
    return {
        "status": "ok",
        "mqtt_enabled": settings.mqtt_enabled,
    }


@app.middleware("http")
async def audit_mutations(request, call_next):
    response = await call_next(request)
    context = getattr(request.state, "access", None)
    db = getattr(request.state, "access_db", None)
    from app.services.route_policies import policy_for

    endpoint = request.scope.get("endpoint")
    policy = policy_for(endpoint) if endpoint else None
    if (
        context
        and db
        and (
            request.method not in ("GET", "HEAD", "OPTIONS")
            or policy == "inventory.export_secrets"
        )
    ):
        from app.services.access_audit import audit

        route = request.scope.get("route")
        path = getattr(route, "path", "authenticated-action")
        if response.status_code >= 400:
            db.rollback()
        from sqlalchemy.orm import Session

        with Session(bind=request.state.audit_bind) as journal:
            audit(
                journal,
                request.state.audit_actor_id,
                request.method + " " + path,
                ":".join(str(v) for v in request.path_params.values()),
                "success" if response.status_code < 400 else "denied",
            )
            journal.commit()
    response.headers["Cache-Control"] = "no-store"
    return response
