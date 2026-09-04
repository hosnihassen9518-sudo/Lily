# Lily ESP32-S3 Firmware

PlatformIO / Arduino firmware for the physical Lily device.

## Implemented

- Factory serial + factory device secret
- Wi-Fi setup AP
- Local `/info` endpoint
- Secure `/provision` endpoint
- Short-lived account pairing token support
- Backend activation
- Persistent home Wi-Fi credentials
- MQTT connection
- MQTT Last Will offline state
- Retained online state
- Heartbeat every 30 seconds
- RGB LED control
- MP3 play/stop/volume
- LittleFS MP3 storage
- One-audio-only replacement flow
- Temporary upload file
- SHA-256 validation
- MQTT state reporting
- Schedule JSON persistence
- Local NTP schedule execution
- Europe/Paris DST-aware timekeeping
- Duplicate-run protection per schedule/minute
- Reserved microphone pin definitions

## Required hardware

Recommended development target:

- ESP32-S3 with 16 MB flash
- WS2812/NeoPixel-compatible RGB LED
- I2S amplifier such as MAX98357A
- Speaker
- I2S microphone later, e.g. INMP441

## Create factory device config

Copy:

```text
include/device_config.example.h
```

to:

```text
include/device_config.h
```

Then change:

```cpp
#define DEVICE_SERIAL "LILY-000001"
#define DEVICE_SECRET "..."
#define BACKEND_HOST "192.168.1.50"
#define MQTT_HOST "192.168.1.50"
```

The serial + secret must match the inventory device created by the administrator portal.

## Build

Install VS Code + PlatformIO, then open `esp32_device/`.

Build:

```text
PlatformIO: Build
```

Upload:

```text
PlatformIO: Upload
```

## Local provisioning API

### GET /info

Returns device identity and setup state.

### POST /provision

```json
{
  "ssid": "HomeWiFi",
  "password": "password",
  "pairing_token": "short-lived-backend-token"
}
```

The ESP32 then joins the home network and calls:

```text
POST /api/v1/devices/activate
```

using:

- factory serial
- factory secret
- pairing token
- firmware version

The backend atomically associates the factory device with that user's account.

## MP3 upload

Mobile sends multipart POST to:

```text
POST /audio
```

with:

- `file`: MP3 bytes
- `sha256`: checksum supplied by the server catalog

Firmware writes `/upload.tmp`, verifies SHA-256, then replaces `/current.mp3`.

## MQTT

Subscribe:

```text
devices/<SERIAL>/command
devices/<SERIAL>/schedule
```

Publish:

```text
devices/<SERIAL>/status
devices/<SERIAL>/heartbeat
devices/<SERIAL>/state
```

## Scheduling

The ESP32 synchronizes time over NTP and applies the Europe/Paris timezone including daylight-saving transitions. Schedules received over MQTT are persisted in LittleFS and executed locally, so the mobile app does not need to remain open.

If a future hardware version needs schedules to survive long internet outages and full power loss without NTP access, an RTC can be added later without changing the backend/mobile schedule format.
