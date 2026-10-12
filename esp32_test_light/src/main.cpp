#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <LittleFS.h>

#include "device_config.h"
#include "device_lifecycle.h"
#include "device_message_rules.h"
#include "wifi_transaction.h"
#include "ble_provisioning.h"

static const char* CONFIG_PATH = "/wifi.json";

class BoundedWifiClient : public WiFiClient {
 public:
  int connect(IPAddress ip, uint16_t port) override {
    return WiFiClient::connect(ip, port, 2000);
  }
  int connect(const char* host, uint16_t port) override {
    return WiFiClient::connect(host, port, 2000);
  }
};
BoundedWifiClient wifiClient;
PubSubClient mqtt(wifiClient);

String homeSsid;
String homePassword;
String pairingToken;
bool lightEnabled = false;
unsigned long lastHeartbeat = 0;
unsigned long lastReconnectAttempt = 0;

String topic(const char* suffix) {
  return "devices/" + String(DEVICE_SERIAL) + "/" + suffix;
}

void applyLight() {
  digitalWrite(LED_PIN, lightEnabled ? HIGH : LOW);
  Serial.printf("LED GPIO%d: %s\n", LED_PIN, lightEnabled ? "ON" : "OFF");
}

bool saveConfig(const String& ssid, const String& password) {
  JsonDocument doc;
  doc["ssid"] = ssid;
  doc["password"] = password;

  const char* temporaryPath = "/wifi.tmp";
  File file = LittleFS.open(temporaryPath, "w");
  if (!file) return false;
  const size_t expected = measureJson(doc);
  const size_t written = serializeJson(doc, file);
  file.flush();
  const bool complete = written == expected && file.size() == expected;
  file.close();
  if (!complete || !LittleFS.rename(temporaryPath, CONFIG_PATH)) {
    LittleFS.remove(temporaryPath);
    return false;
  }
  return true;
}

bool loadConfig() {
  if (!LittleFS.exists(CONFIG_PATH)) return false;
  File file = LittleFS.open(CONFIG_PATH, "r");
  if (!file) return false;

  JsonDocument doc;
  auto error = deserializeJson(doc, file);
  file.close();
  if (error) return false;

  homeSsid = doc["ssid"] | "";
  homePassword = doc["password"] | "";
  return homeSsid.length() > 0;
}

bool activateWithBackend() {
  if (pairingToken.length() == 0) return false;

  HTTPClient http;
  String url = "http://" + String(BACKEND_HOST) + ":" +
               String(BACKEND_PORT) + "/api/v1/devices/activate";
  http.setConnectTimeout(5000);
  http.setTimeout(10000);
  http.begin(url);
  http.addHeader("Content-Type", "application/json");

  JsonDocument doc;
  doc["serial_number"] = DEVICE_SERIAL;
  doc["device_secret"] = DEVICE_SECRET;
  doc["pairing_token"] = pairingToken;
  doc["firmware_version"] = FIRMWARE_VERSION;
  doc["device_type_key"] = DEVICE_TYPE_KEY;

  String body;
  serializeJson(doc, body);
  int code = http.POST(body);
  String response=http.getString();
  if(code>=200 && code<300){JsonDocument result;deserializeJson(result,response);setDeviceGeneration(result["generation"]|0);}
  http.end();

  Serial.printf("Activation HTTP %d\n", code);
  return code >= 200 && code < 300;
}

void publishState() {
  if (!mqtt.connected()) return;

  // Keep the same state shape used by V0.6 so the existing UI updates correctly.
  JsonDocument doc;
  if(deviceManagementSupported())doc["generation"]=deviceGeneration();
  if(deviceManagementSupported())doc["generation"]=deviceGeneration();
  JsonObject light = doc["light"].to<JsonObject>();
  light["enabled"] = lightEnabled;
  light["brightness"] = 100;
  light["r"] = 255;
  light["g"] = 255;
  light["b"] = 255;

  String payload;
  serializeJson(doc, payload);
  mqtt.publish(topic("state").c_str(), payload.c_str(), false);
}

void publishHeartbeat() {
  if (!mqtt.connected()) return;

  JsonDocument doc;
  if(deviceManagementSupported())doc["generation"]=deviceGeneration();
  doc["wifi_rssi"] = WiFi.RSSI();
  doc["free_heap"] = ESP.getFreeHeap();
  doc["free_storage"] =
      LittleFS.totalBytes() > LittleFS.usedBytes()
          ? LittleFS.totalBytes() - LittleFS.usedBytes()
          : 0;
  doc["firmware"] = FIRMWARE_VERSION;

  String payload;
  serializeJson(doc, payload);
  mqtt.publish(topic("heartbeat").c_str(), payload.c_str(), false);
}

void handleCommand(const JsonDocument& doc) {
  if(deviceRuntimeReady() && String(doc["type"] | "")=="status_request"){publishState();publishHeartbeat();return;}
  if(!deviceRuntimeReady())return;
  const String type = doc["type"] | "";

  // Existing V0.6 DeviceCard/DeviceScreen sends this form through /devices/{id}/light.
  if (type == "light") {
    JsonObjectConst payload = doc["payload"];
    if (!payload["enabled"].isNull()) {
      lightEnabled = payload["enabled"].as<bool>();
      applyLight();
      publishState();
    }
    return;
  }

  // Also accept the generic power command for future capability-only widgets.
  if (type == "power") {
    JsonObjectConst payload = doc["payload"];
    if (!payload["enabled"].isNull()) {
      lightEnabled = payload["enabled"].as<bool>();
      applyLight();
      publishState();
    }
  }
}

