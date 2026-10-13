# Room creates WorkManager's generated database with getDeclaredConstructor().
# Preserve the public zero-argument constructor in optimized release builds.
-keep class androidx.work.impl.WorkDatabase_Impl {
    public <init>();
}
