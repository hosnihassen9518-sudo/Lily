#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <HTTPClient.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <Adafruit_NeoPixel.h>
#include <Audio.h>
#include <mbedtls/sha256.h>

#include "device_config.h"
#include "storage_paths.h"

WebServer webServer(80);
WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
Adafruit_NeoPixel pixel(1, RGB_PIN, NEO_GRB + NEO_KHZ800);
Audio audio;

String homeSsid;
String homePassword;
String pairingToken;

bool lightEnabled = false;
uint8_t lightBrightness = 100;
uint8_t lightR = 255;
uint8_t lightG = 255;
uint8_t lightB = 255;
uint8_t audioVolume = 50;

unsigned long lastHeartbeat = 0;
unsigned long lastReconnectAttempt = 0;
unsigned long lastScheduleCheck = 0;

String topic(const char* suffix) {
  return "devices/" + String(DEVICE_SERIAL) + "/" + suffix;
}

void applyLight() {
  if (!lightEnabled) {
    pixel.clear();
    pixel.show();
    return;
  }

  pixel.setBrightness(map(lightBrightness, 0, 100, 0, 255));
  pixel.setPixelColor(0, pixel.Color(lightR, lightG, lightB));
  pixel.show();
}

void saveConfig() {
  JsonDocument doc;
  doc["ssid"] = homeSsid;
  doc["password"] = homePassword;

  File file = LittleFS.open(CONFIG_PATH, "w");
  if (!file) return;
  serializeJson(doc, file);
  file.close();
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

String sha256File(const char* path) {
  File file = LittleFS.open(path, "r");
  if (!file) return "";

  mbedtls_sha256_context ctx;
  mbedtls_sha256_init(&ctx);
  mbedtls_sha256_starts(&ctx, 0);

  uint8_t buffer[1024];
  while (file.available()) {
    size_t read = file.read(buffer, sizeof(buffer));
    if (read > 0) {
      mbedtls_sha256_update(&ctx, buffer, read);
    }
  }

  uint8_t hash[32];
  mbedtls_sha256_finish(&ctx, hash);
  mbedtls_sha256_free(&ctx);
  file.close();

  char output[65];
  for (int i = 0; i < 32; i++) {
    sprintf(output + (i * 2), "%02x", hash[i]);
  }
  output[64] = '\0';

  return String(output);
}

bool activateWithBackend() {
  if (pairingToken.length() == 0) return false;

  HTTPClient http;
  String url = "http://" + String(BACKEND_HOST) + ":" +
               String(BACKEND_PORT) + "/api/v1/devices/activate";

  http.begin(url);
  http.addHeader("Content-Type", "application/json");

  JsonDocument doc;
  doc["serial_number"] = DEVICE_SERIAL;
  doc["device_secret"] = DEVICE_SECRET;
  doc["pairing_token"] = pairingToken;
  doc["firmware_version"] = FIRMWARE_VERSION;

  String body;
  serializeJson(doc, body);

  int code = http.POST(body);
  String response = http.getString();
  http.end();

  Serial.printf("Activation HTTP %d: %s\n", code, response.c_str());
  return code >= 200 && code < 300;
}

void publishState() {
  if (!mqtt.connected()) return;

  JsonDocument doc;
  JsonObject light = doc["light"].to<JsonObject>();
  light["enabled"] = lightEnabled;
  light["brightness"] = lightBrightness;
  light["r"] = lightR;
  light["g"] = lightG;
  light["b"] = lightB;

  JsonObject audioState = doc["audio"].to<JsonObject>();
  audioState["loaded"] = LittleFS.exists(AUDIO_CURRENT_PATH);
  audioState["playing"] = audio.isRunning();
  audioState["volume"] = audioVolume;

  String payload;
  serializeJson(doc, payload);
  mqtt.publish(topic("state").c_str(), payload.c_str(), false);
}

void publishHeartbeat() {
  if (!mqtt.connected()) return;

  JsonDocument doc;
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
  String type = doc["type"] | "";

  if (type == "light") {
    JsonObjectConst payload = doc["payload"];
    lightEnabled = payload["enabled"] | lightEnabled;
    lightBrightness = payload["brightness"] | lightBrightness;
    lightR = payload["r"] | lightR;
    lightG = payload["g"] | lightG;
    lightB = payload["b"] | lightB;
    applyLight();
  } else if (type == "audio_play") {
    if (LittleFS.exists(AUDIO_CURRENT_PATH)) {
      audio.connecttoFS(LittleFS, AUDIO_CURRENT_PATH);
    }
  } else if (type == "audio_stop") {
    audio.stopSong();
  } else if (type == "volume") {
    audioVolume = doc["payload"]["volume"] | audioVolume;
    // ESP32-audioI2S uses 0..21 internally.
    audio.setVolume(map(audioVolume, 0, 100, 0, 21));
  }

  publishState();
}

void mqttCallback(char* rawTopic, byte* payload, unsigned int length) {
  String incoming;
  incoming.reserve(length);

  for (unsigned int i = 0; i < length; i++) {
    incoming += (char)payload[i];
  }

  if (String(rawTopic) == topic("command")) {
    JsonDocument doc;
    if (!deserializeJson(doc, incoming)) {
      handleCommand(doc);
    }
    return;
  }

  if (String(rawTopic) == topic("schedule")) {
    File file = LittleFS.open(SCHEDULES_PATH, "w");
    if (file) {
      file.print(incoming);
      file.close();
    }
  }
}

bool connectMqtt() {
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(4096);

  const String clientId = "lily-" + String(DEVICE_SERIAL);
  const String statusTopic = topic("status");

  bool ok = mqtt.connect(
      clientId.c_str(),
      statusTopic.c_str(),
      1,
      true,
      "{\"status\":\"offline\"}");

  if (!ok) return false;

  mqtt.subscribe(topic("command").c_str(), 1);
  mqtt.subscribe(topic("schedule").c_str(), 1);
  mqtt.publish(statusTopic.c_str(), "{\"status\":\"online\"}", true);

  publishState();
  publishHeartbeat();
  return true;
}

void beginProvisioningAccessPoint() {
  WiFi.mode(WIFI_AP_STA);

  String apName = "LILY-" + String(DEVICE_SERIAL);
  if (apName.length() > 20) {
    apName = "LILY-" + String((uint32_t)ESP.getEfuseMac(), HEX);
  }

  WiFi.softAP(apName.c_str());
  Serial.print("Provisioning AP: ");
  Serial.println(apName);

  webServer.on("/info", HTTP_GET, []() {
    JsonDocument doc;
    doc["serial"] = DEVICE_SERIAL;
    doc["model"] = "LILY-V1";
    doc["firmware"] = FIRMWARE_VERSION;
    doc["configured"] = homeSsid.length() > 0;
    doc["audio_loaded"] = LittleFS.exists(AUDIO_CURRENT_PATH);

    String output;
    serializeJson(doc, output);
    webServer.send(200, "application/json", output);
  });

  webServer.on("/provision", HTTP_POST, []() {
    if (!webServer.hasArg("plain")) {
      webServer.send(400, "application/json", "{\"detail\":\"Missing body\"}");
      return;
    }

    JsonDocument doc;
    auto error = deserializeJson(doc, webServer.arg("plain"));
    if (error) {
      webServer.send(400, "application/json", "{\"detail\":\"Invalid JSON\"}");
      return;
    }

    homeSsid = String((const char*)doc["ssid"]);
    homePassword = String((const char*)doc["password"]);
    pairingToken = String((const char*)doc["pairing_token"]);

    if (homeSsid.isEmpty() || pairingToken.isEmpty()) {
      webServer.send(400, "application/json", "{\"detail\":\"Missing configuration\"}");
      return;
    }

    saveConfig();
    webServer.send(
        200,
        "application/json",
        "{\"ok\":true,\"detail\":\"Joining home Wi-Fi\"}");

    delay(400);

    WiFi.begin(homeSsid.c_str(), homePassword.c_str());

    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) {
      delay(250);
    }

    if (WiFi.status() == WL_CONNECTED) {
      setenv("TZ", "CET-1CEST,M3.5.0,M10.5.0/3", 1);
      tzset();
      configTime(0, 0, "pool.ntp.org", "time.google.com");

      activateWithBackend();

      if (!mqtt.connected()) {
        connectMqtt();
      }
    }
  });

  webServer.on(
      "/audio",
      HTTP_POST,
      []() {
        const String expectedHash = webServer.arg("sha256");

        if (!LittleFS.exists(AUDIO_UPLOAD_PATH)) {
          webServer.send(400, "application/json", "{\"detail\":\"No upload received\"}");
          return;
        }

        String actual = sha256File(AUDIO_UPLOAD_PATH);

        if (!expectedHash.isEmpty() && !actual.equalsIgnoreCase(expectedHash)) {
          LittleFS.remove(AUDIO_UPLOAD_PATH);
          webServer.send(
              422,
              "application/json",
              "{\"detail\":\"SHA-256 checksum mismatch\"}");
          return;
        }

        audio.stopSong();

        if (LittleFS.exists(AUDIO_CURRENT_PATH)) {
          LittleFS.remove(AUDIO_CURRENT_PATH);
        }

        if (!LittleFS.rename(AUDIO_UPLOAD_PATH, AUDIO_CURRENT_PATH)) {
          webServer.send(
              500,
              "application/json",
              "{\"detail\":\"Could not finalize audio file\"}");
          return;
        }

        publishState();
        webServer.send(200, "application/json", "{\"ok\":true}");
      },
      []() {
        HTTPUpload& upload = webServer.upload();

        if (upload.status == UPLOAD_FILE_START) {
          if (LittleFS.exists(AUDIO_UPLOAD_PATH)) {
            LittleFS.remove(AUDIO_UPLOAD_PATH);
          }
          File file = LittleFS.open(AUDIO_UPLOAD_PATH, "w");
          file.close();
        } else if (upload.status == UPLOAD_FILE_WRITE) {
          File file = LittleFS.open(AUDIO_UPLOAD_PATH, "a");
          if (file) {
            file.write(upload.buf, upload.currentSize);
            file.close();
          }
        } else if (upload.status == UPLOAD_FILE_ABORTED) {
          LittleFS.remove(AUDIO_UPLOAD_PATH);
        }
      });

  webServer.on("/health", HTTP_GET, []() {
    webServer.send(200, "application/json", "{\"status\":\"ok\"}");
  });

  webServer.begin();
}

