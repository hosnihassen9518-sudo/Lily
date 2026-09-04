from pydantic import BaseModel

class ActiveUpdate(BaseModel):
    active: bool

class DisabledUpdate(BaseModel):
    disabled: bool

class EnabledUpdate(BaseModel):
    enabled: bool
