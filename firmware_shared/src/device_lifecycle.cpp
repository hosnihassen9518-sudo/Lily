#include "device_lifecycle.h"
#include "device_config.h"
#include "reset_state.h"
#include <Preferences.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <mbedtls/pk.h>
#include <mbedtls/base64.h>
#include <mbedtls/sha256.h>
#include <esp_gap_ble_api.h>
#include <memory>
#ifndef DEVICE_SERVER_PUBLIC_KEY
#define DEVICE_SERVER_PUBLIC_KEY ""
#endif
#ifndef DEVICE_RECEIPT_PRIVATE_KEY
#define DEVICE_RECEIPT_PRIVATE_KEY ""
#endif

namespace {
Preferences storage;
EraseUserConfiguration eraseConfiguration;
String challenge;
bool ready = false;
bool initialized = false;
bool bluetoothReady = false;
unsigned long lastPoll = 0;
int rng(void*, unsigned char* bytes, size_t count) { esp_fill_random(bytes, count); return 0; }
String receiptKey() {
  // A provisioned factory key must match the identity registered by inventory.
  // Generated NVS keys are only for boards without a factory receipt key.
  if(strlen(DEVICE_RECEIPT_PRIVATE_KEY)>0) return String(DEVICE_RECEIPT_PRIVATE_KEY);
  String key=storage.getString("receipt-key", "");
  if(!key.isEmpty()) return key;
  if(strlen(DEVICE_RECEIPT_PRIVATE_KEY)>0) key=DEVICE_RECEIPT_PRIVATE_KEY;
  else {
    mbedtls_pk_context ctx; mbedtls_pk_init(&ctx);
    int result=mbedtls_pk_setup(&ctx,mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY));
    if(result==0) result=mbedtls_ecp_gen_key(MBEDTLS_ECP_DP_SECP256R1,mbedtls_pk_ec(ctx),rng,nullptr);
    unsigned char pem[512]={0};
    if(result==0) result=mbedtls_pk_write_key_pem(&ctx,pem,sizeof(pem));
    if(result==0) key=(const char*)pem;
    mbedtls_pk_free(&ctx);
  }
  if(key.isEmpty() || storage.putString("receipt-key",key)==0) return "";
  return key;
}
String publicKey() {
  const String key=receiptKey();
  if(key.isEmpty()) return "";
  mbedtls_pk_context ctx; mbedtls_pk_init(&ctx);
  int result=mbedtls_pk_parse_key(&ctx,(const unsigned char*)key.c_str(),key.length()+1,nullptr,0);
  unsigned char pem[512]={0};
  if(result==0) result=mbedtls_pk_write_pubkey_pem(&ctx,pem,sizeof(pem));
  String output=result==0 ? String((const char*)pem) : String("");
  mbedtls_pk_free(&ctx); return output;
}
String signReceipt(const String& body) {
  String key=receiptKey();
  mbedtls_pk_context ctx; mbedtls_pk_init(&ctx);
  int result=mbedtls_pk_parse_key(&ctx,(const unsigned char*)key.c_str(),key.length()+1,nullptr,0);
  unsigned char hash[32], signature[128], encoded[256]; size_t size=0, encodedSize=0;
  mbedtls_sha256_ret((const unsigned char*)body.c_str(),body.length(),hash,0);
  if(result==0) result=mbedtls_pk_sign(&ctx,MBEDTLS_MD_SHA256,hash,32,signature,&size,rng,nullptr);
  if(result==0) result=mbedtls_base64_encode(encoded,sizeof(encoded)-1,&encodedSize,signature,size);
  mbedtls_pk_free(&ctx);
  if(result!=0) return "";
  encoded[encodedSize]=0;
  JsonDocument doc;doc["body"]=body;doc["signature"]=(const char*)encoded;
  String output;serializeJson(doc,output);return output;
}
bool post(const char* path,JsonDocument& request,JsonDocument& response) {
  if(WiFi.status()!=WL_CONNECTED) return false;
  HTTPClient http;
  http.setConnectTimeout(2000);http.setTimeout(5000);
  http.begin("http://"+String(BACKEND_HOST)+":"+String(BACKEND_PORT)+"/api/v1"+path);
  http.addHeader("Content-Type","application/json");
  String body;serializeJson(request,body);
  int code=http.POST(body);String result=http.getString();http.end();
  body="";
  if (code < 200 || code >= 300) {
    Serial.printf("Lily runtime %s failed: HTTP %d\n", path, code);
    return false;
  }
  if (deserializeJson(response,result)) {
    Serial.printf("Lily runtime %s failed: invalid JSON response\n", path);
    return false;
  }
  return true;
}
void credentials(JsonDocument& doc) {doc["serial_number"]=DEVICE_SERIAL;doc["device_secret"]=DEVICE_SECRET;}
bool verifyEnvelope(const String& raw,const String& expectedKind,const String& expectedChallenge,JsonDocument& operation) {
  if(raw.length()>1800 || !deviceManagementSupported()) return false;
  JsonDocument envelope;if(deserializeJson(envelope,raw))return false;
  if(!envelope["body"].is<const char*>() || !envelope["signature"].is<const char*>())return false;
  const String body=envelope["body"].as<String>();const String signature=envelope["signature"].as<String>();
  unsigned char decoded[128],hash[32];size_t count=0;
  if(mbedtls_base64_decode(decoded,sizeof(decoded),&count,(const unsigned char*)signature.c_str(),signature.length())!=0)return false;
  mbedtls_pk_context ctx;mbedtls_pk_init(&ctx);
  int result=mbedtls_pk_parse_public_key(&ctx,(const unsigned char*)DEVICE_SERVER_PUBLIC_KEY,strlen(DEVICE_SERVER_PUBLIC_KEY)+1);
  mbedtls_sha256_ret((const unsigned char*)body.c_str(),body.length(),hash,0);
  if(result==0)result=mbedtls_pk_verify(&ctx,MBEDTLS_MD_SHA256,hash,32,decoded,count);
  mbedtls_pk_free(&ctx);
  if(result!=0 || deserializeJson(operation,body))return false;
  const String id=operation["operation_id"]|"";
  return operation["serial"]==String(DEVICE_SERIAL) && operation["kind"]==expectedKind &&
         operation["challenge"]==expectedChallenge && operation["generation"].is<int>() &&
         operation["generation"].as<int>()==deviceGeneration() && id.length()==32 &&
         (expectedKind=="reset_ack" || storage.getString("completed-id","")!=id);
}
bool eraseAndSeal() {
  const String pending=storage.getString("pending","");
  if(pending.isEmpty())return true;
  JsonDocument operation;if(deserializeJson(operation,pending))return false;
  const ResetStage stage=resetCompletionReceipt().isEmpty()?ResetStage::Prepared:ResetStage::Erased;
  const String previousSsid=WiFi.SSID(),previousPassword=WiFi.psk();
  return resumeReset(stage,[&]() {
    if(!eraseConfiguration || !eraseConfiguration())return false;
    if(!bluetoothReady)return false;
    int count=esp_ble_get_bond_device_num();
    if(count>0) {
      std::unique_ptr<esp_ble_bond_dev_t[]> bonds(new esp_ble_bond_dev_t[count]);
      if(esp_ble_get_bond_device_list(&count,bonds.get())!=ESP_OK)return false;
      for(int i=0;i<count;i++)if(esp_ble_remove_bond_device(bonds[i].bd_addr)!=ESP_OK)return false;
      const auto start=millis();while(esp_ble_get_bond_device_num()>0 && millis()-start<2000)delay(10);
      if(esp_ble_get_bond_device_num()>0)return false;
    }
    WiFi.persistent(false);
    WiFi.mode(WIFI_STA);
    if(!WiFi.disconnect(false,true))return false; // Explicitly erase Wi-Fi stack credentials.
    return true;
  },[&]() {
    const String body="reset|"+String(DEVICE_SERIAL)+"|"+operation["operation_id"].as<String>()+"|"+String(operation["generation"].as<int>());
    const String receipt=signReceipt(body);
    if(receipt.isEmpty() || storage.putString("receipt",receipt)==0)return false;
    // Reconnect only in RAM to deliver the erased receipt. Never save old credentials.
    if(!previousSsid.isEmpty()) {
      WiFi.mode(WIFI_STA);WiFi.begin(previousSsid.c_str(),previousPassword.c_str());
      const auto start=millis();while(WiFi.status()!=WL_CONNECTED && millis()-start<5000)delay(50);
    }
    return true;
  });
}
}

