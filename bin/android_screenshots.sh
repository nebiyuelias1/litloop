#!/usr/bin/env bash
set -euo pipefail

# Capture Google Play phone screenshots (and optionally app preview videos)
# from the Android Emulator. Routes are passed to the app as litloop:// deep
# links (handled by MainActivity's onNewIntent routing), which avoids stale
# navigation state between captures. Captures are rewritten as clean RGB PNGs
# (no alpha, no metadata), as Play Console requires a 9:16 aspect ratio
# (1080x1920, each side 320-3840px) and 24-bit PNG without alpha.
#
# Requirements: Android SDK (adb, emulator, avdmanager + a system image) and a
# JDK for the Gradle wrapper. Run from anywhere; paths are resolved from the
# repository root.
#
# Usage:
#   bin/android_screenshots.sh
#   ROUTES="home:|club:book_clubs/1|book:books/2453" bin/android_screenshots.sh
#   VIDEO=1 bin/android_screenshots.sh
#
# Environment:
#   AVD_NAME      Emulator AVD for the capture set; created from the pixel_2
#                 device profile (420dpi) when missing
#                 (default: litloop-pixel-2)
#   SCREEN_SIZE   Emulator skin override, WxH (default: 1080x1920, Play's 9:16).
#                 "auto" keeps the AVD's own resolution (dims are not verified)
#   ROUTES        "name:path|name:path"; an empty path launches the home tab.
#                 A path may be a full https:// URL; prefer bare paths
#                 (litloop:// is more reliable than App Links on the emulator)
#   OUTPUT_DIR    Destination directory (default: build/play-store-screenshots)
#   WAIT_SECONDS  Delay after opening each route (default: 6)
#   LOAD_TIMEOUT  Max seconds to wait for a stable screen before capturing
#                 (default: 45; loading spinners count as animating)
#   VIDEO         1 to record an app preview (needs ffmpeg to trim)
#   HEADLESS      1 to run the emulator without a window (default: 0)
#   KEEP_EMULATOR 1 to leave the emulator running afterwards (default: 0)
#   EMU_RAM       Emulator RAM in MB (default: 4096)
#   EMU_FEATURES  Emulator -feature flags (default: GLDirectMem,
#                 HasSharedSlotsHostMemoryAllocator; required by Android 16
#                 images, see boot_emulator)
#   EMU_DNS       DNS server for the emulator guest network (default: 8.8.8.8;
#                 CI runners' host resolver is unreachable from the guest;
#                 "none" skips the flag)
#   NET_CHECK     1 to fail the run when the WebView logs network errors after
#                 the warm-up launch (default: 1)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PACKAGE="${PACKAGE:-et.netale.litloop}"
ACTIVITY="${ACTIVITY:-.activities.MainActivity}"
AVD_NAME="${AVD_NAME:-litloop-pixel-2}"
SCREEN_SIZE="${SCREEN_SIZE:-1080x1920}"
OUTPUT_DIR="${OUTPUT_DIR:-build/play-store-screenshots}"
ROUTES="${ROUTES:-club:book_clubs/1|home:|book_read:book_clubs/1/book_reads/6|clubs:book_clubs|book:books/2453}"
WAIT_SECONDS="${WAIT_SECONDS:-6}"
VIDEO="${VIDEO:-0}"
HEADLESS="${HEADLESS:-0}"
KEEP_EMULATOR="${KEEP_EMULATOR:-0}"
EMU_DNS="${EMU_DNS:-8.8.8.8}"
APK="$ROOT_DIR/android/app/build/outputs/apk/debug/app-debug.apk"
EMU_LOG="$ROOT_DIR/build/android-screenshots/emulator.log"

if [[ "$SCREEN_SIZE" == "auto" ]]; then
  EXPECTED=""
else
  EXPECTED="${SCREEN_SIZE/x/ }"
fi

# Locate the SDK (ANDROID_HOME, ANDROID_SDK_ROOT, then common install paths).
if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
  for candidate in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    if [[ -d "$candidate" ]]; then
      ANDROID_HOME="$candidate"
      break
    fi
  done
fi
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -n "$ANDROID_HOME" && -d "$ANDROID_HOME" ]] || {
  echo "error: Android SDK not found (set ANDROID_HOME)" >&2
  exit 1
}
export ANDROID_HOME
PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
export PATH

ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"

for tool in "$ADB" "$EMULATOR" "$ROOT_DIR/android/gradlew"; do
  [[ -e "$tool" ]] || { echo "error: $tool not found" >&2; exit 1; }
done
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

AVDMANAGER="$(find "$ANDROID_HOME/cmdline-tools" -maxdepth 3 -name avdmanager -type f 2>/dev/null | sort | tail -1 || true)"

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