void mqttCallback(char* rawTopic, byte* payload, unsigned int length) {
  if (String(rawTopic) != topic("command")) return;

  String incoming;
  incoming.reserve(length);
  for (unsigned int i = 0; i < length; i++) incoming += (char)payload[i];

  JsonDocument doc;
  if (!deserializeJson(doc, incoming) && acceptDeviceMessage(deviceRuntimeReady(),deviceManagementSupported(),deviceGeneration(),doc["generation"].is<int>() ? doc["generation"].as<int>() : -1)) {
    Serial.println("MQTT command received");
    handleCommand(doc);
  }
}

bool connectMqtt() {
  if(!deviceRuntimeReady())return false;
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(2048);
  mqtt.setSocketTimeout(2);

  const String clientId = "lily-" + String(DEVICE_SERIAL);
  const String statusTopic = topic("status");
  JsonDocument status;status["status"]="offline";
  if(deviceManagementSupported())status["generation"]=deviceGeneration();
  String offline;serializeJson(status,offline);
  status["status"]="online";String online;serializeJson(status,online);

  const bool ok = mqtt.connect(
      clientId.c_str(),
      statusTopic.c_str(),
      1,
      true,
      offline.c_str());
  if (!ok) {
    Serial.printf("MQTT connection failed rc=%d\n", mqtt.state());
    return false;
  }

  mqtt.subscribe(topic("command").c_str(), 1);
  mqtt.publish(statusTopic.c_str(), online.c_str(), true);
  publishState();
  publishHeartbeat();
  Serial.println("MQTT connected");
  return true;
}

bool provisionOverBle(const BleWifiRequest& request, String& detail) {
  const String previousSsid = homeSsid;
  const String previousPassword = homePassword;
  bleProvisionStatus(request.requestId, "connecting_wifi");
  mqtt.disconnect();
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(false, false);
  delay(100);
  WiFi.begin(request.ssid.c_str(), request.password.c_str());
  const unsigned long started = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - started < 20000) delay(100);
  if (WiFi.status() != WL_CONNECTED) {
    detail = "Could not connect to Wi-Fi. Check the name/password and use a 2.4 GHz network.";
  } else {
    bleProvisionStatus(request.requestId, "activating");
    pairingToken = request.token;
    const bool activated = request.command=="update_wifi" ? confirmWifiConnection() : activateWithBackend();
    pairingToken = "";
    if (activated) {
      if (saveConfig(request.ssid, request.password)) {
        homeSsid = request.ssid;
        homePassword = request.password;
        Serial.printf("Lily Wi-Fi connected: %s\n", WiFi.localIP().toString().c_str());
        // MQTT connection happens in loop(), after success has been reported.
        return true;
      }
      detail = "Backend registered Lily, but Wi-Fi settings could not be saved. Check flash storage and retry setup.";
    } else {
      detail = "Wi-Fi connected, but backend activation failed. Check the firmware server address and device inventory credentials.";
    }
  }
  WiFi.disconnect(false, false);
  if (!previousSsid.isEmpty()) WiFi.begin(previousSsid.c_str(), previousPassword.c_str());
  else WiFi.mode(WIFI_OFF);
  return false;
}

void connectStoredWifi() {
  if (homeSsid.isEmpty()) return;

  WiFi.mode(WIFI_STA);
  WiFi.begin(homeSsid.c_str(), homePassword.c_str());
  Serial.printf("Connecting to %s", homeSsid.c_str());

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
    delay(300);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("LAN IP: %s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("Stored Wi-Fi connection failed; BLE setup will be available.");
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.printf("Lily boot: reset_reason=%d / heap=%lu / firmware=%s\n", (int)esp_reset_reason(), (unsigned long)ESP.getFreeHeap(), FIRMWARE_VERSION);

  pinMode(LED_PIN, OUTPUT);
  lightEnabled = false;
  applyLight();

  if (!LittleFS.begin(true)) Serial.println("LittleFS mount failed");
  beginDeviceLifecycle([](){
    lightEnabled=false;applyLight();homeSsid="";homePassword="";pairingToken="";
    const char* files[]={"/wifi.json","/wifi.tmp"};
    for(auto path:files)if(LittleFS.exists(path) && !LittleFS.remove(path))return false;
    return true;
  });
  if(!deviceResetPending())loadConfig();

  WiFi.mode(WIFI_OFF);
  connectStoredWifi();
  if(WiFi.status()!=WL_CONNECTED){WiFi.disconnect(false,false);WiFi.mode(WIFI_OFF);}
  beginBleProvisioning(!homeSsid.isEmpty(), provisionOverBle);
  // Saved Wi-Fi runs normally; new credentials are received over BLE.

}

void loop() {
  pollDeviceLifecycle();
  pollBleProvisioning();

  if (WiFi.status() == WL_CONNECTED) {
    if (!mqtt.connected() && millis() - lastReconnectAttempt > 5000) {
      connectMqtt();
      lastReconnectAttempt = millis();
    }

    if(deviceRuntimeReady())mqtt.loop();

    if (millis() - lastHeartbeat > 30000) {
      lastHeartbeat = millis();
      publishHeartbeat();
    }
  }

  delay(5);
}
