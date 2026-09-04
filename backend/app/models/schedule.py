from datetime import datetime, timezone, time
from sqlalchemy import String, Boolean, DateTime, ForeignKey, JSON, Time
from sqlalchemy.orm import Mapped, mapped_column
from app.db.session import Base

class Schedule(Base):
    __tablename__ = "schedules"

    id: Mapped[int] = mapped_column(primary_key=True)
    device_id: Mapped[int] = mapped_column(ForeignKey("devices.id"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)

    name: Mapped[str] = mapped_column(String(120))
    time_of_day: Mapped[time] = mapped_column(Time)
    days_of_week: Mapped[list] = mapped_column(JSON, default=list)
    action: Mapped[dict] = mapped_column(JSON)

    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )
