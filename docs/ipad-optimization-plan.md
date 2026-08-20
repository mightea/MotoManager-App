# iPad Optimization Plan

*Status: **implemented** (Phases 1–3 plus parts of 4) — 2026-08-20, commits `ef99710` and `e03977f`. Originally proposed the same day after verifying the app on an iPad Pro 13" (M5) simulator with seeded test data (local API) plus a full source survey.*

## Implementation status

- **Phase 1 — done.** `UI/AdaptiveLayout.swift` provides `.contentColumn()` (700 pt, Workshop 860 pt) and `.gridCardChrome()`; `glassSheet()` gained `presentationSizing(.form)`; the hero header and empty-fleet chrome lost their hardcoded status-bar guesses; documents grid is adaptive; all background halos are proportional.
- **Phase 2 — done, with two items resolved differently.** Fuel got a full `ConsumptionTrendChart` (area fill + y-axis) on regular width; Parts/locations/public render as 2-up card grids (delete via context menu); Workshop is a two-column card dashboard; detail maps/photos grew. 2.4 (garage grid) became unnecessary — the garage sheet is now a form sheet; 2.5 (stat strip) is solved by the content column cap rather than extra tiles.
- **Phase 3 — done for Fuel and Service.** `NavigationSplitView` on regular width with the compact list as sidebar, selection-driven detail column, selection cleared on local/synced delete, and detail pages keeping the top tab strip via the `keepsTabBar` environment key. **Parts still pushes full-screen** (two detail types — part and storage location — need an enum selection; follow-up).
- **Phase 4 — partially done.** ⌘N opens the fuel form (4.1, partial). Still open: the AddFuelView hidden-TextField keypad rework for hardware keyboards (4.1), pointer hover polish (4.2), popovers for print-label sheets (4.3), scanner rotation (4.4), multi-window (4.5).
- Verified on iPad Pro 13" (M5): all four tabs, both split views, form sheets; iPhone 17 Pro re-checked (compact unchanged); full test suite green. Not yet manually verified: iPad Split View/Stage Manager widths and landscape.

## Current state

iPad support is **already enabled** at the project level: `TARGETED_DEVICE_FAMILY = "1,2"`, all four iPad orientations allowed, and the app builds, installs, and runs on iPad simulators without changes. What's missing is any iPad-*aware* layout: there is not a single `horizontalSizeClass`, `userInterfaceIdiom`, or adaptive-column check in the SwiftUI layer. Every screen is the iPhone layout stretched to 1032 pt.

What that looks like in practice (screenshots in the session scratchpad):

- **Login** — the server/username/password fields span the full 1032 pt width.
- **All four tabs** — single-column `List(.insetGrouped)` rows with content pinned to the far left and far right edges and ~600 pt of dead space in between. The fuel sparkline is a fixed 150×34 pt speck at the far right.
- **StatStrip** — exactly 3 tiles, each stretched to ~330 pt wide holding a 17 pt number.
- **Hero header** — the 180 pt motorcycle photo band with a hardcoded `.padding(.top, 54)` status-bar guess; on iPad it's a thin letterbox.
- **Sheets** — `glassSheet()`'s `[.medium, .large]` detents are silently ignored on iPad (regular size class); every quick-add sheet opens as one fixed-size centered form sheet. The garage sheet happens to look acceptable.
- **One good surprise** — the native iOS 26 `TabView` renders as a floating top tab-strip on iPad and looks right without any work.

## Guiding decisions

1. **Size class, not idiom.** Branch on `@Environment(\.horizontalSizeClass)`, never `userInterfaceIdiom`. This makes Split View / Stage Manager correct for free: an iPad at compact width gets the (correct) iPhone layout.
2. **Keep the TabView.** The iOS 26 top tab-strip already reads natively on iPad. Do **not** rebuild navigation around a global `NavigationSplitView` sidebar in the first pass — it invalidates the `tabViewBottomAccessory` status bar and the quick-action routing for uncertain gain. Revisit only if Phase 2 proves insufficient.
3. **One shared primitive first.** Most of the waste is the same problem repeated: unconstrained width. A single `.contentColumn()` modifier (max content width ~700 pt, centered, wider gutters on regular width) fixes the majority of screens without per-view rewrites.

---

## Phase 1 — Foundations (small, low-risk, high leverage)

| # | Change | Files |
|---|--------|-------|
| 1.1 | Add `ContentColumn` modifier: on regular width, constrain content to a readable max width (~700 pt) and center it; no-op on compact. Apply to the four tab lists, `DetailPage`, `SettingsView`, `GarageView`. | new `UI/AdaptiveLayout.swift`; `FuelListView.swift`, `WorkshopView.swift`, `MaintenanceLogsView.swift`, `PartsView.swift`, `UI/DetailPage.swift` |
| 1.2 | Login: cap the form at ~560 pt, centered; keep the full-bleed photo. | `Views/LoginView.swift:50` |
| 1.3 | Sheet sizing: in `glassSheet()`, the detent design is dead on iPad — adopt `presentationSizing(.form)` (or `.fitted`) behind a size-class check so quick-add sheets get a sane fixed size instead of pretending detents exist. | `UI/SheetStyle.swift:13` |
| 1.4 | Fix the hardcoded chrome: replace `.padding(.top, 54)` in the hero header with real safe-area insets; same for the 110 pt empty-fleet bar. | `Views/MotorcycleSummaryHeader.swift:56`, `Views/MainTabView.swift:141` |
| 1.5 | Documents grid: swap the hardcoded 2 `.flexible()` columns for `GridItem(.adaptive(minimum: 200))`. | `Views/WorkshopView.swift:283` |
| 1.6 | Background halos: position the `LiquidBackgroundView` / login / splash halos proportionally instead of fixed offsets tuned to a 390 pt phone. | `UI/LiquidBackgroundView.swift:22-36`, `Views/LoginView.swift:106`, `Views/SplashScreenView.swift:73-83` |

