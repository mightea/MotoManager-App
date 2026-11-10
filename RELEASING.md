# Releasing to TestFlight

Builds are uploaded by the GitHub Actions workflow
[`.github/workflows/testflight.yml`](.github/workflows/testflight.yml):
push a tag like `v1.2` (sets the marketing version) or run the workflow
manually. Unit tests run first; the archive job signs with cloud signing
(App Store Connect API key + a distribution certificate from secrets) and
uploads straight to App Store Connect.

## One-time setup

All steps below need your Apple account or GitHub admin access and can't be
automated.

### Apple Developer / App Store Connect

1. **App record** — App Store Connect → Apps → **+** → New App:
   platform iOS, bundle ID `ltd.herrmann.MotoManager` (register the bundle ID
   at developer.apple.com → Identifiers first if it isn't offered), any SKU.
   While registering the identifier, enable the **Associated Domains**
   capability on it.
2. **API key** — App Store Connect → Users and Access → Integrations →
   App Store Connect API → **+**. Role: **App Manager**. Download the
   `AuthKey_XXXX.p8` (single download — keep it in your password manager).
   Note the Key ID and the Issuer ID shown on that page.
3. **Distribution certificate** — on your Mac: Xcode → Settings → Accounts →
   (paid team) → Manage Certificates → **+** → Apple Distribution. Then in
   Keychain Access, export that certificate (with private key) as a `.p12`
   with a strong password.
4. **Associated domains / passkeys** — the AASA file served at
   `https://<MOTO_WEB_HOST>/.well-known/apple-app-site-association` must
   list the paid team's prefix: `<TeamID>.ltd.herrmann.MotoManager`.
   Without this, passkey login fails in TestFlight builds. `MOTO_WEB_HOST`
   is the deployed webapp's host; it is not kept in the repo (the committed
   `Supporting/Deployment.xcconfig` only holds an `example.com`
   placeholder). CI takes it from the `testflight` environment secret
   `MOTO_WEB_HOST`; for local builds put
   `MOTO_WEB_HOST = <host>` into the gitignored
   `Supporting/Deployment.local.xcconfig`.

### GitHub

5. Create the (private) repo and push this project; the workflow triggers on
   `v*` tags.
6. Settings → Environments → create **`testflight`** (optionally add
   yourself as required reviewer — uploads then need a manual approval).
   Add to that environment:
   - Secrets: `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`,
     `ASC_API_KEY_P8` (base64: `base64 -i AuthKey_XXXX.p8 | pbcopy`),
     `DIST_CERT_P12` (base64: `base64 -i cert.p12 | pbcopy`),
     `DIST_CERT_PASSWORD`
   - Variable: `APPLE_TEAM_ID` — the **paid** team's ID (Membership page),
     not the personal team that Debug builds sign with.

### Project

7. Debug builds keep signing with the personal team and the
   Debug-only entitlements (no Associated Domains — passkeys don't work in
   on-device Debug builds; use password login). Release signing on CI gets
   the team via the `APPLE_TEAM_ID` variable, so nothing in the project
   file needs to change.

## Releasing

```sh
git tag v1.2 && git push origin v1.2
```

Marketing version = tag without the `v`; build number = workflow run number
(unique across re-runs via the attempt suffix). After Apple finishes
processing (a few minutes), the build appears in App Store Connect →
TestFlight; add it to a tester group there. Export compliance is answered
by `ITSAppUsesNonExemptEncryption=false` in `Supporting/Info.plist`
(standard HTTPS only).

## App Store listing (metadata & screenshots)

The store listing lives in the repo and is pushed by
[`.github/workflows/appstore.yml`](.github/workflows/appstore.yml)
(via `scripts/appstore_assets.py`, authenticated with the same
`ASC_API_KEY_*` secrets — no signing material involved):

- **Metadata** — `appstore/metadata/de-DE/*.txt` (description, keywords,
  promo text, name/subtitle, support/marketing/privacy-policy URLs). Edit the
  files, push to `main`, done. `release_notes.txt` (optional) becomes the
  version's "What's New". The privacy policy URL points at
  [`PRIVACY.md`](PRIVACY.md) in this repo.
- **App Review** — `appstore/review/notes.txt` plus `demo_account.txt` /
  `demo_password.txt` (the public demo server's `admin-demo` account) fill
  the version's "App Review Information". Reviewers can't run a server, so
  the notes tell them to enter the demo server's address on the login
  screen. That address is not kept in the repo: `notes.txt` carries a
  `{{DEMO_SERVER_URL}}` placeholder that the push script fills from the
  `testflight` environment secret `DEMO_SERVER_URL` (the run aborts when it
  is missing). App Store Connect insists on the review contact
  (name/phone/email) with every update; it is personal data, so it comes
  from the optional `testflight` environment secrets
  `ASC_REVIEW_CONTACT_FIRST_NAME` / `_LAST_NAME` / `_PHONE` / `_EMAIL`, or
  from what is already stored in App Store Connect. Without either, the
  run logs a warning and leaves the review details alone.
- **Availability** — `appstore/availability.txt` lists the territories the
  app is sold in (ISO 3166-1 alpha-3; currently only `CHE`). Every other
  territory and "available in new territories" are switched off.
- **Screenshots** — `appstore/screenshots/de-DE/<DISPLAY_TYPE>/*.png`,
  uploaded in filename order, re-uploaded only when checksums change.
  Regenerate them locally with `scripts/make-screenshots.sh`: it builds the
  app and the UI-test bundle, fresh-installs on the iPhone 17 Pro, iPhone
  Air, iPhone Duo and iPad Pro 13-inch simulators, and runs the
  `AppStoreScreenshots` XCUITest (`MotoManagerUITests/`), which signs in to
  the live demo server (`DEMO_SERVER_URL`, required in the environment;
  account `admin-demo`, override via `DEMO_USER`/`DEMO_PASSWORD`), walks the
  tabs and writes pixel-exact PNGs. Slots: `APP_IPHONE_61` (1206×2622, the
  one Apple requires), `APP_IPHONE_67` (1260×2736), `APP_IPHONE_DUO`
  (1398×2034 outer display — the simulator can't be unfolded from the CLI
  on Xcode 27.1, so the inner 2007×2853 size is not shot; Duo screenshots
  become mandatory in April 2027 for iOS 27.1 SDK builds) and
  `APP_IPAD_PRO_3GEN_129` (2064×2752, required). Review the images, commit.
  No `idb` involved (it no longer works with Xcode 27).

Two one-time settings, both in the browser:

- The `testflight` environment must allow deployments from `main`
  (Settings → Environments → testflight → Deployment branches and tags),
  otherwise the workflow is rejected before it starts.
- App Privacy labels and the age rating are not in the public ASC API and
  stay manual in App Store Connect.

Metadata is only writable while a version is editable (Prepare for
Submission / rejected). Every run aligns the App Store version with the
builds: the version string defaults to the newest `v*` tag (which is the
`MARKETING_VERSION` of the TestFlight build), the single editable version
is renamed or created to match, and the newest processed build of that
version is attached — App Store Connect only offers builds whose version
matches, and the listing's icon comes from the attached build. A manual
dispatch can override the version (e.g. `1.0.0` after a `Release-As`
release) or skip the build attachment.

## Submitting to the App Store

Everything the repo can hold is in `appstore/`; the rest is a short manual
pass in App Store Connect — see [TODO-APPSTORE.md](TODO-APPSTORE.md) for the
checklist.

## Annual chore

The Apple Distribution certificate expires after one year. Re-export a new
`.p12` (step 3) and update `DIST_CERT_P12` / `DIST_CERT_PASSWORD`.
