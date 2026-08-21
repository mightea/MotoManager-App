# AGENTS.md

Guidance for AI coding agents working in this repository. Read this before exploring the codebase — it captures conventions and constraints that aren't obvious from the code alone.

## Project Summary

**MotoManager** is a SwiftUI iOS app for managing a personal motorcycle fleet — fuel logs and consumption analytics, service/maintenance records, issues, torque specs, a parts inventory, and a document vault. It is backed by the self-hosted Rust/Axum API in `../MotoManagerApi` (opaque bearer session tokens, with passkey/WebAuthn support); the server URL is entered on the login screen (TestFlight builds get a pre-filled default injected from a CI secret).

## Build & Run

This is a plain Xcode project. **No CocoaPods, Carthage, or fastlane.** Exactly one SPM dependency: `BRLMPrinterKit` (the Brother label-printer SDK used by `Printing/LabelPrinterService.swift`). It links CoreBluetooth and ExternalAccessory for Bluetooth/MFi printer models the app doesn't use — which is why `Supporting/Info.plist` carries `NSBluetoothAlwaysUsageDescription` (App Store validation ITMS-90683 demands the purpose string for the mere API reference).

| Setting | Value |
|---|---|
| Scheme | `MotoManager` |
| Bundle ID | `ltd.herrmann.MotoManager` |
| Deployment target | iOS 26.0 |
| Swift version | 5.0 language mode; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency |
| Project file | `MotoManager.xcodeproj` |

Build:
```sh
env -u LD -u LD_FOR_TARGET xcodebuild -scheme MotoManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Test (same destination, `test` instead of `build`). The `env -u LD` wrapper matters — see below.

New `.swift` files under `MotoManager/` are auto-included (Xcode 26 `PBXFileSystemSynchronizedRootGroup`) — no `project.pbxproj` edit needed.

### Driving the Simulator

**CLI builds work if you unset `LD`.** The Nix dev shell exports `LD=ld`, which Xcode uses as
its linker driver → the real `ld` chokes on clang flags (`ld: -objc_abi_version '-Xlinker'
not supported`). `env -u LD -u LD_FOR_TARGET` fixes it — full build/test link cleanly:

```sh
env -u LD -u LD_FOR_TARGET xcodebuild build -scheme MotoManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Then drive the produced `.app` with `xcrun simctl` (no `env -u LD` needed for these):

1. `xcrun simctl boot` a device (target: **`iPhone 17 Pro`**)
2. `xcrun simctl install <device> <DerivedData>/…/MotoManager.app`
3. `xcrun simctl launch <device> ltd.herrmann.MotoManager`
4. `xcrun simctl io <device> screenshot out.png` to see the screen; `openurl` for deep links

For taps and swipes, `idb` **is installed** (client via pipx at `~/.local/bin/idb`, companion
via `brew install facebook/fb/idb-companion` — the tap-qualified name matters). It is
deterministic where AppleScript/CGEvent hacks are not:

```sh
idb ui tap   --udid <udid> 158 821                      # coordinates in device POINTS
idb ui swipe --udid <udid> --duration 0.4 200 700 200 250
```

Gotchas: without the companion, gesture tools hang ~120s; accessibility-tree queries report
scroll-content coordinates that shift as you scroll — re-query right before tapping. To
fabricate data scenarios, run `../MotoManagerApi` on a scratch DB and point the app at it
via the login screen's Server field — see CLAUDE.md for the recipe.

## iOS 27 Compatibility — required

The app must stay compatible with iOS 27 (audited 2026-08 against the Xcode 27.0 beta; the
app builds warning-free, all tests pass, and every screen was verified on the iOS 27
simulator). Any change that touches views or the build must not regress this.

- **The `@State` rule (the one change that actually bit us):** iOS 27's revised `@State`
  macro **silently discards `_x = State(initialValue:)` assignments made in `init` when the
  property also has a declaration-site default**. For any `@State` property seeded from
  `init` (edit sheets prefilled from an existing record), the declaration must have **no
  default value**, and every `init` path must assign it. Never write both
  `@State private var x = ""` *and* `_x = State(initialValue:)` — on iOS 27 the form opens
  with the declaration default instead of the record's data.
