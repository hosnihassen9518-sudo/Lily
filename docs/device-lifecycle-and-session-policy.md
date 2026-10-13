# Device provisioning and mobile account settings (0.8.0)

## Operator setup

Back up the database before upgrading. Backend startup applies the Alembic baseline/migration, preserving existing users and devices; `cd backend && alembic upgrade head` is also supported. PostgreSQL and SQLite are supported. The backend container now includes migration files.

Create one persistent P-256 signing key for device management. Never replace it on each restart or commit it to source control:

```sh
cd backend
python -m app.core.device_keys ./data/device-signing.pem
```

Set `DEVICE_SIGNING_KEY_FILE` to that file in the backend environment. Configure `FACTORY_BACKEND_HOST`, `FACTORY_BACKEND_PORT`, `FACTORY_MQTT_HOST`, and `FACTORY_MQTT_PORT` to the addresses reachable by the ESP32. These are manufacturing settings; mobile users change Wi-Fi only. Save and back up the signing key with the database.

With Compose, set factory host addresses in the root `.env`, rebuild/start the containers, then create the signing key once in the persistent backend data volume:

```sh
docker compose up -d --build
docker compose exec backend python -m app.core.device_keys /data/device-signing.pem
```

The command refuses to overwrite an existing private key. Inventory creation returns a setup error if the configured signing key is missing or invalid; it does not create a partial inventory device.

## Create and flash a device

Open Admin → Devices → Add device. Select the type and a compatible model. The supported models are LILY-V1 (audio/light, `esp32_device`) and Lily Test Light (`esp32_test_light`). Other types remain available in the platform but cannot generate unsupported firmware models.

Create the device and download its configuration immediately. The backend stores the factory secret's hash and the device receipt public key. It does not keep a recoverable copy of the plaintext secret or private receipt key. Keep the downloaded file privately.

Copy the download to `<firmware-target>/include/device_config.h`. Review the GPIO assignments for the actual board. This is a source header, not a flashable binary; build it into the firmware:

```sh
pio run --project-dir esp32_test_light
pio run --project-dir esp32_test_light --target upload
```

Use `esp32_device` for the audio/light model. The shared library must remain beside both target directories. Both targets use encrypted Secure Connections Just Works BLE bonding without passkey entry. New factory boards may format their empty LittleFS filesystem on first boot. Identity, reset markers and receipt keys live separately in NVS and survive a filesystem format.

Normal user resets preserve factory identity. Do not erase the entire ESP32 flash or NVS during normal account removal. When manufacturing a different inventory identity onto a previously used board, explicitly clear the old manufacturing identity first; changing the header is not an account-removal operation.

## Existing devices

Keep existing serials and factory secrets. Existing rows and manually provisioned inventory remain compatible. Install 0.8.0 firmware on both the app and device before using reset or Wi-Fi management. Export the server's public verification header:

```sh
cd backend
python -m app.core.device_keys ./data/device-signing.pem --public-header ../esp32_test_light/include/device_public_key.h
```

Add `#include "device_public_key.h"` to the existing private `device_config.h`. Set its firmware version to `0.8.0-test_light` or `0.8.0-lily_audio_light`, as applicable. The public header contains no signing secret. The firmware generates a persistent receipt identity for a legacy board and registers it using its existing factory credentials; a previously registered receipt identity cannot be silently replaced. The admin-only `/api/v1/admin/device-factory-public-key` endpoint also exposes the public key for operators.

Devices that have not registered the compatible management protocol prompt for an upgrade instead of being unlinked while retaining user configuration.

## Mobile login duration

Admin → Settings configures duration in whole months, from 1 to 12. The default is three calendar months after login or registration. For example, January 31 plus three months expires April 30. Changes apply to new sessions; existing sessions keep their original expiry.

