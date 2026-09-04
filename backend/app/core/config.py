from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    app_name: str = "Lily Device Platform API"
    environment: str = "development"

    secret_key: str = "change-me"
    access_token_expire_minutes: int = 30

    database_url: str = "sqlite:///./lily.db"

    mqtt_enabled: bool = False
    mqtt_host: str = "localhost"
    mqtt_port: int = 1883
    mqtt_username: str | None = None
    mqtt_password: str | None = None

    music_dir: str = "./data/music"
    max_music_size_mb: int = 20

    cors_origins: str = "http://localhost:5173,http://127.0.0.1:5173"

    admin_email: str = "admin@example.com"
    admin_password: str = "ChangeThisAdminPassword!"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

settings = Settings()
