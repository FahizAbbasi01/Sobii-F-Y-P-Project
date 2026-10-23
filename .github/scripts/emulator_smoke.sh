#!/usr/bin/env bash
# Installs the release APK on the CI emulator, drives the main screens through
# Android's accessibility tree (uiautomator) and saves screenshots + logcat.
set -u
APK="$1"; OUT="$2"
mkdir -p "$OUT"
PKG=com.devicetrust.devicetrust
FAIL=0

STEP=0
shot() { adb exec-out screencap -p > "$OUT/$1.png"; echo "screenshot: $1" | tee -a "$OUT/steps.txt"; }
log() { echo "$*" | tee -a "$OUT/steps.txt"; }

# Emulator system apps sometimes show "X isn't responding" dialogs; press "Wait" and carry on.
dismiss_system_dialogs() {
  if grep -q "isn't responding" "$OUT/ui.xml" 2>/dev/null; then
    local xy
    xy=$(python3 - "$OUT/ui.xml" <<'PY'
import re, sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for n in root.iter('node'):
    if (n.get('text') or '').strip().lower() == 'wait':
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', n.get('bounds')))
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
PY
)
    [ -n "$xy" ] && adb shell input tap $xy && log "dismissed a system 'isn't responding' dialog" && sleep 2
  fi
}

# tap_text "label" : find a node whose text/content-desc contains label and tap its centre.
tap_text() {
  local label="$1"
  for i in $(seq 1 30); do
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb pull /sdcard/ui.xml "$OUT/ui.xml" >/dev/null 2>&1
    dismiss_system_dialogs
    local xy
    xy=$(python3 - "$OUT/ui.xml" "$label" <<'PY'
import re, sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(0)
want = sys.argv[2].lower()
best = None
for n in root.iter('node'):
    txt = ((n.get('text') or '') + ' ' + (n.get('content-desc') or '')).lower()
    if want in txt:
        m = re.findall(r'\d+', n.get('bounds') or '')
        if len(m) == 4:
            x1, y1, x2, y2 = map(int, m)
            area = (x2 - x1) * (y2 - y1)
            if area > 0 and (best is None or area < best[0]):
                best = (area, (x1 + x2) // 2, (y1 + y2) // 2)
if best:
    print(best[1], best[2])
PY
)
    if [ -n "$xy" ]; then adb shell input tap $xy; log "tapped '$label' at $xy"; sleep 2; return 0; fi
    sleep 1
  done
  STEP=$((STEP+1)); cp "$OUT/ui.xml" "$OUT/fail_${STEP}_ui.xml"; shot "fail_${STEP}_tap"
  log "::error::Could not find '$label' on screen"; FAIL=1; return 1
}

wait_for() {
  local label="$1"
  for i in $(seq 1 40); do
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb pull /sdcard/ui.xml "$OUT/ui.xml" >/dev/null 2>&1
    dismiss_system_dialogs
    if grep -qi -- "$label" "$OUT/ui.xml"; then log "found '$label'"; return 0; fi
    sleep 1
  done
  STEP=$((STEP+1)); cp "$OUT/ui.xml" "$OUT/fail_${STEP}_ui.xml"; shot "fail_${STEP}_wait"
  log "::error::'$label' never appeared"; FAIL=1; return 1
}

# Let the freshly booted emulator settle before starting.
adb wait-for-device; sleep 30
adb logcat -c
adb install -r "$APK" || { echo "::error::install failed"; exit 1; }
log "device: $(adb shell wm size) $(adb shell wm density)"
# Airplane mode ON: prove the demo works with no network at all.
adb shell cmd connectivity airplane-mode enable 2>/dev/null || adb shell settings put global airplane_mode_on 1
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 6
shot 01_splash_or_onboarding
wait_for "Discover Trusted Phones" && shot 02_onboarding
tap_text "Skip"
wait_for "Welcome Back" && shot 03_login
cp "$OUT/ui.xml" "$OUT/login_ui.xml"
tap_text "Use demo account"
sleep 3; shot 03b_after_demo_login
wait_for "Find Your Next Phone" && sleep 2 && shot 04_home
tap_text "Explore"
wait_for "phones found" && sleep 1 && shot 05_explore
tap_text "iPhone 14 Pro"
wait_for "Request to Buy" && sleep 1 && shot 06_listing_detail
tap_text "Back"
wait_for "phones found"
tap_text "Check IMEI"
wait_for "Try a sample IMEI" && shot 07_imei_screen
tap_text "Reported stolen"
wait_for "Reported Stolen" && sleep 1 && shot 08_imei_stolen_result
tap_text "Sell"
wait_for "Register a new phone" && shot 09_sell
tap_text "Profile"
wait_for "My activity" && shot 10_profile

adb logcat -d > "$OUT/logcat.txt"
if grep -E "FATAL EXCEPTION|E/flutter" "$OUT/logcat.txt" | grep -v "^--" > "$OUT/errors.txt"; then
  echo "::error::Crash or Flutter error in logcat"; cat "$OUT/errors.txt" | head -40; FAIL=1
fi
if ! adb shell pidof $PKG >/dev/null; then echo "::error::App is not running at the end"; FAIL=1; fi
echo "smoke result: FAIL=$FAIL"
exit $FAIL
