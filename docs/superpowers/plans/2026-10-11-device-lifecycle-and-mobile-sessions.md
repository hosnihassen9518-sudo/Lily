# Device Lifecycle and Mobile Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Generate ESP32 inventory credentials, retain configurable mobile sessions, change Wi-Fi from mobile, and erase user settings before completing device removal.

**Architecture:** Extend the existing FastAPI, React, Flutter, and ESP32 flows. SQL holds model/session policy and durable reset operations; a shared firmware module provides bonded BLE and recoverable reset for both firmware targets. Ownership becomes transferable only after authenticated reset completion.

**Tech Stack:** FastAPI, SQLAlchemy, Alembic, pytest, React/Vite, Flutter, platform secure storage, Arduino/PlatformIO, ArduinoJson, ESP32 mbedTLS, MQTT.

**Spec:** `docs/superpowers/specs/2026-10-11-device-lifecycle-and-mobile-sessions-design.md`

## Global Constraints

- Default: three calendar months from login or registration; end-of-month dates clamp to the last valid day.
- Admin duration is in months, allowed range 1–12; changes apply to newly created sessions.
- Refresh never extends absolute session expiry. Preserve valid sessions through transient network failures.
- User network configuration covers Wi-Fi SSID/password only.
- Preserve factory identity/server addresses, firmware, verification key, and stable hardware pairing PIN through reset.
- Removal clears learned configuration and returns the device to unconfigured BLE advertising.
- Offline removal is reset pending; claims and activation are blocked until verified completion.
- Support SQLite and PostgreSQL; migrate existing installations without dropping accounts or devices.
- Keep pairing tokens short-lived and separate from user credentials; never log secrets.
- Physical reset button is future work. Use a shared reset function that can support it later.
- All API paths below are relative to `/api/v1`. Only implemented hardware models generate headers.

## Review Focus

1. Calendar-month expiry across leap years and time zones: test exact UTC dates in Task 3.
2. Lost refresh response and concurrent refresh: test credential rotation recovery and single-flight in Tasks 3 and 4.
3. Reboot after erasure but before acknowledgement: test durable completion receipt and blocked reactivation in Tasks 6 and 7.
4. An old authorized BLE or MQTT message reaching a new owner: test operation generation, nonce binding, and completed-ID rejection in Tasks 6 and 7.
5. Legacy models/firmware and unsupported mobile platforms: test explicit upgrade/support messages rather than partial reset in Tasks 1, 2, and 9.

## Structure and execution

This plan contains three deliveries in order: inventory creation (Tasks 1–2), sessions (Tasks 3–5), and device Wi-Fi/reset (Tasks 6–9). Each delivery can be reviewed separately. Task 10 validates them together. Shared backend changes are sequential. Tests use temporary databases, fake clocks, fake HTTP/MQTT, and fake BLE transports; physical-device checks are separate.

Repository acquisition is a prerequisite to product edits. The workspace currently contains these design artifacts only; the GitHub connector was used for inspection because the configured proxy is unreachable. Restore clone access through the supported environment networking path, then clone into a temporary sibling directory, check repository instructions and current main, and move the review artifacts into an isolated feature branch. If main has changed since tree `551986bfcabaf90e4377f88ecad9f2682f1852ec`, reconcile the plan before editing. Never represent this directory as a full checkout or claim unrun tests passed.

### Task 1: Persistent schema and model inventory

**Files:** Create `backend/alembic.ini`, `backend/migrations/env.py`, `backend/migrations/versions/20261011_device_lifecycle.py`, `backend/app/models/device_lifecycle.py`, `backend/tests/conftest.py`, `backend/tests/test_migrations.py`; modify `backend/requirements.txt`, `backend/app/main.py`, `backend/app/models/__init__.py`.

