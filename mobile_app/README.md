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
