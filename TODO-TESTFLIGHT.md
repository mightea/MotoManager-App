# TODO: Erste TestFlight-Veröffentlichung

Stand 2026-07-10. Pipeline, Repo-Härtung und Push sind erledigt — es fehlen
nur noch die manuellen Schritte, die Apple-Zugang bzw. Keychain brauchen.
Details zu jedem Schritt: [RELEASING.md](RELEASING.md).

## Apple Developer / App Store Connect

- [ ] **Bundle-ID registrieren**: developer.apple.com → Identifiers → `+` →
      `ltd.herrmann.MotoManager`, dabei **Associated Domains** aktivieren
- [ ] **App-Eintrag anlegen**: App Store Connect → Apps → `+` → New App
      (iOS, obige Bundle-ID, beliebige SKU)
- [ ] **ASC-API-Key erstellen**: Users and Access → Integrations →
      App Store Connect API → `+`, Rolle **App Manager**.
      `AuthKey_XXXX.p8` herunterladen (einmaliger Download → Passwortmanager),
      Key ID + Issuer ID notieren
- [ ] **Distribution-Zertifikat**: Xcode → Settings → Accounts → (bezahltes
      Team) → Manage Certificates → `+` → Apple Distribution; dann in
      Keychain Access als `.p12` mit starkem Passwort exportieren

## GitHub (Repo `mightea/MotoManager-App`)

Alles in **Settings → Environments → `testflight`** eintragen
(Environment existiert schon, mit Required Reviewer + `v*`-Tag-Beschränkung —
**nicht** als Repo-Secrets anlegen):

- [ ] Secret `ASC_API_KEY_ID`
- [ ] Secret `ASC_API_ISSUER_ID`
- [ ] Secret `ASC_API_KEY_P8` — base64: `base64 -i AuthKey_XXXX.p8 | pbcopy`
- [ ] Secret `DIST_CERT_P12` — base64: `base64 -i cert.p12 | pbcopy`
- [ ] Secret `DIST_CERT_PASSWORD`
- [ ] Variable `APPLE_TEAM_ID` — ID des **bezahlten** Teams (Membership-Seite),
      nicht das persönliche Team der Debug-Builds

## Server

- [ ] **AASA aktualisieren**: `https://moto.herrmann.ltd/.well-known/apple-app-site-association`
      muss den Prefix des bezahlten Teams listen:
      `<TeamID>.ltd.herrmann.MotoManager` — sonst schlägt Passkey-Login
      in TestFlight-Builds fehl

## Erster Release

- [ ] `git tag v1.0 && git push origin v1.0`
- [ ] Run in GitHub Actions freigeben (Environment-Approval, ein Klick)
- [ ] Nach Apples Processing: App Store Connect → TestFlight → Build einer
      Tester-Gruppe zuweisen (Export-Compliance ist per
      `ITSAppUsesNonExemptEncryption=false` schon beantwortet)

## Merkzettel

- Jährlich: Distribution-Zertifikat läuft nach 1 Jahr ab → neues `.p12`
  exportieren, `DIST_CERT_P12`/`DIST_CERT_PASSWORD` aktualisieren
- Der GitHub-PAT (`GH_SOURCE_PAT`) läuft am **2026-08-31** ab
- Nie `pull_request_target`- oder `issue_comment`-getriggerte Workflows in
  dieses (öffentliche) Repo aufnehmen — klassischer Secret-Leak-Vektor
- Debug-Builds auf dem Gerät: persönliches Team, keine Associated Domains →
  Passkeys funktionieren dort nicht, Passwort-Login nutzen
