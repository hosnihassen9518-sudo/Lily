# Model features and device configuration (0.10.0)

The device page keeps everyday controls separate from Configuration. Its
header displays the device name and an accessible green/red status dot.
The bottom Configuration entry contains rename, Information, Location,
Wi-Fi management and the existing confirmed removal/reset flow.

The admin portal's Models & features page manages model keys, names, hardware,
firmware association and feature checkboxes. Keys identify existing factory
devices and cannot change. Models used by devices cannot be deleted or have
their factory association changed. Brightness/color require Light and Power;
Volume requires Audio. An empty model feature list enables no controls.

Existing models inherit their current type's features until explicitly edited.
The backend migration adds model feature overrides and associates known legacy
models while preserving home, room, custom metadata and device credentials.
Unknown devices do not receive arbitrary controls. The app, music-device
selection, schedules and widget projection consume explicit effective features.
The server also validates controls, rather than relying on hidden UI elements.

Model feature edits revalidate downloaded schedules and publish the updated
projection. Failed delivery is persisted and retried when the broker or device
reconnects; the admin page shows a pending-delivery notice. A device that is
offline can continue its old local schedules until it receives the update.

## Upgrade

Deploy backend and admin changes with the new APK. Backend startup applies
Alembic migration `20261013_model_features`; `alembic upgrade head` can also be
run from the backend directory. Back up the deployment database first.
The new light endpoint accepts omitted brightness/RGB fields, allowing a
light-only model to switch power without requesting unsupported controls.

## Android widgets

Tap commands use a queue per device, separate from deduplicated refresh work.
On Android 12+, expedited work is requested, falling back to ordinary work when
OS quota is exhausted. Sending feedback appears immediately; repeated taps are
suppressed during the pending command. UUID/account/generation guards prevent
stale callbacks and commands from affecting a new account or device generation.

A pending lease expires after 60 seconds and schedules a separate recovery
update. Android may delay that worker; manual Refresh is still available.
Network/broker/device reporting latency remains outside the local queue's
control. The widget does not claim physical state changed before it is reported.
iOS widget execution behavior is preserved; native iOS builds require macOS.

## Verification

Release 0.10.0 (build 9) cold-launched successfully on the same Pixel 10 Pro XL
emulator. The device and Configuration screens were inspected using the existing
signed-in account without changing its device configuration. The APK's signature,
version and Lily application label were verified. Android's release constructor
retention fix is preserved.
