#include "device_message_rules.h"
#include <cassert>
int main(){
  assert(acceptDeviceMessage(true,true,2,2));
  assert(!acceptDeviceMessage(true,true,2,1));
  assert(!acceptDeviceMessage(true,true,2,-1));
  assert(!acceptDeviceMessage(false,true,2,2));
  assert(acceptDeviceMessage(true,false,0,-1));
  assert(!allowsUserFileMutation(true));
  assert(allowsUserFileMutation(false));
}