sq() {
  local s="$1"
  s=${s//\'/\'\\\'\'}
  printf "'%s'" "$s"
}

run_with_timeout() {
  local seconds="$1"
  shift
  local status pid watchdog
  "$@" &
  pid=$!
  (
    sleep "$seconds"
    if kill -0 "$pid" 2>/dev/null; then
      echo "error: timed out after ${seconds}s: $*" >&2
      kill -TERM "$pid" 2>/dev/null || true
      sleep 5
      kill -KILL "$pid" 2>/dev/null || true
    fi
  ) &
  watchdog=$!
  wait "$pid" && status=0 || status=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  return "$status"
}

png_dims() {
  python3 - "$1" <<'PY'
import struct
import sys

with open(sys.argv[1], "rb") as handle:
    header = handle.read(24)
print("%d %d" % struct.unpack(">II", header[16:24]))
PY
}

find_system_image() {
  local api variant abi dir
  local -a apis=(36.1 36 35 34 33 32)
  local -a variants=(google_apis_playstore google_apis default)
  local -a abis=(x86_64 arm64-v8a)
  for api in "${apis[@]}"; do
    for variant in "${variants[@]}"; do
      for abi in "${abis[@]}"; do
        dir="$ANDROID_HOME/system-images/android-$api/$variant/$abi"
        if [[ -d "$dir" ]]; then
          printf 'system-images;android-%s;%s;%s' "$api" "$variant" "$abi"
          return 0
        fi
      done
    done
  done
  echo "error: no installed system image found; install one, e.g." >&2
  echo '  sdkmanager "system-images;android-35;google_apis;x86_64"' >&2
  return 1
}

ensure_avd() {
  local avds image candidate
  # Newer avdmanager writes to $HOME/.config/.android/avd while the emulator
  # only searches $HOME/.android/avd; pin ANDROID_AVD_HOME to wherever the
  # AVD actually lives.
  if [[ -z "${ANDROID_AVD_HOME:-}" ]]; then
    for candidate in "$HOME/.android/avd" "$HOME/.config/.android/avd" "${XDG_CONFIG_HOME:-$HOME/.config}/.android/avd"; do
      if [[ -f "$candidate/$AVD_NAME.ini" ]]; then
        export ANDROID_AVD_HOME="$candidate"
        break
      fi
    done
  fi
  avds="$("$EMULATOR" -list-avds 2>/dev/null || true)"
  if grep -Fxq "$AVD_NAME" <<< "$avds"; then
    log "   AVD $AVD_NAME already exists"
    return 0
  fi
  image="$(find_system_image)"
  [[ -n "$AVDMANAGER" ]] || {
    echo 'error: avdmanager not found; install cmdline-tools, e.g. sdkmanager "cmdline-tools;latest"' >&2
    exit 1
  }
  log "   creating AVD $AVD_NAME ($image, pixel_2 profile)"
  printf 'no\n' | "$AVDMANAGER" create avd \
    -n "$AVD_NAME" \
    -k "$image" \
    -d pixel_2 \
    --force >/dev/null
  if [[ -z "${ANDROID_AVD_HOME:-}" ]]; then
    for candidate in "$HOME/.android/avd" "$HOME/.config/.android/avd" "${XDG_CONFIG_HOME:-$HOME/.config}/.android/avd"; do
      if [[ -f "$candidate/$AVD_NAME.ini" ]]; then
        export ANDROID_AVD_HOME="$candidate"
        break
      fi
    done
  fi
  if [[ -z "${ANDROID_AVD_HOME:-}" ]]; then
    echo "error: AVD $AVD_NAME not found after creation" >&2
    exit 1
  fi
}

wait_for_boot() {
  local waited=0 stable=0
  local boot_timeout="${BOOT_TIMEOUT:-300}"
  # Poll boot_completed directly; adb reports the device as "offline" while the
  # guest is coming up, and `adb wait-for-device` would block indefinitely there.
  # The package service is required for installs and must be up for a few
  # consecutive polls: right after boot it briefly disappears while the system
  # finishes settling.
  while (( waited < boot_timeout )); do
    if [[ "$(adb -e shell getprop sys.boot_completed 2>/dev/null | tr -d ' \r')" == "1" ]] &&
      [[ "$(adb -e shell service check package 2>/dev/null | tr -d ' \r')" == *"found"* ]]; then
      stable=$((stable + 1))
      if (( stable >= 4 )); then
        log "   emulator booted after ${waited}s (Android $(adb -e shell getprop ro.build.version.release 2>/dev/null | tr -d ' \r'))"
        return 0
      fi
    else
      stable=0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "error: emulator $AVD_NAME did not finish booting within ${boot_timeout}s; emulator log tail:" >&2
  tail -30 "$EMU_LOG" >&2 || true
  return 1
}

boot_emulator() {
  # 4GB: modern images with Play services breach the low watermark at the
  # pixel_2 profile default (1536M) and system_server starts flapping.
  # GLDirectMem + HasSharedSlotsHostMemoryAllocator make the host advertise
  # ReadColorBufferDma, which Android 16 gralloc asserts on; without them
  # surfaceflinger crash-loops and the system wedges. An explicit DNS server
  # is required on CI runners: the guest cannot reach the host resolver, and
  # every page would load as an error page.
  local -a emu_flags=(
    "-avd" "$AVD_NAME"
    "-skin" "$SCREEN_SIZE"
    "-memory" "${EMU_RAM:-4096}"
    "-feature" "${EMU_FEATURES:-GLDirectMem,HasSharedSlotsHostMemoryAllocator}"
    "-no-snapshot" "-no-audio" "-no-boot-anim"
  )
  if [[ "$EMU_DNS" != "none" ]]; then
    emu_flags+=("-dns-server" "$EMU_DNS")
  fi
  mkdir -p "$(dirname "$EMU_LOG")"
  if [[ "$HEADLESS" == "1" ]]; then
    emu_flags+=("-no-window" "-gpu" "swiftshader_indirect")
  fi
  log "== booting $AVD_NAME (emulator log: $EMU_LOG)"
  "$EMULATOR" "${emu_flags[@]}" > "$EMU_LOG" 2>&1 &
  EMU_PID=$!
  wait_for_boot
}

# SystemUI demo mode pins a clean status bar: 9:41, full battery, full wifi,
# no notifications, no SIM/spinner clutter.
prepare_status_bar() {
  adb -e shell settings put global sysui_demo_allowed 1
  adb -e shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
  adb -e shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 >/dev/null
  adb -e shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null
  adb -e shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 -e fully true -e mobile hide >/dev/null
  adb -e shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false >/dev/null
}

reset_status_bar() {
  adb -e shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null
}

launch_app() {
  local path="$1" uri=""
  if [[ -n "$path" ]]; then
    case "$path" in
      http://* | https://*) uri="$path" ;;
      *) uri="litloop://$path" ;;
    esac
  fi
  if [[ -n "$uri" ]]; then
    adb -e shell "am start -a android.intent.action.VIEW -d $(sq "$uri") $(sq "$PACKAGE")"
  else
    adb -e shell "am start -n $(sq "${PACKAGE}/${ACTIVITY}")"
  fi
}

