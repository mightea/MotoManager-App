# TODO: App-Store-Einreichung

Stand 2026-11-10. TestFlight läuft seit v0.1.0 automatisch; Listing-Texte,
Screenshots, Datenschutzerklärung und Review-Hinweise liegen im Repo
(`appstore/`, `PRIVACY.md`) und werden von `appstore.yml` hochgeladen.
Übrig bleiben die Schritte, die nur im Browser gehen.

## Version

- [ ] **Versionsnummer festlegen.** release-please zählt bei `0.x` weiter
      (nächste wäre 0.20.0). Für einen 1.0-Launch einen Commit mit Footer
      `Release-As: 1.0.0` auf `main` pushen, Release-PR mergen → Tag
      `v1.0.0` → TestFlight-Build mit `MARKETING_VERSION=1.0.0`.
- [ ] **App-Store-Version anlegen:** `appstore.yml` manuell mit
      `version=1.0.0` dispatchen (legt die Version an und spielt Metadaten,
      Review-Hinweise und Screenshots ein). Danach reicht jeder Push auf
      `appstore/**`.

## App Store Connect – einmalig von Hand

- [ ] **App Privacy** (App Information → App Privacy): «Data Not
      Collected» – die App sendet alles ausschliesslich an den vom Nutzer
      selbst betriebenen Server; der Entwickler erhebt nichts (siehe
      PRIVACY.md). Standort/Fotos werden nicht an uns übermittelt.
- [ ] **Altersfreigabe** (Age Rating): Fragebogen durchgehen → 4+.
- [ ] **Kategorie:** primär *Utilities* (alternativ *Lifestyle*), sekundär
      optional *Productivity*.
- [ ] **Copyright:** `2026 Tobias Herrmann`.
- [ ] **Preis & Verfügbarkeit:** kostenlos, alle Länder (oder nur CH/DE/AT –
      das Listing ist nur Deutsch).
- [ ] **App Review Information → Kontakt:** Name, Telefon, E-Mail eintragen
      (bleibt absichtlich nicht im Repo). Demo-Account und Hinweise kommen
      aus `appstore/review/`.
- [ ] **Build auswählen:** den TestFlight-Build der Zielversion an die
      App-Store-Version hängen.
- [ ] **Anmelden-Hinweis prüfen:** Guideline 5.1.1 verlangt, dass eine
      Login-Pflicht begründet ist – die Beschreibung sagt es (eigener Server),
      die Review-Notes erklären es dem Reviewer nochmals.

## Vor dem Absenden

- [ ] Demo-Server `https://moto-api-demo.herrmann.ltd` erreichbar und
      `admin-demo` / `demo-admin-2026` funktioniert (Reviewer loggen sich
      damit ein; Server nicht während der Review neu seeden).
- [ ] Listing im App Store Connect einmal durchlesen (Umbrüche, Umlaute).
- [ ] **Submit for Review.** Bei «Metadata Rejected» Texte im Repo anpassen
      und pushen – die Version bleibt bearbeitbar.

## Merkzettel

- Jährlich: Distribution-Zertifikat und Provisioning Profile laufen zusammen
  ab → neues `.p12`/Profil exportieren, `DIST_CERT_P12`,
  `DIST_CERT_PASSWORD`, `DIST_PROFILE_B64` aktualisieren.
- Nie `pull_request_target`- oder `issue_comment`-getriggerte Workflows in
  dieses (öffentliche) Repo aufnehmen – klassischer Secret-Leak-Vektor.
- Debug-Builds auf dem Gerät: persönliches Team, keine Associated Domains →
  Passkeys funktionieren dort nicht, Passwort-Login nutzen.
