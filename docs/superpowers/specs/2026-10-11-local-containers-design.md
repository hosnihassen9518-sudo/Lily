# Local Ubuntu container deployment

## Outcome

Start the Lily FastAPI backend, MQTT broker, and admin portal together with `docker compose up -d --build`, as three separate containers on a local Ubuntu server. Existing mobile and ESP32 protocols remain compatible. The user approved implementation and pushing to GitHub, including configurable host ports.

## Services

- `backend`: built from a new `backend/Dockerfile`, using Python 3.12 slim, the existing requirements, and one Uvicorn worker bound to port 6100. Run without development reload. One worker avoids duplicate MQTT clients using the fixed `lily-backend` client ID.
- `mqtt`: the official `eclipse-mosquitto:2` image, with a repository-owned Mosquitto configuration listening on port 1883. A custom MQTT image is unnecessary.
- `admin`: built with Node 22 and served with Nginx on internal port 6080. Bake `/api/v1` into the portal and proxy `/api/` to `backend:6100`, preserving the request path. Also proxy `/docs`, `/redoc`, and `/openapi.json` for convenient browser access. Support SPA routes and provide `/healthz` for container health.

The backend uses `MQTT_ENABLED=true`, `MQTT_HOST=mqtt`, and port 1883 over the Compose network. Phones and ESP32 devices use the Ubuntu server's LAN IP and the published backend and MQTT ports. Root `.env` variables `ADMIN_PORT`, `BACKEND_PORT`, and `MQTT_PORT` configure host ports, defaulting to 6080, 6100, and 1883; `BIND_ADDRESS` defaults to `0.0.0.0`. Internal service ports remain fixed. Changing host ports requires recreating containers, not rebuilding images.

## Configuration and persistence

Add root `compose.yaml`, root `.env.example`, `backend/.dockerignore`, `admin_portal/Dockerfile`, `admin_portal/.dockerignore`, `admin_portal/nginx.conf`, broker configuration under `deploy/mosquitto/`, and an Ubuntu deployment guide.

Compose requires a user-supplied JWT secret and initial admin password in the root `.env`. No real credentials, existing database, local environment files, or generated files are copied into the image.

Use a named backend volume mounted at `/data`, with SQLite at `/data/lily.db` and music at `/data/music`. Use a separate Mosquitto data volume with persistence enabled. This is a fresh deployment; the current local database is not automatically migrated.

## Startup and recovery

All services use `restart: unless-stopped`. Mosquitto has a publish-based health check. The backend waits for the broker's health check before starting; its HTTP health check uses the existing `/health` endpoint. The portal waits for backend HTTP health. That endpoint checks HTTP service availability and does not prove MQTT connectivity. Broker logs and an end-to-end LED command verify MQTT integration.

Compose manages startup order; a single command starts the whole stack, although the backend begins after the broker becomes healthy. Logs go to container stdout with bounded Docker log rotation.

## LAN compatibility

Enable anonymous MQTT for compatibility with the current ESP32 test-light firmware, whose connect call has no username/password. This deployment is intended for the local network, without router port forwarding. MQTT authentication and TLS would require coordinated firmware and backend changes and are outside this first deployment.

## Validation

Validate the Compose model with sample non-secret environment values and inspect the rendered ports, network hostname, volume paths, and startup dependency. Build and run both containers when a Docker engine is available, check HTTP health and broker logs, then restart the stack and confirm persistence. Report explicitly if runtime verification is unavailable.

## Alternatives considered

Separate Docker commands require manual network and lifecycle management. Compose provides the requested one-command lifecycle. An additional PostgreSQL container adds operational complexity beyond this first iteration; retain the existing SQLite default.
