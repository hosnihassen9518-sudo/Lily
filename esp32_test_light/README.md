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
