plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.xiangshang.youth"
    compileSdk = 36
    val configuredApiBaseUrl = providers.gradleProperty("apiBaseUrl").orElse("https://api.example.com/").get().trim()
    val configuredSchoolId = providers.gradleProperty("schoolId").orElse("school-1").get()
    val releaseBuildRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
    val configuredRemoteDataSource = providers.gradleProperty("useRemoteDataSource").orElse(if (releaseBuildRequested) "true" else "false").get().toBoolean()
    if (releaseBuildRequested && !configuredApiBaseUrl.startsWith("https://")) {
        throw GradleException("Release build requires -PapiBaseUrl=<production HTTPS URL>")
    }
    if (releaseBuildRequested && configuredApiBaseUrl.removeSuffix("/") == "https://api.example.com") {
        throw GradleException("Release build cannot use the placeholder api.example.com URL")
    }
    if (releaseBuildRequested && !configuredRemoteDataSource) {
        throw GradleException("Release build requires -PuseRemoteDataSource=true")
    }
    // These values are supplied by CI or a developer-local gradle.properties;
    // they intentionally remain empty in source control. An empty DSN means
    // the SDK never initializes and no telemetry leaves a test build.
    val configuredSentryDsn = providers.gradleProperty("sentryDsn").orElse("").get()
    val configuredReleaseChannel = providers.gradleProperty("releaseChannel").orElse("internal").get()
    val configuredRolloutConfigUrl = providers.gradleProperty("rolloutConfigUrl").orElse("").get()
    val configuredFeatureOverrides = providers.gradleProperty("featureOverrides").orElse("").get()
    defaultConfig {
        applicationId = "com.xiangshang.youth"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "API_BASE_URL", "\"$configuredApiBaseUrl\"")
        buildConfigField("String", "SCHOOL_ID", "\"$configuredSchoolId\"")
        buildConfigField("boolean", "USE_REMOTE_DATA_SOURCE", configuredRemoteDataSource.toString())
        buildConfigField("String", "SENTRY_DSN", "\"$configuredSentryDsn\"")
        buildConfigField("String", "RELEASE_CHANNEL", "\"$configuredReleaseChannel\"")
        buildConfigField("String", "ROLLOUT_CONFIG_URL", "\"$configuredRolloutConfigUrl\"")
        buildConfigField("String", "FEATURE_OVERRIDES", "\"$configuredFeatureOverrides\"")
    }
    buildFeatures { compose = true; buildConfig = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.15" }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    lint {
        lintConfig = file("lint.xml")
        // Lifecycle 2.8's detector crashes under AGP 8.11/Kotlin 1.9 while
        // analysing generated Moshi adapters (b/its own lint runtime). This
        // app uses StateFlow rather than MutableLiveData; keep every other
        // release lint gate enabled until the upstream detector is compatible.
        disable += "NullSafeMutableLiveData"
    }
    buildTypes {
        release {
            // Exercise the same optimized/obfuscated artifact that will be
            // handed to a school pilot or store review, rather than treating a
            // debug-like release APK as production-ready.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.09.00"))
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.2")
    // AndroidJUnitRunner 1.6 uses Trace.forceEnableAppTracing(). Activity's
    // legacy transitive graph resolves tracing 1.0.0 otherwise, which makes
    // connected Compose tests crash before the first frame on API 34.
    implementation("androidx.tracing:tracing:1.2.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.6")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-moshi:2.11.0")
    implementation("com.squareup.moshi:moshi-kotlin:1.15.2")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("io.sentry:sentry-android:8.53.0")
    // Family posture capture performs a local quality pass on shoulder/hip
    // landmarks.  No source photo or video is persisted by the app.
    // Accurate model is required for child-scale joints and the follow-along
    // quality gate. Keep the detector behind the same repository API so it can
    // be swapped or remotely configured later.
    implementation("com.google.mlkit:pose-detection-accurate:18.0.0-beta5")
    // Face count is used only as a local multi-person safety gate for the
    // single-person pose model; no face image is persisted.
    implementation("com.google.mlkit:face-detection:16.1.7")
    implementation("androidx.camera:camera-core:1.4.2")
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
    implementation("androidx.camera:camera-view:1.4.2")
    testImplementation("junit:junit:4.13.2")
    // JVM unit tests use a concrete org.json implementation; Android instrumentation keeps
    // using the platform json classes shipped with the SDK.
    testImplementation("org.json:json:20240303")
    androidTestImplementation(platform("androidx.compose:compose-bom:2024.09.00"))
    // The runner executes in the test APK, so it needs the same tracing API
    // explicitly; app runtime dependencies are not sufficient for this
    // separate instrumentation process.
    androidTestImplementation("androidx.tracing:tracing:1.2.0")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
