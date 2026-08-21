#!/bin/zsh
# Generate the App Store screenshots in appstore/screenshots/de-DE/ against
# the live demo server — clean 9:41 status bar, exact App Store pixel sizes
# (iPhone 1260x2736, iPad 13" 2064x2752 — per Apple's current screenshot
# spec; both verified accepted by the ASC API).
#
# What it does:
#   1. builds the app for the simulator (skip with --skip-build)
#   2. per device (iPhone Air, iPad Pro 13-inch): fresh-installs the app,
#      signs in to the demo server as the demo admin, drives the tab
#      navigation with idb, captures the five listing screenshots
#
# Data comes from the demo instance (moto-api-demo.herrmann.ltd), which is
# seeded with the curated demo garage — the same content the public demo
# shows. Override DEMO_SERVER_URL / DEMO_USER / DEMO_PASSWORD to shoot
# against a different instance (e.g. a local scratch API).
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
OUT="$APP_DIR/appstore/screenshots/de-DE"
IDB="${IDB:-$HOME/.local/bin/idb}"
SERVER_URL="${DEMO_SERVER_URL:-https://moto-api-demo.herrmann.ltd}"
DEMO_USER="${DEMO_USER:-admin-demo}"
DEMO_PASSWORD="${DEMO_PASSWORD:-demo-admin-2026}"
BUNDLE_ID="ltd.herrmann.MotoManager"

IPHONE_NAME="iPhone Air"   # 420x912 pt @3x = 1260x2736 px, the required size
IPAD_NAME="iPad Pro 13-inch (M5)"

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

# --- 2. Demo server reachable? -----------------------------------------------
echo "==> Checking demo server $SERVER_URL"
curl -sf -m 10 "$SERVER_URL/api/health" >/dev/null \
  || { echo "Demo server unreachable — screenshots need live data"; exit 1; }

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

# --- 3a. iPhone --------------------------------------------------------------
# Point geometry 420x912 (iPhone Air). Login fields: server y=500, user
# y=558 (tap at x=210 — a right-edge tap does not move focus here),
# password y=625, Anmelden y=691. "Not Now" (126,580). Tab bar y=874:
# Tanken 74, Werkstatt 156, Service 256, Teile 347. Mängel segment (112,320).
echo "==> iPhone ($IPHONE_NAME)"
DISPLAY_TYPE="APP_IPHONE_67"   # top iPhone slot; takes all 6.9" sizes
mkdir -p "$OUT/$DISPLAY_TYPE"
boot_device "$IPHONE_NAME"
clear_field 380 500; type_ "$SERVER_URL"
tap 210 558 0.8;     type_ "$DEMO_USER"
tap 200 625 0.8;     type_ "$DEMO_PASSWORD"
tap 210 691 5                      # Anmelden (live server: allow a beat more)
tap 126 580 1.5                    # Save Password? -> Not Now (blind)
tap 74 874                         # normalize: pop Tanken to root
shot 01-tanken
tap 156 874 2.5;  shot 02-werkstatt
tap 256 874 2.5;  shot 03-service
tap 112 320 2;    shot 04-maengel  # Mängel segment
tap 347 874 2.5;  shot 05-teile

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
clear_field 700 1030; type_ "$DEMO_USER"
tap 480 1054 0.8;     type_ "$DEMO_PASSWORD"
tap 515 1122 5                     # Anmelden
tap 440 788 1.5                    # Save Password? -> Not Now (blind)
tap 381 53                         # normalize: pop Tanken to root
shot 01-tanken
tap 482 53 2.5;  shot 02-werkstatt
tap 580 53 2.5;  shot 03-service
tap 256 317 2;   shot 04-maengel
tap 657 53 2.5;  shot 05-teile

echo "==> Done. Review the PNGs in $OUT before committing."
