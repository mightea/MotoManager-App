# Improvement Backlog

Remaining work from the August 2026 app review. The high-impact reliability,
performance, upload, loading-state, accessibility, and adaptive-width changes
have already been implemented; this file tracks the deliberately deferred work.

## 1. Bundle the login hero image

**Priority:** Medium
**Status:** Complete (August 2026)

The login screen previously downloaded its hero image from Wikimedia. This made
the first impression dependent on network availability, added an external
request before authentication, and made screenshots less deterministic.

### Work

- Select an owned or appropriately licensed motorcycle image and record any
  required attribution.
- Add an optimized asset to `Assets.xcassets`, including suitable light/dark or
  appearance variants if needed.
- Replace the remote `AsyncImage` in `LoginView` with the bundled asset.
- Preserve the existing scrim, adaptive crop, Dynamic Type behavior, and
  always-white `Theme.Colors.onPhoto*` text treatment.
- Keep the asset reasonably sized for phones and large iPads without shipping
  an unnecessarily large source image.

### Acceptance criteria

- The complete login screen renders correctly in airplane mode on first launch.
- No request to `upload.wikimedia.org` is made.
- Light mode, dark mode, portrait, landscape, and accessibility text sizes are
  visually checked on iPhone and iPad.
- App Store screenshots remain visually stable and the app-size increase is
  reviewed.

### Completion notes

- Bundled an optimized 2560 × 1703 JPEG derivative of the existing login photo
  in `LoginHero.imageset`; the source, author, license, and modifications are
  recorded in [`image-attributions.md`](image-attributions.md).
- `LoginView` now renders the local asset directly and makes no pre-auth photo
  request. The optimized source is 0.88 MB; the compiled simulator
  `Assets.car` grew by approximately 1.7 MB compared with the existing
  pre-change build.
- Verified the first-launch screen on iPhone and 13-inch iPad in portrait and
  landscape, both system appearances, and accessibility XXXL. The Passkey
  action now wraps to two lines at large content sizes rather than truncating.
- The App Store screenshot sets contain post-login screens, so their rendered
  content is unaffected.

## 2. Move user-facing copy into a String Catalog

**Priority:** Medium
**Status:** Open

Most interface text is currently embedded directly in Swift views and view
models. German should remain the current product language, but the copy should
be centralized before more screens or languages are added.

### Work

- Add `Localizable.xcstrings` with German as the source language.
- Move user-facing labels, empty states, errors, confirmations, accessibility
  labels, and formatted messages into the catalog.
- Use typed or structured formatting for counts, dates, currencies, and values;
  avoid constructing sentences by concatenating localized fragments.
- Leave API field names, persistence keys, notification names, accessibility
  identifiers, and server error payloads unchanged.
- Add English only as a separate, reviewed product decision rather than as
  machine-generated placeholder translations.

### Acceptance criteria

- No significant user-facing copy remains hardcoded outside previews and test
  fixtures.
- German wording and pluralization are reviewed in every main flow.
- Long localized strings and accessibility text sizes do not truncate controls.
- The iOS 27 build and full test suite remain green.

## 3. Design a richer regular-width iPad experience

**Priority:** Deferred
**Status:** Requires explicit product/design approval

The current implementation constrains primary content to a readable width but
does not introduce tab-specific grids, dashboards, or two-pane navigation. A
previous split-view implementation was intentionally reverted because it did
not fit the visual design. Do not begin this work as a mechanical layout port.

The historical investigation and possible phases are documented in
[`ipad-optimization-plan.md`](ipad-optimization-plan.md).

### Decision required

- Approve representative wireframes for Fuel, Workshop, Service, and Parts.
- Decide whether the goal is centered readable columns, richer dashboards, or
  persistent list/detail navigation.
- Confirm which iPad-native features are in scope: hardware keyboard, pointer,
  popovers, scanner rotation, and multi-window support.

### Implementation constraints

- Adapt using size classes, not device checks, so Split View and Stage Manager
  widths behave correctly.
- Keep `NavigationStack` and the existing tab/status-accessory behavior unless
  an approved prototype proves a structural change is worthwhile.
- Preserve the compact iPhone layout and avoid fixed screen-size assumptions.
- Follow the iOS 27 `@State` initialization rule documented in `AGENTS.md`.

### Acceptance criteria

- Approved layouts are verified on iPad Pro and iPad mini in portrait,
  landscape, Split View, and Stage Manager widths.
- All four tabs use regular-width space intentionally without looking like a
  stretched phone or adding visually empty panes.
- Quick actions, motorcycle switching, sheets, sync status, and navigation
  state continue to work at every supported width.
- iPhone behavior is unchanged and the iOS 27 build/test suite remains green.
