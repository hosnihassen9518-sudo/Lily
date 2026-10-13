# Android release startup crash

On 2026-10-13, the Pixel 10 Pro XL emulator reproduced an immediate release
crash while the debug build opened normally. Android failed before Flutter's
first screen, during `androidx.startup.InitializationProvider` initialization:

```text
Caused by: java.lang.NoSuchMethodException:
androidx.work.impl.WorkDatabase_Impl.<init> []
```

Room loads WorkManager's generated database constructor through reflection.
The release optimizer removed that constructor. The app's release ProGuard
rules now retain `WorkDatabase_Impl` and its public zero-argument constructor.
Release optimization remains enabled, and the cloud theme is unchanged.

Verification: rebuilt release APK, installed over the previous build, then
force-stopped and cold-launched on Pixel 10 Pro XL. Launch returned `Status: ok`,
the process stayed alive, and the cloud sign-in screen rendered. R8's generated
`seeds.txt` includes `androidx.work.impl.WorkDatabase_Impl: WorkDatabase_Impl()`.
All 46 Flutter tests passed. The S23 Ultra still needs on-device confirmation.

To check a release build on a connected test device:

```powershell
flutter build apk --release
adb -s <device-id> install -r build/app/outputs/flutter-apk/app-release.apk
adb -s <device-id> shell am force-stop com.example.lily_mobile
adb -s <device-id> shell am start -W -n com.example.lily_mobile/.MainActivity
adb -s <device-id> shell pidof com.example.lily_mobile
adb -s <device-id> logcat -d -b crash
```

Check the current process and crash timestamps; the crash buffer can contain
failures from older APKs. Compilation alone does not verify release startup.
