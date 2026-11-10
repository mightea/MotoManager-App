#!/bin/zsh
# Generate the App Store screenshots in appstore/screenshots/de-DE/ against
# the live demo server — clean 9:41 status bar, exact App Store pixel sizes
# per Apple's screenshot spec:
#   APP_IPHONE_61          iPhone 17 Pro   1206x2622  (REQUIRED: "iPhone with
#                                                     Dynamic Island, medium")
#   APP_IPHONE_67          iPhone Air      1260x2736  (large display)
#   APP_IPHONE_DUO         iPhone Duo      1398x2034  (outer display; the
#                                                     inner 2007x2853 needs an
#                                                     unfolded simulator, which
#                                                     Xcode 27.1 can't set up
#                                                     from the CLI; required
#                                                     from April 2027 for
#                                                     iOS 27.1 SDK builds —
#                                                     undocumented in the ASC
#                                                     OpenAPI enum but accepted)
#   APP_IPAD_PRO_3GEN_129  iPad Pro 13"    2064x2752  (REQUIRED for iPad apps)
#
# What it does:
#   1. builds the app + UI test bundle once for the simulator (skip with
#      --skip-build)
#   2. per device: fresh-installs the app, resets the keychain, overrides the
#      status bar, then runs the `AppStoreScreenshots` XCUITest
#      (MotoManagerUITests/), which signs in to the demo server and captures
#      every listing slot on every screen of the device
#   3. keeps the PNGs whose pixel size matches the slot and copies them into
#      appstore/screenshots/de-DE/<DISPLAY_TYPE>/
#
# Data comes from the demo instance, seeded with the curated demo garage.
# Its address is not kept in the repo: DEMO_SERVER_URL is REQUIRED (export it
# in your shell / direnv; CI holds the same value as a secret). Set it and
# DEMO_USER / DEMO_PASSWORD to shoot against a different instance (e.g. a
# local scratch API).
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
SERVER_URL="${DEMO_SERVER_URL:?set DEMO_SERVER_URL to the demo server base URL (not kept in the repo)}"
DEMO_USER="${DEMO_USER:-admin-demo}"
DEMO_PASSWORD="${DEMO_PASSWORD:-demo-admin-2026}"
BUNDLE_ID="ltd.herrmann.MotoManager"
TMP="$(mktemp -d)"

# device name → display type → accepted pixel sizes (WxH)
typeset -A SIZES
SIZES[APP_IPHONE_61]="1206x2622 1179x2556"
SIZES[APP_IPHONE_67]="1260x2736 1290x2796 1320x2868"
SIZES[APP_IPHONE_DUO]="1398x2034 2007x2853"
SIZES[APP_IPAD_PRO_3GEN_129]="2064x2752 2048x2732"

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

px() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}'; }

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
  local kept=0
  for f in "$shots"/*.png; do
    local size; size=$(px "$f")
    if [[ " ${SIZES[$display_type]} " == *" $size "* ]]; then
      # Secondary screens (Duo) carry a "-screen-N" suffix; keep the slot
      # name so the upload order stays by number.
      cp "$f" "$OUT/$display_type/$(basename "$f" | sed -E 's/-screen-[0-9]+//')"
      echo "    $display_type/$(basename "$f") $size"
      kept=$((kept + 1))
    else
      echo "    skipped $(basename "$f") ($size is not a $display_type size)"
    fi
  done
  [[ $kept -gt 0 ]] || { echo "No $display_type-sized screenshot from $name"; exit 1; }
}

shoot "iPhone 17 Pro"          APP_IPHONE_61           # required slot
shoot "iPhone Air"             APP_IPHONE_67
shoot "iPhone Duo"             APP_IPHONE_DUO
shoot "iPad Pro 13-inch (M5)"  APP_IPAD_PRO_3GEN_129   # required for iPad

rm -rf "$TMP"
echo "==> Done. Review the PNGs in $OUT before committing."
