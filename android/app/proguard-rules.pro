# Retrofit discovers endpoint annotations through reflection. Keep those
# interfaces and the DTOs used by the staged RemoteRepository readable until
# the server contract moves to generated Moshi adapters.
-keep,allowoptimization,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}

-keep class com.xiangshang.youth.core.model.** { *; }
-keep class com.xiangshang.youth.core.repository.DashboardData { *; }
-keep class com.xiangshang.youth.core.service.**Request { *; }

# The future API payloads include TaskStatus and other enums. Preserve their
# standard lookup methods for JSON adapters and persisted local feature state.
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
