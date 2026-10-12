#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
#include <functional>
using EraseUserConfiguration = std::function<bool()>;
void beginDeviceLifecycle(EraseUserConfiguration erase);
bool deviceResetPending();
bool deviceRuntimeReady();
void pollDeviceLifecycle();
bool validateWifiAuthorization(const String& envelope, const String& challenge);
bool requestUserReset(const String& envelope, const String& challenge);
bool acknowledgeUserReset(const String& envelope, const String& challenge);
String resetCompletionReceipt();
String deviceChallenge();
void renewDeviceChallenge();
void setDeviceGeneration(int generation);
int deviceGeneration();
bool deviceManagementSupported();
bool confirmWifiConnection();
void deviceBluetoothReady();
