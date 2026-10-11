# Lily Flutter App

One Flutter codebase for Android, iOS, and Web.

## Implemented

- User registration
- Login/logout and saved JWT
- Device list
- Online/offline status, auto refresh every 15 seconds
- Secure Wi-Fi provisioning flow
- Short-lived account/device pairing token
- RGB light control
- Brightness
- Color presets
- Audio play/stop/volume
- Music catalog
- Server MP3 download
- Direct local MP3 upload to ESP32
- Schedule list/create/delete

## Generate native Flutter folders

Flutter itself is not installed in the build environment used to prepare this project, so the source application is complete but the generated Android/iOS/Web runner folders are intentionally not checked in.

On your development PC:

```powershell
cd mobile_app
flutter create . --platforms=android,ios,web
flutter pub get
```

The existing `lib/` and `pubspec.yaml` are kept.

## Backend address

Tap the gear icon at the top right of the login screen or main screen to set
the server IP address/hostname, port (default 6100), and HTTP/HTTPS protocol.
The app adds `/api/v1` automatically and saves settings on this device across
restarts. A saved address overrides the build-time `BACKEND_URL` default.
Changing servers clears the current login and loaded devices; sign in again
on the selected server. Saving the same address keeps your session.

Use the Ubuntu server's LAN IP, not the container name `backend`. Backend
settings do not change the ESP32's own server configuration.

For a physical phone, the backend must be reachable on your LAN.

Example:

```powershell
flutter run --dart-define=BACKEND_URL=http://192.168.1.50:6100/api/v1
```

For Android emulator:

```powershell
flutter run --dart-define=BACKEND_URL=http://10.0.2.2:6100/api/v1
```

For Flutter Web on the same PC:

```powershell
flutter run -d chrome --dart-define=BACKEND_URL=http://127.0.0.1:6100/api/v1
```

## Android Wi-Fi permissions

After `flutter create .`, make sure AndroidManifest.xml contains the permissions required by the `wifi_iot` package, including nearby Wi-Fi/location permissions appropriate for your Android SDK level.

## iOS Wi-Fi

iOS requires the Hotspot Configuration capability for programmatic Wi-Fi joining. Add it in Xcode for the Runner target.

## Important web limitation

Browsers generally cannot programmatically join an ESP32 Wi-Fi network. The same Flutter app can run on Web for account/device control, but initial Wi-Fi provisioning is intended for Android/iOS.
