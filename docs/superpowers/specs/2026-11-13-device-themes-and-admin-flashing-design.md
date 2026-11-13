# Device themes and admin USB flashing

Use the existing catalog model keys for the two kids’ room devices. `lily_led_strip` is Lily Light and `lily_v2` is Lily Light + Speaker. Keep existing inventory associations and capabilities. Give each model a catalog display name, a theme key, and its own product image. Extend those fields to future gaming models. Use distinct illustrations until product photos are available. Existing and unknown models get a capability-appropriate fallback image.

The mobile app reads presentation metadata with the owned device list. It automatically applies the available theme if all owned devices share one. With multiple themes, Appearance offers the available choices and remembers the selection for that account on the phone. With no devices, it uses the current Lily theme. A removed theme falls back to an available theme. Cards and device details always show the image assigned to that model. The audio chooser and device details use the selected app theme with opaque surfaces and readable text.

## Approaches

Use the existing server catalog as the source of model presentation instead of hard-coding model names and images in every client. Keep the supported palettes in the mobile app so contrast and navigation can be tested. New models can use an existing palette without a mobile release.

Use desktop Web Serial and Espressif’s browser flasher in the admin inventory workflow. This accesses the USB port on the admin’s computer. A local flashing helper would support a plain HTTP portal but adds an install and maintenance step. The Web Serial path requires HTTPS or localhost. The current LAN HTTP deployment needs a trusted HTTPS endpoint before it can use browser flashing.

## Admin flow

1. The admin selects Connect USB and grants browser access to a port. Probe the ESP32 family, flash size, and readable Lily identity and layout. A USB bridge or chip ID alone cannot determine the Lily model. Treat an unreadable or unrecognized board separately from a verified blank board.
2. For a blank board, ask the admin to choose the model, create or reuse one pending inventory record for that board, and install the matching firmware and factory configuration. Verify the write and boot identity before reporting success. Retries reuse the pending identity.
3. For an existing Lily, show the detected identity and matched inventory model. Offer **Keep identity and settings** or **Reset settings and keep identity**. Keep is the default. Reset clears pairing and user data through Lily’s authorized reset flow while retaining factory identity. Show the data affected and confirm before resetting. Require ownership reset completion before offering the device for pairing again. Do not infer permission to replace an existing serial from a request to reset settings.
4. Use authenticated, model-specific packages and verify their integrity, chip compatibility, layout, and target identity before writing. Keep per-device secrets out of shared firmware packages, logs, and caches. Current factory identities are compiled into firmware. Use device-specific artifacts for legacy updates unless an explicitly tested migration moves the identity to a separate region. Protect the settings and identity regions when keeping settings. An unsupported layout or unavailable artifact blocks the write with a specific error.
5. Restrict package and factory configuration endpoints to authorized inventory admins. Verify the flashed image and show the reboot result. Distinguish successful writes from interrupted writes and failed boots. Test detection, blank provisioning, update, reset, and retry on physical boards before calling flashing complete.

The mobile app contains appearance settings and device controls. USB flashing lives in the admin portal.
