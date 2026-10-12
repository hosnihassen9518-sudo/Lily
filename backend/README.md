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

The backend listens on port 6100. When running the Docker stack, you can also
open the API docs through Nginx:

```text
http://127.0.0.1:6080/docs
```

For a standalone backend, open `http://127.0.0.1:6100/docs` or verify it using
`curl http://127.0.0.1:6100/health`.

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

## Device lifecycle and session policy

See [0.8.0 provisioning, login duration, Wi-Fi changes, and account reset](../docs/device-lifecycle-and-session-policy.md).
