from datetime import datetime
from pydantic import BaseModel, Field, ConfigDict, PositiveInt


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class RoleInput(Strict):
    key: str = Field(pattern=r"^[a-z][a-z0-9_]{2,79}$")
    name: str = Field(min_length=1, max_length=120)
    permissions: list[str] = Field(max_length=100)


class RoleEdit(Strict):
    name: str = Field(min_length=1, max_length=120)
    permissions: list[str] = Field(max_length=100)


class Assignment(Strict):
    roles: list[str] = Field(max_length=50)


class Ceiling(Strict):
    permissions: list[str] = Field(max_length=100)


class UserInput(Strict):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=12, max_length=72)
    roles: list[str] = Field(default_factory=list, max_length=50)


class UserStatus(Strict):
    active: bool = Field(strict=True)


class ResourceScope(Strict):
    all: bool = False
    devices: list[PositiveInt] = Field(default_factory=list, max_length=500)
    homes: list[PositiveInt] = Field(default_factory=list, max_length=500)


class CredentialInput(Strict):
    name: str = Field(min_length=1, max_length=120)
    roles: list[str] = Field(max_length=50)
    scope: ResourceScope
    expires_at: datetime
    rate_limit: int = Field(default=120, ge=1, le=100000)


class Exchange(Strict):
    credential: str = Field(min_length=40, max_length=180)


class PasswordReset(Strict):
    password: str = Field(min_length=12, max_length=72)
