# AGENTS.md

Guidance for AI coding agents working in this repository. Read this before exploring the codebase — it captures conventions and constraints that aren't obvious from the code alone.

## Project Summary

**MotoManager** is a SwiftUI iOS app for managing a personal motorcycle fleet — fuel logs and consumption analytics, service/maintenance records, torque specs, and a document vault. It is backed by a private API at `https://moto-api.herrmann.ltd` (JWT auth, with passkey/WebAuthn support).

## Build & Run

This is a plain Xcode project. **No SPM, CocoaPods, Carthage, or fastlane.** Currently zero third-party dependencies.

| Setting | Value |
|---|---|
| Scheme | `MotoManager` |
| Bundle ID | `ltd.herrmann.MotoManager` |
| Deployment target | iOS 26.4 |
| Swift version | 5.0 |
| Project file | `MotoManager.xcodeproj` |

Build:
```sh
xcodebuild -project MotoManager.xcodeproj -scheme MotoManager \
  -destination 'generic/platform=iOS' build
```

Test:
```sh
xcodebuild -project MotoManager.xcodeproj -scheme MotoManager \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

### Driving the Simulator

**Building still happens in Xcode.** CLI `xcodebuild` hits this machine's broken link phase
(`ld: -objc_abi_version '-Xlinker' not supported`), so build once in Xcode (or CI) → then
drive the produced `.app` with `xcrun simctl`:

1. `xcrun simctl boot` a device (target: **`iPhone 17 Pro`** — iOS 26.5 runtime matches the
   26.4 deploy target)
2. `xcrun simctl install <device> <DerivedData>/…/MotoManager.app`
3. `xcrun simctl launch <device> ltd.herrmann.MotoManager`
4. `xcrun simctl io <device> screenshot out.png` to see the screen; `openurl` for deep links

## Architecture

MVVM. Source layout under `MotoManager/`:

```
MotoManager/
├── MotoManagerApp.swift     # @main entry point — minimal
├── ContentView.swift        # auth gate + fleet load orchestration
├── Models/                  # Codable structs
├── ViewModels/              # @MainActor ObservableObjects
├── Views/                   # SwiftUI screens
├── Networking/              # NetworkManager + KeychainHelper
└── UI/                      # design tokens + reusable visual primitives
```

### State & Concurrency

- ViewModels are classes marked `@MainActor`, conforming to `ObservableObject`, exposing state via `@Published`. The codebase has **not** migrated to `@Observable` — keep ViewModels in the existing style for consistency.
- Networking is fully `async/await`. **No completion handlers.**
- Views load data via `.task { }` and refresh via `.refreshable { }`.

### Navigation

- Use `NavigationStack` — **never** `NavigationView`. The codebase was recently modernized; do not regress.
- `Views/MainTabView.swift` is the post-auth root, with 5 tabs: Fuel, Service, Torque, Docs, Settings.
- `Views/GarageView.swift` opens via `.sheet()` for motorcycle selection.
- The selected motorcycle ID persists to `UserDefaults` under `com.motomanager.lastSelectedId`.

## Networking & Auth

Singleton at `MotoManager/Networking/NetworkManager.swift`.

- **Base URL**: stored in `UserDefaults` under `com.motomanager.baseURL`, defaulting to `https://moto-api.herrmann.ltd`. Always go through `NetworkManager.shared.baseURL` — do not hardcode the URL.
- **Auth**: JWT bearer token, stored in Keychain via `MotoManager/Networking/KeychainHelper.swift` (service `com.motomanager.auth`, account `jwt-token`). Use `NetworkManager.saveToken(_:)`, `getToken()`, `deleteToken()` — do not touch the Keychain directly from elsewhere.
- **401 handling**: `NetworkManager.performRequest` posts `NetworkManager.unauthorizedNotification` (`com.motomanager.unauthorized`) on a 401 response. `AuthViewModel` observes this and clears the session.
- **Passkey login**: WebAuthn types live in `Models/AuthModels.swift`; `NetworkManager` exposes `fetchPasskeyLoginOptions` / `verifyPasskeyLogin`.

## Models & Persistence