void connectStoredWifi() {
  if (homeSsid.isEmpty()) return;

  WiFi.mode(WIFI_AP_STA);
  WiFi.begin(homeSsid.c_str(), homePassword.c_str());

  Serial.printf("Connecting to %s", homeSsid.c_str());

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
    delay(300);
    Serial.print(".");
  }

  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("LAN IP: ");
    Serial.println(WiFi.localIP());

    // Europe/Paris with automatic CET/CEST daylight-saving transitions.
    setenv("TZ", "CET-1CEST,M3.5.0,M10.5.0/3", 1);
    tzset();
    configTime(0, 0, "pool.ntp.org", "time.google.com");
  }
}

String executedMinuteKey = "";
String executedScheduleIds = "";

void applyScheduleAction(JsonObjectConst action) {
  if (action["light"].is<JsonObjectConst>()) {
    JsonObjectConst light = action["light"];

    if (!light["enabled"].isNull()) {
      lightEnabled = light["enabled"].as<bool>();
    }
    if (!light["brightness"].isNull()) {
      lightBrightness = light["brightness"].as<uint8_t>();
    }
    if (!light["r"].isNull()) lightR = light["r"].as<uint8_t>();
    if (!light["g"].isNull()) lightG = light["g"].as<uint8_t>();
    if (!light["b"].isNull()) lightB = light["b"].as<uint8_t>();

    applyLight();
  }

  if (action["audio"].is<const char*>()) {
    String audioAction = action["audio"].as<String>();

    if (audioAction == "play" && LittleFS.exists(AUDIO_CURRENT_PATH)) {
      audio.connecttoFS(LittleFS, AUDIO_CURRENT_PATH);
    } else if (audioAction == "stop") {
      audio.stopSong();
    }
  }

  if (!action["volume"].isNull()) {
    audioVolume = action["volume"].as<uint8_t>();
    audio.setVolume(map(audioVolume, 0, 100, 0, 21));
  }

  publishState();
}

