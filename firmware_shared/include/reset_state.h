#pragma once
enum class ResetStage { None, Prepared, Erased };
inline bool mustErase(ResetStage stage) { return stage == ResetStage::Prepared; }
inline bool blocksProvisioning(ResetStage stage) { return stage != ResetStage::None; }
template<class Erase,class Seal>
bool resumeReset(ResetStage stage,Erase erase,Seal seal) {
  if(!mustErase(stage))return true;
  if(!erase())return false;
  return seal();
}
template<class Complete,class RemoveMarker,class RemoveReceipt>
bool finishReset(Complete complete,RemoveMarker removeMarker,RemoveReceipt removeReceipt) {
  if(!complete() || !removeMarker())return false;
  removeReceipt();return true;
}
