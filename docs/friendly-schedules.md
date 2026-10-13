# Schedule editing and execution

Lily 0.10.1 supports editing a schedule by tapping its card, readable weekday names, repeat presets, pause/resume and confirmed deletion. Times are explicitly Europe/Paris, including CET/CEST changes. Schedules repeat on the selected weekdays; at least one weekday is required.

Deploy the backend update for the PATCH schedule endpoint and durable delivery retries. Flash the correct firmware target onto the light: the test-light target previously did not subscribe to schedules or execute them. Both firmware targets now initialize NTP using configTzTime so the Paris timezone is not overwritten with UTC. The test-light stores retained schedules atomically, checks ownership generation, clears schedules on reset, and applies the light action once per scheduled minute. It needs an initial successful NTP sync. Saved schedules run on the device without the phone open; the existing runner checks while Wi-Fi is connected.

Verification: Flutter editor and model-change tests, backend ownership/edit/pause/delete/retry payload tests, source regression for clock initialization, and PlatformIO compilation of both firmware targets. A real light turning on at a future time requires updated firmware and physical hardware; an Android emulator cannot verify that action.

## Release verification

- 67 Flutter tests passed; analyzer has no errors or warnings (10 existing informational findings).
- 41 applicable backend checks passed, one PostgreSQL-only check skipped; two known Windows-incompatible checks excluded (native g++ header compile, Unix0600 key-file permissions).
- Both ESP32 firmware targets compiled successfully.
- Signed release APK installed on Pixel_10_Pro_XL / emulator-5554; cold start Status ok (1264ms), process remained alive. Existing schedule list shows readable times and Every day; saved schedule opens with its current time/days/actions, repeat presets, and Paris time label. Editing was cancelled without changing stored schedules or sending device commands.
- LilyV12.apk: package com.example.lily_mobile, version0.10.1, code10. SHA256 B5900B090FD21FF6214119FF314F569C840CE02A71129DF4E0F6E1B315198687.
- Review found command-form actions could change during editing; normalization and optional light/audio action selections now preserve intent, including typed off/audio/volume schedules. Regressions pass at320 and800px widths. Scoped review has no further material findings.