The mobile app stores credentials in platform secure storage, silently rotates refresh credentials, and uses access tokens lasting at most 15 minutes. Refresh does not extend the absolute session expiry. A lost refresh response can be retried with the same persisted request ID until that session expires, provided a later rotation has not superseded it. Other reuse is rejected. Temporary connection failures keep the session and show a retryable error. Expired/revoked sessions and disabled users require authentication again. Explicit logout clears local credentials even if the server is unreachable. Changing backend addresses clears the old server's session.

Legacy saved access tokens continue until their existing expiry, followed by one login to establish the new session format. Admin portal login behavior is unchanged. Android backup is disabled to avoid restoring encrypted credentials without the platform key that can decrypt them.

## Change Wi-Fi

Open the device → Change Wi-Fi. Keep the phone near the ESP32, discover and bond with the device, then select a scanned 2.4 GHz network or enter a hidden SSID. Enter its password and save.

The app checks the exact serial and obtains device-specific owner authorization. Credentials travel over encrypted BLE; the backend does not store them. Firmware tests the candidate Wi-Fi and backend connection, saves atomically on success, and restores previous credentials on failure. Changing Wi-Fi preserves ownership, factory addresses, schedules, and downloaded audio.

Bluetooth stays available on configured devices, so users can change networks even when the old Wi-Fi is unavailable. Bluetooth operations are supported on Android/iOS; other platforms show availability guidance.

## Remove and reset

Open the device → Remove device and confirm. Normal controls stop while reset is pending. The ESP32 checks the persistent backend operation when connected, erases user files/settings and saved Wi-Fi/Bluetooth bonds, turns outputs off, and returns to BLE setup. Its factory serial/secret, receipt identity, server verification key remain intact.

The backend clears ownership, home/room placement, schedules, telemetry, user state, and the user-facing name only after verifying the device's signed completion receipt. It retains the factory inventory entry and its selected type/model. Retained MQTT schedules/state are cleared with acknowledgement before reassignment. If the broker is unavailable, activation waits for that cleanup to complete.

If the device is off or unreachable, removal remains **Reset pending**. Keep it near the phone and use **Finish reset over Bluetooth**, or wait for it to reconnect. Power loss during erasure leaves a durable reset marker; reboot resumes the erase operation. A receipt survives a lost acknowledgement and can be relayed through the app. If reset was confirmed on the server but the device missed the reply, the Add Device flow can relay the receipt and confirm Bluetooth recovery before provisioning.

After the device clears its saved bond, a phone that remembers the previous bond may need to forget the old Lily entry and pair again without a code. New owner setup requires compatible firmware and completion of the reset. The physical reset button is deferred; there is no GPIO reset action in this change.

## Acceptance checks

Automated coverage includes database preservation, calendar expiry, refresh retry/revocation, session restore/outage retention, generated headers including native C++ Unicode escaping, reset authorization and cleanup, legacy firmware refusal, and removal UI pending/completed states. Run backend tests with `python -m pytest`; PostgreSQL uses a disposable database selected by `LILY_TEST_DATABASE_URL` and per-test temporary schemas. Run `flutter test`, the admin production build, and both PlatformIO builds.

Before deployment to real devices, check both targets on the actual phone/ESP32: initial provisioning, correct and incorrect Wi-Fi changes, online/offline removal, power interruption at each erase/acknowledgement stage, fresh BLE advertising and bonding, no reconnection to old Wi-Fi, no old schedules/audio, receipt recovery, and pairing to a different account. Automated tests and builds do not establish physical BLE/radio or flash-write behavior.

Ownership transitions and device controls lock the current database row. Managed MQTT commands, schedules, and reports carry the ownership generation; firmware ignores stale or missing generations. Broker cleanup retries every 15 seconds while connected and on reconnection. Its durable pending flag blocks reassignment until PUBACK confirms cleanup.

The supplied LilyV7.apk is version 0.8.0 (build 5), built with the repository's existing debug signing configuration for sideload testing. If Android rejects an update because the installed build used a different key, back up needed local settings before replacing that installation. This build does not deploy the backend or flash the ESP32 firmware.
