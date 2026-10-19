"""Persistence for human and API authorization; secrets are never stored here."""

from datetime import datetime, timezone
from sqlalchemy import String, Boolean, DateTime, ForeignKey, JSON, Integer, Text
from sqlalchemy.orm import Mapped, mapped_column
from app.db.session import Base


def now():
    return datetime.now(timezone.utc)


class Role(Base):
    __tablename__ = "access_roles"
    key: Mapped[str] = mapped_column(String(80), primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    audience: Mapped[str] = mapped_column(String(16), default="portal")
    predefined: Mapped[bool] = mapped_column(Boolean, default=False)
    permissions: Mapped[list] = mapped_column(JSON, default=list)
    revision: Mapped[int] = mapped_column(Integer, default=1)


class RoleAssignment(Base):
    __tablename__ = "access_role_assignments"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), primary_key=True)
    role_key: Mapped[str] = mapped_column(
        ForeignKey("access_roles.key"), primary_key=True
    )


class GrantCeiling(Base):
    __tablename__ = "access_grant_ceilings"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), primary_key=True)
    permissions: Mapped[list] = mapped_column(JSON, default=list)


class ServicePrincipal(Base):
    __tablename__ = "access_service_principals"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), primary_key=True)
    issuer_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    scope: Mapped[dict] = mapped_column(JSON, default=dict)


class ApiCredential(Base):
    __tablename__ = "access_api_credentials"
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("access_service_principals.user_id"), index=True
    )
    name: Mapped[str] = mapped_column(String(120))
    secret_hash: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    rate_limit: Mapped[int] = mapped_column(Integer, default=120)


class AccessSession(Base):
    __tablename__ = "access_sessions"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    permissions: Mapped[list] = mapped_column(JSON, default=list)
    role_revisions: Mapped[dict] = mapped_column(JSON, default=dict)
    scope: Mapped[dict] = mapped_column(JSON, default=dict)
    auth_method: Mapped[str] = mapped_column(String(16))
    credential_id: Mapped[str | None] = mapped_column(
        ForeignKey("access_api_credentials.id"), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )
    last_activity: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=now
    )


class AuditEvent(Base):
    __tablename__ = "access_audit"
    id: Mapped[int] = mapped_column(primary_key=True)
    actor_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    action: Mapped[str] = mapped_column(String(120))
    target: Mapped[str] = mapped_column(String(160))
    result: Mapped[str] = mapped_column(String(16), default="success")
    details: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=now, index=True
    )


class RateBucket(Base):
    __tablename__ = "access_rate_buckets"
    key: Mapped[str] = mapped_column(String(160), primary_key=True)
    count: Mapped[int] = mapped_column(Integer, default=0)
    reset_at: Mapped[int] = mapped_column(Integer, index=True)
