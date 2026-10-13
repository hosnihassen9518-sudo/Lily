# Device configuration and model features

Approved scope: simpler kid-friendly device controls, a bottom Configuration
entry, admin-managed models/features, server-enforced controls, and responsive
widgets. Keep the Lily Cloud theme and verified Android release startup fix.

## App
The device page displays name and an accessible green/red status dot. Everyday
controls are shown only for explicit supported features; an empty list grants
none. Configuration is a separate screen entered from the bottom of the device
page, containing rename, information, Location (home/room), Wi-Fi management,
and the existing confirmed removal/reset flow. Audio/music and volume require
audio and volume respectively. Only eligible devices can receive music.

## Model catalog and backend
Extend the existing DeviceModel, not a parallel registry. Models keep their
immutable key and existing device-type, hardware and firmware associations.
Add model-specific capabilities; null inherits existing type capabilities for
backwards-compatible migration, while [] intentionally enables no controls.
Expose the effective explicit list to the app and widgets. Use the existing
factory-owned DeviceProfile.metadata.model_key to associate inventory devices;
backfill known legacy devices without losing home/room data. Users cannot change
model identity through profile metadata or bypass model features by changing type.

Admin can create, edit and delete unused models and assign supported features
using a validated built-in catalog: power, light, brightness, rgb, audio, volume.
Reject unknown features and invalid dependencies. Block deletion of models in use.
Preserve current model provisioning and credentials. Enforce features on light,
audio, volume, generic command, state updates, schedules and widget routes.
Light requests may omit brightness/color; reject unsupported supplied fields.
Build complete firmware commands with unchanged stored values for omitted fields.
Existing user ownership, generation and reset guards remain enforced.

## Widget
Investigate actual queueing and telemetry paths. Prevent refresh work from
delaying taps; show immediate sending feedback and temporarily disable pending
controls. Do not claim device state changed until telemetry confirms it. Keep
account/generation guards, encrypted storage, bounded timeouts and error recovery.
Repeated taps must not produce stale commands. Preserve iOS behavior and shared
widget projection correctness.

## Acceptance
Regression tests for per-feature visibility and forbidden server commands,
model CRUD/validation/access control, migration and device associations,
configuration isolation and Location copy, and widget scheduling/error state.
Run Flutter, admin, and applicable backend tests and admin production build.
Build release, install on the same Pixel 10 Pro XL emulator, cold-launch,
inspect crash logs and render device/configuration screens. Deliver the APK only
after release runtime verification. Do not alter local unrelated edits.
