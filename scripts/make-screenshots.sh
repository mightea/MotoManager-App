#!/bin/zsh
# Generate the App Store screenshots in appstore/screenshots/de-DE/ against
# the live demo server — clean 9:41 status bar, exact App Store pixel sizes
# (iPhone 1260x2736, iPad 13" 2064x2752 — per Apple's current screenshot
# spec; both verified accepted by the ASC API).
#
# What it does:
#   1. builds the app + UI test bundle once for the simulator (skip with
#      --skip-build)
#   2. per device (iPhone Air, iPad Pro 13-inch): fresh-installs the app,
#      resets the keychain, overrides the status bar, then runs the
#      `AppStoreScreenshots` XCUITest (MotoManagerUITests/), which signs in
#      to the demo server and captures every listing slot
#   3. copies the PNGs into appstore/screenshots/de-DE/<DISPLAY_TYPE>/
#
# Data comes from the demo instance (moto-api-demo.herrmann.ltd), seeded
# with the curated demo garage. Override DEMO_SERVER_URL / DEMO_USER /
# DEMO_PASSWORD to shoot against a different instance (e.g. a local scratch
# API).
#
# The test navigates by accessibility labels/identifiers (tab titles,
# `statistics.link`, `fuel.record.*`), so it survives layout changes; after
# a bigger UI change still REVIEW THE PNGs before committing. Upload happens
# separately — commit the PNGs and let .github/workflows/appstore.yml push.
#
# Prereqs: both simulators present in Xcode (no idb needed). If xcodebuild
# only offers "My Mac" as destination, run `xcodebuild -runFirstLaunch`.

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$APP_DIR/appstore/screenshots/de-DE"
DERIVED="$APP_DIR/build/DerivedData"
SERVER_URL="${DEMO_SERVER_URL:-https://moto-api-demo.herrmann.ltd}"
DEMO_USER="${DEMO_USER:-admin-demo}"
DEMO_PASSWORD="${DEMO_PASSWORD:-demo-admin-2026}"
BUNDLE_ID="ltd.herrmann.MotoManager"
TMP="$(mktemp -d)"

IPHONE_NAME="iPhone Air"             # 420x912 pt @3x = 1260x2736 px
IPAD_NAME="iPad Pro 13-inch (M5)"    # 2064x2752 px

# --- 1. Build ----------------------------------------------------------------
if [[ "${1:-}" != "--skip-build" ]]; then
  echo "==> Building app + UI tests for the simulator"
  env -u LD -u LD_FOR_TARGET xcodebuild build-for-testing -quiet \
    -project "$APP_DIR/MotoManager.xcodeproj" -scheme MotoManager-UI \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED"
fi

# --- 2. Demo server reachable? -----------------------------------------------
echo "==> Checking demo server $SERVER_URL"
curl -sf -m 10 "$SERVER_URL/api/health" >/dev/null \
  || { echo "Demo server unreachable — screenshots need live data"; exit 1; }

# --- helpers -----------------------------------------------------------------
find_udid() {
  # Fixed-string name match (names may contain parens, e.g. "(M5)"); prefer
  # the newest iOS runtime; the UDID is the first UUID-shaped token.
  xcrun simctl list devices available | \
    awk -v n="$1 (" 'index($0, n) && match($0, /[0-9A-F]{8}-[0-9A-F-]{27}/) \
      {print substr($0, RSTART, RLENGTH)}' | tail -1
}

shoot() {  # shoot <device name> <display type>
  local name="$1" display_type="$2" udid
  udid=$(find_udid "$name")
  [[ -n "$udid" ]] || { echo "Simulator '$name' not found"; exit 1; }
  echo "==> $name ($udid) → $display_type"
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2>/dev/null || true
  # Wipe saved sessions/passwords so every run starts logged out and the
  # "Save Password?" sheet appears at the same point.
  xcrun simctl keychain "$udid" reset 2>/dev/null || true
  xcrun simctl status_bar "$udid" override --time "09:41" \
    --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --operatorName "" --wifiBars 3 \
    2>/dev/null || true
  xcrun simctl ui "$udid" appearance light 2>/dev/null || true

  local shots="$TMP/$display_type"
  mkdir -p "$shots"
  # -parallel-testing-enabled NO: otherwise the test runs on a clone device.
  TEST_RUNNER_MM_UI_TEST_SERVER="$SERVER_URL" \
  TEST_RUNNER_MM_UI_TEST_USER="$DEMO_USER" \
  TEST_RUNNER_MM_UI_TEST_PASSWORD="$DEMO_PASSWORD" \
  TEST_RUNNER_MM_UI_TEST_SHOTS="$shots" \
  env -u LD -u LD_FOR_TARGET xcodebuild test-without-building -quiet \
    -project "$APP_DIR/MotoManager.xcodeproj" -scheme MotoManager-UI \
    -destination "platform=iOS Simulator,id=$udid" \
    -parallel-testing-enabled NO -derivedDataPath "$DERIVED" \
    -only-testing:MotoManagerUITests/AppStoreScreenshots \
    || { echo "Screenshot test failed on $name"; exit 1; }

  mkdir -p "$OUT/$display_type"
  rm -f "$OUT/$display_type"/*.png
  cp "$shots"/*.png "$OUT/$display_type/"
  for f in "$OUT/$display_type"/*.png; do
    echo "    $display_type/$(basename "$f") $(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"
  done
}

shoot "$IPHONE_NAME" APP_IPHONE_67          # top iPhone slot; takes all 6.9" sizes
shoot "$IPAD_NAME"   APP_IPAD_PRO_3GEN_129

rm -rf "$TMP"
echo "==> Done. Review the PNGs in $OUT before committing."
