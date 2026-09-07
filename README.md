# Lily Device Platform — V0.5 Smart Home Core

> V0.5 adds generic smart-home Homes, Rooms, Device Types, Capabilities, State and Telemetry while preserving V0.4 RGB/audio compatibility. See `docs/v0.5-smart-home-core.md`.

Complete development workspace for the connected RGB/audio device.

```text
lily_device_platform/
│
├── backend/          FastAPI REST API + database + MQTT integration
├── admin_portal/     React/Vite administration portal
├── mobile_app/       Flutter Android/iOS/Web companion app
├── esp32_device/     ESP32-S3 PlatformIO firmware
└── docs/             Architecture and development notes
```

## Current V0.4 coverage

### Backend
- User registration/login
- JWT auth
- Device inventory
- Secure factory device activation
- Short-lived pairing tokens
- Device ownership
- Online/offline state
- MQTT telemetry
- RGB/audio commands
- Music catalog/files
- Schedules
- Admin APIs

### Admin Portal
- Admin login
- Dashboard
- Device inventory
- Add/disable/delete devices
- Online/offline monitoring
- User management
- Music upload/publish/delete

### Flutter App
- Android/iOS/Web source
- Registration/login
- Device list + presence
- Secure Wi-Fi pairing
- RGB controls
- Audio controls
- Music catalog
- MP3 server download
- Direct MP3 device upload
- Schedules
- Account/logout

### ESP32
- ESP32-S3 PlatformIO firmware
- Factory serial/secret
- Setup Wi-Fi AP
- Secure pairing
- Backend activation
- MQTT LWT/presence/heartbeat
- RGB control
- MP3 LittleFS storage/playback
- One-file replacement
- SHA-256 verification
- Schedule synchronization storage

See `docs/development_flow.md` for startup order.