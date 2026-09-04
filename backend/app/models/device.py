from datetime import datetime, timezone
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Integer
from sqlalchemy.orm import Mapped, mapped_column
from app.db.session import Base

class Device(Base):
    __tablename__ = "devices"

    id: Mapped[int] = mapped_column(primary_key=True)
    serial_number: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    secret_hash: Mapped[str] = mapped_column(String(255))

    name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    model: Mapped[str] = mapped_column(String(80), default="LILY-V1")
    hardware_version: Mapped[str | None] = mapped_column(String(50), nullable=True)
    firmware_version: Mapped[str | None] = mapped_column(String(50), nullable=True)

    lifecycle_status: Mapped[str] = mapped_column(String(30), default="INVENTORY")
    owner_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)

    is_online: Mapped[bool] = mapped_column(Boolean, default=False)
    last_seen: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_connected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_disconnected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    wifi_rssi: Mapped[int | None] = mapped_column(Integer, nullable=True)
    free_heap: Mapped[int | None] = mapped_column(Integer, nullable=True)
    free_storage: Mapped[int | None] = mapped_column(Integer, nullable=True)

    light_on: Mapped[bool] = mapped_column(Boolean, default=False)
    brightness: Mapped[int] = mapped_column(Integer, default=100)
    color_r: Mapped[int] = mapped_column(Integer, default=255)
    color_g: Mapped[int] = mapped_column(Integer, default=255)
    color_b: Mapped[int] = mapped_column(Integer, default=255)

    audio_loaded: Mapped[bool] = mapped_column(Boolean, default=False)
    audio_playing: Mapped[bool] = mapped_column(Boolean, default=False)
    volume: Mapped[int] = mapped_column(Integer, default=50)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )
    activated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