**Interfaces:** Produce `DeviceModel(key, name, device_type_id, hardware_version, firmware_target, supports_generation)`; `AppSetting(key, value_json)`; `MobileSession(id, user_id, current_refresh_hash, previous_refresh_hash, rotation_request_id, expires_at, revoked_at)`; `DeviceOperation(id, device_id, requested_by_id, kind, generation, status, created_at, completed_at)`; `DeviceIdentity(device_id, receipt_public_key, generation)`. Keep model identity in `DeviceProfile.metadata_json` so legacy Device.model remains compatible.

- [ ] Write migration tests asserting an existing SQLite database retains IDs, secret hashes, owners, schedules, and types; new tables exist; upgrade twice is safe. Test an unknown legacy model retains its label and cannot generate a header.
- [ ] Run `cd backend && python -m pytest tests/test_migrations.py -v`; confirm failure before implementation.
- [ ] Implement versioned migration, legacy baseline detection, new mapped models, and supported model seeds (`lily_v1` / `lily_audio_light` / `esp32_device`; `lily_test_light` / `test_light` / `esp32_test_light`). Bootstrap uses migrations before seed data, not `create_all` to alter existing schemas. Initialize `mobile_session_months` to 3.
- [ ] Run migration tests on SQLite and a disposable PostgreSQL service; assert constraints and rollback behavior on both. Run `alembic upgrade head` on a copied development database.
- [ ] Commit schema, tests, and migration instructions.

### Task 2: Generated inventory and admin download

**Files:** Create `backend/app/services/device_inventory.py`, `backend/app/schemas/device_inventory.py`, `backend/tests/test_device_inventory.py`; modify `backend/app/api/devices.py`, `backend/app/api/admin.py`, `backend/app/core/config.py`, `admin_portal/src/pages/DevicesPage.jsx`, `admin_portal/src/services/api.js`, both `esp32_*/include/device_config.example.h`.

**Interfaces:** `GET /admin/device-models?device_type_id=N` returns compatible models. `POST /admin/device-inventory` accepts `{device_type_id, model_key}` and returns `{device, serial_number, device_secret, filename, config_header}` once. `create_inventory(db: Session, type_id: int, model_key: str) -> InventoryResult`; `render_device_header(model: DeviceModel, credentials: FactoryCredentials) -> str`.

- [ ] Add tests for admin-only creation, invalid combinations, unsupported models, unique serial collision retries, hash verification, transaction rollback, correct per-target macros/pins, C-string escaping, and no secret in list responses. Assert activation cannot overwrite the generated type with a different firmware type.
- [ ] Run `python -m pytest tests/test_device_inventory.py -v` from backend and confirm initial failure.
- [ ] Implement generation using `secrets.token_urlsafe(32)` and unique random serials with five bounded retries. Generate an ECDSA P-256 device receipt key pair: only the public key is persisted server-side; the private key appears once in the factory header. Add factory backend verification public key to each supported header. Configure the backend signing key outside source control; missing configuration returns an actionable error and creates no inventory row. Preserve manual legacy inventory creation.
- [ ] Replace manual entry in admin creation with type/model selectors. Keep the creation result open until download; download `<serial>-device_config.h` from memory, revoke Blob URLs, and warn that the secret cannot be retrieved later. Do not store generated credentials in localStorage.
- [ ] Run backend tests and `cd admin_portal && npm run build`; manually verify validation and header download for both models.
- [ ] Commit generated inventory and admin UI.

### Task 3: Mobile session policy and refresh API

**Files:** Create `backend/app/services/mobile_sessions.py`, `backend/tests/test_mobile_sessions.py`; modify `backend/app/core/security.py`, `backend/app/api/auth.py`, `backend/app/api/deps.py`, `backend/app/schemas/auth.py`, `backend/app/api/admin.py`.

