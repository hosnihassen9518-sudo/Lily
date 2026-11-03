# Lily audio UX: Player first

Reviewable mockup: lily-audio-redesign.html in this chat's visualization directory.
User clarified the required correction: audio selection appears black with unreadable
text and must be fixed. Use explicitly painted light surfaces and dark readable type;
proceed with the existing Player first structure and simplified selection controls.

## Screen behavior
Keep Lily's lavender/cream styling. On audio devices, show a compact player before
light controls: selected track, live request/download/playback/error state, primary
Play/Stop, Choose audio and volume. Keep schedules and settings secondary. Collapse
advanced color choices to reduce scrolling, preserve existing color/brightness behavior.

The music picker shows the destination device, search, My files/Catalog tabs, a
secondary Add from phone action, selectable track rows and one primary Play action.
Keep private uploads and auto store-or-stream behavior. Move explicit streaming into
Playback options instead of making every Play tap open a mode menu. Show file sizes,
empty/offline states and actionable errors. Preserve the target when opened from a device.

Refresh device telemetry every few seconds only while a playback screen is visible
and the app is foregrounded. Use a devices-only refresh with session/server guards;
avoid reloading the whole catalog/homes list. Dispose timers and never overwrite
in-progress slider gestures. A sent command is not a confirmed playing state.

## Playback diagnosis
Live firmware reports a loaded local track, 50% volume, 44.1kHz/16-bit stereo and
advancing decode time. I2S reports pins BCLK10/LRC40/DIN15 configured successfully.
Diagnostic firmware is installed on COM7 preserving pairing and the stored MP3.
Speaker remains silent according to user. Amp VIN/GND are connected to separate
USB-C 5V supply; user subsequently confirmed shared ground with ESP32. SD is left unconnected; its onboard
pull-up depends on exact module. Do not claim hardware fault or successful sound
until verified. Live server has catalog playback but lacks the latest private-upload
endpoint, so private phone uploads need the already-pushed backend update.

## Verification
Cover 320px/large text, search/source filters, target binding, upload cancellation,
direct Play dispatch, pending versus confirmed status, offline/error controls,
session switches, visibility-aware refresh and disposal, and preserved LED controls.
Provide a versioned APK and push source after tests and review; user deploys backend.
