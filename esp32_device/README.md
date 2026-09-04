# ESP32 Firmware

Planned target: ESP32-S3.

Primary responsibilities:

- Hardcoded factory serial number
- Hardcoded factory device secret
- Initial Wi-Fi provisioning mode
- Local configuration HTTP service
- Backend activation
- MQTT persistent connection
- MQTT Last Will for offline status
- Online status publish
- Heartbeat every 30-60 seconds
- RGB LED control
- MP3 playback from flash
- Keep only one MP3
- Local HTTP MP3 upload endpoint
- SHA-256 validation before replacing current MP3
- Local schedule storage/execution

Planned filesystem:

```text
/current.mp3
/upload.tmp
/config.json
/schedules.json
```

MQTT topics:

```text
devices/<SERIAL>/command
devices/<SERIAL>/schedule
devices/<SERIAL>/status
devices/<SERIAL>/heartbeat
devices/<SERIAL>/state
```
