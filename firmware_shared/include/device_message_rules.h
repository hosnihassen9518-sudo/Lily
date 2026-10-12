#pragma once
inline bool acceptDeviceMessage(bool ready,bool managed,int currentGeneration,int receivedGeneration) {
  return ready && (!managed || receivedGeneration==currentGeneration);
}
inline bool allowsUserFileMutation(bool resetPending) { return !resetPending; }