**Interfaces:** `POST /auth/mobile/login`, `/auth/mobile/register` return `{access_token, refresh_token, token_type, access_expires_at, session_expires_at, session_id}`. `POST /auth/mobile/refresh` accepts `{refresh_token, request_id}` and returns that shape. `POST /auth/mobile/logout` accepts `{refresh_token}`. `GET/PATCH /admin/mobile-session-policy` uses `{months: int}`. `calendar_expiry(now: datetime, months: int) -> datetime`; `issue_mobile_session(db, user, now) -> MobileTokenResponse`; `rotate_mobile_session(db, refresh_token, request_id, now) -> MobileTokenResponse`.

- [ ] Write tests asserting default expiry, Jan 31 plus three months = Apr 30, Nov 30 plus three months in a leap year = Feb 29, UTC consistency, range validation, policy persistence, existing-session expiry unchanged, logout revocation, disabled users, absolute expiry, wrong token type, and legacy admin login compatibility.
- [ ] Add rotation tests: reused refresh with a different request ID fails; retry with the same ID within a 60-second recovery window returns the same replacement credential; a crash/lost response does not unnecessarily force login. Store only credential hashes; derive the replacement credential reproducibly from session ID and request ID with a separate server HMAC key, without persisting plaintext. Serialize rotation using a conditional database update and check row count on both database engines.
- [ ] Run `python -m pytest tests/test_mobile_sessions.py -v`; confirm failure.
- [ ] Implement the above API and pure date function. Set mobile access expiry to 15 minutes capped by absolute session expiry. Access tokens include the session ID; dependencies verify access token type, active user, and unrevoked/unexpired session for mobile tokens. Keep existing admin access lifetime. Cap the brief refresh retry window at session expiry.
- [ ] Run tests on both database engines and confirm refresh credentials/pairing tokens cannot authorize access endpoints.
- [ ] Commit backend session policy and API.

### Task 4: Secure mobile persistence and silent refresh

**Files:** Create `mobile_app/lib/models/mobile_session.dart`, `mobile_app/lib/services/session_store.dart`, `mobile_app/test/mobile_session_test.dart`, `mobile_app/test/session_restore_test.dart`; modify `mobile_app/pubspec.yaml`, `mobile_app/pubspec.lock`, `mobile_app/lib/services/api_service.dart`, `mobile_app/lib/state/app_state.dart`, platform secure-storage configuration as required by the chosen package.

**Interfaces:** `MobileSession.fromJson(Map<String,dynamic>)`; `SessionStore.read(String backendUrl)`, `.write(String backendUrl, MobileSession session)`, `.clear(String backendUrl)`; inject SessionStore and clock into AppState. ApiService uses a single authenticated `request(method, path, body)` for JSON, lists, and binary downloads; expose typed `ApiException(statusCode, message)` and one in-flight refresh Future.

- [ ] Write fake-client/store tests for valid restore, access expiry, concurrent 401 requests causing one refresh, session expiry requiring login, 403 retaining session, timeout/500 retaining session, refresh retry after lost response, malformed stored data, logout during an in-flight request, and backend switching. Assert session revision guards prevent an old request restoring cleared credentials.
- [ ] Run `flutter test test/mobile_session_test.dart test/session_restore_test.dart`; confirm initial failure.
- [ ] Add secure storage, MobileSession, and restoration. Save a refresh request ID before sending and retain it across failed responses/restarts until successful rotation. Retry an authenticated request at most once after refresh; refresh endpoints never recurse. Keep legacy token migration until first expiry. Centralize current direct list/download calls under the same authentication handling.
- [ ] Clear local credentials even if logout request fails; retain the existing session-revision guards. Distinguish expired/rejected credentials from temporary data errors in initialize/login/refresh. Display retryable connectivity errors without navigating to login.
- [ ] Run focused tests, existing backend-settings tests, `flutter analyze`, and full `flutter test`.
- [ ] Commit mobile session changes and platform setup.

### Task 5: Admin session settings

**Files:** Create `admin_portal/src/pages/SettingsPage.jsx`; modify `admin_portal/src/App.jsx`, `admin_portal/src/components/Layout.jsx`, `admin_portal/src/services/api.js`.

