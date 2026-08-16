# MotoManager (iOS)

SwiftUI app for managing a personal motorcycle fleet — fuel logs with
consumption analytics, service history with interval tracking, torque specs
and documents, and a parts inventory with printable QR labels. The UI is
German (Swiss).

The app is offline-first: records are stored in SwiftData and synced against
the companion Rust/Axum backend with client-side IDs, so entries created
without connectivity push cleanly once the network returns. A React Router
webapp covers the same data from the desktop.

## Features by tab

- **Tanken** — fuel entries with price, consumption (L/100 km) and station
  location; odometer OCR via the camera.
- **Werkstatt** — torque specs, motorcycle details, tire pressures and a
  document vault.
- **Service** — maintenance history grouped by year with type-specific
  summaries, service-interval insights (ok/due/overdue, tire age from DOT
  codes), bundled works, consumed parts, and open issues (Mängel).
- **Teile** — parts inventory with stock per storage location, consumption
  booking from repairs, and QR label printing on a Brother PT-E550W.

## Requirements & build

- Xcode 26, iOS 26.4+ deployment target (iPhone + iPad).
- No third-party dependencies except `BRLMPrinterKit` (SPM, label printing).

```sh
xcodebuild build -scheme MotoManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test -scheme MotoManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Tests use Swift Testing. If your shell exports `LD` (e.g. a Nix dev shell),
prefix the commands with `env -u LD -u LD_FOR_TARGET` — Xcode otherwise picks
it up as the linker driver and the link phase fails.

### Local backend for testing

The login screen has a server field (persisted; repo builds start blank,
while CI-built TestFlight binaries pre-fill a default injected from the
`DEFAULT_SERVER_URL` secret). The app can therefore be pointed at a locally
running `MotoManagerApi` with a throwaway database — useful for self-hosted
deployments and for reproducing states a production account can't, such as
a freshly created motorcycle:

```sh
# in ../MotoManagerApi — registration is open while the users table is empty
DATABASE_URL="sqlite:/tmp/test.sqlite?mode=rwc" PORT=3010 ENABLE_REGISTRATION=true cargo run
```

Then enter `http://localhost:3010` in the login screen's server field and
sign in.

For scripted UI checks, [idb](https://fbidb.io) (`brew install
facebook/fb/idb-companion` plus the `fb-idb` pip client) drives taps and
swipes on the simulator reliably; screenshots come from
`xcrun simctl io booted screenshot`.

See `AGENTS.md` for the detailed contributor/agent guide (architecture,
sync invariants, conventions).

## Releases

Commits follow [Conventional Commits](https://www.conventionalcommits.org).
[release-please](https://github.com/googleapis/release-please) maintains a
rolling release PR on `main`; merging it tags a release (`vX.Y.Z`) and
dispatches the TestFlight pipeline, which archives with the tag as
`MARKETING_VERSION` and the CI run number as the build number. Signing and
upload run through an App Store Connect API key — required secrets are
documented in the header of `.github/workflows/testflight.yml`.
