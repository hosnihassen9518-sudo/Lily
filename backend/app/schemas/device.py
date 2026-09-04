from pydantic import BaseModel, Field

class DeviceCreate(BaseModel):
    serial_number: str
    device_secret: str = Field(min_length=16)
    model: str = "LILY-V1"
    hardware_version: str | None = None

class DeviceClaim(BaseModel):
    serial_number: str
    name: str | None = None

class DeviceActivate(BaseModel):
    serial_number: str
    device_secret: str
    firmware_version: str | None = None

class LightCommand(BaseModel):
    enabled: bool
    brightness: int = Field(ge=0, le=100)
    r: int = Field(ge=0, le=255)
    g: int = Field(ge=0, le=255)
    b: int = Field(ge=0, le=255)

class VolumeCommand(BaseModel):
    volume: int = Field(ge=0, le=100)
