# Lily device provisioning, mobile sessions, and device reset

Date: 2026-10-11
Repository: hosnihassen9518-sudo/Lily, main
Inspected tree: 551986bfcabaf90e4377f88ecad9f2682f1852ec
Status: Approved by the user on 2026-10-11; implementation has not started.

## Agreed intent

Administrators create inventory devices by selecting device type and model. Lily generates the serial number and secret and provides a configuration header for compiling and flashing the ESP32. Mobile users remain signed in until their configured session expires, defaulting to three calendar months after authentication. Users can change their device's Wi-Fi credentials and remove their device from their account. Removal must erase learned user configuration and return the ESP32 to Bluetooth setup mode.

User-facing network configuration covers Wi-Fi SSID and password only. Backend and MQTT addresses remain factory configuration.

A physical reset button is future work and is excluded from this implementation. Firmware reset will be a reusable operation so that button can invoke it later.

## Existing system

The repository contains FastAPI/SQLAlchemy, a React admin portal, Flutter mobile, and two ESP32 firmware targets. Inventory creation currently requires manually entered serial and secret. Device types and profiles already exist; models are currently strings rather than a catalog. Access tokens have a static configured lifetime. Mobile startup logs out on any failure while fetching profile or data. The test-light firmware has bonded BLE provisioning but disables advertising after successful setup and enables it on boot only if Wi-Fi fails. The audio/light target uses local HTTP provisioning and needs BLE support for the requested reset behavior.

## Administrator provisioning

- Add an explicit model catalog with model key, display name, device type, hardware version, and firmware target. Seed entries for the two implemented firmware targets. Types without a supported model cannot generate flash configuration; do not imply that selecting a type creates corresponding hardware capabilities.
- The administrator selects type, then a compatible model. Backend validation enforces that relationship.
- Generate a unique serial using a database unique constraint and bounded collision retries. Generate a cryptographically random device secret within the existing bcrypt input limit.
- Save inventory, selected model, and device profile/type in one transaction. Preserve that type through activation rather than silently accepting a conflicting firmware type.
- Return the plaintext secret once with a downloadable `device_config.h`, generated from the supported target's example header. Include serial, secret, type, model, hardware defaults, and configured factory server addresses. Escape and validate all C string values.
- Show the generated serial and a download action in the create result. The header is compile-time configuration, used with PlatformIO to build and upload firmware; it is not itself a flashable binary.
- Persist only the secret hash. Do not expose the secret in inventory listing, logs, or browser persistent storage. Explain that the downloaded header must be saved; later retrieval of the original secret is unavailable.
- Retain compatibility for existing manually provisioned inventory and firmware during migration.

## Mobile session policy

Use short-lived access tokens and persisted, revocable mobile refresh sessions. This avoids using a three-month access token and gives the server authoritative expiry.

- Store a validated global mobile session duration in a database settings row. Default: three calendar months from login or registration, with end-of-month dates clamped to the last valid day. Admin portal exposes duration in months, allowed range 1–12.
- Each mobile session has an absolute expiry computed at authentication; refreshing does not extend it. Policy changes apply to newly created sessions; the admin form states that behavior.
- Store only a hash of each cryptographically random refresh credential on the server, with user, session identifier, creation, expiry, and revocation data. Rotate refresh credentials transactionally; tolerate concurrent mobile requests using a single-flight client refresh.
- Store mobile credentials in platform secure storage, scoped to the configured backend. Persist expiry metadata. Migrate legacy access tokens through the existing access-token flow; when those expire, require one login to create the new session.
- Restore unexpired sessions on app launch and silently refresh expired access tokens. Expired/revoked sessions or disabled users require login. A network timeout, unavailable backend, or unrelated data failure retains the unexpired session and presents a retryable error.
- Explicit logout revokes the refresh session when reachable and always clears local credentials. Changing the backend clears credentials for the old backend. Retain existing admin login behavior; the configurable duration governs mobile sessions.
- Keep pairing tokens short-lived and distinct from user access/refresh credentials.

## Wi-Fi changes

- Add a Change Wi-Fi action to device settings. Use bonded BLE, the existing paginated scan, hidden-network entry, and Wi-Fi validation.
- Backend issues a short-lived, device-specific operation authorization only to the current owner. Firmware validates authorization before applying credentials; Bluetooth bonding alone does not establish account ownership.
- Enable BLE on configured devices for this flow as well as setup/recovery. Use a separate update operation so changing Wi-Fi never claims or transfers a device.
- Firmware tests the requested network and backend connectivity, atomically saves credentials on success, and restores previous credentials on failure. Credentials travel locally over encrypted BLE, not through cloud MQTT or backend persistence.
- Preserve serial, factory secret, model, ownership, schedules, and other user settings during Wi-Fi changes. Never log passwords or authorization tokens.
- Extend audio/light firmware with the shared BLE provisioning support. Keep legacy provisioning compatible, while enforcing the same ownership checks for configuration updates.

