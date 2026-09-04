# Architecture

```text
                   ┌─────────────────┐
                   │  Admin Portal   │
                   └────────┬────────┘
                            │ REST/HTTPS
                            │
                    ┌───────▼────────┐
                    │ FastAPI Backend│
                    └───────┬────────┘
                            │
               ┌────────────┼────────────┐
               │            │            │
             SQL          MQTT        MP3 files
               │            │
               ▼            ▼
          PostgreSQL     Mosquitto
                            │
                            │ MQTT
                            ▼
                         ESP32
                           ▲
                           │ local HTTP
                           │ MP3 upload +
                           │ provisioning
                           │
                    ┌──────┴───────┐
                    │ Flutter App  │
                    └──────────────┘
```

During development the backend defaults to SQLite so it can run without installing PostgreSQL.
Later, changing `DATABASE_URL` is enough to move to PostgreSQL.

## Communication responsibilities

### REST
- User registration/login
- Device listing and ownership
- Admin inventory
- Music catalog
- MP3 download
- Schedule management
- Device control requests

### MQTT
- Online/offline presence
- Heartbeat
- Device state
- RGB commands
- Audio play/stop/volume
- Schedule synchronization

### Local HTTP between mobile and ESP32
- Wi-Fi provisioning
- Read device information
- Upload one MP3 file
- Query local upload progress
