# MotoManager (iOS)

**MotoManager** is a SwiftUI iOS app for managing a personal motorcycle fleet — fuel logs and consumption analytics, service/maintenance records, torque specs, and a document vault. It is backed by the Rust/Axum API in `../MotoManagerApi` (deployed at `https://moto-api.herrmann.ltd`).

> **`AGENTS.md` in this directory is the canonical, detailed guide.** Read it first. This file only summarizes the essentials and the gotchas that bite most often. Where the two ever disagree, AGENTS.md wins — but note the corrections below, which apply to both.

## Facts (verified against `project.pbxproj`)

| | |
|---|---|
| Platform | iOS **26.4** deployment target (iPhone + iPad) |
| Language | Swift **5.0** language mode; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` |
| Architecture | MVVM with `ObservableObject` + `@Published` — **not** `@Observable` |
| Dependencies | none (plain Xcode project — no SPM/CocoaPods) |
| Build tooling | plain `xcodebuild` (there is no XcodeBuildMCP setup) |
| Scheme / Bundle | `MotoManager` / `ltd.herrmann.MotoManager` |

## Auth (correction)

The API issues **opaque Bearer session tokens** stored server-side (14-day expiry, deleted on logout) — **not JWTs**, despite the `jwt-token` Keychain account name and older "JWT" wording in the code and AGENTS.md. The token is an opaque string; you cannot inspect its expiry client-side. Expired sessions are caught on launch: the first authorized request returns 401 → `NetworkManager.unauthorizedNotification` → `AuthViewModel` logs out. Passkey/WebAuthn login is also supported.

## Post-auth shell (correction)

`Views/MainTabView.swift` is the post-auth root with **3 tabs** — Fuel (`Tanken`), Service, Workshop (`Werkstatt`) — defined by `AppTab` in `UI/GlassTabBar.swift`. (Not the 5 tabs some older docs claim.)

## Offline-first sync — the part most likely to bite

- On-device source of truth is **SwiftData** for the three syncable write entities: `SDMaintenanceRecord`, `SDTorqueSpec`, `SDIssue` (`Persistence/`). Each carries `clientId` (stable identity + server idempotency key), `serverId`, `syncState`, and push-failure counters (`syncAttempts`/`lastSyncError`).
- Motorcycles and documents are **not** in SwiftData — still DTOs cached via the JSON `CacheStore`.
- `Networking/SyncEngine.swift`: push (create→update→delete, keyed by `clientId`) then pull (`?since=` per resource), last-write-wins with local-pending winning. **Invariant to preserve:** each pull `save()`s the context *before* advancing its cursor — never reorder these, or an interrupted pull will skip records permanently.
- Poisoned records (5 failed pushes) stop retrying and surface as a tappable "retry" on `UI/SyncStatusPill.swift`.
- Backend support is `MotoManagerApi` migration `011_sync_metadata.sql` (only `maintenanceRecords`, `torqueSpecs`, `issues` are sync-enabled).

## Build & test caveat (this machine)

CLI `xcodebuild` **compiles** every file fine but the **link phase is broken** here: `ld: -objc_abi_version '-Xlinker' not supported`. So you can validate compilation from the CLI but cannot link or run tests without the IDE / a repaired Xcode. Compile-check with a concrete simulator destination:

```sh
xcodebuild build -scheme MotoManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

New `.swift` files under `MotoManager/` are auto-included (Xcode 26 `PBXFileSystemSynchronizedRootGroup`) — no `project.pbxproj` edit needed.

## Conventions

See AGENTS.md for the full list. The load-bearing ones: `NavigationStack` (never `NavigationView`); Swift Testing (never XCTest) in `MotoManagerTests/`; no new dependencies; read the base URL from `NetworkManager.shared.baseURL`; go through `NetworkManager` for the token; don't migrate ViewModels to `@Observable` piecemeal. Commits: Conventional Commits, no scope.
