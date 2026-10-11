# Execution ledger — docs/superpowers/plans/2026-10-11-ble-provisioning.md

Spec and plan approved; user selected native execution.

Ruling: Work in the existing checkout on a feature branch and preserve unrelated changes — test-light firmware and device naming edits exist only in this dirty checkout; user approved work here — focused staging must avoid unrelated edits.

Task 1: in progress. Shared protocol tests first.

Task 1: complete. BLE protocol and firmware implemented and compiled.
Task 2: complete. Mobile transport, permissions, Add Device UI, and recovery implemented.
Task 3: complete for local delivery. Documentation, independent review, full tests, static analysis, firmware build and APK build passed. Physical phone/ESP32 acceptance remains pending. Changes remain in the existing working tree on codex/ble-provisioning; no commit/push performed because unrelated existing edits and required pre-existing naming dependencies need focused integration separately.

Protocol tests: observed initial missing-file failure, then 3 passing tests.
Transport tests: observed initial missing-file failure, then 5 passing tests.
Firmware compiled with installed Arduino 2.0.17 BLE headers. Full Flutter suite: 24 passed, including disposal and finalization retry.

Ruling: Use readable polled status without notification hints — review identified that the bundled BLE library's read-blob offset can be invalidated by a concurrent notify value replacement — polling already provides progress and missed-event recovery, at a 500 ms interval.

Review persistence finding fixed: save through wifi.tmp, verify full serialized byte count/file size, then atomic rename; failed persistence reports error and preserves old saved credentials.
Ruling: Compile Android against SDK 37 — reactive_ble_mobile 5.6.0 requires it — Android min/target SDK behavior otherwise remains configured by Flutter.

Final verification: 24 Flutter tests passed; scoped analysis of seven BLE source/test files reported no issues; Android release APK built (51.7 MB); firmware compiled (20.4% RAM, 45.9% flash). Independent reviewer verified both important fixes and found no remaining important defects.

## 0.7.1 correction pass

User reports unstable pairing/write failures and requires ESP32-visible Wi-Fi list. Ruling: enable station Wi-Fi temporarily on explicit BLE scan request, then turn it off if previously off — latest user requirement supersedes the original manual-only/off-until-credentials restriction.

Confirmed source defects: PIN was regenerated every boot; connection had no explicit Android bond completion gate; UI lacked Wi-Fi scanning. Added persistent per-device NVS PIN, Android bond-state wait before GATT, firmware authenticated-ready check, async Wi-Fi scan with bounded paginated status, dropdown/rescan/manual fallback. Shared tests observed failure before implementing scan and authentication wait, then passed. Fixed oversized stack envelope risk in BLE callback; logs capture boot reset reason, auth result, and chunk sizes without credentials. GATT 133 physical cause remains unconfirmed because user capture contains startup only. No automatic retransmission of credential writes.

0.7.1 review: no actionable defects found. Installed BLE library explicitly requests encryption on every GATT connection. Scoped static analysis clean; final firmware compile successful (21.1% RAM, 46.1% flash). Android native bonding code compiles in release APK. Physical pairing/scan/write stability remains for hardware testing.
