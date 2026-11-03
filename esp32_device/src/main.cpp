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

#include "lily_factory_config.h"
#include "device_lifecycle.h"
#include "device_message_rules.h"
#include "wifi_transaction.h"
#include "ble_provisioning.h"
#include "storage_paths.h"
#include "audio_storage_policy.h"

WebServer webServer(80);
WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
#ifdef LILY_V2
#undef RGB_PIN
#undef I2S_BCLK_PIN
#undef I2S_LRC_PIN
#undef I2S_DOUT_PIN
#undef FIRMWARE_VERSION
#define RGB_PIN 18
#define I2S_BCLK_PIN 10
#define I2S_LRC_PIN 40
#define I2S_DOUT_PIN 15
#define FIRMWARE_VERSION "2.0.0"
#endif
#ifndef LED_COUNT
#ifdef LILY_V2
#define LED_COUNT 5
#else
#define LED_COUNT 1
#endif
#endif
Adafruit_NeoPixel pixel(LED_COUNT, RGB_PIN, NEO_GRB + NEO_KHZ800);
Audio audio;
String catalogPending, streamUrl, audioTitle, audioError;
String playbackSource = "local";
HTTPClient catalogHttp;
WiFiClient catalogClient;
File catalogFile;
size_t catalogExpected = 0, catalogReceived = 0;
String catalogHash, catalogTitle;
bool catalogDownloading = false;
unsigned long catalogLastData = 0;
bool audioStateDirty = false;
void publishState();
void pollCatalog();
void cancelCatalog();
void startSpeakerTest();
void finishSpeakerTest();
bool speakerTestRequested = false, speakerTestActive = false;
String beforeTestSource, beforeTestTitle;
static const char* SPEAKER_TEST_PATH = "/speaker-test.wav";

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

  pixel.setBrightness(255);
  pixel.fill(pixel.Color(lightR * lightBrightness / 100, lightG * lightBrightness / 100,
                        lightB * lightBrightness / 100));
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

void cancelCatalog() {
  catalogPending = "";
  catalogFile.close();
  catalogHttp.end();
  if (catalogDownloading) LittleFS.remove(AUDIO_UPLOAD_PATH);
  catalogDownloading = false;
}

void catalogFailure(const char* detail) {
  cancelCatalog();
  audioError = detail;
  publishState();
}

void finishSpeakerTest() {
  speakerTestActive = false;
  if (LittleFS.exists(SPEAKER_TEST_PATH)) LittleFS.remove(SPEAKER_TEST_PATH);
  playbackSource = beforeTestSource;
  audioTitle = beforeTestTitle;
}

void startSpeakerTest() {
  speakerTestRequested = false;
  cancelCatalog();
  audio.stopSong();
  if (speakerTestActive) finishSpeakerTest();
  constexpr uint32_t rate = 16000, samples = 24000, dataBytes = samples * 2;
  if (!canStageAudio(LittleFS.totalBytes() - LittleFS.usedBytes(), dataBytes + 44)) {
    audioError = "Not enough temporary space for speaker test"; publishState(); return;
  }
  uint8_t header[44] = {};
  memcpy(header, "RIFF", 4); memcpy(header + 8, "WAVEfmt ", 8); memcpy(header + 36, "data", 4);
  auto put16 = [&](size_t at, uint16_t value) {header[at] = value; header[at + 1] = value >> 8;};
  auto put32 = [&](size_t at, uint32_t value) {for (int i = 0; i < 4; ++i) header[at + i] = value >> (i * 8);};
  put32(4, dataBytes + 36); put32(16, 16); put16(20, 1); put16(22, 1);
  put32(24, rate); put32(28, rate * 2); put16(32, 2); put16(34, 16); put32(40, dataBytes);
  File file = LittleFS.open(SPEAKER_TEST_PATH, "w");
  bool ok = file && file.write(header, sizeof(header)) == sizeof(header);
  int16_t buffer[256];
  for (uint32_t offset = 0; ok && offset < samples; offset += 256) {
    const size_t count = min(size_t(256), size_t(samples - offset));
    for (size_t i = 0; i < count; ++i) {
      const uint32_t sample = offset + i;
      const float frequency = (sample / 8000) % 2 ? 880.0f : 440.0f;
      buffer[i] = sample % 8000 < 6400 ? int16_t(2048.0f * sinf(TWO_PI * frequency * sample / rate)) : 0;
    }
    ok = file.write(reinterpret_cast<uint8_t*>(buffer), count * 2) == count * 2;
  }
  file.close();
  if (!ok) {LittleFS.remove(SPEAKER_TEST_PATH); audioError = "Could not prepare speaker test"; publishState(); return;}
  beforeTestSource = playbackSource; beforeTestTitle = audioTitle;
  playbackSource = "test"; audioTitle = "Speaker test"; audioError = "";
  speakerTestActive = audio.connecttoFS(LittleFS, SPEAKER_TEST_PATH);
  if (!speakerTestActive) {finishSpeakerTest(); audioError = "Speaker test could not start";}
  publishState();
}

