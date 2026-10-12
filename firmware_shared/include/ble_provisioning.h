#pragma once
#include <Arduino.h>
#include <functional>

struct BleWifiRequest {
  String requestId;
  String ssid;
  String password;
  String token;
  String command = "provision";
  String authorization;
  String challenge;
};
using BleProvisionHandler = std::function<bool(const BleWifiRequest&, String&)>;

void beginBleProvisioning(bool configured, BleProvisionHandler handler);
void pollBleProvisioning();
void bleProvisionStatus(const String& requestId, const char* stage, const String& detail = "");