app_running() {
  [[ -n "$(adb -e shell pidof "$PACKAGE" 2>/dev/null | tr -d '[:space:]')" ]]
}

screen_hash() {
  adb -e exec-out screencap -p 2>/dev/null | python3 -c 'import hashlib, sys; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest())'
}

# A loading spinner changes pixels every frame; once several consecutive
# screencap hashes match, the screen is static and safe to capture. Falls
# back to capturing anyway when a screen legitimately keeps animating.
wait_for_static_screen() {
  local last="" current stable=0 waited=0
  local timeout="${LOAD_TIMEOUT:-45}"
  while (( waited < timeout )); do
    current="$(screen_hash)"
    if [[ -n "$current" && "$current" == "$last" ]]; then
      stable=$((stable + 1))
      if (( stable >= 2 )); then
        return 0
      fi
    else
      stable=0
      last="$current"
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "   warning: screen still animating after ${timeout}s; capturing anyway" >&2
}

# The app is a WebView around litloop.club; if the guest network is broken
# (e.g. DNS on CI runners) every capture would silently show Hotwire's error
# page, so fail loudly instead of uploading garbage.
check_webview_errors() {
  [[ "${NET_CHECK:-1}" == "1" ]] || return 0
  local errs
  errs="$(adb -e logcat -d 2>/dev/null | grep -oE 'net::ERR_[A-Z_]+' | sort | uniq -c | sort -rn | head -5)"
  if [[ -n "$errs" ]]; then
    echo "error: WebView reported network errors; screenshots would show error pages:" >&2
    echo "$errs" >&2
    echo "hint: set EMU_DNS (default 8.8.8.8) if the guest cannot resolve hosts" >&2
    return 1
  fi
}

