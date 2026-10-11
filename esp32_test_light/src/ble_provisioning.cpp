#include "ble_provisioning.h"
#include "device_config.h"
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLESecurity.h>
#include <Preferences.h>
#include <WiFi.h>
#include <vector>
#include <algorithm>
#include <atomic>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/semphr.h>

namespace {
const char* SERVICE = "8c9a0001-6f32-4b88-a5c1-1e1d7c6a0000";
const char* INFO = "8c9a0002-6f32-4b88-a5c1-1e1d7c6a0000";
const char* COMMAND = "8c9a0003-6f32-4b88-a5c1-1e1d7c6a0000";
const char* STATUS_UUID = "8c9a0004-6f32-4b88-a5c1-1e1d7c6a0000";
constexpr size_t MAX_MESSAGE = 2048;
struct Message { char bytes[MAX_MESSAGE + 1]; };
QueueHandle_t requests;
SemaphoreHandle_t bufferLock;
SemaphoreHandle_t statusLock;
BLEServer* server = nullptr;
BLECharacteristic* statusCharacteristic = nullptr;
BleProvisionHandler provisionHandler;
std::string incoming;
String statusJson;
String successId;
std::atomic<bool> connected{false}, authenticated{false}, busy{false}, acknowledged{false};
std::atomic<bool> advertiseAgain{false};
bool discarding = false;
bool enabled = false;
unsigned long successAt = 0;
uint32_t passkey;
struct WifiNetwork { String ssid; int rssi; bool secure; };
std::vector<WifiNetwork> scannedNetworks;
String scanRequestId;
unsigned long scanStarted = 0;
bool scanning = false;
bool wifiWasOff = false;

void publishNetworks(const String& id, int page) {
  constexpr int perPage = 1; // Escaped 32-byte SSIDs must still fit a 512-byte GATT value.
  const int pages = std::max(1, (int)(scannedNetworks.size() + perPage - 1) / perPage);
  if (page < 0 || page >= pages) { bleProvisionStatus(id, "error", "Invalid Wi-Fi scan page."); return; }
  JsonDocument doc;
  doc["version"] = 1; doc["request_id"] = id;
  doc["stage"] = "wifi_networks"; doc["page"] = page; doc["total_pages"] = pages;
  auto networks = doc["networks"].to<JsonArray>();
  for (int i = page * perPage; i < std::min((int)scannedNetworks.size(), (page + 1) * perPage); i++) {
    auto network = networks.add<JsonObject>();
    network["ssid"] = scannedNetworks[i].ssid;
    network["rssi"] = scannedNetworks[i].rssi;
    network["secure"] = scannedNetworks[i].secure;
  }
  String output; serializeJson(doc, output);
  xSemaphoreTake(statusLock, portMAX_DELAY); statusJson = output; xSemaphoreGive(statusLock);
}

class SecurityCallbacks : public BLESecurityCallbacks {
  uint32_t onPassKeyRequest() override { return passkey; }
  void onPassKeyNotify(uint32_t key) override { Serial.printf("Lily BLE pairing PIN: %06lu\n", (unsigned long)key); }
  bool onSecurityRequest() override { return true; }
  bool onConfirmPIN(uint32_t) override { return false; } // Display-only passkey entry, not numeric comparison.
  void onAuthenticationComplete(esp_ble_auth_cmpl_t result) override {
    authenticated = result.success;
    Serial.printf("Lily BLE authentication: %s / reason=%u / heap=%lu\n", result.success ? "OK" : "FAILED", result.fail_reason, (unsigned long)ESP.getFreeHeap());
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    connected = true;
    authenticated = false;
    Serial.println("Lily BLE connected; enter the serial PIN when prompted.");
  }
  void onDisconnect(BLEServer*) override {
    connected = false;
    authenticated = false;
    Serial.printf("Lily BLE disconnected / heap=%lu\n", (unsigned long)ESP.getFreeHeap());
    xSemaphoreTake(bufferLock, portMAX_DELAY);
    incoming.clear();
    discarding = false;
    xSemaphoreGive(bufferLock);
    // Restart advertising from loop(), not from the BLE callback.
    advertiseAgain = true;
  }
};

class StatusCallbacks : public BLECharacteristicCallbacks {
  void onRead(BLECharacteristic* characteristic) override {
    xSemaphoreTake(statusLock, portMAX_DELAY);
    JsonDocument doc;
    deserializeJson(doc, statusJson);
    doc["authenticated"] = authenticated.load();
    String output; serializeJson(doc, output);
    characteristic->setValue(std::string(output.c_str()));
    xSemaphoreGive(statusLock);
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    if (!authenticated.load()) { Serial.println("Lily BLE write ignored: link is not authenticated"); return; }
    const std::string fragment = characteristic->getValue();
    Serial.printf("Lily BLE command chunk: %u bytes\n", (unsigned)fragment.size());
    xSemaphoreTake(bufferLock, portMAX_DELAY);
    for (const char byte : fragment) {
      if (byte == '\n') {
        if (!discarding && !incoming.empty()) {
          // Keep the 2 KB envelope off the Bluetooth callback task's stack.
          static Message message;
          memset(message.bytes, 0, sizeof(message.bytes));
          memcpy(message.bytes, incoming.data(), incoming.size());
          // Parsing and network work occur in loop(). The queue is bounded.
          if (xQueueSend(requests, &message, 0) != pdTRUE) {
            bleProvisionStatus("", "error", "Setup is busy. Wait and retry.");
          }
          memset(message.bytes, 0, sizeof(message.bytes));
        }
        incoming.clear();
        discarding = false;
      } else if (!discarding) {
        if (byte == '\0' || incoming.size() >= MAX_MESSAGE - 1) {
          incoming.clear();
          discarding = true;
          bleProvisionStatus("", "error", "Malformed or oversized setup message.");
        } else {
          incoming += byte;
        }
      }
    }
    xSemaphoreGive(bufferLock);
  }
};
}

