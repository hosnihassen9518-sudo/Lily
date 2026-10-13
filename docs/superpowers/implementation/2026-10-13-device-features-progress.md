# Device feature/configuration implementation

Spec: ../specs/2026-10-13-device-features-design.md
Plan: ../plans/2026-10-13-device-features.md
Branch: codex/model-features-device-config; base bee4405.

Approved design and explicit execution authorization: user “go ahead”. Work is
on a feature branch in the existing checkout, preserving unrelated local edits.

Mobile: implementation and stale schedule-capability review fix complete;
61 Flutter tests passed. Narrow/large-text layouts, music eligibility,
configuration isolation and optional light payloads covered.

Admin: task review passed; integration aligned Light -> Power dependency with
the backend. Root regression failed before fix, then admin suite 7/7 and
production build passed.

Android widgets: pending tickets and independent queues implemented. Native
tests failed before implementation; all 4 JVM regressions passed afterward.
Review fixes: async enqueue failure handling, separate timeout work, and
background broadcast preparation. Scoped re-review found no blocking findings.
Ruling: lease timeout scheduling is OS-dependent — separate recovery work plus
manual Refresh handles delayed quotas; a precise 60-second UI update cannot be
guaranteed by Android WorkManager.

Runtime: release 0.10.0+9 signature and metadata verified; cold launch succeeded
on Pixel_10_Pro_XL (emulator-5554). Actual existing account/device controls and
Configuration screens inspected without changing settings or sending commands.
Device name/status dot and bottom Configuration/Location/removal layout confirmed.
No new crash record; previous 16:00 WorkDatabase crash retained in emulator log.

Backend: root completed review fixes after implementer test calls stalled.
Mixed schedule shapes rejected, typed schedules canonicalized, audio title
metadata authorized, inherited legacy light features normalized, and model
identity preserved through renames. Feature edits persist schedule sync markers
until broker retries or device reconnect/heartbeat can deliver the projection.
An offline device cannot receive updated schedules until it reconnects.
Admin displays pending delivery instead of claiming immediate hardware change.
Scoped backend re-review found no blocking findings.

Final checks: 61 Flutter, 8 admin, 4 Android JVM and 39 applicable backend tests
passed. Backend also has one PostgreSQL-only skip and two known Windows-only
exclusions (g++ compilation and Unix file mode assertion). Admin build passed.
APK: LilyV11.apk, 0.10.0+9, signature verified. No production backend deployment
performed; upgrade backend/admin with the app for the new command contract.
Integration ruling: bring tested feature work into main, following the user's
existing request to keep all latest changes/theme on main. Keep branches.
