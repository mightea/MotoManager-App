# MotoManager (iOS)

**MotoManager** is a SwiftUI iOS app for managing a personal motorcycle fleet — fuel logs and consumption analytics, service/maintenance records, issues, torque specs, a parts inventory, and a document vault. It is backed by the Rust/Axum API in `../MotoManagerApi` (self-hosted; the server URL is entered on the login screen, and TestFlight builds get a pre-filled default injected from a CI secret).

> **`AGENTS.md` in this directory is the canonical, detailed guide.** Read it first. This file only summarizes the essentials and the gotchas that bite most often.

## Facts (verified against `project.pbxproj`)

| | |
|---|---|
| Platform | iOS **26.0** deployment target (iPhone + iPad) |
| Language | Swift **5.0** language mode; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` |
| Architecture | MVVM with `ObservableObject` + `@Published` — **not** `@Observable` |
| Dependencies | one SPM package: `BRLMPrinterKit` (Brother printer SDK; links CoreBluetooth/ExternalAccessory, hence `NSBluetoothAlwaysUsageDescription` in `Supporting/Info.plist`) |
| Build tooling | plain `xcodebuild` (there is no XcodeBuildMCP setup) |
| Scheme / Bundle | `MotoManager` / `ltd.herrmann.MotoManager` |

## Auth

The API issues **opaque Bearer session tokens** stored server-side (14-day expiry, deleted on logout) — **not JWTs**, despite the legacy `jwt-token` Keychain account name. The token is an opaque string; you cannot inspect its expiry client-side. Expired sessions are caught on launch: the first authorized request returns 401 → `NetworkManager.unauthorizedNotification` → `AuthViewModel` logs out. Passkey/WebAuthn login is also supported.

## Post-auth shell

`Views/MainTabView.swift` is the post-auth root with **4 tabs** — Fuel (`Tanken`), Workshop (`Werkstatt`), Service, Parts (`Teile`) — defined by `AppTab` in `UI/GlassTabBar.swift`.

## iOS 27 compatibility — required

The app must stay iOS 27 compatible (Xcode 27 beta at `/Applications/Xcode-beta.app`; full checklist in AGENTS.md). The rule that actually bites: **never give a `@State` property both a declaration-site default and a `State(initialValue:)` assignment in `init`** — iOS 27's macro silently discards the init value, so edit sheets open with defaults instead of the record's data.

## Offline-first sync — the part most likely to bite

- On-device source of truth is **SwiftData** for the syncable write entities (`Persistence/`): per-motorcycle `SDMaintenanceRecord`, `SDTorqueSpec`, `SDIssue`, `SDMotorcycleDetail`, plus the user-scoped parts inventory `SDPart`, `SDPartStock`, `SDPartConsumption`, `SDStorageLocation`. Each carries `clientId` (stable identity + server idempotency key), `serverId`, `syncState`, and push-failure counters (`syncAttempts`/`lastSyncError`).
- Motorcycles and documents are **not** in SwiftData — still DTOs cached via the JSON `CacheStore`.
- `Networking/SyncEngine.swift`: push (create→update→delete, keyed by `clientId`) then pull (`?since=` per resource), last-write-wins with local-pending winning. **Invariant to preserve:** each pull `save()`s the context *before* advancing its cursor — never reorder these, or an interrupted pull will skip records permanently.
- Poisoned records (5 failed pushes) stop retrying and surface as a tappable "retry" on `UI/StatusAccessoryBar.swift` (the TabView bottom accessory).
- Backend support lives in the `MotoManagerApi` migrations, starting with `011_sync_metadata.sql` and extended by the parts/details migrations.

## Build & test caveat (this machine)

CLI `xcodebuild` fails at the **link phase** with `ld: -objc_abi_version '-Xlinker' not supported` — **but this is fixable.** The Nix dev shell exports `LD=ld` (and `LD_FOR_TARGET=ld`), which Xcode's build system honours as its linker *driver*, so the real `ld` receives clang-driver flags (`-Xlinker …`) it can't parse. **Unset `LD` and it links cleanly** (full build + tests, not just compile):

```sh
env -u LD -u LD_FOR_TARGET xcodebuild build -scheme MotoManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Same `env -u LD` wrapper works for `xcodebuild test` and `xcrun swift`, and for iOS 27 builds with `DEVELOPER_DIR=/Applications/Xcode-beta.app`. The built `.app` installs/launches via `xcrun simctl` on the booted `iPhone 17 Pro` — bundle id `ltd.herrmann.MotoManager`.

