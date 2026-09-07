from datetime import datetime, timezone
from sqlalchemy import String, DateTime, ForeignKey, JSON, Float, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column
from app.db.session import Base


class DeviceType(Base):
    __tablename__ = "device_types"

    id: Mapped[int] = mapped_column(primary_key=True)
    key: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class DeviceTypeCapability(Base):
    __tablename__ = "device_type_capabilities"
    __table_args__ = (
        UniqueConstraint("device_type_id", "capability", name="uq_type_capability"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    device_type_id: Mapped[int] = mapped_column(ForeignKey("device_types.id", ondelete="CASCADE"), index=True)
    capability: Mapped[str] = mapped_column(String(80), index=True)
    config: Mapped[dict] = mapped_column(JSON, default=dict)


class DeviceProfile(Base):
    """V0.5 smart-home metadata attached to the legacy Device row."""
    __tablename__ = "device_profiles"

    device_id: Mapped[int] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"), primary_key=True)
    device_type_id: Mapped[int | None] = mapped_column(ForeignKey("device_types.id"), nullable=True, index=True)
    home_id: Mapped[int | None] = mapped_column(ForeignKey("homes.id", ondelete="SET NULL"), nullable=True, index=True)
    room_id: Mapped[int | None] = mapped_column(ForeignKey("rooms.id", ondelete="SET NULL"), nullable=True, index=True)
    metadata_json: Mapped[dict] = mapped_column(JSON, default=dict)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )


class DeviceState(Base):
    __tablename__ = "device_states"

    device_id: Mapped[int] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"), primary_key=True)
    state: Mapped[dict] = mapped_column(JSON, default=dict)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc), index=True,
    )


class DeviceTelemetry(Base):
    __tablename__ = "device_telemetry"

    id: Mapped[int] = mapped_column(primary_key=True)
    device_id: Mapped[int] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"), index=True)
    metric: Mapped[str] = mapped_column(String(100), index=True)
    numeric_value: Mapped[float | None] = mapped_column(Float, nullable=True)
    text_value: Mapped[str | None] = mapped_column(Text, nullable=True)
    extra: Mapped[dict] = mapped_column(JSON, default=dict)
    recorded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )
