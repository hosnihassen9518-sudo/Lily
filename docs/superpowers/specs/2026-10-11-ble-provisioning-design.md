# Lily test-light BLE provisioning

Status: proposed for user review. Replaces setup Wi-Fi in the mobile Add Device flow for test-light firmware only.

Approved by user and implemented locally. Implementation refinement: status uses read polling only; notification hints were removed after code review identified a race with ATT long reads in the installed Arduino BLE library. Progress and missed-event recovery are preserved through 500 ms polling.

## Outcome

The phone stays on its normal network. It discovers Lily over Bluetooth Low Energy, reads the device identity, sends home Wi-Fi credentials and a freshly obtained backend pairing token, and waits for activation results. ESP32 Wi-Fi starts after credentials arrive. Existing Wi-Fi/MQTT LED control continues after activation.

## Scope and user flow

- Increment the mobile app and test-light firmware versions and document that both must be installed together.
- Add Device scans for Lily BLE devices and displays their names and identities. Request Bluetooth permissions when needed; explain disabled Bluetooth and permission denial.
- Connect, read serial/type/capabilities, and verify the Lily provisioning service before accepting credentials.
- Enter the home Wi-Fi SSID manually and its password. Retain device naming and optional home/room assignment. SSID entry permits hidden networks and keeps ESP32 Wi-Fi off during discovery.
- Fetch a new pairing token from the configured backend immediately before sending credentials. Backend access remains on the phone's normal network.
- Show Wi-Fi connection, backend activation, success, or an actionable failure. Save credentials only after successful activation. Refresh the backend and complete naming/assignment; report a separate retryable error if these final steps fail.

## BLE protocol

Use a versioned custom GATT service with read-only device information, writable control/data, and readable/notifiable status characteristics. UUIDs are fixed shared constants in app and firmware. Advertise the service UUID and a short Lily name; serial comes from the information characteristic.

Messages are UTF-8 JSON, framed by a newline. App writes sequential chunks sized to the negotiated MTU, using writes with response. Firmware limits a message to 2048 bytes, rejects overflow/malformed JSON, clears incomplete input on disconnect, and never logs passwords or tokens. Readable status provides recovery if a notification is missed; notifications stay within the negotiated payload size or are framed/chunked consistently.

Commands include a protocol version and request ID. Provision contains SSID, password, and pairing token. Validate SSID byte length (1–32), password byte length (empty or 8–63 for this first version), token presence, and supported version. Status echoes request ID and stage: accepted, connecting_wifi, activating, success, or error. Reject overlapping provisioning requests. Work runs outside BLE callbacks so Wi-Fi and HTTP waits do not block BLE handling.

## Security

Require encrypted, authenticated BLE pairing before credentials can be written. ESP32 uses a six-digit passkey displayed in the Serial Monitor; Android/iOS perform the pairing interaction. This is a development version, so the serial passkey is acceptable; a production onboarding label or physical confirmation is future work. Ensure bonding records and stale bonds are handled during reset/reflash testing. No credentials or device secret appear in advertising, logs, or status.

## Firmware lifecycle

On an unconfigured boot, start BLE with Wi-Fi off. After a provisioning request, enable station Wi-Fi, connect with a bounded timeout, then activate against the existing backend. On error, keep BLE available for corrected credentials and return a specific failure; do not overwrite previously working saved credentials.

On configured boot, try saved station credentials. If connection fails within the startup timeout, enable BLE recovery. After successful activation, keep the final status readable long enough for acknowledgment, then disconnect and stop advertising. Reboot permits setup recovery when saved Wi-Fi fails. No setup AP is required in this firmware version.

Bound backend HTTP and MQTT connection attempts. MQTT availability must not gate successful backend activation or starve BLE status reporting. Preserve existing LED command/state behavior.

## App lifecycle and compatibility

Scan, connect, and provision have independent timeouts. Stop scanning before connecting. Cancel subscriptions, disconnect BLE, and ignore late callbacks when leaving the screen. Never change the phone's Wi-Fi connection or process network binding in this flow. Keep the old HTTP ProvisionService for existing consumers outside Add Device until separately migrated.

Add Android Bluetooth scan/connect permissions with legacy permissions scoped to older Android versions; add iOS Bluetooth usage descriptions. Desktop/web display an unsupported setup message. The existing full esp32_device firmware is outside this first migration.

## Validation and acceptance

Test message framing across MTU-sized chunks, UTF-8 boundaries, malformed/oversized messages, matching request IDs, timeout/disconnect handling, and token acquisition before credential transfer. Test UI disposal and success versus backend-finalization failure where feasible. Run Flutter analysis/tests, build Android APK, and compile test-light firmware.

Hardware acceptance requires the updated APK and firmware: first boot discovery, authenticated pairing, successful activation/LED control, wrong password, unreachable backend, BLE disconnect, and recovery after saved Wi-Fi fails. Compilation and mocked tests alone do not confirm physical BLE provisioning.
