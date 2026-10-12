#pragma once

// Lily V0.7.0 - LED integration test with BLE Wi-Fi setup.
// Copy this file to device_config.h and customize it for the test board.

#define DEVICE_SERIAL       "LILY-TEST-000001"
#define DEVICE_SECRET       "replace-with-the-same-factory-secret-used-in-admin-inventory"

#define BACKEND_HOST        "192.168.1.100"
#define BACKEND_PORT        6100

#define MQTT_HOST           "192.168.1.100"
#define MQTT_PORT           1883

#define FIRMWARE_VERSION    "0.7.1-test-light-ble"

#define DEVICE_TYPE_KEY     "test_light"
#define DEVICE_TYPE_AP_TAG  "TEST-LIGHT"
#define DEVICE_TYPE_NAME    "Lily Test Light"

// GPIO18 -> 330 ohm resistor -> LED anode (+)
// LED cathode (-) -> GND
#define LED_PIN             18

// For 0.8.0 management, prefer the admin-generated device_config.h.
// Legacy boards: export device_public_key.h from the server signing key,
// and include it here; never put the server private key on a device.
