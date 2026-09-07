from datetime import datetime
from typing import Any
from pydantic import BaseModel, Field


class HomeCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    timezone: str = Field(default="Europe/Paris", max_length=80)


class HomeUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    timezone: str | None = Field(default=None, max_length=80)


class RoomCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    icon: str | None = Field(default=None, max_length=80)


class RoomUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    icon: str | None = Field(default=None, max_length=80)


class DeviceTypeCreate(BaseModel):
    key: str = Field(pattern=r"^[a-z0-9][a-z0-9_-]{1,79}$")
    name: str = Field(min_length=1, max_length=120)
    description: str | None = None
    capabilities: list[str] = Field(default_factory=list)


class DeviceProfileUpdate(BaseModel):
    home_id: int | None = None
    room_id: int | None = None
    device_type_id: int | None = None
    metadata: dict[str, Any] | None = None


class GenericCommand(BaseModel):
    type: str = Field(min_length=1, max_length=80)
    payload: dict[str, Any] = Field(default_factory=dict)


class DeviceStateUpdate(BaseModel):
    state: dict[str, Any]


class TelemetryIn(BaseModel):
    metric: str = Field(min_length=1, max_length=100)
    value: float | int | str | bool | None = None
    extra: dict[str, Any] = Field(default_factory=dict)
    recorded_at: datetime | None = None
