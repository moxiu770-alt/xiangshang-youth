#!/bin/zsh

# Uses the JDK bundled with Android Studio when JAVA_HOME is not configured.
# This keeps the repository runnable on a clean macOS shell without changing
# the user's global shell profile.
set -euo pipefail

project_dir="${0:A:h}"
# Prefer an explicitly configured SDK, then fall back to the standard macOS
# location for the current user.  Do not bake one developer's account path
# into the verification workflow.
sdk_dir="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${HOME}/Library/Android/sdk}}"

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

# Assemble, JVM tests and lint share Kotlin/Android compiler workers.  A small
# default keeps the one-command verification reliable on developer laptops and
# CI runners; powerful agents can opt in to more with GRADLE_MAX_WORKERS=4.
gradle_max_workers="${GRADLE_MAX_WORKERS:-2}"
if [[ ! "$gradle_max_workers" =~ '^[1-9][0-9]*$' ]]; then
  print -u2 "GRADLE_MAX_WORKERS 必须是正整数，当前值：$gradle_max_workers"
  exit 1
fi
gradle_args=(--no-daemon "--max-workers=$gradle_max_workers")

function device_finished_booting() {
  local serial="$1"
  local boot_file query_pid attempts boot_value
  boot_file="$(mktemp -t xiangshang-adb-boot)"
  adb -s "$serial" shell getprop sys.boot_completed >"$boot_file" 2>/dev/null &
  query_pid=$!
  attempts=0
  # A device may be visible to `adb devices` while its framework is frozen or
  # still starting. Bound the probe so local/CI checks never wait forever.
  while kill -0 "$query_pid" 2>/dev/null && (( attempts < 15 )); do
    sleep 1
    attempts=$((attempts + 1))
  done
  if kill -0 "$query_pid" 2>/dev/null; then
    kill "$query_pid" 2>/dev/null || true
    wait "$query_pid" 2>/dev/null || true
    rm -f "$boot_file"
    return 1
  fi
  wait "$query_pid" 2>/dev/null || true
  boot_value="$(tr -d '\r\n' <"$boot_file")"
  rm -f "$boot_file"
  [[ "$boot_value" == "1" ]]
}

cd "$project_dir"
print "JAVA_HOME=$JAVA_HOME"
print "ANDROID_HOME=$ANDROID_HOME"
print "GRADLE_MAX_WORKERS=$gradle_max_workers"
./gradlew :app:assembleDebug :app:assembleAndroidTest :app:testDebugUnitTest :app:lintDebug "${gradle_args[@]}" "$@"
if (( $+commands[adb] )); then
  ready_devices=()
  # `status` is a readonly special parameter in zsh.  Naming this column
  # `device_state` keeps the script compatible with its declared zsh shebang
  # after Gradle has successfully completed all checks.
  while read -r serial device_state _; do
    [[ "$device_state" == "device" ]] || continue
    if device_finished_booting "$serial"; then
      ready_devices+=("$serial")
    else
      print -u2 "设备 $serial 尚未完成系统启动或 ADB 无响应，跳过仪器测试。"
    fi
  done < <(adb devices | awk 'NR > 1 && NF >= 2 { print $1, $2 }')
  if (( ${#ready_devices} > 0 )); then
    print "检测到 ${#ready_devices} 台已启动的 Android 设备，运行 Compose 仪器测试。"
    ./gradlew :app:connectedDebugAndroidTest "${gradle_args[@]}" "$@"
  else
    print "未检测到已完成启动的 Android 真机/模拟器：已完成 APK、AndroidTest APK、JVM 单测和 lint；仪器测试待设备启动完成后执行。"
  fi
else
  print "未找到 adb：已完成 APK、AndroidTest APK、JVM 单测和 lint；仪器测试待 Android SDK 连接后执行。"
fi
print "APK: $project_dir/app/build/outputs/apk/debug/app-debug.apk"