- **Verify against the iOS 27 SDK** for anything non-trivial: Xcode 27 beta lives at
  `/Applications/Xcode-beta.app` with the iOS 27.0 SDK and simulator runtime. Build/test with:

  ```sh
  env -u LD -u LD_FOR_TARGET DEVELOPER_DIR=/Applications/Xcode-beta.app \
    xcodebuild test -scheme MotoManager \
    -destination 'platform=iOS Simulator,OS=27.0,name=iPhone 17 Pro'
  ```
- Already satisfied — don't regress: generated scene manifest + launch screen
  (`INFOPLIST_KEY_UIApplicationSceneManifest_Generation` / `…UILaunchScreen_Generation`),
  no `actionSheet` (use `confirmationDialog`), no `UIScreen.main` (use
  `windowScene.screen`), no SceneKit, no Liquid Glass compatibility opt-out
  (`UIDesignRequiresCompatibility` is removed in iOS 27 — the app adopted the design
  natively).
- iOS 27 also makes iPhone apps live-resizable (iPad large displays, iPhone Mirroring):
  no hard-coded screen-size assumptions in layout code (decorative fixed frames are fine).

## Architecture

MVVM. Source layout under `MotoManager/`:

```
MotoManager/
├── MotoManagerApp.swift     # @main entry point — minimal
├── ContentView.swift        # auth gate + fleet load orchestration
├── Models/                  # Codable structs (API DTOs)
├── ViewModels/              # @MainActor ObservableObjects
├── Views/                   # SwiftUI screens
├── Networking/              # NetworkManager, KeychainHelper, SyncEngine, CacheStore
├── Persistence/             # SwiftData @Model entities + DTO⇆model mapping
├── Printing/                # part-label rendering + AirPrint
├── Scanning/                # odometer OCR + part-label scanning
└── UI/                      # design tokens + reusable visual primitives
```

### State & Concurrency

- ViewModels are classes marked `@MainActor`, conforming to `ObservableObject`, exposing state via `@Published`. The codebase has **not** migrated to `@Observable` — keep ViewModels in the existing style for consistency.
- Networking is fully `async/await`. **No completion handlers.**
- Views load data via `.task { }` and refresh via `.refreshable { }`.

### Navigation

- Use `NavigationStack` — **never** `NavigationView`. The codebase was recently modernized; do not regress.
- `Views/MainTabView.swift` is the post-auth root, with 4 tabs defined by `AppTab` in `UI/GlassTabBar.swift`: Fuel (`Tanken`), Workshop (`Werkstatt`), Service, Parts (`Teile`).
- `Views/GarageView.swift` opens via `.sheet()` for motorcycle selection.
- The selected motorcycle ID persists to `UserDefaults` under `com.motomanager.lastSelectedId`.

## Networking & Auth

Singleton at `MotoManager/Networking/NetworkManager.swift`.

- **Base URL**: stored in `UserDefaults` under `com.motomanager.baseURL`, entered by the user on the login screen. The build-time default comes from the `MMDefaultBaseURL` Info.plist key (`MM_DEFAULT_BASE_URL` build setting — empty in repo builds, injected from the `DEFAULT_SERVER_URL` CI secret for TestFlight). Always go through `NetworkManager.shared.baseURL` — do not hardcode a URL.
- **Auth**: opaque Bearer session token stored server-side (14-day expiry, deleted on logout) — **not a JWT**, despite the legacy `jwt-token` Keychain account name; its expiry cannot be inspected client-side. Stored in Keychain via `MotoManager/Networking/KeychainHelper.swift` (service `com.motomanager.auth`, account `jwt-token`). Use `NetworkManager.saveToken(_:)`, `getToken()`, `deleteToken()` — do not touch the Keychain directly from elsewhere.
- **401 handling**: `NetworkManager.performRequest` posts `NetworkManager.unauthorizedNotification` (`com.motomanager.unauthorized`) on a 401 response. `AuthViewModel` observes this and clears the session.
- **Passkey login**: WebAuthn types live in `Models/AuthModels.swift`; `NetworkManager` exposes `fetchPasskeyLoginOptions` / `verifyPasskeyLogin`.

