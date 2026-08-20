#!/bin/zsh
# Generate the App Store screenshots in appstore/screenshots/de-DE/ from a
# seeded local API — deterministic demo data, clean 9:41 status bar, exact
# App Store pixel sizes (iPhone 6.9" 1320x2868, iPad 13" 2064x2752).
#
# What it does:
#   1. builds the app for the simulator (skip with --skip-build)
#   2. starts ../MotoManagerApi on a throwaway SQLite DB (port 3010) and
#      seeds it via scripts/seed-demo-data.py
#   3. per device (iPhone 17 Pro Max, iPad Pro 13-inch): fresh-installs the
#      app, drives the login form and tab navigation with idb, captures the
#      five listing screenshots
#
# Semi-automated by design: the tap coordinates below are tuned to the
# current login/tab layout on exactly these two simulator models. After any
# bigger UI change, run it, REVIEW THE PNGs, and adjust coordinates if a tap
# missed. The iOS "Save Password?" sheet is dismissed blind (the tap is
# followed by a pop-to-root tab tap, so a stray touch is harmless).
#
# Prereqs: idb (pipx) + idb_companion (brew install facebook/fb/idb-companion);
# both simulators present in Xcode. Upload happens separately — commit the
# PNGs and let .github/workflows/appstore.yml push them.

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
API_DIR="$APP_DIR/../MotoManagerApi"
OUT="$APP_DIR/appstore/screenshots/de-DE"
IDB="${IDB:-$HOME/.local/bin/idb}"
PORT=3010
SERVER_URL="http://localhost:$PORT"
BUNDLE_ID="ltd.herrmann.MotoManager"
WORK="$(mktemp -d /tmp/mm-screenshots.XXXXXX)"

IPHONE_NAME="iPhone 17 Pro Max"
IPAD_NAME="iPad Pro 13-inch (M5)"

cleanup() {
  [[ -n "${API_PID:-}" ]] && kill "$API_PID" 2>/dev/null || true
}
trap cleanup EXIT

# --- 1. Build ----------------------------------------------------------------
if [[ "${1:-}" != "--skip-build" ]]; then
  echo "==> Building app for the simulator"
  env -u LD -u LD_FOR_TARGET xcodebuild build -quiet \
    -project "$APP_DIR/MotoManager.xcodeproj" -scheme MotoManager \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$APP_DIR/build/DerivedData"
fi
APP="$APP_DIR/build/DerivedData/Build/Products/Debug-iphonesimulator/MotoManager.app"
[[ -d "$APP" ]] || { echo "No built app at $APP"; exit 1; }

# --- 2. API + seed -----------------------------------------------------------
echo "==> Starting scratch API on port $PORT"
if ! (cd "$API_DIR" && cargo build --quiet); then
  echo "cargo build failed"; exit 1
fi
mkdir -p "$WORK/data" "$WORK/cache"
DATABASE_URL="sqlite:$WORK/demo.sqlite?mode=rwc" PORT=$PORT \
  ENABLE_REGISTRATION=true BACKUP_ENABLED=false \
  DATA_DIR="$WORK/data" CACHE_DIR="$WORK/cache" \
  "$API_DIR/target/debug/moto-manager-api" >"$WORK/api.log" 2>&1 &
API_PID=$!
for i in {1..30}; do
  curl -sf -m 1 "$SERVER_URL/api/health" >/dev/null && break
  sleep 0.5
  [[ $i == 30 ]] && { echo "API did not come up — see $WORK/api.log"; exit 1; }
done
python3 "$APP_DIR/scripts/seed-demo-data.py" "$SERVER_URL"

# --- helpers -----------------------------------------------------------------
tap()   { "$IDB" ui tap --udid "$UDID" "$1" "$2"; sleep "${3:-1.5}"; }
type_() { "$IDB" ui text --udid "$UDID" "$1"; sleep 0.3; }
clear_field() {  # tap the field's right edge, then delete everything
  tap "$1" "$2" 0.6
  for i in {1..60}; do "$IDB" ui key --udid "$UDID" 42; done
}
shot() {
  xcrun simctl io "$UDID" screenshot "$OUT/$DISPLAY_TYPE/$1.png" >/dev/null 2>&1
  echo "    $DISPLAY_TYPE/$1.png"
}

boot_device() {
  # Fixed-string name match (names may contain parens, e.g. "(M5)"); the
  # UDID is the first UUID-shaped token on the line.
  UDID=$(xcrun simctl list devices available | \
    awk -v n="$1 (" 'index($0, n) && match($0, /[0-9A-F]{8}-[0-9A-F-]{27}/) \
      {print substr($0, RSTART, RLENGTH); exit}')
  [[ -n "$UDID" ]] || { echo "Simulator '$1' not found"; exit 1; }
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  # Wipe saved credentials so the "Save Password?" sheet appears at the same
  # point every run — its dismissal tap below assumes it is showing.
  xcrun simctl keychain "$UDID" reset 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP" 2>/dev/null
  xcrun simctl status_bar "$UDID" override --time "09:41" \
    --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --operatorName "" --wifiBars 3 \
    2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null 2>&1
  sleep 4
}

# --- 3a. iPhone 6.9" ---------------------------------------------------------
# Point geometry 440x956. Login fields at x=220: server y=544, user y=612,
# password y=679, Anmelden y=736. "Not Now" (178,587). Tab bar y=920:
# Tanken 62, Werkstatt 171, Service 270, Teile 361. Mängel segment (118,319).
echo "==> iPhone ($IPHONE_NAME)"
DISPLAY_TYPE="APP_IPHONE_67"   # the 6.7" slot also takes 6.9" (1320x2868)
mkdir -p "$OUT/$DISPLAY_TYPE"
boot_device "$IPHONE_NAME"
clear_field 390 544; type_ "$SERVER_URL"
clear_field 390 612; type_ "demo"
tap 200 679 0.8;     type_ "demo-pass-123"
tap 220 736 4                      # Anmelden
tap 178 587 1.5                    # Save Password? -> Not Now (blind)
tap 62 920                         # normalize: pop Tanken to root
shot 01-tanken
tap 171 920 2.5;  shot 02-werkstatt
tap 270 920 2.5;  shot 03-service
tap 118 319 2;    shot 04-maengel  # Mängel segment
tap 361 920 2.5;  shot 05-teile

# --- 3b. iPad 13" ------------------------------------------------------------
# Point geometry 1032x1376 portrait. Login fields at x=515: server y=969,
# user y=1030, password y=1054 (accessory bar shifts the form up once the
# keyboard attaches), Anmelden y=1122. "Not Now" (440,788). Top tab bar y=53:
# Tanken 381, Werkstatt 482, Service 580, Teile 657. Mängel segment (256,317).
echo "==> iPad ($IPAD_NAME)"
DISPLAY_TYPE="APP_IPAD_PRO_3GEN_129"
mkdir -p "$OUT/$DISPLAY_TYPE"
boot_device "$IPAD_NAME"
clear_field 700 969;  type_ "$SERVER_URL"
clear_field 700 1030; type_ "demo"
tap 480 1054 0.8;     type_ "demo-pass-123"
tap 515 1122 4                     # Anmelden
tap 440 788 1.5                    # Save Password? -> Not Now (blind)
tap 381 53                         # normalize: pop Tanken to root
shot 01-tanken
tap 482 53 2.5;  shot 02-werkstatt
tap 580 53 2.5;  shot 03-service
tap 256 317 2;   shot 04-maengel
tap 657 53 2.5;  shot 05-teile

echo "==> Done. Review the PNGs in $OUT before committing."
