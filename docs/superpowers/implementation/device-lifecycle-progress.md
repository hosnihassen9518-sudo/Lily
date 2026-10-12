# Execution ledger: device lifecycle and mobile sessions
Plan: docs/superpowers/plans/2026-10-11-device-lifecycle-and-mobile-sessions.md
Spec approved. Native execution; physical button deferred.
Network repaired via per-command additional network permission. Full checkout isolated at /workspace/lily-feature, branch feat/device-lifecycle-sessions, base 551986b.
Task 1: SQLite migration and model seeds RED→GREEN, 2 tests passed, b8530b6. PostgreSQL verification still pending.
Ruling: use external worktree path within /workspace — approved plan requires isolation; avoids editing main's ignore file.
Ruling: cloud skill helper scripts unavailable locally; maintain this ledger directly.
Pre-flight: catalog → inventory; session models → refresh/store/admin; identities/operations → backend/firmware/mobile. Byte protocol must be fixed before firmware.
Tasks 2–3: generated inventory/header/admin and session API implemented; 8 backend tests passed after wrong test request ID corrected to meet min length. Type mismatch test RED→GREEN. Admin build passed. Session client/admin settings are in progress.
Baseline: 29 existing Flutter tests passed. Flutter analytics needed FLUTTER_SUPPRESS_ANALYTICS; Dart native hooks additionally need writable .dart-tool.
Ruling: existing unsupported models remain legacy strings with no generated catalog entry; preserves compatibility without claiming firmware support.
Ruling: session rotation HMAC uses domain separation of existing server key; separate persisted key is unnecessary to enforce credential separation.
Tasks 4–5: secure session store, silent single-flight refresh, policy Settings page implemented. Mobile suite exposed stale-response exception during backend switching; existing revision guard now discards those errors. Baseline test bindings initialized for secure store.
Task 6: reset operation/receipt verification RED→GREEN; all 10 backend tests pass. Pending controls, claim and activation rejected, identity and catalog preserved, signed receipt required. Broker cleanup retry included.
Tasks 7–9: shared BLE lifecycle, Wi-Fi management, durable reset receipt, and management screen implementation ongoing. Native stage checks pass. ESP32 builds exposed missing local test-light config and C++11 aggregate initialization; using example config for build and explicit field assignments.
Ruling: remote reset reconnects briefly with volatile credentials after erasing Wi-Fi NVS solely to acknowledge completion; on failure local BLE relays durable receipt. Credentials are never saved again.
Recovery checks: 4 new tests failed first, then passed (invalid receipt key validation, admin cannot cancel pending reset, claim blocks retained cleanup, lost refresh response after five-minute outage). 14 SQLite tests and 15 PostgreSQL tests pass.
Ruling: refresh retry with the same last request ID remains recoverable until absolute session expiry — avoids early reauthentication after a lost response/outage. A different request ID or older rotated credential still fails.
Ruling: broker-retained cleanup must receive PUBACK before reassignment; persisted cleanup retry runs outside MQTT callback thread.
Both ESP32 firmware targets built; audio dependency registry missing, so use pinned upstream 3.0.12 commit. Explicit targeted shared library dependency avoids compiling sibling projects.
Mobile: 32 tests pass; new removal widget test exposed eager platform BLE initialization before user action; transport made lazy. Analyzer has five pre-existing infos and one new style info being fixed.
Additional checks: native C++ roundtrip catches Unicode escaping of generated headers; backend header builder now uses UTF-8 octal byte escapes. Migration schema is frozen rather than importing live ORM definitions. Container copies migration files and preserves signing-key path in data volume.
Android build: public Android SDK 37 is unavailable while reactive_ble_mobile 5.6.0 hardcodes it. Ruling: compile app against Flutter SDK default 36 and override that plugin to the supported 36 as existing file_picker override already does. No used BLE API requires 37. Artifact version is 0.8.0+5; requested filename LilyV7.apk.
User requested copy to \\192.168.1.254\Media\Project\Lily\LilyV7.apk. Environment snapshot has vpn_configured=false and no TCP grants. Asked user to configure secure NAS access or accept a download. File copy is authorized but blocked pending connectivity.
Native reset marker completion now retries failed marker deletion and checks receipt operation/generation; stale receipts cannot skip a new erase. Physical button remains deferred.
Final review: one fresh independent review returned ten findings. Single fix pass addressed all; no second review requested.
1–2: lock and refresh current device/operation/identity rows before activation or completion; stale duplicate receipts cannot clear a reassigned device. Regression reproductions RED→GREEN.
3: serialize secure storage writes/clears; guard session revision and backend URL across every await and before dispatch. Logout/host-switch race regression RED→GREEN; malformed saved sessions request login.
4: bind commands, retained schedules and reports to ownership generation; publish while holding current owner lock; firmware rejects old/missing generation. Native and backend generation checks RED→GREEN.
5,9: audio BLE and legacy HTTP provisioning share a tested transaction that rolls back connection/auth/save failure and initializes schedule clock on success; legacy setup keeps AP available.
6: periodically retry retained cleanup on healthy connections; serialize cleanup and release DB locks while awaiting PUBACK, preserving pending flag until acknowledgement. Retry regression RED→GREEN.
7: stop HTTP serving and block multipart file writes while reset pending; firmware uses host-tested mutation guard.
8: pending generation cannot dismiss inventory dialog; generated configuration survives reopen, explicit confirmation before creating another. UI regression RED→GREEN.
10: validate persisted session fields before installation; malformed map cannot abort startup with TypeError.
Final verification: PostgreSQL backend 21 passed; Flutter 37 passed; admin one-time credential regression 1 passed and production build passed; native reset/message/Wi-Fi tests passed. Flutter analyzer: 7 informational findings (five existing deprecations/import notices and two brace style notices), no warnings/errors. Both firmware final builds checked separately below.
Android release built successfully, version 0.8.0+5, compile/target SDK36; APK signature verified. Build uses existing debug signing configuration (sideload/test artifact). LilyV7.apk SHA256 a170a0a0be94f7d4370bc604165fe41c818b1d7b88208559ee82112a5de6e23e.
User chose download instead of NAS access. Artifact copied to /workspace/shared/downloads/LilyV7.apk; no LAN copy or deployment performed. Backend/firmware need coordinated deployment and physical acceptance checks. Manual reset button deferred by user; no unresolved review findings deferred.
Ruling: approved plan already specifies draft PR, so finish with that choice without another approval menu. Preserve worktree for review. Do not merge/deploy.
Final firmware validation: audio/light SUCCESS (26.80s /18.30s); all three native helper binaries returned exit0. No hardware flashed. APK package metadata confirms com.example.lily_mobile, versionCode5, versionName0.8.0; apksigner verification exit0.
Repository publication blocked: GitHub create-tree returned HTTP403 Resource not accessible by integration. Main head still551986b; no remote changes, PR, merge or deployment. Retain committed local branch and provide downloadable source patch/git bundle alongside requested APK. No alternate credentials attempted.
Docker deployment follow-up: backend .dockerignore's deny-by-default allowlist omitted Alembic config/migrations. Docker COPY-only build reproduced /alembic.ini and /migrations missing errors before the fix; adding exactly those allowlist entries made the same Docker build succeed. No application behavior changed.
