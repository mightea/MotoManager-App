# TODO: App-Store-Einreichung

Stand 2026-11-10. TestFlight läuft seit v0.1.0 automatisch; Listing-Texte,
Screenshots, Datenschutzerklärung und Review-Hinweise liegen im Repo
(`appstore/`, `PRIVACY.md`) und werden von `appstore.yml` hochgeladen.
Übrig bleiben die Schritte, die nur im Browser gehen.

## Version & Build (auch die Ursache für das fehlende App-Icon)

Das App-Icon im App Store Connect kommt nicht aus dem Listing, sondern aus
dem Build, der an die App-Store-Version gehängt ist. Version «1.0» hat noch
keinen Build → Platzhalter-Raster. Builds sind nur auswählbar, wenn ihre
Marketing-Version exakt dem Versions-String entspricht; alle TestFlight-
Builds sind bisher `0.x.y`, deshalb ist die Build-Liste leer bzw. ausgegraut.
Das Icon selbst ist in Ordnung: `MotoManager/AppIcon.icon` (Icon Composer,
Liquid Glass) plus 1024-px-Fallbacks in `Assets.xcassets/AppIcon.appiconset`,
und jeder TestFlight-Upload wurde von Apple akzeptiert (ITMS-90704 bliebe
sonst nicht aus).

- [x] **Versions-String an den Build angleichen (2026-11-10):** jeder
      Lauf von `appstore.yml` nimmt den neuesten `v*`-Tag als Versions-String,
      benennt die vorbereitete Version entsprechend um (ASC erlaubt nur eine
      bearbeitbare Version) und hängt den neuesten verarbeiteten Build dieser
      Version an – damit erscheint auch das Icon. Nach einem neuen Release-Tag
      genügt ein Push auf `appstore/**` oder ein manueller Dispatch.
- [ ] Optional für einen «1.0»-Launch: Commit mit Footer `Release-As: 1.0.0`
      auf `main`, Release-PR mergen → Tag `v1.0.0` → TestFlight-Build, dann
      den Dispatch mit `version=1.0.0` wiederholen (oder einfach pushen –
      der Tag ist dann der neueste). (Die
      `MARKETING_VERSION = 1.0` im Projekt ist nur der Debug-Wert; CI setzt
      sie aus dem Tag.)

## App Store Connect – einmalig von Hand

- [ ] **App Privacy** (App Information → App Privacy): «Data Not
      Collected» – die App sendet alles ausschliesslich an den vom Nutzer
      selbst betriebenen Server; der Entwickler erhebt nichts (siehe
      PRIVACY.md). Standort/Fotos werden nicht an uns übermittelt.
- [ ] **Altersfreigabe** (Age Rating): Fragebogen durchgehen → 4+.
- [ ] **Kategorie:** primär *Utilities* (alternativ *Lifestyle*), sekundär
      optional *Productivity*.
- [ ] **Copyright:** `2026 Tobias Herrmann`.
- [ ] **Preis:** kostenlos (Preisstufe 0). Verfügbarkeit ist repo-verwaltet
      (`appstore/availability.txt` → nur Schweiz, «in neuen Ländern
      verfügbar» aus) – im Browser nur kontrollieren.
- [ ] **App Review Information → Kontakt:** Name, Telefon, E-Mail. Entweder
      einmal von Hand in App Store Connect eintragen oder als Secrets im
      Environment `testflight` hinterlegen (`gh secret set --env testflight
      ASC_REVIEW_CONTACT_FIRST_NAME` usw.). Ohne Kontakt lehnt ASC jede
      Änderung der Review-Details ab – der Lauf vom 2026-11-10 hat deshalb
      nur Notizen und Demo-Account vom ersten Lauf drin, Updates folgen
      sobald der Kontakt existiert. Demo-Account und Hinweise kommen aus
      `appstore/review/`.
- [ ] **Build prüfen:** nach dem Dispatch zeigt die Version den Build und
      das Icon; sonst von Hand den TestFlight-Build der Zielversion wählen.
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

- Das Secret `DEFAULT_SERVER_URL` im Environment `testflight` wird seit
  2026-11-10 nicht mehr gelesen (Builds enthalten keine Server-Adresse mehr)
  → löschen: `gh secret delete DEFAULT_SERVER_URL --env testflight`.

- Jährlich: Distribution-Zertifikat und Provisioning Profile laufen zusammen
  ab → neues `.p12`/Profil exportieren, `DIST_CERT_P12`,
  `DIST_CERT_PASSWORD`, `DIST_PROFILE_B64` aktualisieren.
- Nie `pull_request_target`- oder `issue_comment`-getriggerte Workflows in
  dieses (öffentliche) Repo aufnehmen – klassischer Secret-Leak-Vektor.
- Debug-Builds auf dem Gerät: persönliches Team, keine Associated Domains →
  Passkeys funktionieren dort nicht, Passwort-Login nutzen.
