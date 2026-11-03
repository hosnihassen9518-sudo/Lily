# Audio page readability and playback diagnostics

**Goal:** Repair the black picker route, simplify audio selection/device controls,
and isolate persistent silence with a bounded known test tone.
**Spec:** ../specs/2026-11-03-audio-ux-redesign.md

- [ ] Reproduce the missing picker Scaffold, source search and direct Play behavior
  with widget tests. Add an opaque light page, clear source tabs/search/target,
  direct track playback, secondary upload/options and concise feedback.
- [ ] Move compact device player above light controls. Add foreground/current-route
  devices-only polling with session guards and cancellation; preserve LED gestures.
- [ ] Add and exercise a short low-amplitude diagnostic tone without replacing
  current.mp3 or formatting the filesystem. Record decoder/I2S state and user result.
- [ ] Run regressions/builds, review, produce versioned APK, update source on GitHub.

Root evidence: MusicScreen lacks Scaffold when pushed as a standalone route.
Current song decodes nonzero stereo at 44.1kHz, 16-bit; configured I2S10/40/15;
user reports silence and confirms common ground. SD is floating; enable voltage and
test with SD at 3V3 remain unconfirmed. Do not declare amplifier failure from this.

## Verification outcome
- Added the missing opaque Scaffold and explicit light theme; regression covers background, text color and source tabs.
- Player moved above light controls; foreground/current-route telemetry polling added.
- All 84 mobile tests passed; additional color/source regression passed. Static analysis has 10 existing informational findings, no new diagnostics.
- Lily 0.10.5+14 debug APK built and installed on emulator-5554.
- Speaker-test firmware compiles. Review fixes clear temporary test state on reset, boot and scheduled playback.
- Upload is pending: only COM1 is currently visible, COM7 is disconnected. Audible output remains unverified.