**Exit criteria:** no screen shows full-width stretched form fields or edge-pinned row content on iPad; sheets open at a deliberate size.

## Phase 2 — Use the width (per-screen layout)

| # | Change | Files |
|---|--------|-------|
| 2.1 | **Fuel tab**: give the consumption trend real space on regular width — a proper chart section (Swift Charts) instead of the 150×34 pt sparkline; consider a two-column stat block (consumption trend + cost trend). Fuel rows stay in the content column. | `Views/FuelListView.swift:409`, header area |
| 2.2 | **Parts tab**: parts, storage locations, and public parts become a `LazyVGrid` of cards (`.adaptive(minimum: ~320)`) on regular width; keep list rows on compact. This is the single biggest visual win. | `Views/PartsView.swift:37-83` |
| 2.3 | **Workshop tab**: on regular width, lay the four sections out as a two-column dashboard (tire pressure + details left; torque specs + documents right) instead of one long scroll. | `Views/WorkshopView.swift:98-140` |
| 2.4 | **Garage**: bike picker becomes a card grid on regular width (52 pt thumbnails → cards with the bike photo). | `Views/GarageView.swift:59,191` |
| 2.5 | **StatStrip**: cap tile width so the strip hugs the content column; optionally show more tiles on regular width (the data exists — e.g. cost/month, total km). | `UI/StatStrip.swift:21-32` |
| 2.6 | **Detail pages**: maps and part photos get sane aspect ratios instead of `height: 160–180` full-width letterboxes; content column applies. | `Views/FuelDetailView.swift:115,222`, `Views/MaintenanceDetailView.swift:117`, `Views/PartDetailView.swift:145` |

**Exit criteria:** each tab visibly uses the extra width for information, not whitespace; nothing looks like a scaled-up phone screen.

## Phase 3 — Side-by-side navigation (the structural win)

On regular width, a tapped fuel entry currently replaces the whole 1032 pt screen with one narrow detail. All pushes are already value-driven `.navigationDestination(item:)` bindings — the easiest shape to port.

- 3.1 Introduce list + detail presentation per tab on regular width (selection-driven `NavigationSplitView` inside the tab, or a custom two-pane layout that preserves the glass look): Fuel list ↔ fuel detail, Service log ↔ maintenance detail, Parts grid ↔ part detail.
- 3.2 Keep `DetailPage`'s tab-bar hiding compact-only (`.toolbar(.hidden, for: .tabBar)` is a phone convention).
- 3.3 Re-check the `.id(dVM.motorcycle.id)` teardown and quick-action routing still behave with the new structure.

This phase is the most valuable *and* the most invasive — do it after Phases 1–2 have proven the primitives, and prototype on the Fuel tab first.

## Phase 4 — iPad-native polish

- 4.1 **Keyboard**: `AddFuelView`'s hidden zero-size `TextField` keypad trick (`AddFuelView.swift:284-306`) breaks with a hardware keyboard — replace with real focusable fields; add a keyboard-dismiss toolbar; add `⌘N`-style shortcuts for add-fuel / scan-part.
- 4.2 **Pointer**: `.hoverEffect` on tappable cards/rows.
- 4.3 **Popovers**: print-label and other small toolbar-anchored sheets become popovers on regular width (`PartDetailView.swift:79`, `StorageLocationDetailView.swift:69`).
- 4.4 **Camera rotation**: the odometer/label scanners (`Scanning/`) have no rotation handling; iPads live in landscape.
- 4.5 **Multi-window** (optional, last): requires de-singleton-ing `QuickActionRouter` and the passkey presentation-anchor lookup in `AuthViewModel.swift:165-177` before flipping `UIApplicationSupportsMultipleScenes`.

## Verification

- Build/test with the `env -u LD` wrapper; run on iPad Pro 13" (M5) and iPad mini (A17 Pro), portrait + landscape, plus 1/3-width Split View (compact) to prove the size-class branches.
- Drive UI with `idb ui tap/swipe` + `simctl screenshot` per screen; the seeded local-API scenario (scratch DB, user `tester`) reproduces all states.
- iOS 27 checklist still applies (no `@State` declaration-default + init double-set in any new adaptive views).

## Suggested order of implementation

Phase 1 in one PR (mechanical, reviewable). Phase 2 as one PR per tab. Phase 3 prototyped on Fuel, then rolled out. Phase 4 items are independent and can land anytime after Phase 1.
