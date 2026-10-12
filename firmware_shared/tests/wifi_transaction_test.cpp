#include "wifi_transaction.h"
#include <cassert>
int main(){
  int clocks=0,restores=0;
  auto ok=[](){return true;};auto fail=[](){return false;};
  auto restore=[&](){++restores;};auto clock=[&](){++clocks;};
  assert(applyWifiConfiguration(ok,ok,ok,restore,clock));
  assert(clocks==1 && restores==0); // Initial BLE setup starts the schedule clock immediately.
  assert(!applyWifiConfiguration(ok,ok,fail,restore,clock));
  assert(clocks==1 && restores==1); // Storage failure preserves previous Wi-Fi.
  assert(!applyWifiConfiguration(ok,fail,ok,restore,clock));
  assert(clocks==1 && restores==2);
  assert(!applyWifiConfiguration(fail,ok,ok,restore,clock));
  assert(clocks==1 && restores==3);
}
