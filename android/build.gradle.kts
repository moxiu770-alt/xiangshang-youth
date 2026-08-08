plugins {
    // AGP 8.11 supports compileSdk 36 and pairs with Gradle 8.13. Keeping
    // these versions aligned avoids Gradle 10 deprecations emitted by AGP 8.6.
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "1.9.25" apply false
}
