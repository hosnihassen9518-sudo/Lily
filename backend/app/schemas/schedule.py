from datetime import time
from pydantic import BaseModel, Field, field_validator

class ScheduleCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    time_of_day: time
    days_of_week: list[int] = Field(min_length=1)
    action: dict
    enabled: bool = True

    @field_validator("days_of_week")
    @classmethod
    def validate_days(cls, value):
        if not value:
            raise ValueError("Select at least one day")
        if any(day < 0 or day > 6 for day in value):
            raise ValueError("days_of_week values must be between 0 and 6")
        return sorted(set(value))
