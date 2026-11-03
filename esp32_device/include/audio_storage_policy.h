#pragma once
#include <stddef.h>

constexpr size_t AUDIO_STORAGE_RESERVE = 64 * 1024;
constexpr bool canStageAudio(size_t freeBytes, size_t incomingBytes) {
  return incomingBytes > 0 && freeBytes > AUDIO_STORAGE_RESERVE
      && incomingBytes <= freeBytes - AUDIO_STORAGE_RESERVE;
}
static_assert(!canStageAudio(0, 1), "Empty filesystem budget must stream");
static_assert(!canStageAudio(AUDIO_STORAGE_RESERVE, 1), "Keep settings reserve");
static_assert(canStageAudio(AUDIO_STORAGE_RESERVE + 10, 10), "Exact fit may stage");
static_assert(!canStageAudio(AUDIO_STORAGE_RESERVE + 10, 11), "Oversize must stream");
static_assert(!canStageAudio(size_t(-1), 0), "Reject empty track");
