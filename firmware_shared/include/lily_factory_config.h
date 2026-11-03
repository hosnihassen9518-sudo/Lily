#pragma once
// All translation units must use the same factory identity, including BLE and lifecycle.
#if defined(LILY_V2) && __has_include("device_config_v2.local.h")
#include "device_config_v2.local.h"
#else
#include "device_config.h"
#endif
#if defined(LILY_V2_CONFIG) && !defined(LILY_V2)
#error "Lily v2 factory configuration requires PlatformIO environment lily_v2"
#endif
