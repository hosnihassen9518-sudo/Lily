# Lily Backend V0.5

FastAPI backend for the Lily smart-home platform. V0.5 introduces Home/Room organization, generic Device Types and Capabilities, latest device state, and time-series telemetry while remaining compatible with V0.4 devices.

Full V0.5 notes: `../docs/v0.5-smart-home-core.md`.

FastAPI backend for the Lily device platform.

## Requirements

- Python 3.11+ recommended
- MQTT broker is optional during early API development
- SQLite is used by default

## Windows setup

Open PowerShell inside the `backend` directory:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
python run.py
```

## Linux/macOS setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python run.py
```

Open:

```text
http://127.0.0.1:8000/docs
```

The SQLite database is automatically created as:

```text
backend/lily.db
```

## Initial admin

The first backend startup automatically creates the admin configured in `.env`.

Default development credentials:

```text
admin@example.com
ChangeThisAdminPassword!
```

Change these before sharing the service with anyone.

## MQTT

MQTT is disabled by default during the first development stage.

Install Mosquitto locally later, then configure:

```text
MQTT_ENABLED=true
MQTT_HOST=localhost
MQTT_PORT=1883
```

The API still runs when MQTT is disabled. Control endpoints return:

```json
{
  "mqtt_published": false
}
```

until MQTT is enabled.