## Removal and reset lifecycle

Removal is an acknowledged operation rather than simply clearing `owner_id`.

1. The authenticated owner confirms that removing the device erases its user settings and downloaded content. Backend transactionally creates a persistent reset operation and moves the device to RESET_PENDING. Hide it from normal controls but show pending progress to its former owner.
2. Block commands, schedules, new claims, activation, and Wi-Fi changes while reset is pending. Repeated removal requests return the same operation. Record the requesting user separately so eventual ownership removal does not lose progress access.
3. Send an operation notification over MQTT when available, and check pending operations whenever updated firmware reconnects. Backend persistence is the source of truth; broker publish success does not mean reset completion. Do not retain reset commands that could affect a later owner.
4. Firmware authenticates reset authorization against the backend using its factory credentials. For local BLE recovery, use a short-lived device-bound signed authorization that firmware can verify without a working Wi-Fi connection; provision the backend verification public key as factory configuration. Bind authorization to operation ID and device serial, and persist processed operation IDs to prevent replay.
5. Firmware saves a reset-in-progress marker, erases Wi-Fi files and temporary files, pairing/ownership session data, schedules and execution history, downloaded audio/uploads where present, remembered light/audio preferences, and Wi-Fi credentials stored by the ESP32 stack. Turn outputs off. Preserve factory identity/server addresses, firmware, the verification key, and the stable hardware pairing PIN.
6. Persist a reset-completed marker before acknowledging. For remote reset, keep only the current live connection long enough to report completion after saved credentials have been erased; never save those credentials again. Then disconnect Wi-Fi and reboot into unconfigured BLE advertising. On interruption or reboot, finish the marked reset and advertise BLE; completion can also be reported through the bonded mobile connection.
7. Backend accepts completion only with device authentication or a verifiable device-generated receipt relayed through BLE. In one transaction, clear owner, home/room association, schedules, telemetry/user state, and user-facing name; return the device to INVENTORY while retaining its type, model, serial, and secret hash. Clear retained schedules and stale broker state for the old configuration.
8. Clear reset operation delivery state after completion. Further acknowledgments are idempotent. Block stale operation messages after new activation using the stored completed operation ID and authorization rules.

Offline removal remains visibly reset pending. Updated firmware completes it when connectivity returns; the app can also guide the user through bonded nearby BLE reset. If the device is powered off and unreachable, no system can erase its storage immediately, so the app must not claim it has reset or make it available for another owner yet.

Unsupported older firmware is identified before starting removal and prompts the user to install the compatible firmware. Avoid unlinking an old device while leaving its learned configuration intact.

## Database and compatibility

Add versioned migrations for the model catalog, settings, refresh sessions, and reset operations. Support the existing SQLite development database and PostgreSQL deployment. Preserve current devices, credentials, and accounts; map known legacy models to supported catalog entries and retain unknown models as legacy entries without fabricated firmware support. Do not rely on `create_all` to modify existing tables. New lifecycle checks must cover legacy claim and activation endpoints as well as new endpoints.

## Validation

- Backend tests: admin authorization, supported type/model combinations, serial uniqueness, secret/header correctness, no secret exposure, existing database migration, session expiry and rotation, policy persistence, disabled users, owner authorization, reset retries, offline pending state, acknowledged cleanup, blocked claim/activation during reset, stale operation replay rejection.
- Admin checks: production build and interactive creation/download and settings validation.
- Flutter tests: restart with valid credentials, silent refresh, absolute expiry, concurrent requests, network outage retention, backend switch, logout, Wi-Fi flow and rollback errors, removal confirmation and pending/completed states.
- Firmware: build both targets; verify bounded parsing, authorization failures, reset persistence, interrupted reset recovery, credential erasure, Bluetooth recovery, Wi-Fi rollback, and removal of user files.
- Physical acceptance: provision each target, change Wi-Fi successfully and with a wrong password, remove online and offline, reboot during reset, verify no old Wi-Fi reconnect or schedule/audio execution, observe BLE advertising, and re-pair to another account. Build/test results cannot substitute for those hardware checks.

## Delivery boundaries

Implement backend/migrations, admin UI, mobile sessions and settings, and both firmware targets together with deployment and flashing instructions. Prepare a reviewable branch/PR after local checks. Deployment and physical flashing are separate from code implementation.

The current workspace cannot clone the repository because its configured proxy is unreachable. Inspection used the connected GitHub tools. This spec is a local review artifact; it has not been committed to the repository.
