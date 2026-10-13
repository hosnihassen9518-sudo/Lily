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
#include "device_lifecycle.h"
#include "device_message_rules.h"
#include "wifi_transaction.h"
#include "ble_provisioning.h"
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

bool saveConfig() {
  JsonDocument doc;
  doc["ssid"] = homeSsid;
  doc["password"] = homePassword;

  File file = LittleFS.open("/config.tmp", "w");
  if (!file) return false;
  const size_t expected=measureJson(doc);
  const size_t written=serializeJson(doc,file);
  file.flush();const bool complete=written==expected && file.size()==expected;file.close();
  if(!complete || !LittleFS.rename("/config.tmp",CONFIG_PATH)){LittleFS.remove("/config.tmp");return false;}
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
  doc["device_type_key"] = DEVICE_TYPE_KEY;

  String body;
  serializeJson(doc, body);

  int code = http.POST(body);
  String response = http.getString();
  if(code>=200 && code<300){JsonDocument result;deserializeJson(result,response);setDeviceGeneration(result["generation"]|0);}
  http.end();

  Serial.printf("Activation HTTP %d\n", code);
  return code >= 200 && code < 300;
}

void publishState() {
  if (!mqtt.connected()) return;

  JsonDocument doc;
  if(deviceManagementSupported())doc["generation"]=deviceGeneration();
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
    if (!deserializeJson(doc, incoming) && acceptDeviceMessage(deviceRuntimeReady(),deviceManagementSupported(),deviceGeneration(),doc["generation"].is<int>() ? doc["generation"].as<int>() : -1)) {
      handleCommand(doc);
    }
    return;
  }

  if (String(rawTopic) == topic("schedule")) {
    JsonDocument doc;
    if(deserializeJson(doc,incoming) || !acceptDeviceMessage(deviceRuntimeReady(),deviceManagementSupported(),deviceGeneration(),doc["generation"].is<int>() ? doc["generation"].as<int>() : -1))return;
    File file = LittleFS.open(SCHEDULES_PATH, "w");
    if (file) {
      file.print(incoming);
      file.close();
    }
  }
}

bool connectMqtt() {
  if(!deviceRuntimeReady())return false;
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(4096);

  const String clientId = "lily-" + String(DEVICE_SERIAL);
  const String statusTopic = topic("status");
  JsonDocument status;status["status"]="offline";
  if(deviceManagementSupported())status["generation"]=deviceGeneration();
  String offline;serializeJson(status,offline);
  status["status"]="online";String online;serializeJson(status,online);

  bool ok = mqtt.connect(
      clientId.c_str(),
      statusTopic.c_str(),
      1,
      true,
      offline.c_str());

  if (!ok) return false;

  mqtt.subscribe(topic("command").c_str(), 1);
  mqtt.subscribe(topic("schedule").c_str(), 1);
  mqtt.publish(statusTopic.c_str(), online.c_str(), true);

  publishState();
  publishHeartbeat();
  return true;
}

bool provisionWifi(const BleWifiRequest& request,String& detail,bool keepAp);

