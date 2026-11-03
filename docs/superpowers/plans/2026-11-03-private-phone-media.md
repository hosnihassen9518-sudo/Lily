# Private Phone Media Implementation Plan

**Goal:** Select phone MP3s privately, then use existing Lily local/Wi-Fi playback.
**Spec:** ../specs/2026-11-03-phone-media-and-bluetooth-design.md
**Architecture:** Nullable Music.owner_id distinguishes shared tracks from private
uploads. All read/play paths enforce ownership. Flutter uses existing file_picker
and authenticated multipart uploads. Existing firmware is unchanged.

- [x] Backend: add privacy regression tests, migration preservation test and bounded
  upload validation tests; verify failure. Add owner field/migration and private
  upload/list endpoint, enforce visibility on download, playback and media tokens.
  Exclude private tracks from shared admin catalog mutation endpoints. Verify tests.
- [x] Mobile: test multipart authentication, cancellation/session changes and source
  selection. Implement file picker, upload/status, My files and Server catalog;
  retain device-target binding. Build app 0.10.4+13 and run regressions.
- [x] Review changes, document deployment migration, install emulator APK, publish
  source changes to existing GitHub branch following the user's deployment preference.

Review focus: cross-user guessed IDs and tokens; existing shared tracks after migration;
oversized/empty/fake MP3s and partial uploads; token refresh and server switches;
picker cancellation and leaving the screen while upload completes. No Bluetooth work.

## Verification record
Full backend suite: 114 passed, 2 skipped. Full Flutter suite: 84 passed.
Migration test upgrades the previous frozen schema with an existing shared track;
ownership remains null. Tests deny cross-account listing/download/playback and signed
device media, enforce upload limits/header checks, and clean files on commit failure.
Independent review found a server-switch race after the final file-stream chunk;
reproduced red, fixed and verified green. Multipart token refresh/retry and offline
private-file labels are covered. No ESP32 firmware changes or Bluetooth integration.
Backend deployment applies migration 20261103_private_music; user handles server rollout.
Android debug APK 0.10.4+13 built and installed/launched successfully on emulator-5554.
Phone artifact: tmp/Lily-0.10.4-debug.apk (excluded from Git). Publish on existing
codex/lily-0.9-rbac branch. Physical file-picker and speaker playback remain manual
acceptance checks after the user deploys the updated backend.
