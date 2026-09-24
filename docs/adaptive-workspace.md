# Adaptive motorcycle workspace

Implemented from the September 2026 UX review and approved photo-header mockup.

- The selected motorcycle's photo, name, plate, mileage and switcher stay above
  the scrolling content. Refreshed fleet metadata updates the header without
  discarding the current record or list position. The photo extends behind the
  top safe area while controls remain below it. Short landscape windows use a
  smaller, single-row motorcycle header. Compact layouts omit redundant
  content titles. Expanded list headings and the single search field are
  ordinary list rows, so both scroll away with the records.
- The content scrolls beneath the header and drives its collapse point for
  point: over the first ~140 points the name, the switcher pill and the
  actions move into a single row, so the header follows the finger and its
  controls never swap or flash. Scrolling back to the top restores the photo
  header. Every list ends with a room row worth the collapse distance, so a
  list that just fills the screen still collapses fully; a list much shorter
  than the screen collapses partially. Wide layouts keep the header static,
  since two columns would fight over it.
- Native tabs adapt to an optional iPad sidebar. Fuel, maintenance, parts and
  storage locations use list/detail columns on wide layouts; compact windows
  push the record full screen over the motorcycle header with native back
  navigation. The new fuel entry form and the motorcycle switcher stay sheets. Expanded details have a visible “Zur Übersicht” text-and-arrow
  button inside the pane, including on Duo where native toolbar controls move
  into a side rail. Switching motorcycles resets record selection.
- Fuel has a larger consumption overview on wide screens. Maintenance pairs
  its history with intervals and open issues. Technik exposes searchable
  categories and keeps an opened document alongside the reference list.
- Expanded fuel history contains only entries; its statistics and chart live
  in the right-hand overview. Maintenance similarly keeps statistics and
  service intervals in its overview, and does not repeat issues when the
  issues list is selected. Compact layouts retain their inline summaries.
  Technik's overview omits pressure values or details when that category is
  already visible in the reference list. Parts inventory totals remain
  distinct from the selected part's stock details.
- Statistics use plain adaptive surfaces. Inventory labels distinguish the
  filtered count from the complete inventory. Empty states provide actions.
- Fuel entry uses native text fields, preserves complete values on focus,
  offers previous/next/done keyboard controls, and keeps Save/Cancel available.
  Add forms have comfortable maximum widths and Command-N/Command-S/Escape
  shortcuts where applicable.
- Large text reflows statistics and segmented controls vertically. Login is
  centered vertically when the window has room.

## Verification

The `MotoManager` scheme runs the Swift Testing unit suite, including motorcycle
selection regression tests. The separate `MotoManager-UI` scheme runs XCUITest.
Its workspace tests are opt-in: supply
`MM_UI_TEST_SERVER`, `MM_UI_TEST_USER`, and `MM_UI_TEST_PASSWORD` through the test
runner environment. Use a seeded account with fuel history and at least two
motorcycles to exercise all assertions. The test opens and cancels forms; it
never saves or deletes server records.

`testAdaptiveWorkspaceAndFuelEditing` checks compact back/reopen navigation, persistent motorcycle
context, existing and newly seeded fuel values, all four tabs, and motorcycle
switching. Screenshot attachments capture the screens. Optional
`MM_UI_TEST_LARGE_TEXT=1` exercises accessibility text sizes. Set the simulator
appearance to dark before running to check dark surfaces. The test starts the
app in portrait orientation.

`testPartsSearchAcrossLayouts` checks that only one search field is visible in
portrait and landscape, that the query survives rotation, and that filtering
and clearing it update the list. It also checks that the heading and search
scroll away. It uses the same seeded account and makes no server changes.

`testWorkspaceInformationIsNotDuplicated` checks fuel summaries through
rotation, smaller landscape headers, record selection and the visible return
to the overview, as well as maintenance
intervals, issues and technical reference categories. Set
`MM_UI_TEST_EXPANDED=1` for the unfolded Duo; iPad runs expect expanded layouts
automatically. Run without this flag on a compact iPhone to check that its
inline summaries remain available.

Verified on 21 September 2026 with Xcode 27 / iOS 27: all 107 unit tests
passed, as did the workspace smoke checks on iPhone 17 Pro and iPad Pro
13-inch (M5). The iPhone check also passed in dark appearance at the largest
accessibility text size. Native screenshots are in
[`design/implementation/`](../design/implementation/README.md).

UI checks also passed on iPhone Duo with Xcode 27.1 beta / iOS 27.1, including
the launch appearance/orientation variants. The smoke test uses the visible
overview button in expanded Duo layouts and the native Back button in compact
layouts, including system controls outside `NavigationBar`.
The parts-search regression reproduced two visible fields before the fix and
passed afterward on Duo and iPhone 17 Pro, including rotation and clearing.

The subsequent summary-deduplication and scrolling-header checks passed on
unfolded iPhone Duo (iOS 27.1), iPad Pro 13-inch (M5), and iPhone 17 Pro
(iOS 27). They cover scrolling headings/search, one search field through
rotation, the condensed landscape header, and returning from expanded fuel
details to the overview. The compact iPhone workspace/editing smoke test also
passed after these changes. Updated screenshots are linked from the design
implementation README.

Known validation limitation: SwiftUI emits an `Invalid frame dimension
(negative or non-finite)` runtime warning when opening the fuel editor. The
simulator checks pass and the captured form has no visible clipping at normal
text size; the source of the warning is not yet isolated.

Use Xcode 27 / iOS 27. For CLI runs, unset Nix's `LD`, `LD_FOR_TARGET`, and
`SDKROOT` and set `DEVELOPER_DIR` to the installed Xcode Developer directory.

Physical hardware keyboard and pointer behavior, camera rotation, and actual
Stage Manager window resizing remain manual device checks. Multi-window and
scanner internals were not changed by this design implementation.