## Models & Persistence

- Models in `Models/` are Codable structs used as **API DTOs** (decoded by `NetworkManager`).
- **SwiftData is the on-device source of truth** for the syncable write entities — see `Persistence/`:
  - Per-motorcycle: `SDMaintenanceRecord`, `SDTorqueSpec`, `SDIssue`, `SDMotorcycleDetail` (`SyncModels.swift`). User-scoped (parts inventory): `SDPart`, `SDPartStock`, `SDPartConsumption`, `SDStorageLocation` (`PartsSyncModels.swift`).
  - Each `@Model` carries sync metadata: `clientId: UUID` (stable identity + server idempotency key), `serverId: Int?`, `syncState`, `serverUpdatedAt`, plus push-failure counters (`syncAttempts`/`lastSyncError`). `description` is spelled `recordDescription` to avoid the `CustomStringConvertible` clash.
  - `SyncMapping.swift` / `PartsSyncMapping.swift` convert DTO ⇆ `@Model` and build the camelCase create/update payloads (always including `clientId`).
  - `PersistenceController.shared` owns the `ModelContainer`; the VMs and `SyncEngine` share `mainContext`.
- Motorcycles & documents are **not** in SwiftData yet — still fetched as DTOs and cached via the JSON `CacheStore` (offline reads). Keychain (session token) and UserDefaults (base URL, last-selected id, sync cursors) are unchanged.
- `MaintenanceRecord` is polymorphic via a `type` discriminator (`fuel`, `oil`, `tire`, `battery`, `inspection`, …). Maps `type` → `recordType` in `CodingKeys`.

## Offline-first sync

- **Writes are offline-first**: VM methods (`createFuelRecord`, `createIssue`, `createTorque`, `createMaintenance`, plus update/delete) write to SwiftData with a `pending*` `syncState`, then call `SyncEngine.shared.requestSync`. Deletes are tombstones (`pendingDelete`) until the server confirms.
- `Networking/SyncEngine.swift` does **push (create→update→delete, keyed by `clientId`) then pull (`?since=` per resource)**, reconciling by `clientId` (fallback `serverId`), last-write-wins (local pending wins). `Networking/ConnectivityMonitor.swift` (`NWPathMonitor`) triggers a flush when connectivity returns; `MotoManagerApp` also flushes on foreground.
- **Invariant to preserve:** each pull `save()`s the context *before* advancing its sync cursor — never reorder these, or an interrupted pull will skip records permanently.
- Poisoned records (5 failed pushes) stop retrying and surface as a tappable "retry" in the status accessory.
- Status is **transparent**: `UI/StatusAccessoryBar.swift` renders in the TabView's bottom accessory (offline / syncing / N pending / refresh-failed; hidden when synced) + `UI/PendingBadge.swift` on unsynced rows.
- Backend support lives in the `MotoManagerApi` migrations, starting with `011_sync_metadata.sql` (`clientId`/`updatedAt`/`deletedAt` + idempotent creates + soft-delete + `?since`) and extended by the parts/details migrations. **Deploy the API before the client relies on it** (the client tolerates missing fields: falls back to `serverId` matching + full fetch).

## UI / Visual Style