**Interfaces:** `api.mobileSessionPolicy()` and `api.setMobileSessionPolicy({months})` consume Task 3 API.

- [ ] Implement Settings navigation and a form with default 3, integer months 1–12, load/save/error states, and explicit text that changes apply to future logins. Disable duplicate saves and reflect persisted values after success.
- [ ] Run `npm run build`. Exercise 1, 3, 12, rejected 0/13/fractional input, save failure, reload, and unauthorized access against the backend.
- [ ] Commit admin settings.

### Task 6: Authorized Wi-Fi operations and persistent reset

**Files:** Create `backend/app/services/device_operations.py`, `backend/app/services/device_authorization.py`, `backend/app/api/device_operations.py`, `backend/app/schemas/device_operations.py`, `backend/tests/test_device_operations.py`; modify `backend/app/main.py`, `backend/app/api/devices.py`, `backend/app/api/smart_home.py`, `backend/app/api/schedules.py`, `backend/app/services/mqtt_service.py`.

**Interfaces:** `POST /devices/{id}/wifi-session` accepts `{challenge}` and returns `{authorization}`; `POST /devices/{id}/removal` returns `{operation_id,status}`; `GET /device-operations/{id}` returns progress to requesting user/admin; `POST /device-operations/{id}/ble-authorization` accepts `{challenge}`; `POST /device-runtime/operations` accepts `{serial_number,device_secret}` and returns pending operation authorization; `POST /device-runtime/reset-complete` accepts `{receipt}` and is usable by firmware or a mobile relay. `ensure_device_mutable(db, device, user)` guards all device commands, state/profile/name updates, schedules, claim and activation paths.

- [ ] Write tests for owner-only actions, disabled devices, firmware capability checks, idempotent removal, offline pending, reset notifications after reconnect/backend restart, transactional cleanup only on verified receipt, old-owner progress access, inventory identity/type preservation, and stale-message replay after reactivation. Assert unsigned acknowledgements cannot release inventory.
- [ ] Run `python -m pytest tests/test_device_operations.py -v`; confirm failure.
- [ ] Implement P-256/SHA-256 signed authorization, a bounded versioned JSON envelope, and signature verification fixtures shared with firmware. Bind serial, operation kind/ID, ownership generation, and a random 32-byte BLE challenge. For clockless offline BLE verification, the challenge is generated fresh by firmware and is valid only for its current encrypted connection; backend expiry limits issuance. Reject challenge reuse. Backend-connected operations authenticate against server state before erasure. Keep envelope under 2048 bytes and use strict JSON/type/length validation.
- [ ] Persist RESET_PENDING and operation atomically, block normal mutations, and send non-retained MQTT notification only after commit. Recheck pending operations after reconnect and by periodic authenticated device HTTP polling; do not depend on MQTT for durability. Clear retained schedule/state/status data upon completion, retry broker cleanup on reconnection, and discard incoming user-state telemetry while reset is pending.
- [ ] Verify device completion receipts signed with Task 2 device key and matching operation/generation. Existing devices register a firmware-generated receipt public key through a factory-secret-authenticated registration endpoint; refuse replacement during reset. Never persist the factory secret or receipt private key.
- [ ] Run tests including concurrent reset requests and activation races on SQLite/PostgreSQL. Commit API, guards, and shared protocol fixtures.

### Task 7: Shared bonded BLE and recoverable firmware reset

**Files:** Create `firmware_shared/include/device_lifecycle.h`, `firmware_shared/src/device_lifecycle.cpp`, `firmware_shared/include/device_authorization.h`, `firmware_shared/src/device_authorization.cpp`, `firmware_shared/tests/reset_state_test.cpp`; move the shared BLE code from `esp32_test_light/include/ble_provisioning.h` and `esp32_test_light/src/ble_provisioning.cpp` into `firmware_shared`; modify both targets' `platformio.ini` and `src/main.cpp`.

