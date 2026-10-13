# Bluetooth setup without a PIN

Lily 0.10.2 removes the stale PIN instructions from setup, Wi-Fi change and Bluetooth error messages. The shared ESP32 firmware still used a fixed six-digit passkey; it now uses Secure Connections Just Works with NoInputNoOutput capability. GATT identity/status reads and setup writes still require encryption, and writes are gated by the completed encrypted-link authentication. Existing backend pairing token and signed owner/challenge authorization checks remain in place. Just Works does not provide passkey-based MITM verification.

Flash the updated firmware for the actual model, without erasing all flash or manufacturing identity. Install LilyV13.apk (0.10.2, code11). Android can still show its system pairing confirmation, but no numeric passkey is required by the updated firmware. If the phone retains an incompatible old bond, forget its Lily Bluetooth entry once and reconnect through the app. Changing the app cannot alter an old firmware passkey requirement. The unused old PIN preference is left untouched; it is no longer read or configured.

Both targets use firmware_shared/src/ble_provisioning.cpp. Regression checks guard the no-passkey security configuration, encrypted characteristic permissions, authenticated-write gate, and absence of PIN instructions in current app screens/errors.

## Verification

- 67 Flutter tests passed; setup widget test additionally checks the no-code guidance and completes setup without re-sending Wi-Fi credentials on retry.
- Both no-passkey/encryption contract regressions passed after reproducing failures in the old code.
- Both ESP32 firmware targets compile successfully. Focused review found no material defects in the encryption/Just Works setup and confirmed existing signed management authorization is unchanged.
- Signed APK installed and launched successfully on Pixel10 emulator-5554 (0.10.2, versionCode11). Real setup page reads: "Bluetooth setup connects securely without a code." Discovery was cancelled without pairing or changing a device.
- APK SHA256 7CEAB3AEB3409F131ACDF38D7D946136EF12F0F7BBEA6BC9DA59099228877736.
- A USB serial device appeared on COM7, but reading it returned Access denied because another program owns the port. Flashing and real Android/ESP32 bonding verification are pending identification of the connected model and release of COM7.
