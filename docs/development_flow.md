# Development Flow

## 1. Backend

```powershell
cd backend
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python run.py
```

Swagger for the standalone backend:

```text
http://127.0.0.1:6100/docs
```

For a standalone backend, use `curl http://127.0.0.1:6100/health` to verify it.

## 2. Admin portal

```powershell
cd admin_portal
npm install
npm run dev
```

## 3. MQTT broker

For local development install Eclipse Mosquitto normally on the host.

Then in `backend/.env`:

```text
MQTT_ENABLED=true
MQTT_HOST=127.0.0.1
MQTT_PORT=1883
```

The ESP32 must point to the computer's LAN IP, not 127.0.0.1.

## 4. ESP32

Create `esp32_device/include/device_config.h` from the example.

Create the same serial/secret in Admin Portal.

Build/upload using PlatformIO.

## 5. Flutter app

```powershell
cd mobile_app
flutter create . --platforms=android,ios,web
flutter pub get
flutter run --dart-define=BACKEND_URL=http://YOUR_PC_LAN_IP:6100/api/v1
```

## Full pairing flow

```text
Admin creates factory inventory record
            │
            ▼
ESP32 flashed with same serial + secret
            │
            ▼
User creates account in Flutter
            │
            ▼
Flutter asks backend for 10-minute pairing token
            │
            ▼
Flutter joins ESP32 setup AP
            │
            ▼
Flutter sends home Wi-Fi + pairing token locally
            │
            ▼
ESP32 joins home Wi-Fi
            │
            ▼
ESP32 sends serial + factory secret + pairing token to backend
            │
            ▼
Backend validates all three
            │
            ▼
Device becomes owned by logged-in user
            │
            ▼
ESP32 connects MQTT and appears ONLINE
```