**Interfaces:** `requestUserReset(const AuthorizedOperation&) -> ResetResult`; `resumeUserReset() -> ResetResult`; `beginBleProvisioning(bool configured, BleProvisionHandler handler)` remains compatible. Extend requests with `command`, `authorization`, and expose `protocol_features`, model, serial, ownership generation, and current challenge in encrypted info. Commands: `provision`, `update_wifi`, `reset`, existing scan/ack. Persistent reset states: prepared → erased → completion_pending → acknowledged; never roll back to configured after prepared.

- [ ] Write reset state-machine tests using fake storage/network/output adapters: power loss at every state transition resumes erasure; completed receipt survives restart; duplicate operations are harmless; stale generation/challenge and malformed signatures fail before any write; factory settings/PIN persist; all user files and ESP32 Wi-Fi persistence are erased.
- [ ] Run the host/native PlatformIO test environment and confirm failure before implementing the state machine.
- [ ] Implement authorization verification with ESP32 mbedTLS and the exact Task 6 fixtures. Generate and retain a device receipt key for legacy devices, authenticated registration before supporting reset, and preserve that identity key during reset. Store signed completion receipt after erasure; expose it over encrypted BLE and attempt backend acknowledgement over the current live connection. Reboot without Wi-Fi credentials whether or not acknowledgement succeeds; new pairing stays blocked until receipt reaches the backend.
- [ ] Reset outputs and target-specific user files (Wi-Fi config/tmp, schedules, audio current/upload, preferences); explicitly erase Wi-Fi NVS credentials without erasing factory identity or stable PIN. Use a durable reset marker and fail closed on flash-write failure. Keep configured BLE available so offline nearby management works. Replace BLE auth state/challenge per connection and preserve the sequential bounded command queue.
- [ ] Add non-retained MQTT operation notifications plus authenticated pending-operation polling before schedules/commands on reconnect. Notify firmware capability support in runtime registration; the backend must reject removal on old firmware.
- [ ] Build both firmware targets using `pio run` and run native state/protocol tests. Check code paths cannot print credentials or authorization envelopes. Commit shared firmware lifecycle.

### Task 8: Firmware Wi-Fi update and initial provisioning

**Files:** Modify `firmware_shared/src/device_lifecycle.cpp`, shared BLE sources, `esp32_device/src/main.cpp`, `esp32_test_light/src/main.cpp`; create `firmware_shared/tests/wifi_update_test.cpp`.

**Interfaces:** `updateWifi(const AuthorizedWifiRequest&) -> WifiUpdateResult` consumes Task 6 challenge-bound authorization. Initial provisioning continues to use the short-lived pairing token and device activation endpoint; Wi-Fi update is a separate owner-authorized operation with no ownership mutation.

- [ ] Write tests: invalid credentials never change saved config; wrong password/backend unreachable/save failure restores old Wi-Fi; successful update atomically persists and reconnects MQTT; ownership, schedules/audio and factory settings remain unchanged; initial provisioning still works for both types.
- [ ] Run native tests and confirm failure.
- [ ] Implement shared candidate-connect/backend-validate/atomic-save flow with target callbacks. Clear password/token buffers after processing; do not automatically resend ambiguous writes. Reject new Wi-Fi requests during reset. Bring audio/light onto BLE while preserving legacy HTTP provisioning with equivalent authorization for updates.
- [ ] Run native tests and build both targets. Commit Wi-Fi management.

### Task 9: Mobile Wi-Fi and removal flows

**Files:** Create `mobile_app/lib/models/device_operation.dart`, `mobile_app/lib/screens/device_wifi_screen.dart`, `mobile_app/lib/screens/device_removal_screen.dart`, `mobile_app/test/device_wifi_test.dart`, `mobile_app/test/device_removal_test.dart`; modify `mobile_app/lib/models/device.dart`, `mobile_app/lib/services/api_service.dart`, `mobile_app/lib/services/ble_provision_protocol.dart`, `mobile_app/lib/services/ble_provision_service.dart`, `mobile_app/lib/screens/device_screen.dart`, `mobile_app/lib/screens/home_screen.dart`, `mobile_app/lib/state/app_state.dart`.

