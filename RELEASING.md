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
   `https://moto.herrmann.ltd/.well-known/apple-app-site-association` must
   list the paid team's prefix: `<TeamID>.ltd.herrmann.MotoManager`.
   Without this, passkey login fails in TestFlight builds.

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

## Annual chore

The Apple Distribution certificate expires after one year. Re-export a new
`.p12` (step 3) and update `DIST_CERT_P12` / `DIST_CERT_PASSWORD`.
