#!/bin/bash
set -euo pipefail

export PATH="$HOME/Library/Android/sdk/emulator:$HOME/Library/Android/sdk/platform-tools:$HOME/Library/Android/sdk/build-tools/36.0.0:$PATH"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"

APK="/Users/sahanakumari/Desktop/LocationBasedPhoto-CRM/photo-tracker/mobile-app/releases/app-release.apk"
AVD="geotag_test"
LOG="/tmp/android_emulator.log"

echo "==> Checking for existing emulator..."
if ! adb devices | grep -E 'emulator-[0-9]+[[:space:]]+device' >/dev/null; then
  # Clean stale emulators
  pkill -f "qemu-system-aarch64" 2>/dev/null || true
  pkill -f "emulator .*${AVD}" 2>/dev/null || true
  sleep 1

  echo "==> Starting AVD: ${AVD}"
  nohup emulator -avd "$AVD" -netdelay none -netspeed full >"$LOG" 2>&1 &
  echo "Emulator PID $!"
fi

echo "==> Waiting for device..."
adb wait-for-device

echo "==> Waiting for boot..."
for i in $(seq 1 90); do
  BOOT=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
  if [ "$BOOT" = "1" ]; then
    echo "Boot completed"
    break
  fi
  echo "  booting ($i)..."
  sleep 2
done

adb devices -l

echo "==> Installing APK: $APK"
adb install -r "$APK"

AAPT=$(ls -d "$HOME/Library/Android/sdk/build-tools"/*/aapt 2>/dev/null | sort -V | tail -1)
PKG=$("$AAPT" dump badging "$APK" | awk -F"'" '/package: name=/{print $2; exit}')
ACT=$("$AAPT" dump badging "$APK" | awk -F"'" '/launchable-activity: name=/{print $2; exit}')
echo "Package=$PKG"
echo "Activity=$ACT"

if [ -n "${ACT:-}" ]; then
  adb shell am start -n "$PKG/$ACT"
else
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
fi

echo "==> Done. App should be on the emulator."