void bleProvisionStatus(const String& id, const char* stage, const String& detail) {
  JsonDocument doc;
  doc["version"] = 1;
  doc["request_id"] = id;
  doc["stage"] = stage;
  if (!detail.isEmpty()) doc["detail"] = detail;
  String output;
  serializeJson(doc, output);
  xSemaphoreTake(statusLock, portMAX_DELAY);
  statusJson = output;
  xSemaphoreGive(statusLock);
  // Only onRead changes the characteristic value. Updating it here (even for
  // a short notify hint) would corrupt an in-flight ATT read-blob response.
  Serial.printf("Lily BLE setup stage: %s\n", stage);
}

void beginBleProvisioning(bool configured, BleProvisionHandler handler) {
  if (enabled) return;
  provisionHandler = handler;
  requests = xQueueCreate(1, sizeof(Message));
  bufferLock = xSemaphoreCreateMutex();
  statusLock = xSemaphoreCreateMutex();
  if (!requests || !bufferLock || !statusLock) {
    Serial.println("Lily BLE initialization failed: insufficient memory");
    return;
  }
  Preferences pairingSettings;
  if (!pairingSettings.begin("lily-ble", false)) {
    Serial.println("Lily BLE setup cannot start: pairing settings storage failed"); return;
  }
  passkey = pairingSettings.getUInt("pin", 0);
  if (passkey < 100000 || passkey > 999999) {
    passkey = 100000 + esp_random() % 900000;
    if (pairingSettings.putUInt("pin", passkey) != sizeof(passkey)) {
      pairingSettings.end();
      Serial.println("Lily BLE setup cannot start: could not persist fixed PIN"); return;
    }
  }
  pairingSettings.end();
  const String name = "LILY-" + String(DEVICE_SERIAL).substring(0, 18);
  BLEDevice::init(name.c_str());
  BLEDevice::setMTU(247);
  BLEDevice::setEncryptionLevel(ESP_BLE_SEC_ENCRYPT_MITM);
  BLEDevice::setSecurityCallbacks(new SecurityCallbacks());
  auto* security = new BLESecurity();
  security->setStaticPIN(passkey);
  // setStaticPIN changes some defaults, so enforce these AFTER it.
  security->setAuthenticationMode(ESP_LE_AUTH_REQ_SC_MITM_BOND);
  security->setCapability(ESP_IO_CAP_OUT);
  security->setInitEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);
  security->setRespEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);
  server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  auto* service = server->createService(SERVICE);
  auto* info = service->createCharacteristic(INFO, BLECharacteristic::PROPERTY_READ);
  // Reading identity triggers the system PIN prompt before any credential write.
  info->setAccessPermissions(ESP_GATT_PERM_READ_ENC_MITM);
  JsonDocument doc;
  doc["version"] = 1;
  doc["serial"] = DEVICE_SERIAL;
  doc["firmware"] = FIRMWARE_VERSION;
  doc["device_type_key"] = DEVICE_TYPE_KEY;
  doc["device_type_name"] = DEVICE_TYPE_NAME;
  doc["configured"] = configured;
  doc["wifi_scan"] = true;
  auto capabilities = doc["capabilities"].to<JsonArray>();
  capabilities.add("power"); capabilities.add("light");
  String output;
  serializeJson(doc, output);
  info->setValue(std::string(output.c_str()));
  auto* command = service->createCharacteristic(COMMAND, BLECharacteristic::PROPERTY_WRITE);
  command->setAccessPermissions(ESP_GATT_PERM_WRITE_ENC_MITM);
  command->setCallbacks(new CommandCallbacks());
  statusCharacteristic = service->createCharacteristic(STATUS_UUID, BLECharacteristic::PROPERTY_READ);
  statusCharacteristic->setAccessPermissions(ESP_GATT_PERM_READ_ENC_MITM);
  statusCharacteristic->setCallbacks(new StatusCallbacks());
  bleProvisionStatus("", "ready");
  service->start();
  auto* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE);
  advertising->setScanResponse(true);
  advertising->start();
  enabled = true;
  Serial.printf("Lily BLE setup: %s / pairing PIN: %06lu / firmware: %s\n", name.c_str(), (unsigned long)passkey, FIRMWARE_VERSION);
}