record_preview() {
  local dir="$1"
  local raw="$dir/app-preview-raw.mp4"
  local final="$dir/app-preview.mp4"
  local rec_pid entry path
  local -a route_list

  echo "   recording app preview..."
  adb -e shell screenrecord --time-limit 180 /sdcard/app-preview-raw.mp4 &
  rec_pid=$!

  IFS='|' read -ra route_list <<< "$ROUTES"
  local shots=0
  for entry in "${route_list[@]}"; do
    [[ -n "$entry" ]] || continue
    path="${entry#*:}"
    shots=$((shots + 1))
    adb -e shell am force-stop "$PACKAGE" 2>/dev/null || true
    launch_app "$path"
    sleep 5
  done
  if (( shots * 5 < 15 )); then
    echo "   warning: preview will be shorter than the 15s minimum; add routes or lengthen the loop" >&2
  fi
  sleep 1
  adb -e shell 'for p in $(pidof screenrecord); do kill -2 $p; done' >/dev/null 2>&1 || true
  wait "$rec_pid" 2>/dev/null || true

  adb -e pull /sdcard/app-preview-raw.mp4 "$raw" >/dev/null
  adb -e shell rm -f /sdcard/app-preview-raw.mp4

  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -loglevel error -i "$raw" -t 20 -c copy "$final"
    rm -f "$raw"
    echo "   wrote $final"
  else
    echo "   warning: ffmpeg not found; raw video left at $raw (trim to 15-30s manually)" >&2
  fi
}

capture_set() {
  local dir="$OUTPUT_DIR/phone"
  local out entry name path dims index
  local -a route_list

  rm -rf "$dir"
  mkdir -p "$dir"

  log "   installing app..."
  adb -e uninstall "$PACKAGE" >/dev/null 2>&1 || true
  local install_output attempt install_ok=1
  for attempt in 1 2 3; do
    if install_output="$(adb -e install -r "$APK" 2>&1)"; then
      install_ok=0
      break
    fi
    log "   install attempt $attempt failed; retrying in 5s..."
    sleep 5
  done
  if [[ "$install_ok" != "0" ]]; then
    echo "error: adb install failed for $APK: $install_output" >&2
    return 1
  fi

  log "   preparing status bar (demo mode)..."
  adb -e shell settings put global window_animation_scale 0.0
  adb -e shell settings put global transition_animation_scale 0.0
  adb -e shell settings put global animator_duration_scale 0.0
  prepare_status_bar

  # Warm-up: the first launch fetches the remote path configuration and spins
  # up the WebView, so the first capture route does not show a loading state.
  log "   warm-up launch (home)..."
  launch_app ""
  sleep "$WAIT_SECONDS"
  wait_for_static_screen
  check_webview_errors

  IFS='|' read -ra route_list <<< "$ROUTES"
  index=0
  for entry in "${route_list[@]}"; do
    [[ -n "$entry" ]] || continue
    index=$((index + 1))
    name="${entry%%:*}"
    path="${entry#*:}"
    out="$(printf '%s/%02d-%s.png' "$dir" "$index" "$name")"

    adb -e shell am force-stop "$PACKAGE" 2>/dev/null || true
    sleep 1
    log "   $name -> ${path:-home}"
    launch_app "$path"
    sleep "$WAIT_SECONDS"
    wait_for_static_screen

    if ! app_running; then
      echo "warning: $PACKAGE does not appear to be running; recent logcat:" >&2
      adb -e logcat -d -t 30 2>/dev/null | tail -30 >&2 || true
    fi

    adb -e exec-out screencap -p > "$out"
    python3 "$ROOT_DIR/bin/png_rgb.py" "$out"
    dims="$(png_dims "$out")"
    if [[ -n "$EXPECTED" && "$dims" != "$EXPECTED" ]]; then
      echo "   warning: expected ${EXPECTED// /x} (Play 9:16), got ${dims// /x}" >&2
    fi
    log "   wrote $out (${dims// /x}, RGB)"
  done

  if [[ "$VIDEO" == "1" ]]; then
    record_preview "$dir"
  fi

  reset_status_bar
}

cleanup() {
  [[ "${CLEANED:-0}" == "1" ]] && return
  CLEANED=1
  if [[ -n "${EMU_PID:-}" ]] && kill -0 "$EMU_PID" 2>/dev/null; then
    if [[ "$KEEP_EMULATOR" != "1" ]]; then
      log "stopping emulator..."
      reset_status_bar >/dev/null 2>&1 || true
      adb -e emu kill >/dev/null 2>&1 || true
      sleep 3
      kill -TERM "$EMU_PID" 2>/dev/null || true
    else
      log "leaving emulator $EMU_PID running (KEEP_EMULATOR=1)"
    fi
  fi
}
trap cleanup EXIT

log "Building LitLoop debug APK..."
(
  cd "$ROOT_DIR/android"
  run_with_timeout "${BUILD_TIMEOUT:-1500}" ./gradlew assembleDebug --console=plain
)
[[ -f "$APK" ]] || { echo "error: built APK not found at $APK" >&2; exit 1; }

ensure_avd
boot_emulator
capture_set

echo
echo "Screenshots ready in $OUTPUT_DIR"
