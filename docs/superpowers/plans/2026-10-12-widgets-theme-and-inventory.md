# Lily Widgets, Theme and Inventory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship native home-screen device controls, restore the agreed visual theme and complete administrator provisioning/export workflows.
**Architecture:** Native widget clients use delegated session-bound credentials and restricted backend endpoints. Flutter synchronizes public snapshots and securely stored native configuration. Factory provisioning archives are encrypted under the persistent signing key.
**Tech Stack:** Flutter/Dart, Kotlin/Android RemoteViews, Swift/WidgetKit/AppIntents/Keychain, FastAPI/SQLAlchemy/Alembic, React/Vitest.
**Spec:** docs/superpowers/specs/2026-10-12-widgets-theme-and-inventory-design.md

## Global Constraints
- Maintain absolute mobile-session expiry and ownership/reset protections.
- Never write application refresh tokens or device secrets into widget/public preferences.
- Keep existing package identifiers, cloud artwork and signing key stable.
- Interactive iOS controls require iOS17; iOS14–16 provide an app-opening fallback.
- Work on feat/device-home-widget; publish for review, do not merge/deploy.

## Review Focus
- Logout/backend switching during an in-flight widget update must not resurrect old account data.
- Parent session expiry/revocation must block widget commands without affecting app refresh rotation.
- Reset/reassignment and delayed native commands must recheck current ownership/generation.
- Missing signing keys may initialize, invalid keys must survive untouched; encrypted archives must stay recoverable across restart.
- Narrow screens, unsupported sensors, offline status and spreadsheet-formula metadata must remain usable and safe.

### Task1: Restore cloud theme
**Files:** Flutter main/theme/screens/widgets and cloud layout test.
**Interfaces:** Existing AppState and Device; cloud asset assets/branding/lily_cloud.png.
- [x] Restore the original layout regression and observe failure against current UI.
- [x] Restore visual files only; retain secure session/reset implementations.
- [x] Run Flutter tests, inspect relevant layout and commit.

### Task2: Inventory workflow and restricted widget API
**Files:** backend services/device_authorization.py, services/device_inventory.py, api/admin.py, api/widgets.py, models/widget.py, additive migration, tests; admin DevicesPage/api/tests.
**Interfaces:** POST /widgets/session {installation_id} → {token,expires_at}; GET /widgets/devices → public snapshot; POST /widgets/devices/{id}/power {enabled:bool,expected_generation:int|null} → {mqtt_published,snapshot}; admin credentials/config/CSV/resync endpoints.
- [x] Reproduce missing-key provisioning, recoverable credential retrieval and CSV selection failures; test revoked/expired widget sessions, ownership and pending/offline controls.
- [x] Implement atomic missing-key initialization, encrypted config archive, scoped delegated credentials and locked explicit power publication.
- [x] Implement admin action dialogs/export field selector and confirmed resync semantics.
- [x] Run backend and admin suites/builds, commit.

### Task3: Flutter/native synchronization and Android widget
**Files:** Dart widget bridge/state tests, Kotlin widget package, Android layouts/provider/manifest and MainActivity channel.
**Interfaces:** MethodChannel lily/widgets configure({url,token,expires_at,snapshot}), update(snapshot), clear(); native credentials encrypted, public snapshots separate.
- [x] Test stale configure completion, logout, unsupported platforms and snapshots with pending devices.
- [x] Implement serialized Flutter publication and current-session guards; native Keystore, network client, scrolling RemoteViews provider and refresh/power receiver.
- [x] Build Android release, inspect provider/actions and package metadata, commit.

### Task4: iOS extension
**Files:** Shared WidgetStore/API Swift, Runner bridge, LilyWidget extension, entitlements/plists/assets and Xcode target/embedding settings.
**Interfaces:** Same restricted widget API and snapshot schema; shared AppGroup/keychain, WidgetCenter refresh; AppIntent explicit boolean power.
- [x] Validate schema and native target wiring/entitlement agreement; test credential snapshot guards where executable.
- [x] Implement small/medium/large views, timeline refresh and iOS17 interactive buttons; minimum widget OS is iOS17; the main app retains its earlier support.
- [x] Validate project references/plists/assets and document signing requirements/native build limitation; commit.

### Task5: Final review and delivery
- [x] Run complete backend/mobile/admin suites and appropriate native/build checks.
- [x] Use one fresh whole-branch reviewer, fix important findings with regression coverage in one pass.
- [x] Publish branch/draft PR, build/download APK, report verification and actual platform limits.
