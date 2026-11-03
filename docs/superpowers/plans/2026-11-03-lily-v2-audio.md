# Lily v2 Audio Implementation Plan

**Goal:** Catalog playback with one local MP3 and Wi-Fi streaming fallback.
**Architecture:** Authenticated selection publishes a generation-bound MQTT command with a signed
catalog URL. Firmware decides storage versus streaming from actual space. Flutter requests and
observes device state.
**Tech stack:** FastAPI, SQLAlchemy, Arduino/PlatformIO, ESP32-audioI2S, Flutter.
**Spec:** ../specs/2026-11-03-lily-v2-audio-design.md

## Constraints and review focus
Preserve GPIO18 LEDs and existing devices. Audio pins 10/40/15. Reserve 64KiB storage.
Test unauthorized selections, expired URLs, reset generation changes, oversized replacements,
and incomplete downloads. Never claim hardware sound is verified by a build.

## Tasks
- [x] Backend: test and implement catalog selection, signed device media delivery, model generation.
- [x] Firmware: configure v2 partitions/PSRAM/LEDs; implement deferred download/stream commands,
  bounded verified replacement, storage reporting, error and completion state. Build target.
- [x] Mobile: replace legacy AP transfer with auto/stream catalog selection and confirmed state.
  Add API tests, analyze, and build/test where available.
- [x] Review diff and run relevant regressions. Document deployment and hardware checks.

## Execution record
Implemented inline following the user's instruction to implement both modes.
Backend: 109 tests passed, 2 skipped. Flutter: 77 tests passed; final changed
catalog/model/disposal subset also passed. Android debug APK built and installed
on emulator-5554. Analysis has no errors/warnings, 10 existing informational notices.
V2 firmware and empty filesystem image build successfully. Binary partition check
confirms 16MiB bounds, no overlap, 9.875MiB filesystem. Independent review findings
were fixed: legacy firmware rejection, build-environment guard, scheduled cancellation
and scheduled source state. Existing board identity is in an ignored local header,
selected consistently by main, BLE and lifecycle code.

Hardware deployment remains pending: no ESP32 serial port visible (only COM1), no
local backend on port 6100 detected, and filesystem initialization requires explicit
acceptance of losing saved Wi-Fi/settings/audio. No flashing or backend deployment
performed; physical speaker, Wi-Fi media transfer and BLE pairing are unverified.

## Hardware follow-up
Live server is 192.168.1.104 (separate host). Created live model lily_v2 with all
six audio/light capabilities and inventory device Lily V2 Audio, serial
LILY-2523AF441737C556. Firmware has not been flashed with that new identity.
COM7 now exposes the ESP32-S3 with embedded 8MB PSRAM. Read and verified a complete
16MiB flash backup at tmp/lily-com7-before-v2.bin; SHA256 recorded alongside it.
Backup shows current factory identity LILY-2DA1E30362B4711D and old 8MiB partition
layout with 1.5MiB filesystem. The new header was blocked by Chrome; filesystem
checks in Downloads (including host view) found only older LILY-976E3D7A8E03681C
headers. User was asked for the saved file's actual filename/folder. Do not flash
an unrelated identity. Existing SSH configuration uses lily@192.168.1.104 but
BatchMode authentication failed. Updated backend source archive is prepared at
tmp/lily-v2-backend-source.tar.gz; live backend deployment remains pending.

New header subsequently found in Downloads. Prepared ignored v2 local header with
serial LILY-2523AF441737C556, original factory keys, server 192.168.1.104, and pins
10/40/15 with five GPIO18 LEDs. Firmware and filesystem images rebuilt successfully.
Automatic approval review rejected the combined COM7 write before execution because
the user has not explicitly approved loss of saved Wi-Fi, schedules and audio.
No flash writes performed. Ask for explicit approval of this concrete flash before
retrying; do not work around the rejection. Full backup and checksum are verified.

User subsequently explicitly approved destructive flashing. COM7 firmware, partition
table and 9.875MiB filesystem were written and verified. Initial manual esptool upload
incorrectly forced QIO and caused ROM watchdog restarts; corrected bootloader header
to DIO (matching both original backup and built image). Added missing-key guard for
reset-pending checks and boot diagnostics, then rebuilt/uploaded through PlatformIO.
Final upload succeeded and boot log confirms serial LILY-2523AF441737C556, firmware
2.0.0, 16777216-byte flash, 8386167 usable PSRAM bytes, filesystem 10354688 bytes,
free 10346496 bytes, and BLE setup ready. No watchdog reset loop or pending-key log
flood in final capture. Saved Wi-Fi was cleared; new device must be paired.
Live schema check confirms v2 catalog/media routes still absent. Server SSH access
was requested from user to deploy prepared backend update. Physical playback remains
unverified until backend deployment and pairing are completed.
