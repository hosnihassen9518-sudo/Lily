# Ubuntu LAN deployment

This Compose stack starts three separate containers: `admin` (Nginx),
`backend` (FastAPI), and `mqtt` (Mosquitto). It requires Docker Engine
with the Docker Compose plugin: https://docs.docker.com/engine/install/ubuntu/.

## First startup

Clone the repository on the Ubuntu server, then work in its root:

```bash
git clone https://github.com/hosnihassen9518-sudo/Lily.git
cd Lily
cp .env.example .env
chmod 600 .env
openssl rand -hex 32
nano .env
```

Paste the generated value into `SECRET_KEY` and choose `ADMIN_PASSWORD`.
Keep the password under 72 UTF-8 bytes because the current backend uses bcrypt.
Single-quote environment values containing `$` or `#` to keep them literal.
Set the initial `ADMIN_EMAIL` as desired. Compose refuses to start if either
required secret is empty. The root `.env` is separate from `backend/.env`;
the latter is excluded from the image.

Change the published ports if desired:

```dotenv
BIND_ADDRESS=0.0.0.0
ADMIN_PORT=8080
BACKEND_PORT=8000
MQTT_PORT=1883
```

`BIND_ADDRESS` may instead be the server's LAN IP. Internal container ports
remain fixed, so changing published ports requires no image changes.

```bash
docker compose config --quiet
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 backend mqtt admin
```

Compose waits for MQTT health before starting the backend, and for backend
health before starting the portal. All services restart automatically after
server reboot while Docker is enabled, unless explicitly stopped.

## Access from the LAN

For a server at `192.168.1.100` and the example ports above:

| Client | Address |
| --- | --- |
| Admin portal | `http://192.168.1.100:8080` |
| Backend API docs | `http://192.168.1.100:8000/docs` |
| Backend health | `http://192.168.1.100:8000/health` |
| MQTT clients | `192.168.1.100:1883` |

Log into the portal with the initial admin email/password from the root `.env`.
The portal sends requests to `/api/v1` on its own origin; Nginx forwards these
to `backend:8000`. It works with any `ADMIN_PORT` without rebuilding its API URL.

For the mobile application, use the published backend address:

```bash
flutter build apk --release --dart-define=BACKEND_URL=http://192.168.1.100:8000/api/v1
```

In the ESP32 configuration set `BACKEND_HOST` and `MQTT_HOST` to the server LAN IP,
and `BACKEND_PORT` and `MQTT_PORT` to the published ports from `.env`.
Container names such as `mqtt` only resolve inside the Compose network.

The broker allows anonymous MQTT to match the current ESP32 firmware.
Keep these services on the trusted LAN; do not forward these ports on your router.
If the server has a firewall, allow the selected TCP ports from your LAN subnet.
Browser clients calling the backend directly need their origin added to
`CORS_ORIGINS`; the portal's same-origin proxy does not require that.

## Verification

```bash
curl --fail http://192.168.1.100:8000/health
curl --fail http://192.168.1.100:8080/healthz
docker compose exec mqtt mosquitto_pub -h localhost -t lily/manual-check -m ok -q 1
docker compose logs --tail=100 backend
```

Backend logs should show `MQTT connected: Success`. HTTP `/health` reports
whether MQTT is configured, not whether the MQTT connection is healthy.
Verify device control using an actual command from the mobile application.

## Storage, updates, and restart

Named volumes retain the SQLite database, music, and Mosquitto persistence.
This deployment starts with a new database; it does not copy an existing
development database or device inventory. Changing the initial admin password
in `.env` does not reset an account already stored in the database.

```bash
# Recreate after editing ports or environment settings:
docker compose up -d

# Update source and rebuild:
git pull --ff-only
docker compose up -d --build

# Stop and remove containers while preserving named volumes:
docker compose down
```

Do not use `docker compose down -v` unless you intend to delete stored data.
Keep one backend replica/worker: the backend uses a fixed MQTT client ID and SQLite.

For a consistent local backup, stop the backend and copy `/data` before restarting:

```bash
mkdir -p backups
docker compose stop backend
backend_id=$(docker compose ps --all --quiet backend)
docker cp "$backend_id:/data" "backups/backend-$(date +%Y%m%d-%H%M%S)"
docker compose start backend
```

Treat backups as private because they contain accounts and device secrets.

## Troubleshooting

- Port already allocated: change the corresponding host port in `.env` and run
  `docker compose up -d`.
- Backend fails startup: check `docker compose logs backend` for database or
  initial admin errors. A new named volume is initialized with backend write
  permissions; manually supplied storage must be writable by UID 10001.
- Broker unhealthy: check `docker compose logs mqtt` and that the mounted
  configuration file exists.
- Portal loads but API requests fail: check backend health and both service logs;
  do not configure the browser to call the container-only hostname `backend`.

Compose startup behavior: https://docs.docker.com/compose/how-tos/startup-order/.
Mosquitto image configuration: https://github.com/eclipse-mosquitto/mosquitto/blob/master/docker/generic/README.md.
