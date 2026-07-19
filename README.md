# MotoManager (iOS)

SwiftUI app for managing a personal motorcycle fleet — fuel logs with
consumption analytics, service history with interval tracking, torque specs
and documents, and a parts inventory with printable QR labels. The UI is
German (Swiss).

The app is offline-first: records are stored in SwiftData and synced against
the companion Rust/Axum backend (`moto-api.herrmann.ltd`) with client-side
IDs, so entries created without connectivity push cleanly once the network
returns. A React Router webapp covers the same data from the desktop.

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