void pollCatalog() {
  if (!deviceRuntimeReady()) { cancelCatalog(); return; }
  if (!catalogPending.isEmpty()) {
    JsonDocument request;
    const auto error = deserializeJson(request, catalogPending);
    catalogPending = "";
    String path = request["path"] | "";
    String mode = request["mode"] | "auto";
    catalogExpected = request["size"] | size_t(0);
    catalogHash = request["sha256"] | "";
    catalogTitle = request["title"] | "";
    if (error || !path.startsWith("/api/v1/music/") || path.indexOf("/device.mp3?token=") < 0
        || path.indexOf('\r') >= 0 || path.indexOf('\n') >= 0
        || catalogExpected == 0 || catalogHash.length() != 64
        || (mode != "auto" && mode != "stream")) {
      catalogFailure("Invalid catalog request"); return;
    }
    audio.stopSong();
    String url = "http://" + String(BACKEND_HOST) + ":" + String(BACKEND_PORT) + path;
    size_t freeBytes = LittleFS.totalBytes() - LittleFS.usedBytes();
    audioError = "";
    if (mode == "stream" || !canStageAudio(freeBytes, catalogExpected)) {
      streamUrl = url; playbackSource = "stream"; audioTitle = catalogTitle;
      if (!audio.connecttohost(streamUrl.c_str())) audioError = "Wi-Fi stream could not start. Select the track again to retry.";
      publishState(); return;
    }
    catalogHttp.setConnectTimeout(5000);
    catalogHttp.setTimeout(5000);
    if (!catalogHttp.begin(catalogClient, url) || catalogHttp.GET() != HTTP_CODE_OK
        || catalogHttp.getSize() != int(catalogExpected)) {
      catalogFailure("Catalog download unavailable or size changed"); return;
    }
    catalogFile = LittleFS.open(AUDIO_UPLOAD_PATH, "w");
    if (!catalogFile) { catalogFailure("Could not create temporary MP3"); return; }
    catalogDownloading = true;
    catalogReceived = 0;
    catalogLastData = millis();
    publishState();
  }
  if (!catalogDownloading) return;
  WiFiClient* input = catalogHttp.getStreamPtr();
  uint8_t buffer[2048];
  const size_t count = min(size_t(input->available()), min(sizeof(buffer), catalogExpected - catalogReceived));
  if (count) {
    int received = input->read(buffer, count);
    if (received <= 0 || catalogFile.write(buffer, received) != size_t(received)) {
      catalogFailure("MP3 write failed; previous track kept"); return;
    }
    catalogReceived += received;
    catalogLastData = millis();
  }
  if (catalogReceived == catalogExpected) {
    catalogFile.flush(); catalogFile.close(); catalogHttp.end();
    if (!sha256File(AUDIO_UPLOAD_PATH).equalsIgnoreCase(catalogHash)) {
      catalogFailure("MP3 checksum mismatch; previous track kept"); return;
    }
    // LittleFS rename replaces the destination atomically; never delete the old track first.
    if (!LittleFS.rename(AUDIO_UPLOAD_PATH, AUDIO_CURRENT_PATH)) {
      catalogFailure("MP3 replacement failed; previous track kept"); return;
    }
    catalogDownloading = false;
    streamUrl = ""; playbackSource = "local"; audioTitle = catalogTitle;
    if (!audio.connecttoFS(LittleFS, AUDIO_CURRENT_PATH)) audioError = "MP3 stored but playback could not start";
    publishState();
  } else if (WiFi.status() != WL_CONNECTED || millis() - catalogLastData > 15000
             || (!catalogHttp.connected() && !input->available())) {
    catalogFailure("MP3 download interrupted; previous track kept");
  }
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
  audioState["source"] = playbackSource;
  audioState["title"] = audioTitle;
  audioState["error"] = audioError;
  audioState["downloading"] = catalogDownloading || !catalogPending.isEmpty();
  audioState["stream_available"] = !streamUrl.isEmpty();
  audioState["free_bytes"] = LittleFS.totalBytes() - LittleFS.usedBytes();
  audioState["sample_rate"] = audio.getSampleRate();
  audioState["bits_per_sample"] = audio.getBitsPerSample();
  audioState["channels"] = audio.getChannels();
  audioState["position_seconds"] = audio.getAudioCurrentTime();
  const uint16_t audioLevel = audio.getVUlevel();
  audioState["level_left"] = audioLevel >> 8;
  audioState["level_right"] = audioLevel & 255;

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
  if (speakerTestActive && (type == "audio_catalog" || type == "audio_play" || type == "audio_stop")) {
    audio.stopSong(); finishSpeakerTest();
  }

  if (type == "light") {
    JsonObjectConst payload = doc["payload"];
    lightEnabled = payload["enabled"] | lightEnabled;
    lightBrightness = payload["brightness"] | lightBrightness;
    lightR = payload["r"] | lightR;
    lightG = payload["g"] | lightG;
    lightB = payload["b"] | lightB;
    applyLight();
  } else if (type == "audio_test") {
    speakerTestRequested = true;
  } else if (type == "audio_catalog") {
    cancelCatalog();
    serializeJson(doc["payload"], catalogPending);
    audioError = "";
  } else if (type == "audio_play") {
    audioError = "";
    bool ok = !streamUrl.isEmpty() ? audio.connecttohost(streamUrl.c_str())
                                 : audio.connecttoFS(LittleFS, AUDIO_CURRENT_PATH);
    if (!ok) audioError = "Playback could not start. Select the catalog track again to refresh streaming access.";
  } else if (type == "audio_stop") {
    cancelCatalog();
    audio.stopSong();
  } else if (type == "volume") {
    audioVolume = constrain(doc["payload"]["volume"] | int(audioVolume), 0, 100);
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
    doc["model"] =
#ifdef LILY_V2
      "Lily V2";
#else
      "LILY-V1";
#endif
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

#ifndef LILY_V2
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
#endif

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
    if (speakerTestActive && (audioAction == "play" || audioAction == "stop")) {
      audio.stopSong(); finishSpeakerTest();
    }

    if (audioAction == "play" && LittleFS.exists(AUDIO_CURRENT_PATH)) {
      cancelCatalog(); streamUrl = ""; playbackSource = "local"; audioTitle = ""; audioError = "";
      if (!audio.connecttoFS(LittleFS, AUDIO_CURRENT_PATH)) audioError = "Scheduled local playback could not start";
    } else if (audioAction == "stop") {
      cancelCatalog();
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

  if (!LittleFS.begin(false)) {
    Serial.println("LittleFS mount failed; setup stopped to preserve reset state.");
    while(true)delay(1000);
  }
  // Discard only an interrupted transfer, never saved configuration or the current track.
  if (LittleFS.exists(AUDIO_UPLOAD_PATH)) LittleFS.remove(AUDIO_UPLOAD_PATH);
  if (LittleFS.exists(SPEAKER_TEST_PATH)) LittleFS.remove(SPEAKER_TEST_PATH);

  const bool audioPinsReady = audio.setPinout(I2S_BCLK_PIN, I2S_LRC_PIN, I2S_DOUT_PIN);
  Serial.printf("Audio I2S: BCLK=%d LRC=%d DIN=%d configured=%s\n",
                I2S_BCLK_PIN, I2S_LRC_PIN, I2S_DOUT_PIN, audioPinsReady ? "yes" : "no");
  Serial.printf("Lily boot: serial=%s firmware=%s flash=%u psram=%u filesystem=%u free=%u\n",
                DEVICE_SERIAL, FIRMWARE_VERSION, ESP.getFlashChipSize(), ESP.getPsramSize(),
                unsigned(LittleFS.totalBytes()), unsigned(LittleFS.totalBytes() - LittleFS.usedBytes()));
  audio.setConnectionTimeout(5000, 5000);
  audio.setVolume(map(audioVolume, 0, 100, 0, 21));

  beginDeviceLifecycle([](){
    speakerTestRequested=false; speakerTestActive=false;
    beforeTestSource=""; beforeTestTitle=""; playbackSource="local";
    cancelCatalog(); streamUrl=""; audioTitle=""; audioError="";
    audio.stopSong();lightEnabled=false;applyLight();homeSsid="";homePassword="";pairingToken="";
    const char* files[]={CONFIG_PATH,"/config.tmp",SCHEDULES_PATH,AUDIO_CURRENT_PATH,AUDIO_UPLOAD_PATH,SPEAKER_TEST_PATH};
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
  if (speakerTestRequested && deviceRuntimeReady()) startSpeakerTest();
  if (speakerTestActive && !audio.isRunning()) {finishSpeakerTest(); publishState();}
  pollCatalog();
  if (audioStateDirty) { audioStateDirty = false; publishState(); }
  static bool wasPlaying = false;
  const bool playing = audio.isRunning();
  if (playing != wasPlaying) { wasPlaying = playing; publishState(); }
  static unsigned long lastAudioDiagnostic = 0;
  if (playing && millis() - lastAudioDiagnostic >= 5000) {
    lastAudioDiagnostic = millis();
    const uint16_t audioLevel = audio.getVUlevel();
    Serial.printf("Audio progress: rate=%u bits=%u channels=%u time=%us running=%u level=%u,%u\n",
                  audio.getSampleRate(), audio.getBitsPerSample(), audio.getChannels(),
                  audio.getAudioCurrentTime(), unsigned(playing), audioLevel >> 8, audioLevel & 255);
  }

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

// Decoder errors can arrive after connecttohost() has accepted the URL.
void audio_info(const char* info) {
  String message(info); message.toLowerCase();
  if (message.indexOf("http") < 0 && message.indexOf("token") < 0 && message.indexOf("authorization") < 0) {
    Serial.printf("Audio: %s\n", info);
  }
  if (message.indexOf("failed") >= 0 || message.indexOf("error") >= 0
      || message.indexOf("http/1.1 4") >= 0 || message.indexOf("http/1.1 5") >= 0) {
    audioError = "Audio playback failed. Check Wi-Fi and select the catalog track again.";
    audioStateDirty = true;
  }
}
