#pragma once

// Copy this file to device_config.h for each manufactured device.

#define DEVICE_SERIAL       "LILY-000001"
#define DEVICE_SECRET       "replace-with-a-strong-factory-secret-at-least-32-chars"

// Development server configuration:
#define BACKEND_HOST        "192.168.1.100"
#define BACKEND_PORT        6100

#define MQTT_HOST           "192.168.1.100"
#define MQTT_PORT           1883

#define FIRMWARE_VERSION    "0.6.0"

// Advertised device identity/capabilities used during mobile provisioning.
#define DEVICE_TYPE_KEY     "lily_audio_light"
#define DEVICE_TYPE_AP_TAG  "AUDIO-LIGHT"
#define DEVICE_TYPE_NAME    "Lily Audio Light"

// Hardware pins - adjust to your PCB.
#define RGB_PIN             4
#define I2S_BCLK_PIN        12
#define I2S_LRC_PIN         13
#define I2S_DOUT_PIN        14

// Microphone pins reserved for the next voice feature.
#define MIC_BCLK_PIN        15
#define MIC_WS_PIN          16
#define MIC_DATA_PIN        17