bool deviceManagementSupported() {return initialized && strlen(DEVICE_SERVER_PUBLIC_KEY)>0;}
void deviceBluetoothReady() {bluetoothReady=true;}
bool confirmWifiConnection() {
  JsonDocument request,response;credentials(request);
  return post("/device-runtime/operations",request,response) && response["authorization"].isNull() &&
         response["generation"]==deviceGeneration() && response["lifecycle_status"]=="ACTIVE";
}
bool deviceResetPending() {return initialized && !storage.getString("pending","").isEmpty();}
bool deviceRuntimeReady() {return ready && !deviceResetPending();}
String resetCompletionReceipt() {
  if(!initialized)return "";
  JsonDocument operation,receipt;
  const String raw=storage.getString("receipt","");
  if(deserializeJson(operation,storage.getString("pending","")) || deserializeJson(receipt,raw))return "";
  const String expected="reset|"+String(DEVICE_SERIAL)+"|"+operation["operation_id"].as<String>()+"|"+String(operation["generation"].as<int>());
  return receipt["body"]==expected && receipt["signature"].is<const char*>() ? raw : String("");
}
String deviceChallenge() {return challenge;}
void renewDeviceChallenge() {challenge=""; for(int i=0;i<8;i++){char hex[9];snprintf(hex,sizeof(hex),"%08lx",(unsigned long)esp_random());challenge+=hex;}}
int deviceGeneration() {return initialized ? storage.getInt("generation",0) : 0;}
void setDeviceGeneration(int generation) {if(initialized)storage.putInt("generation",generation);}
void beginDeviceLifecycle(EraseUserConfiguration erase) {
  eraseConfiguration=erase;
  initialized=storage.begin("lily-life",false);
  if(!initialized)return;
  renewDeviceChallenge();
  if(deviceResetPending())eraseAndSeal();
}
bool validateWifiAuthorization(const String& envelope,const String& nonce) {
  if(deviceResetPending() || nonce!=challenge)return false;
  JsonDocument operation;
  if(!verifyEnvelope(envelope,"update_wifi",nonce,operation))return false;
  renewDeviceChallenge();return true;
}
bool requestUserReset(const String& envelope,const String& nonce) {
  if(deviceResetPending())return eraseAndSeal();
  if(nonce!="remote" && nonce!=challenge)return false;
  JsonDocument operation;
  if(!verifyEnvelope(envelope,"reset",nonce,operation))return false;
  String pending;serializeJson(operation,pending);
  if(storage.isKey("receipt") && !storage.remove("receipt"))return false;
  if(storage.putString("pending",pending)==0)return false;
  ready=false;renewDeviceChallenge();
  return eraseAndSeal();
}
bool acknowledgeUserReset(const String& envelope,const String& nonce) {
  if(!deviceResetPending() || resetCompletionReceipt().isEmpty() || nonce!=challenge)return false;
  JsonDocument operation,pending;
  if(!verifyEnvelope(envelope,"reset_ack",nonce,operation))return false;
  if(deserializeJson(pending,storage.getString("pending","")) || pending["operation_id"]!=operation["operation_id"])return false;
  const bool done=finishReset([&](){return storage.putString("completed-id",operation["operation_id"].as<String>())>0;},
    [&](){return storage.remove("pending");},[&](){storage.remove("receipt");});
  if(done)renewDeviceChallenge();return done;
}
void pollDeviceLifecycle() {
  if(!initialized)return;
  if(deviceResetPending()) {
    if(!eraseAndSeal())return;
    if(WiFi.status()==WL_CONNECTED) {
      JsonDocument request,response,receipt;
      deserializeJson(receipt,resetCompletionReceipt());request["receipt"]=receipt;
      if(post("/device-runtime/reset-complete",request,response) && response["status"]=="completed") {
        JsonDocument operation;deserializeJson(operation,storage.getString("pending",""));
        finishReset([&](){return storage.putString("completed-id",operation["operation_id"].as<String>())>0;},
          [&](){return storage.remove("pending");},[&](){storage.remove("receipt");});
      }
      WiFi.disconnect(true,true);ESP.restart();
    }
    return;
  }
  if(WiFi.status()!=WL_CONNECTED){ready=false;return;}
  if(lastPoll && millis()-lastPoll<15000)return;
  lastPoll=millis();
  JsonDocument registration,response;credentials(registration);
  registration["receipt_public_key"]=publicKey();registration["protocol_version"]=1;
  if (!deviceManagementSupported()) {
    Serial.println("Lily runtime blocked: missing DEVICE_SERVER_PUBLIC_KEY. Download the matching device configuration from the portal.");
    ready=false;return;
  }
  if(!post("/device-runtime/register",registration,response)){ready=false;return;}
  setDeviceGeneration(response["generation"]|deviceGeneration());
  JsonDocument request,operations;credentials(request);
  if(!post("/device-runtime/operations",request,operations)){ready=false;return;}
  if(!operations["authorization"].isNull()) {
    String envelope;serializeJson(operations["authorization"],envelope);
    requestUserReset(envelope,"remote");ready=false;return;
  }
  const bool wasReady = ready;
  ready=operations["lifecycle_status"]=="ACTIVE";
  if (ready && !wasReady) Serial.println("Lily runtime ready; MQTT enabled");
  if (!ready) Serial.printf("Lily runtime waiting: lifecycle=%s\n", operations["lifecycle_status"] | "unknown");
}
