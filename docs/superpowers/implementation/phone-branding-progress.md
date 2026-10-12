# Lily phone branding — 12 October 2026

User requested the phone display name Lily, the existing smiling-cloud logo, merging the completed changes into main, and a new branch for Android and iOS home-screen widgets listing devices with on/off controls.

Bounded branding: Android application label and iOS display/bundle names are Lily. Existing package identifiers and signing configuration remain intact. Launcher art is reused from codex/mobile-cloud-theme (source blob6457bafc8ed76f7b9f7797719369a365fa92e563); its unrelated theme/cache changes were not merged into the lifecycle implementation.

flutter_launcher_icons0.14.4 generates committed Android density resources and the iOS AppIcon catalog. The wrapper at mobile_app/tool/generate_launcher_icons.dart preserves Xcode project bytes because the generator rewrites unrelated ASSETCATALOG symbol settings. Regeneration wrapper ran successfully; Xcode project diff is empty. The source PNG and regeneration configuration are committed for reproducibility.

Verification:37 Flutter tests passed; Android release build succeeded; aapt confirms application-label Lily, versionName0.8.1 and versionCode6; apksigner verification succeeded. Android density PNGs and every referenced iOS icon dimension were checked, along with iOS plist names. Wrapper analyzer reports no issues. iOS native compilation requires macOS/Xcode and was not run here.

Download artifact:/workspace/shared/downloads/LilyV8.apk, SHA256f4baa9f32b3a12507cf363e09b6e8e3181876e35a2340c534f83bcdf70102f56. Existing debug signing configuration is used for sideload testing; APK is not committed.

Integration authorized explicitly by user: include branding and completed device-lifecycle/session work (including Docker Alembic allowlist correction) in main. Create feat/device-home-widget from the resulting main commit. Widget implementation is future work on that branch; confirmed scope is Android and iOS home-screen widgets, device list and on/off controls. Backend and firmware deployment/hardware checks remain separate.