**Interfaces:** ApiService `createWifiSession(int deviceId,String challenge)`, `removeDevice(int deviceId)`, `getDeviceOperation(String operationId)`, `createResetAuthorization(String operationId,String challenge)`, `submitResetReceipt(Map<String,dynamic> receipt)`. BleProvisionService `updateWifi(...)`, `resetDevice(...)`, and `readResetReceipt()` consume Task 7 encrypted identity/features. Use exact serial matching before sending any management command.

- [ ] Write fake BLE/API widget tests: both supported types connect; wrong serial/old firmware fails safely; scan/hidden SSID validation works; failed update remains retryable; destructive confirmation describes cleared settings/content; offline removal remains pending; receipt submission alone completes UI removal; app restart recovers pending operation; web/unsupported platforms show clear BLE availability guidance.
- [ ] Run focused Flutter tests; confirm initial failure.
- [ ] Implement Change Wi-Fi and Remove Device actions, feature checks, progress UI and bonded local reset. Keep pending cards accessible but disable normal controls. Read and relay durable completion receipts after reboot or reconnect. Preserve completion when acknowledgement is lost; query backend before displaying success. Do not assume broker publish or BLE disconnect proves erasure.
- [ ] Reuse bounded scan/chunk/poll helpers; remove test-light-only assumptions using protocol feature discovery. Disconnect/cancel cleanly on navigation; retain state revision guards around asynchronous operations.
- [ ] Run `flutter analyze`, all Flutter tests, and a release Android build. Commit mobile management flows.

### Task 10: Integration, documentation, and release review

**Files:** Create `docs/device-lifecycle-and-session-policy.md`; update `backend/README.md`, `admin_portal/README.md`, `mobile_app/README.md`, `esp32_device/README.md`, `esp32_test_light/README.md`, `docs/ubuntu-docker-deployment.md`, and non-secret env examples.

- [ ] Document migrations, admin catalog/download, server signing-key setup and backup, secure mobile session migration, policy semantics, firmware upgrade order, generated header compilation/upload, Wi-Fi changes, pending removal and BLE recovery. State physical button is deferred.
- [ ] Run backend suite, migrations on both database engines, admin production build, Flutter tests/analyze/release build, both firmware builds and native protocol/reset tests. Record exact commands and results; identify unavailable tooling instead of inventing success.
- [ ] Exercise integrated flows with fake device HTTP/BLE receipts: generated inventory → activation → session restore/refresh → Wi-Fi update → pending removal → confirmed cleanup → different-owner reactivation. Verify legacy claim cannot bypass pending reset and an old operation cannot reset the new owner.
- [ ] Prepare physical acceptance checklist for both targets: correct/wrong Wi-Fi changes, online/offline removal, power loss during reset, fresh BLE advertising, no old credentials/schedules/audio, and re-pairing. Hardware checks remain pending until actual devices are available.
- [ ] Inspect the full branch diff for secrets, incomplete interfaces, migration safety, and requirements coverage; resolve findings. Commit docs and prepare a reviewable branch/PR using authorized GitHub access. Report automated evidence and physical verification limits; do not deploy or flash physical hardware as part of this code change.

## Self-review

Spec coverage: inventory/header/type preservation (1–2); absolute mobile session policy and secure persistence (3–5); Wi-Fi-only configuration with rollback (6,8–9); authenticated, durable reset and offline pending (6–7,9); both firmware targets, migration compatibility and physical acceptance (1,7,10). Review Focus items have explicit tests in the listed tasks. Interfaces use the same operation IDs, generations, authorization envelope, and receipt throughout. Signing keys are manufacturing/server configuration; neither product secrets nor physical button behavior are added to version control.