void pollBleProvisioning() {
  if (!enabled) return;
  if (scanning) {
    const int count = WiFi.scanComplete();
    if (count >= 0 || millis() - scanStarted > 15000 || count == WIFI_SCAN_FAILED) {
      if (count >= 0) {
        scannedNetworks.clear();
        for (int i = 0; i < count; i++) {
          const String ssid = WiFi.SSID(i);
          if (ssid.isEmpty()) continue;
          auto previous = std::find_if(scannedNetworks.begin(), scannedNetworks.end(), [&](const WifiNetwork& n) { return n.ssid == ssid; });
          WifiNetwork network{ssid, WiFi.RSSI(i), WiFi.encryptionType(i) != WIFI_AUTH_OPEN};
          if (previous != scannedNetworks.end()) { if (network.rssi > previous->rssi) *previous = network; }
          else if (scannedNetworks.size() < 64) scannedNetworks.push_back(network);
        }
        std::sort(scannedNetworks.begin(), scannedNetworks.end(), [](const WifiNetwork& a, const WifiNetwork& b) { return a.rssi > b.rssi; });
      }
      WiFi.scanDelete();
      if (wifiWasOff) WiFi.mode(WIFI_OFF);
      scanning = false;
      if (count >= 0) publishNetworks(scanRequestId, 0);
      else bleProvisionStatus(scanRequestId, "error", "Wi-Fi scan failed. Try again.");
    }
  }
  if (successAt && (acknowledged || millis() - successAt >= 60000)) {
    BLEDevice::getAdvertising()->stop();
    if (connected) server->disconnect(server->getConnId());
    // Advertising is disabled; preserve the BLE stack to avoid unsafe teardown
    // while callbacks are in flight. The next boot determines recovery mode.
    enabled = false;
    return;
  }
  if (!connected && !successAt && advertiseAgain.exchange(false)) BLEDevice::getAdvertising()->start();
  Message message{};
  if (xQueueReceive(requests, &message, 0) != pdTRUE) return;
  JsonDocument doc;
  if (deserializeJson(doc, message.bytes)) {
    bleProvisionStatus("", "error", "Invalid setup JSON."); return;
  }
  const String id = doc["request_id"] | "";
  const String command = doc["command"] | "";
  if (!doc["version"].is<int>() || doc["version"].as<int>() != 1 ||
      !doc["request_id"].is<const char*>() || id.isEmpty() || id.length() > 32) {
    bleProvisionStatus(id, "error", "Unsupported protocol or invalid request ID."); return;
  }
  if (command == "ack" && !successId.isEmpty() && id == successId) {
    acknowledged = true; return;
  }
  if (scanning) { bleProvisionStatus(id, "error", "A Wi-Fi scan is still running. Please wait."); return; }
  if (command == "scan" && !busy && !successAt) {
    bleProvisionStatus(id, "scanning_wifi");
    scanRequestId = id;
    wifiWasOff = WiFi.getMode() == WIFI_OFF;
    // Allow the acknowledged BLE command write to complete before radio changes.
    delay(250);
    WiFi.mode(WIFI_STA);
    WiFi.scanDelete();
    const int result = WiFi.scanNetworks(true, true);
    if (result == WIFI_SCAN_FAILED) {
      if (wifiWasOff) WiFi.mode(WIFI_OFF);
      bleProvisionStatus(id, "error", "Wi-Fi scan could not start.");
    } else {
      scanning = true; scanStarted = millis();
    }
    return;
  }
  if (command == "networks" && id == scanRequestId && doc["page"].is<int>() && !successAt) {
    publishNetworks(id, doc["page"].as<int>()); return;
  }
  if (busy || successAt || command != "provision") {
    bleProvisionStatus(id, "error", "Setup is busy or command is unsupported."); return;
  }
  BleWifiRequest request{id, doc["ssid"] | "", doc["password"] | "", doc["pairing_token"] | ""};
  const auto validString = [](JsonVariantConst value, size_t minimum, size_t maximum) {
    if (!value.is<const char*>()) return false;
    const JsonString text = value.as<JsonString>();
    return text.size() >= minimum && text.size() <= maximum &&
           memchr(text.c_str(), '\0', text.size()) == nullptr;
  };
  if (!validString(doc["ssid"], 1, 32) || !validString(doc["password"], 0, 63) ||
      !validString(doc["pairing_token"], 1, MAX_MESSAGE) ||
      (request.password.length() != 0 && request.password.length() < 8)) {
    bleProvisionStatus(id, "error", "Invalid Wi-Fi name, password, or pairing session."); return;
  }
  busy = true;
  bleProvisionStatus(id, "accepted");
  delay(250); // Let the final GATT write acknowledgment finish before enabling Wi-Fi.
  String detail;
  const bool ok = provisionHandler(request, detail);
  // Wipe the request as soon as network work completes.
  request.password = ""; request.token = "";
  memset(message.bytes, 0, sizeof(message.bytes));
  busy = false;
  if (ok) {
    successId = id;
    successAt = millis();
    bleProvisionStatus(id, "success");
  } else {
    bleProvisionStatus(id, "error", detail);
  }
}