The app is **native-first with a motorsport accent**, and it **supports light and dark mode** — never hardcode white/black ink. The chrome layer (tab bar, nav bars, toolbars, sheets, the header's glass pills) is system Liquid Glass; the content layer (lists, rows, cards) uses standard adaptive list backgrounds, `.insetGrouped` `List`s, `foregroundStyle(.primary/.secondary/.tertiary)`, `ContentUnavailableView` empty states, `.redacted(.placeholder)` loading rows, and Swift Charts. Glass belongs to controls/navigation, not content cards. The only always-white ink is `Theme.Colors.onPhoto*`, reserved for text sitting on photos (hero header, login), which keep their scrim gradients.

**Design tokens** — `MotoManager/UI/Theme.swift`:
- Spacing: `xs=4, s=8, m=16, l=24, xl=32`, `pageH=12`
- Radius (single concentric scale — never hardcode): `sheet=32 > card=22 > field=18 > chip=14 > control=12 > controlInner=10 > badge=8`
- Colors: `primary` (motorsport blue), `accent` (red), adaptive `background`/`backgroundElevated`, `onPhoto*` (photo ink), `Theme.Glass.*` adaptive hairlines. `navy*` is reserved for photo scrims.

**Reusable primitives — reuse, don't reinvent:**
- `UI/LiquidBackgroundView.swift` — adaptive canvas with brand halos (navy in dark, light gray in light)
- `UI/StatusAccessoryBar.swift` — sync/refresh status in the tab bar's bottom accessory
- `Views/MotorcycleSummaryHeader.swift` — immersive photo header (Dynamic Type-scaled height) with the Wechseln pill; gear/add live in the system toolbar
- `Views/RemoteImageView.swift` — auth-aware async image loading
- `UI/GlassSegmentedControl.swift` — the single segmented-control idiom (tabs *and* sheets)

## Tests

- **Framework: Swift Testing** (`import Testing`, `@Test`, `#expect`) — **not XCTest**. New unit tests must follow Swift Testing patterns.
- UI tests in `MotoManagerUITests/` use XCUITest (Apple does not yet provide a Swift Testing alternative for UI tests).
- Real coverage exists in `MotoManagerTests/` (~70 tests): maintenance logic, sync mapping/cursors, parts inventory, passkey decoding, label links. Extend the matching file when touching those areas.

## App Store listing assets

The store listing (description, keywords, screenshots) is repo-managed and
pushed to App Store Connect by `.github/workflows/appstore.yml` →
`scripts/appstore_assets.py`. Metadata: `appstore/metadata/de-DE/*.txt`.
Screenshots: `appstore/screenshots/de-DE/<DISPLAY_TYPE>/*.png`, regenerated
locally with `scripts/make-screenshots.sh` (builds the app, signs in to the
live demo server as `admin-demo`, drives both simulators via idb) —
always review the PNGs before committing. Details in RELEASING.md.

## Commit Messages — Conventional Commits (no scope)

Format: `<type>: <description>` — the optional `(<scope>)` component is **not used** in this repo.

- Allowed types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `style`, `build`, `ci`
- Description: lowercase, imperative mood, no trailing period

Good (matches existing `git log`):
```
feat: optimize launch sequence and persist motorcycle selection
fix: resolve build issues and modernize SwiftUI code
refactor: modernize navigation with NavigationStack and enhance empty state UX
```

Bad — do not write scoped commits like:
```
feat(auth): add passkey login
fix(networking): handle 401 retry
```

## Conventions / Don'ts

- Don't introduce `NavigationView` — use `NavigationStack`.
- Don't introduce XCTest in `MotoManagerTests/` — use Swift Testing.
- Don't add CocoaPods / SPM dependencies without discussion. The repo is intentionally minimal — `BRLMPrinterKit` (Brother printing) is the single sanctioned exception.
- Don't hardcode any server URL — read it from `NetworkManager.shared.baseURL`.
- Don't read or write the session token directly — go through `NetworkManager`.
- Don't migrate ViewModels to `@Observable` piecemeal — either all or none.
- Don't give a `@State` property both a declaration default and a `State(initialValue:)` assignment in `init` — iOS 27 discards the init value (see "iOS 27 Compatibility").

## Recent Direction

Recent work has focused on: offline-first SwiftData sync (including the parts inventory), the parts/label printing & scanning workflow, fuel-station detection, glass/liquid visual language, and iOS 27 readiness. New work should extend this direction, not regress it.