- Models in `Models/` are Codable structs used as **API DTOs** (decoded by `NetworkManager`).
- **SwiftData is the on-device source of truth** for the syncable write entities — see `Persistence/`:
  - `SDMaintenanceRecord`, `SDTorqueSpec`, `SDIssue` (`@Model`), each with sync metadata: `clientId: UUID` (stable identity + server idempotency key), `serverId: Int?`, `syncState`, `serverUpdatedAt`. `description` is spelled `recordDescription` to avoid the `CustomStringConvertible` clash.
  - `SyncMapping.swift` converts DTO ⇆ `@Model` and builds the camelCase create/update payloads (always including `clientId`).
  - `PersistenceController.shared` owns the `ModelContainer`; the VMs and `SyncEngine` share `mainContext`.
- Motorcycles & documents are **not** in SwiftData yet — still fetched as DTOs and cached via the JSON `CacheStore` (offline reads). Keychain (JWT) and UserDefaults (base URL, last-selected id, sync cursors) are unchanged.
- `MaintenanceRecord` is polymorphic via a `type` discriminator (`fuel`, `oil`, `tire`, `battery`, `inspection`, …). Maps `type` → `recordType` in `CodingKeys`.

## Offline-first sync

- **Writes are offline-first**: VM methods (`createFuelRecord`, `createIssue`, `createTorque`, `createMaintenance`, plus update/delete) write to SwiftData with a `pending*` `syncState`, then call `SyncEngine.shared.requestSync`. Deletes are tombstones (`pendingDelete`) until the server confirms.
- `Networking/SyncEngine.swift` does **push (create→update→delete, keyed by `clientId`) then pull (`?since=` per resource)**, reconciling by `clientId` (fallback `serverId`), last-write-wins (local pending wins). `Networking/ConnectivityMonitor.swift` (`NWPathMonitor`) triggers a flush when connectivity returns; `MotoManagerApp` also flushes on foreground.
- Status is **transparent**: `UI/SyncStatusPill.swift` in the header (offline / syncing / N pending / synced) + `UI/PendingBadge.swift` on unsynced rows.
- Backend support lives in `MotoManagerApi` migration `011_sync_metadata.sql` (`clientId`/`updatedAt`/`deletedAt` + idempotent creates + soft-delete + `?since`). **Deploy the API before the client relies on it** (the client tolerates missing fields: falls back to `serverId` matching + full fetch).

## UI / Visual Style

The app has a deliberate glassmorphic, immersive aesthetic — full-bleed images, animated liquid backgrounds, `.ultraThinMaterial`, gradient overlays, SF Symbols, rounded font design. New views should match this language.

**Design tokens** — `MotoManager/UI/Theme.swift`:
- Spacing: `xs=4, s=8, m=16, l=24, xl=32`
- Radius: `s=8, m=12, l=20, xl=30`
- Colors: primary blue, accent orange, glass overlays (`Color.white.opacity(0.05)` / `.opacity(0.2)`)

**Reusable primitives — reuse, don't reinvent:**
- `UI/LiquidBackgroundView.swift` — animated mesh background (~7s loop)
- `UI/GlassShimmerRow.swift` — loading skeleton with `.ultraThinMaterial` shimmer
- `Views/MotorcycleSummaryHeader.swift` — 280pt immersive header with contextual stats per tab
- `Views/RemoteImageView.swift` — auth-aware async image loading

## Tests

- **Framework: Swift Testing** (`import Testing`, `@Test`, `#expect`) — **not XCTest**. New unit tests must follow Swift Testing patterns. See `MotoManagerTests/MotoManagerTests.swift`.
- UI tests in `MotoManagerUITests/` use XCUITest (Apple does not yet provide a Swift Testing alternative for UI tests).
- Coverage is currently scaffolding-only.

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
- Don't add CocoaPods / SPM dependencies without discussion. The repo is intentionally dependency-free.
- Don't hardcode `https://moto-api.herrmann.ltd` — read it from `NetworkManager.shared.baseURL`.
- Don't read or write the JWT directly — go through `NetworkManager`.
- Don't migrate ViewModels to `@Observable` piecemeal — either all or none.

## Recent Direction

Recent commits have focused on: `NavigationStack` migration, immersive headers (`MotorcycleSummaryHeader`), fuel consumption analytics, glass/liquid visual language, and a polished launch sequence (splash + persisted motorcycle selection). New work should extend this direction, not regress it.