bool scheduleContainsToday(JsonArrayConst days, int mondayBasedDay) {
  for (JsonVariantConst day : days) {
    if (day.as<int>() == mondayBasedDay) {
      return true;
    }
  }
  return false;
}

void executeSchedulesIfDue() {
  if (!LittleFS.exists(SCHEDULES_PATH)) return;

  struct tm timeinfo;
  if (!getLocalTime(&timeinfo, 50)) return;

  // Backend uses Monday=0 ... Sunday=6.
  int mondayBasedDay = (timeinfo.tm_wday + 6) % 7;

  char currentTime[6];
  snprintf(
      currentTime,
      sizeof(currentTime),
      "%02d:%02d",
      timeinfo.tm_hour,
      timeinfo.tm_min);

  char minuteKey[20];
  snprintf(
      minuteKey,
      sizeof(minuteKey),
      "%04d-%02d-%02d %02d:%02d",
      timeinfo.tm_year + 1900,
      timeinfo.tm_mon + 1,
      timeinfo.tm_mday,
      timeinfo.tm_hour,
      timeinfo.tm_min);

  if (executedMinuteKey != minuteKey) {
    executedMinuteKey = minuteKey;
    executedScheduleIds = "";
  }

  File file = LittleFS.open(SCHEDULES_PATH, "r");
  if (!file) return;

  JsonDocument doc;
  auto error = deserializeJson(doc, file);
  file.close();

  if (error) return;

  JsonArrayConst schedules = doc["schedules"].as<JsonArrayConst>();

  for (JsonObjectConst schedule : schedules) {
    int scheduleId = schedule["id"] | -1;
    String scheduledTime = schedule["time"] | "";

    if (scheduledTime.length() >= 5) {
      scheduledTime = scheduledTime.substring(0, 5);
    }

    JsonArrayConst days = schedule["days"].as<JsonArrayConst>();

    if (scheduledTime != currentTime) continue;
    if (!scheduleContainsToday(days, mondayBasedDay)) continue;

    String marker = "|" + String(scheduleId) + "|";
    if (executedScheduleIds.indexOf(marker) >= 0) continue;

    JsonObjectConst action = schedule["action"].as<JsonObjectConst>();
    applyScheduleAction(action);

    executedScheduleIds += marker;
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);

  pixel.begin();
  pixel.clear();
  pixel.show();

  if (!LittleFS.begin(true)) {
    Serial.println("LittleFS mount failed");
  }

  audio.setPinout(I2S_BCLK_PIN, I2S_LRC_PIN, I2S_DOUT_PIN);
  audio.setVolume(map(audioVolume, 0, 100, 0, 21));

  loadConfig();

  beginProvisioningAccessPoint();
  connectStoredWifi();

  if (WiFi.status() == WL_CONNECTED) {
    connectMqtt();
  }
}

void loop() {
  webServer.handleClient();
  audio.loop();

  if (WiFi.status() == WL_CONNECTED) {
    if (!mqtt.connected() && millis() - lastReconnectAttempt > 5000) {
      lastReconnectAttempt = millis();
      connectMqtt();
    }

    mqtt.loop();

    if (millis() - lastHeartbeat > 30000) {
      lastHeartbeat = millis();
      publishHeartbeat();
    }

    if (millis() - lastScheduleCheck > 1000) {
      lastScheduleCheck = millis();
      executeSchedulesIfDue();
    }
  }
}
