# Lily home-screen widgets

In Lily, open **Account → Home-screen widgets → Enable / refresh widgets**. Add Lily from the Android launcher or iPhone widget picker. Android has a scrolling device list; iOS small/medium/large sizes show one/two/four devices. On/Off sends an explicit desired state, preserving brightness and colour. Offline, disabled and reset-pending devices cannot be controlled. Refresh updates reported state; publication alone does not confirm the device changed.

Widgets follow the current mobile login's absolute expiry (default three calendar months, configurable in the admin portal). Logout or server changes revoke/clear widget access. Native widgets receive a restricted credential rather than the app's access/refresh tokens. Cached actions are bound to account and device ownership generation.

## Backend and admin

Use the existing Docker Compose deployment instructions. Backend startup runs Alembic upgrades, including `20261012_widgets`, before serving requests. Keep the `/data` volume persistent and writable. Fresh installations initialize a P-256 signing file atomically; established installations require the original key. Back up the key with the database: it signs device commands and decrypts archived provisioning files.

Admin device inventory supports type/model selection and generated serial/secret/header. **Show credentials**, **Download config file**, **Resync**, and **Remove** are available on device rows. Resync requests fresh state and resends schedules, retaining credentials. Device removal retains reset-pending protection. CSV exports standard metadata by default; the field chooser can explicitly include the device secret. Earlier devices with only password hashes cannot have their old secret recovered; their credential/config actions explain that limitation.

## iOS build and signing

The widget extension requires **iOS 17+**. The main app's earlier minimum OS is unchanged. Open `mobile_app/ios/Runner.xcworkspace` on macOS with Xcode. Set your signing team for both **Runner** and **LilyWidget** and register/enable the App Group `group.com.example.lilyMobile` for both App IDs. If you change the bundle identifier, consistently update App Group, Keychain group, entitlements, Info.plist values and build settings.

Runner's default Keychain group remains private; only `.widgets` is shared with the extension. Build Runner for a signed iPhone destination and verify LilyWidget.appex is embedded. Linux validation covers plist/entitlement permissions and Xcode source/resource/target references; it cannot replace an Xcode compile or device test.

## Phone acceptance checks

- Add each supported widget size and verify layout, On/Off, refresh and opening Lily.
- Confirm offline/reset-pending/sensor devices do not offer working power controls.
- Log out, switch backend/account, and expire the parent session; old controls must fail and old rows disappear.
- Reset and reclaim a device, then invoke an old widget action; refresh must be required.
- Suspend network/background refresh and verify retry preserves login. Displayed device status is the last reported snapshot and may be stale until refreshed.

Android builds use the existing sideload signing configuration. Production store signing and physical phone acceptance remain separate release checks.
