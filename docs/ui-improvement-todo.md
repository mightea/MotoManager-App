# UI Improvement TODO

Remaining proposals from the November 2026 iOS UI review. The first batch
shipped in the same session (see "Done" at the bottom); everything below is
open and roughly ordered by value. Items marked **(needs backend)** require an
API change first — the API must stay backwards compatible (additive only).

## Additions

### Widgets and Control Center controls
**Why:** the two highest-frequency actions ("Tankung erfassen", "Etikett
scannen") already exist as App Intents; a Control Center control and a
lock-screen/home widget (next due interval, last consumption) would make them
reachable without opening the app.
**Why deferred:** needs a new Widget Extension target with its own bundle id
and App Group. CI signs manually with a single App Store provisioning profile
(`DIST_PROFILE_B64`), so a second profile for the extension has to be created
in the developer portal and added to the `testflight` environment first,
otherwise the TestFlight pipeline breaks on the next tag. Plan:
1. Create the App ID `ltd.herrmann.MotoManager.Widgets` + App Group
   `group.ltd.herrmann.MotoManager`, issue a profile, add it as a second
   secret, extend `testflight.yml` export options.
2. Add the extension target (pbxproj edit — synchronized groups don't cover
   new targets), share the SwiftData store via the App Group.
3. `ControlWidget`s for the existing intents; a timeline widget fed from the
   insights engine.

### Expenses (Ausgaben)
Server and webapp track non-maintenance costs (insurance, tax, gear). iOS has
no UI for it, so every cost figure on iOS is incomplete. Needs a list +
form per bike (and fleet-wide), ideally as a section on the Wartung tab or a
sub-screen from the garage.

### Fuel stop map
Fuel records carry coordinates and MapKit is already used on the detail pages.
A map of all stops per year in the fuel overview (iPad) / a pushed page on
iPhone; `GET /api/map` can supply tours later.

### Quick odometer update
The only ways to advance the odometer are a fuel or maintenance record. A
single-field sheet (with the camera scanner) for "just rode, no fill". Server
side the `manualOdo` field on the motorcycle already exists (multipart PUT).
Pair with an "Kilometerstand erfassen" App Intent.

### Previous owners and fleet statistics
Both exist on the server and in the webapp. Previous owners fit the Technik tab
as a history section; fleet statistics (`/api/stats/fleet`) fit the garage sheet.

### Spotlight indexing of parts
Index name + part number (`CSSearchableItem`) so a number from an invoice finds
the part from the home screen; route the result through the existing
`QuickActionRouter.openLabel`.

### Parameterized fuel intent
An `AddFuelIntent` variant with liters/price parameters so Shortcuts
automations can pre-fill the sheet.

## Improvements to existing screens

### Garage as an overview
Rows show year/km/plate only, though the DTO carries `openIssues`,
`maintenanceCount` and `latestOdo`. Show open-issue / overdue-interval badges
per bike and a small fleet summary at the top (km this year, costs this year,
open issues), mirroring the webapp home dashboard. Intervals per bike need the
bike's records locally (pulled on first visit) — compute from SwiftData.

### Motorcycle edit — remaining fields
The new edit sheet covers identity, registration numbers, tank, currency,
flags and photo. Still webapp-only: first registration, purchase date/price,
brake/drive types, lifecycle (sold: date, price, buyer, odo), unknown-owners
flag, removing a photo (**needs backend**: the multipart update can't clear
`image`).

### Wartung stat tiles
Fuel uses rolling 12 months, maintenance costs use the calendar year, and
"Letzte Wartung" duplicates the first list row. Replace it with "Nächste
Fälligkeit" (from the insights) and align both tabs on one period.

### Reminders — coverage
Reminders are scheduled per bike when its Wartung tab is on screen. Extend to
every bike whose records are already local (iterate SwiftData on app start),
add MFK/inspection due dates (needs an inspection interval rule, webapp has
none yet), and a "snooze" action on the notification.

### Fuel list
The pump icon on every row carries no information: use the slot for a
per-row consumption bar or the day of month. Add per-year totals (km, liters,
cost) to the section headers. On iPhone, tapping the sparkline should push a
full statistics page (the iPad overview chart already exists).

### Fuel sheet — hidden fields
Fuel type and notes round-trip untouched but cannot be set. A "Mehr"
disclosure for both keeps the fast path short.

### Documents
Only Files import today. Add photo library and document camera capture
(`VNDocumentCameraViewController`), plus rename, delete and share in the tile
context menu (**rename/delete need backend** endpoints — check
`handlers/documents.rs` for PUT/DELETE first).

### Parts — low stock and sorting
Zero on-hand only dims the number. Add a reorder threshold per part
(**needs backend** column), a "Nachbestellen" chip, sort options (name, stock,
recently used). The inventory-value tile hard-codes CHF.

### Settings
Now: server, sync, intervals, reminders, MCP tokens, logout. Still missing:
account name/password change (`PUT /api/settings/password` exists), default
currency, appearance override.

### Consistency
- Three chip styles (glass torque chips, flat history chips, series chips)
  should become one component.
- App Store screenshots still show "Werkstatt"/"Service" tab labels and a
  Veteran badge in the header; regenerate with `scripts/make-screenshots.sh`
  (and decide whether the Veteran badge should return to the header).
- String catalog + iPad polish: tracked in `improvement-backlog.md`.

## Done (November 2026)

- Motorcycle edit sheet with photo (library/camera), VIN scan + server decode
  (series link), delete with full-history warning. Entry points: header name,
  Technik "Fahrzeug" section, garage row swipe/context menu.
- Universal links: `applinks:moto.herrmann.ltd` entitlement + AASA `applinks`
  section in the webapp; `/parts/<id>` and `/storage-locations/<id>` open the
  record in the app via `QuickActionRouter.openLabel`. Apple's CDN caches the
  AASA, so reinstall the app (or wait ~24 h) after the webapp deploy.
- Service intervals from `GET /api/settings` (years + km rules, cached
  offline), editor in Settings, km verdicts on the intervals card.
- Local reminders (opt-in) for due-window and due-date per tracked item.
- Issue lifecycle: swipe/menu done + reopen, collapsed "Erledigt" section,
  "Als Wartung erfassen" (repair entry pre-filled from the defect, closes it).
- "Mangel erfassen" App Shortcut.
