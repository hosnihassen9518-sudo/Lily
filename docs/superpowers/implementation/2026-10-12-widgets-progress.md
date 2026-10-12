# Widget/theme/inventory implementation record
Plan: docs/superpowers/plans/2026-10-12-widgets-theme-and-inventory.md
Base: 1f102a20b7d8aff9d7de81206b292980f9713302

Tasks 1–4 implemented; final review and delivery in progress.
Evidence: original theme red/layout green; provisioning/widget API red then green; native clear failure red then green; stale configure race regression; lost key and stale ownership generation red then green.
Ruling: iOS home-screen widgets require iOS17 — interactive AppIntents and containerBackground need that OS; main app minimum remains unchanged. Cost: earlier iOS users cannot install this widget.
Ruling: native iOS validation is structural on Linux — Xcode/signing are unavailable; build and phone acceptance remain required on macOS. Cost: native compilation or signing issues may remain until that check.
Ruling: publish to the authorized feature branch with a draft PR — preserves main and gives reviewable delivery; no production deployment is requested for this task.

Final review: fresh gpt-6-astra whole-branch review; one fix pass, no re-review.
Final: fixed activation duplicate generation regression — existing stale-activation and receipt tests failed then passed; PostgreSQL suite 29/29 and SQLite 28 passed/1 PostgreSQL-only skip.
Final: fixed default iOS Keychain permissions — host permission regression RED→GREEN; app-private group first, extension only delegated group.
Final: fixed snapshot account mismatch — host source-contract regressions RED→GREEN; locked native readers reject missing/mismatched credentials. Native cross-process/device acceptance remains pending.
Final: fixed unreachable native widget setup — Native account exposes widget setup RED→GREEN; Flutter suite 44/44.
Final: minor (deferred): native widgets do not show last-updated age beside cached device status. The status is the last reported snapshot; manual refresh is available and this limitation is documented in WIDGETS.md.
Additional regression: test-light's obsolete duplicate BLE source shadowed the shared implementation and failed compile. Removed those duplicates; shared BLE now compiles for both firmware targets (audio and light successful).
Verification: admin tests 2/2 and Vite production build; native permissions/source contracts 2/2; iOS plist/catalog/target/source-reference validation passes. Android release build and APK metadata/signature checked separately at delivery.
