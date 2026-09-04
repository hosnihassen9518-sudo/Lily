# Lily Device Platform

Development workspace for the complete connected RGB/audio device solution.

## Project structure

```text
lily_device_platform/
│
├── backend/          FastAPI server and API
├── admin_portal/     Admin web application
├── mobile_app/       Flutter Android/iOS application
├── esp32_device/     ESP32 firmware
└── docs/             Architecture and API notes
```

The components are intentionally separated so they can be developed and tested independently.

## Current development status

### Backend
Implemented and runnable locally:
- User registration/login
- JWT authentication
- Admin bootstrap user
- Device inventory
- Device ownership
- Device activation
- Device online/offline status
- MQTT presence/state handling
- RGB commands
- Audio play/stop/volume commands
- MP3 catalog
- MP3 upload/download
- Schedules
- Swagger/OpenAPI

### Admin portal
Implemented as a React/Vite application:
- Administrator login
- Dashboard
- Device inventory
- Online/offline monitoring
- Add/disable/delete devices
- User management
- Music management
- MP3 upload

### Mobile app
Folder reserved for the Flutter application. It will:
- Register/login users
- Provision Wi-Fi to ESP32
- Associate devices
- Browse/download audio
- Transfer MP3 to ESP32
- Control RGB light
- Control audio
- Manage schedules
- Show online/offline device state

### ESP32 device
Folder reserved for firmware. It will:
- Run Wi-Fi provisioning mode
- Authenticate with backend
- Maintain MQTT connection
- Publish online/offline status and heartbeat
- Receive RGB/audio commands
- Store one MP3 locally
- Run local schedules
- Expose local HTTP API for mobile MP3 upload