## Driving the simulator (UI verification)

`idb` **is installed** (client via pipx at `~/.local/bin/idb`; `idb_companion` via `brew install facebook/fb/idb-companion` — the tap-qualified name matters, plain `idb-companion` resolves to an unrelated cask). Use it for taps and swipes; it is deterministic where AppleScript/CGEvent hacks are not:

```sh
UDID=$(idb list-targets | awk -F'|' '/Booted.*simulator/ {gsub(/ /,"",$2); print $2}')
idb ui tap   --udid $UDID 158 821                      # coordinates in device POINTS (402×874 on iPhone 17 Pro)
idb ui swipe --udid $UDID --duration 0.4 200 700 200 250
xcrun simctl io booted screenshot shot.png
```

Gotchas: without the companion installed, gesture tools hang for ~120s. Accessibility-tree queries report scroll-*content* coordinates that shift as you scroll — re-query right before tapping.

### Fabricating data scenarios (local API)

To verify states the production account can't produce (e.g. a motorcycle with zero workshop data), run `../MotoManagerApi` against a throwaway DB and point the app at it via the **Server field on the login screen** (persisted in UserDefaults key `com.motomanager.baseURL`; defaults to production):

```sh
# 1. API on a scratch DB (registration is always open while the users table is empty)
DATABASE_URL="sqlite:/tmp/test.sqlite?mode=rwc" PORT=3010 ENABLE_REGISTRATION=true \
  BACKUP_ENABLED=false DATA_DIR=/tmp/mm-data CACHE_DIR=/tmp/mm-cache cargo run
# 2. Register (returns a Bearer token directly; password min 8 chars); create a bike (multipart, make+model required)
curl -X POST localhost:3010/api/auth/register -H 'Content-Type: application/json' \
  -d '{"name":"T","email":"t@example.com","username":"t","password":"password123","confirmPassword":"password123"}'
curl -X POST localhost:3010/api/motorcycles -H "Authorization: Bearer $TOKEN" -F make=Yamaha -F model=XT
# 3. In the app: log out if needed, enter http://localhost:3010 in the login screen's
#    SERVER field, and sign in as the test user.
```

Caveats: the app may briefly show stale cached motorcycles from the previous backend (`CacheStore` persists per container), and hitting any backend with an expired/foreign token triggers the 401 → logout path. **`xcrun simctl spawn booted defaults write ltd.herrmann.MotoManager …` does NOT reach the app's real preferences** (the app reads the plist inside its data container — `simctl get_app_container … data` → `Library/Preferences/…plist`, editable with PlistBuddy while the app is terminated); use the login screen's Server field instead.

New `.swift` files under `MotoManager/` are auto-included (Xcode 26 `PBXFileSystemSynchronizedRootGroup`) — no `project.pbxproj` edit needed.

## App Store listing

Repo-managed: metadata in `appstore/metadata/de-DE/`, screenshots in `appstore/screenshots/de-DE/<DISPLAY_TYPE>/`, pushed by `.github/workflows/appstore.yml` (`scripts/appstore_assets.py`). Screenshots are regenerated with `scripts/make-screenshots.sh` (signs in to the live demo server as `admin-demo` + idb-driven simulators — review the PNGs before committing). See RELEASING.md → "App Store listing".

## Conventions

See AGENTS.md for the full list. The load-bearing ones: `NavigationStack` (never `NavigationView`); Swift Testing (never XCTest) in `MotoManagerTests/`; no new dependencies; read the base URL from `NetworkManager.shared.baseURL`; go through `NetworkManager` for the token; don't migrate ViewModels to `@Observable` piecemeal; no `@State` declaration-default + init double-set (iOS 27). Commits: Conventional Commits, no scope.
