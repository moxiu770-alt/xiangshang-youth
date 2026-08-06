#!/bin/zsh

# Uses the JDK bundled with Android Studio when JAVA_HOME is not configured.
# This keeps the repository runnable on a clean macOS shell without changing
# the user's global shell profile.
set -euo pipefail

project_dir="${0:A:h}"
sdk_dir="${ANDROID_HOME:-/Users/luyanpeng/Library/Android/sdk}"

if [[ -z "${JAVA_HOME:-}" || ! -x "$JAVA_HOME/bin/java" ]]; then
  for candidate in \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "/Applications/Android Studio Preview.app/Contents/jbr/Contents/Home" \
    "/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"; do
    if [[ -x "$candidate/bin/java" ]]; then
      export JAVA_HOME="$candidate"
      break
    fi
  done
fi

if [[ -z "${JAVA_HOME:-}" || ! -x "$JAVA_HOME/bin/java" ]]; then
  print -u2 "未找到可用 JDK。请安装 Android Studio，或设置 JAVA_HOME。"
  exit 1
fi

if [[ ! -d "$sdk_dir" ]]; then
  print -u2 "未找到 Android SDK：$sdk_dir"
  exit 1
fi

export ANDROID_HOME="$sdk_dir"
export ANDROID_SDK_ROOT="$sdk_dir"
export PATH="$JAVA_HOME/bin:$sdk_dir/platform-tools:$sdk_dir/emulator:$PATH"

cd "$project_dir"
print "JAVA_HOME=$JAVA_HOME"
print "ANDROID_HOME=$ANDROID_HOME"
./gradlew :app:assembleDebug :app:assembleAndroidTest :app:testDebugUnitTest :app:lintDebug --no-daemon "$@"
if (( $+commands[adb] )); then
  connected_devices=$(adb devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')
  if (( connected_devices > 0 )); then
    print "检测到 $connected_devices 台 Android 设备，运行 Compose 仪器测试。"
    ./gradlew :app:connectedDebugAndroidTest --no-daemon "$@"
  else
    print "未检测到 Android 真机/模拟器：已完成 APK、AndroidTest APK、JVM 单测和 lint；仪器测试待设备连接后执行。"
  fi
else
  print "未找到 adb：已完成 APK、AndroidTest APK、JVM 单测和 lint；仪器测试待 Android SDK 连接后执行。"
fi
print "APK: $project_dir/app/build/outputs/apk/debug/app-debug.apk"
