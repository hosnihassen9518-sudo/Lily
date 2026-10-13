from datetime import datetime, timezone
from sqlalchemy import String, Text, DateTime, ForeignKey, Integer, JSON
from sqlalchemy.orm import Mapped, mapped_column
from app.db.session import Base

def utcnow():
    return datetime.now(timezone.utc)

class DeviceModel(Base):
    __tablename__ = 'device_models'
    key: Mapped[str] = mapped_column(String(80), primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    device_type_id: Mapped[int] = mapped_column(ForeignKey('device_types.id'))
    hardware_version: Mapped[str] = mapped_column(String(50), default='1.0')
    firmware_target: Mapped[str] = mapped_column(String(80))
    capabilities: Mapped[list[str] | None] = mapped_column(JSON(none_as_null=True), nullable=True)

class AppSetting(Base):
    __tablename__ = 'app_settings'
    key: Mapped[str] = mapped_column(String(80), primary_key=True)
    value_json: Mapped[dict] = mapped_column(JSON)

class MobileSession(Base):
    __tablename__ = 'mobile_sessions'
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'), index=True)
    current_refresh_hash: Mapped[str] = mapped_column(String(64), unique=True)
    previous_refresh_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    rotation_request_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    rotated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

class DeviceIdentity(Base):
    __tablename__ = 'device_identities'
    device_id: Mapped[int] = mapped_column(ForeignKey('devices.id'), primary_key=True)
    receipt_public_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    generation: Mapped[int] = mapped_column(Integer, default=0)
    protocol_version: Mapped[int] = mapped_column(Integer, default=0)

class DeviceOperation(Base):
    __tablename__ = 'device_operations'
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    device_id: Mapped[int] = mapped_column(ForeignKey('devices.id'), index=True)
    requested_by_id: Mapped[int] = mapped_column(ForeignKey('users.id'))
    generation: Mapped[int] = mapped_column(Integer)
    kind: Mapped[str] = mapped_column(String(30), default='reset')
    status: Mapped[str] = mapped_column(String(30), default='pending')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    broker_cleanup_pending: Mapped[int] = mapped_column(Integer, default=0)