void beginProvisioningAccessPoint() {
  WiFi.mode(WIFI_AP_STA);

  String serialSuffix = String(DEVICE_SERIAL);
  if (serialSuffix.startsWith("LILY-")) serialSuffix = serialSuffix.substring(5);
  String apName = "LILY-" + String(DEVICE_TYPE_AP_TAG) + "-" + serialSuffix;
  if (apName.length() > 31) {
    apName = "LILY-" + String(DEVICE_TYPE_AP_TAG) + "-" + String((uint32_t)ESP.getEfuseMac(), HEX);
  }

  WiFi.softAP(apName.c_str());
  Serial.print("Provisioning AP: ");
  Serial.println(apName);

  webServer.on("/info", HTTP_GET, []() {
    JsonDocument doc;
    doc["serial"] = DEVICE_SERIAL;
    doc["model"] = "LILY-V1";
    doc["device_type_key"] = DEVICE_TYPE_KEY;
    doc["device_type_name"] = DEVICE_TYPE_NAME;
    JsonArray capabilities = doc["capabilities"].to<JsonArray>();
    capabilities.add("power");
    capabilities.add("brightness");
    capabilities.add("rgb");
    capabilities.add("audio");
    capabilities.add("volume");
    doc["firmware"] = FIRMWARE_VERSION;
    doc["configured"] = homeSsid.length() > 0;
    doc["audio_loaded"] = LittleFS.exists(AUDIO_CURRENT_PATH);

    String output;
    serializeJson(doc, output);
    webServer.send(200, "application/json", output);
  });

  webServer.on("/networks", HTTP_GET, []() {
    int count = WiFi.scanNetworks(false, true);
    JsonDocument doc;
    JsonArray items = doc["networks"].to<JsonArray>();
    for (int i = 0; i < count; i++) {
      String ssid = WiFi.SSID(i);
      if (ssid.length() == 0) continue;
      JsonObject item = items.add<JsonObject>();
      item["ssid"] = ssid;
      item["rssi"] = WiFi.RSSI(i);
      item["secure"] = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
    }
    WiFi.scanDelete();
    String output;
    serializeJson(doc, output);
    webServer.send(200, "application/json", output);
  });

  webServer.on("/provision", HTTP_POST, []() {
    if(deviceResetPending()){webServer.send(409,"application/json","{\"detail\":\"Reset pending\"}");return;}
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

    if(!homeSsid.isEmpty()) {
      String envelope;serializeJson(doc["authorization"],envelope);
      if(!validateWifiAuthorization(envelope,doc["challenge"]|"")){webServer.send(403,"application/json","{\"detail\":\"Use authenticated Bluetooth Wi-Fi management\"}");return;}
    }
    String requestedSsid = String((const char*)doc["ssid"]);
    String requestedPassword = String((const char*)doc["password"]);
    String requestedPairingToken = String((const char*)doc["pairing_token"]);

    if (requestedSsid.isEmpty() || requestedPairingToken.isEmpty()) {
      webServer.send(400, "application/json", "{\"detail\":\"Missing Wi-Fi or pairing configuration\"}");
      return;
    }

    BleWifiRequest request;
    request.ssid=requestedSsid;request.password=requestedPassword;request.token=requestedPairingToken;
    request.command=homeSsid.isEmpty() ? "provision" : "update_wifi";
    String detail;
    if(!provisionWifi(request,detail,true)) {
      webServer.send(422,"application/json","{\"detail\":\"Wi-Fi could not be connected, authorized, or saved. Previous settings were kept.\"}");return;
    }

    webServer.send(200, "application/json",
        "{\"ok\":true,\"detail\":\"Device connected and registered successfully.\"}");
  });

  webServer.on(
      "/audio",
      HTTP_POST,
      []() {
        if(!allowsUserFileMutation(deviceResetPending())) {webServer.send(409,"application/json","{\"detail\":\"Reset pending\"}");return;}
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
        if(!allowsUserFileMutation(deviceResetPending()))return;
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
    configTzTime("CET-1CEST,M3.5.0,M10.5.0/3", "pool.ntp.org", "time.google.com");
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

void initializeScheduleClock() {
  configTzTime("CET-1CEST,M3.5.0,M10.5.0/3", "pool.ntp.org", "time.google.com");
}

bool provisionWifi(const BleWifiRequest& request,String& detail,bool keepAp) {
  const String previousSsid=homeSsid,previousPassword=homePassword;
  auto connect=[&](){
    mqtt.disconnect();WiFi.mode(keepAp ? WIFI_AP_STA : WIFI_STA);WiFi.persistent(false);WiFi.disconnect(false,false);
    bleProvisionStatus(request.requestId,"connecting_wifi");
    WiFi.begin(request.ssid.c_str(),request.password.c_str());
    const auto start=millis();while(WiFi.status()!=WL_CONNECTED && millis()-start<20000)delay(100);
    return WiFi.status()==WL_CONNECTED;
  };
  auto authorize=[&](){
    bleProvisionStatus(request.requestId,"activating");pairingToken=request.token;
    const bool ok=request.command=="update_wifi" ? confirmWifiConnection() : activateWithBackend();pairingToken="";return ok;
  };
  auto persist=[&](){homeSsid=request.ssid;homePassword=request.password;return saveConfig();};
  auto restore=[&](){
    homeSsid=previousSsid;homePassword=previousPassword;pairingToken="";WiFi.disconnect(false,false);
    if(!homeSsid.isEmpty())WiFi.begin(homeSsid.c_str(),homePassword.c_str());else if(!keepAp)WiFi.mode(WIFI_OFF);
  };
  const bool ok=applyWifiConfiguration(connect,authorize,persist,restore,initializeScheduleClock);
  if(!ok)detail="Wi-Fi could not be connected, authorized, or saved. Previous settings were kept.";
  return ok;
}

bool provisionOverBle(const BleWifiRequest& request,String& detail) { return provisionWifi(request,detail,false); }

void setup() {
  Serial.begin(115200);
  delay(500);

  pixel.begin();
  pixel.clear();
  pixel.show();

  if (!LittleFS.begin(true)) {
    Serial.println("LittleFS mount failed; setup stopped to preserve reset state.");
    while(true)delay(1000);
  }

  audio.setPinout(I2S_BCLK_PIN, I2S_LRC_PIN, I2S_DOUT_PIN);
  audio.setVolume(map(audioVolume, 0, 100, 0, 21));

  beginDeviceLifecycle([](){
    audio.stopSong();lightEnabled=false;applyLight();homeSsid="";homePassword="";pairingToken="";
    const char* files[]={CONFIG_PATH,"/config.tmp",SCHEDULES_PATH,AUDIO_CURRENT_PATH,AUDIO_UPLOAD_PATH};
    for(auto path:files)if(LittleFS.exists(path) && !LittleFS.remove(path))return false;
    return true;
  });
  if(!deviceResetPending())loadConfig();

  if(!deviceResetPending())beginProvisioningAccessPoint();
  connectStoredWifi();
  beginBleProvisioning(!homeSsid.isEmpty(),provisionOverBle);

  if (WiFi.status() == WL_CONNECTED) {
    connectMqtt();
  }
}

void loop() {
  pollDeviceLifecycle();
  pollBleProvisioning();
  if(allowsUserFileMutation(deviceResetPending()))webServer.handleClient();
  audio.loop();

  if (WiFi.status() == WL_CONNECTED) {
    if (!mqtt.connected() && millis() - lastReconnectAttempt > 5000) {
      lastReconnectAttempt = millis();
      connectMqtt();
    }

    if(deviceRuntimeReady())mqtt.loop();

    if (millis() - lastHeartbeat > 30000) {
      lastHeartbeat = millis();
      publishHeartbeat();
    }

    if (millis() - lastScheduleCheck > 1000) {
      lastScheduleCheck = millis();
      if(deviceRuntimeReady())executeSchedulesIfDue();
    }
  }
}
