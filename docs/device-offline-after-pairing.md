# Offline after pairing: factory configuration and runtime identity

The tested light connected successfully to home Wi-Fi and could reach the configured backend and broker, but its local header lacked DEVICE_SERVER_PUBLIC_KEY and DEVICE_RECEIPT_PRIVATE_KEY. Runtime management requires the server verification key before enabling MQTT, so pairing/activation could succeed while the device remained offline. The matching portal-downloaded header was verified against the existing serial and factory secret, then its two key definitions were restored locally while preserving GPIO and server settings. Private device configuration is not committed.

Shared firmware now prioritizes a provisioned factory receipt key over a generated NVS fallback key. Inventory devices must register the public identity corresponding to their original factory key; a fallback generated during incomplete configuration must not override that identity. Boards without a provisioned key continue using their persistent generated NVS key. Existing runtime ownership, signature, generation and reset checks remain in place. HTTP failures, invalid JSON, missing verification keys and inactive lifecycle states now have credential-free serial diagnostics.

## Verification

- Actual test light flashed successfully on COM7, upload hashes verified.
- Startup reached "Lily runtime ready; MQTT enabled" and "MQTT connected".
- Read-only subscription to this light's retained status confirmed online, generation1.
- Pixel10 app displayed the newly registered test light as ONLINE.
- Both ESP32 firmware targets compile.
- 44 applicable backend/regression checks passed, one PostgreSQL-only check skipped and two documented Windows-incompatible checks excluded. Three older schedule-feature fixtures omitted newly required weekdays; those fixtures now provide valid weekdays so they exercise feature validation rather than schema rejection.
- No Wi-Fi credentials, factory secrets, keys, user settings or downloaded config contents were printed or committed.
