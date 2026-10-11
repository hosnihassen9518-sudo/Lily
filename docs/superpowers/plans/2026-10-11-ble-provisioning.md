# Lily BLE Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution, or superpowers:subagent-driven-development if selected by the user. Track the steps below.

**Goal:** Ship matching mobile and test-light firmware versions that configure Wi-Fi through BLE without switching the phone's Wi-Fi.

**Architecture:** A custom authenticated GATT service carries device identity, bounded credential messages, and provisioning status. A Flutter BLE transport owns discovery/connection; a protocol layer handles validation/framing/status, while firmware processes credentials outside BLE callbacks. Preserve backend activation, naming, placement, and MQTT LED control.

**Tech Stack:** Flutter, flutter_reactive_ble, permission_handler, Arduino ESP32 bundled BLE library, existing ArduinoJson/HTTPClient/PubSubClient.

**Spec:** ../specs/2026-10-11-ble-provisioning-design.md

## Global constraints

- Both app and test-light firmware become 0.7.0; Android build number becomes 2.
- Authenticated encrypted BLE writes, six-digit passkey shown on Serial Monitor; do not log credential messages.
- Wi-Fi off on unconfigured startup; manual SSID entry, no setup AP.
- Preserve unrelated working-tree changes and existing full esp32_device firmware.
- Firmware buffers at most 2048 message bytes; command version is 1; one provisioning operation at a time.
- UUID service `8c9a0001-6f32-4b88-a5c1-1e1d7c6a0000`, information `8c9a0002-6f32-4b88-a5c1-1e1d7c6a0000`, command `8c9a0003-6f32-4b88-a5c1-1e1d7c6a0000`, status `8c9a0004-6f32-4b88-a5c1-1e1d7c6a0000`.
- Status reads return complete JSON. Notifications carry only a short newline-framed change hint; app polls status to recover missed hints. Correlate request IDs before accepting success/error.

## Review focus

- Permission denial/disabled Bluetooth: actionable error and rescan without restarting app.
- Disconnect or widget disposal during setup: cancel transport work and prevent late UI updates.
- Multibyte SSID/password or escaped JSON: validate UTF-8 byte sizes and split bytes without corruption.
- Wrong password/backend outage: no false success or replacement of saved working credentials.
- Activation succeeds but naming/placement fails: indicate registered device and permit finalization retry without provisioning again.

### Task 1: BLE protocol and firmware

**Files:** Create `mobile_app/lib/services/ble_provision_protocol.dart`, `mobile_app/test/ble_provision_protocol_test.dart`, `esp32_test_light/include/ble_provisioning.h`, `esp32_test_light/src/ble_provisioning.cpp`; modify `esp32_test_light/src/main.cpp`, `include/device_config.h`, `include/device_config.example.h` if present.

**Interfaces:** `BleProvisionProtocol.encodeProvision({required String requestId, required String ssid, required String password, required String token}) -> List<int>`; `chunkMessage(List<int> bytes, int payloadSize) -> List<List<int>>`; `decodeStatus(List<int> bytes, String requestId) -> Map<String,dynamic>?`. Firmware `beginBleProvisioning()`, `pollBleProvisioning()`, and a provision callback consume validated requests and expose correlated status.

- [ ] Write tests: UTF-8/escaped credentials round-trip; chunk concatenation matches encoded bytes for MTU 23/247; invalid SSID/password/token and oversized message rejected; mismatched request IDs ignored; error status does not become success.
- [ ] Run `flutter test --no-pub test/ble_provision_protocol_test.dart` and verify initial failure, implement protocol, then verify pass.
- [ ] Implement GATT server with authenticated encryption permissions on command/status, six-digit serial PIN, bounded newline accumulation, synchronized pending request handoff, disconnect buffer clearing, and explicit overflow/malformed/busy errors. Device information includes protocol version, serial, firmware, type/capabilities.
- [ ] Replace setup AP initialization/HTTP routes in test-light with BLE lifecycle. Execute bounded Wi-Fi/activation work outside callbacks, preserve saved credentials on failure, and retain status until success acknowledgment or a bounded grace period. Stop BLE advertising after success; enable BLE on saved-Wi-Fi startup failure.
- [ ] Limit HTTP connect/read and MQTT waits; MQTT failure does not change successful activation. Compile with `platformio run` and check security/framing code against installed Arduino headers.

### Task 2: Mobile BLE transport and Add Device UI

**Files:** Create `mobile_app/lib/services/ble_provision_service.dart`, transport tests; modify `mobile_app/lib/screens/pair_device_screen.dart`, `pubspec.yaml`, `pubspec.lock`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`.

**Interfaces:** `BleProvisionService.scanDevices() -> Future<List<BleSetupDevice>>`, `connect(BleSetupDevice) -> Future<Map<String,dynamic>>`, `provision({required String ssid, required String password, required Future<String> Function() createToken, required void Function(String) onProgress}) -> Future<void>`, `disconnect() -> Future<void>`, `dispose()`. Service accepts a transport abstraction for deterministic tests.

- [ ] Add tests for token failure preventing credential writes, fresh token fetched immediately before transfer, ordered chunk writes, status request correlation, terminal error/timeout/disconnect, scan cancellation/disposal, and permission denial.
- [ ] Implement Android/iOS permission handling and service-filtered scan (10 seconds), connection (30 seconds including pairing), authenticated identity read, MTU-aware writes with response, status polling (bounded overall provisioning timeout), and cancellation-safe cleanup.
- [ ] Replace Wi-Fi discovery/connection on Add Device with BLE discovery, PIN instructions, manual SSID/password entry, and progress. Fetch backend token only on submit. Retain device name/home/room fields and existing rename/move API integration.
- [ ] Treat registration as complete before finalization; expose retry for naming/placement errors. Test leaving screen during async setup and finalization failure. Disable setup on unsupported desktop/web platforms.
- [ ] Bump app version, declare Bluetooth permissions and iOS usage strings. Retain HTTP service for unrelated existing consumers. Run scoped Flutter analysis and full tests.

### Task 3: Integration, documentation, and deliverables

**Files:** Update `docs/v0.7.0-ble-setup.md`; plan checkboxes; relevant configuration templates.

- [ ] Document flashing test-light on COM4, install matching APK, serial PIN pairing, normal Wi-Fi/backend access, 2.4 GHz network requirement, retry and stale-bond recovery.
- [ ] Review protocol consistency across firmware/app: UUIDs, framing, bounds, IDs, stages, pairing requirements, and success acknowledgment.
- [ ] Run full Flutter tests, scoped analysis, `flutter build apk --release`, and test-light `platformio run`; obtain independent code review and resolve actionable findings.
- [ ] Provide APK/firmware links and exact upload command. State physical Android/ESP32 acceptance tests remain required; do not claim mocked BLE tests prove radio connectivity.
- [ ] Commit only approved migration work if repository permissions permit. Preserve pre-existing unrelated edits; do not push unless within existing user authorization.

## Execution recommendation

Native execution in this chat, with an independent review at the end. The firmware and mobile transport share a tightly coupled protocol; one implementer can keep them aligned while tests check the boundary.
