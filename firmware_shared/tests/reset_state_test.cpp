#include "reset_state.h"
#include <cassert>
int main() {
  assert(mustErase(ResetStage::Prepared));
  assert(!mustErase(ResetStage::None));
  assert(!mustErase(ResetStage::Erased));
  assert(blocksProvisioning(ResetStage::Prepared));
  assert(blocksProvisioning(ResetStage::Erased));
  assert(!blocksProvisioning(ResetStage::None));
  int erases=0,seals=0;
  auto erase=[&](){++erases;return true;};
  auto failedSeal=[&](){++seals;return false;};
  assert(!resumeReset(ResetStage::Prepared,erase,failedSeal));
  assert(erases==1 && seals==1); // Power loss before a durable receipt resumes erasure.
  assert(resumeReset(ResetStage::Prepared,erase,[&](){++seals;return true;}));
  assert(erases==2 && seals==2);
  assert(resumeReset(ResetStage::Erased,erase,failedSeal));
  assert(erases==2 && seals==2); // A durable receipt survives retry without another wipe.
  assert(!resumeReset(ResetStage::Prepared,[](){return false;},failedSeal));
  assert(seals==2); // Storage failure cannot produce a completion receipt.
  int completeWrites=0,markerRemovals=0,receiptRemovals=0;
  assert(!finishReset([&](){++completeWrites;return true;},[&](){++markerRemovals;return false;},[&](){++receiptRemovals;}));
  assert(completeWrites==1 && markerRemovals==1 && receiptRemovals==0);
  assert(finishReset([&](){++completeWrites;return true;},[&](){++markerRemovals;return true;},[&](){++receiptRemovals;}));
  assert(receiptRemovals==1); // A failed marker removal keeps the receipt for recovery.
}
