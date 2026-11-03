# Lily v2 audio

User requested implementation of both catalog MP3 storage and streaming fallback.
ESP32-S3 N16R8: five existing WS2812B LEDs on GPIO18; MAX98357A at 5V,
BCLK GPIO10, LRCLK GPIO40, DIN GPIO15, 8-ohm 2W speaker.

Use Wi-Fi for both server downloads and streaming; BLE retains provisioning and management.
Approaches considered: phone upload (existing, requires network switching), server streaming
only (no offline playback), and device download with streaming fallback (selected by user).
Automatic mode downloads one MP3 when actual LittleFS free space permits a staged,
checksum-verified replacement; otherwise streams. Explicit stream mode is available.
Existing local play/stop/volume and schedules continue to work. Streaming requires Wi-Fi.

Backend issues short-lived signed catalog URLs bound to device generation and owner.
The device accepts URLs only under its configured backend, never arbitrary hosts.
Download requests are deferred outside MQTT callbacks, bounded, checked for length and SHA256,
and preserve the previous file on failure. Reserve 64KiB for settings/schedules.
Use a dedicated 16MB partition layout with two 3MiB app slots and remaining LittleFS.
Changing partition layouts may require reprovisioning: do not automatically flash or format.
New v2 factory model selects correct pins, five LEDs, audio capabilities and PSRAM.
App displays requested versus confirmed playback state and device errors.
BLE audio and multiple stored tracks are out of scope.
