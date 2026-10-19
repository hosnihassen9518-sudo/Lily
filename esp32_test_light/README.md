# Lily Test Light firmware (V0.6.1)

This firmware is an end-to-end hardware test for the Lily V0.6 platform. It keeps the V0.6 mobile provisioning, backend activation, MQTT presence/state, and device-control protocol, but replaces the RGB/audio hardware with one ordinary LED.

## Wiring

Use a normal 3 mm or 5 mm LED only (not a 230 V bulb):

```text
ESP32 GPIO18 ---- 330 ohm resistor ---- LED anode (+)
ESP32 GND ----------------------------- LED cathode (-)
```

## Configure

1. Copy `include/device_config.example.h` to `include/device_config.h`.
2. Set `DEVICE_SERIAL` and `DEVICE_SECRET` to exactly the device inventory values created in the Lily admin portal.
3. Set `BACKEND_HOST` and `MQTT_HOST` to the LAN IP of the Lily server. Do not use `127.0.0.1` because that would mean the ESP32 itself.
4. Build/upload with PlatformIO.

## Expected setup Wi-Fi

The ESP32 advertises an open setup network such as:

`LILY-TEST-LIGHT-TEST-000001`

The Lily mobile app filters `LILY-*`, connects without an AP password, reads `/info`, scans Wi-Fi through `/networks`, and sends the selected home Wi-Fi plus pairing token to `/provision`.

If the home Wi-Fi credentials fail, the setup AP stays available and `/provision` returns a readable 422 error. Credentials are saved only after Wi-Fi and backend activation succeed.

## Expected app behavior

The backend assigns device type `test_light` with capabilities `power` + `light`. In My Devices, the device is shown with online/offline status. Open the device and toggle Light; the existing Lily endpoint publishes an MQTT `light` command and GPIO18 changes HIGH/LOW.

## Device lifecycle and session policy

See [0.8.0 provisioning, login duration, Wi-Fi changes, and account reset](../docs/device-lifecycle-and-session-policy.md).

## Five-pixel WS2812B strip version (ESP32-S3 N16R8)

Build/upload this variant with:

```powershell
platformio run -d esp32_test_light -e led_strip -t upload --upload-port COM7
```

The `led_strip` environment selects five GRB WS2812B pixels, GPIO18 from
`device_config.h`, 16 MB flash, and octal PSRAM for N16R8 boards. It shares Lily
pairing, lifecycle, MQTT, and schedules with the ordinary test light. All five
pixels show the same RGB color and brightness. Off sends black while retaining
the chosen RGB and brightness in RAM; reboot starts off with white selected.

Wire GPIO18 through a 330–470 ohm resistor to the strip's DIN, use 5 V for strip
power, and connect strip GND, power supply GND, and ESP32 GND together. A 1000 uF
capacitor across strip 5 V/GND is recommended (observe polarity). Use a suitable
3.3 V to 5 V data level shifter if required by the strip. Never connect 5 V to a
GPIO. Five pixels can draw about 300 mA at full white, in addition to the board.

The new `lily_led_strip` factory model has power/light/brightness/RGB capabilities.
It uses the `test_light` protocol and `esp32_test_light` target with the
`led_strip` environment. New generated strip headers also define `LILY_LED_STRIP`
and `LED_COUNT`, so the default environment can build them. Existing paired test
boards retain their inventory identity; their catalog model must have brightness
and RGB enabled in the portal before those controls appear in the mobile app.
The ordinary test-light model and firmware remain available.
