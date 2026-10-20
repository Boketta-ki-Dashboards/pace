# Manuelle Tests auf dem iPhone

Die automatisierten Tests laufen in der CI (Simulator, Linux, lokaler Supabase-Stack). Ein Test auf einem echten
iPhone war aus der Entwicklungsumgebung **nicht möglich** – HealthKit-Daten, App-Icon-Wechsel, Mitteilungen,
Fotoauswahl, Drag & Drop und Echtzeit-Chats zwischen zwei Geräten lassen sich nur auf Geräten prüfen. Diese Liste
deckt genau diese Punkte ab.

## Vorbereitung

1. Stand holen, Xcode öffnen und auf das iPhone installieren: Schritt für Schritt in
   [IPHONE_TEST.md](IPHONE_TEST.md). Einmal **Product → Clean Build Folder**, damit die App-Icons sicher im Build
   landen. Signing, Personal Team, Bundle Identifier und `Config/Pace.xcconfig` bleiben unverändert.
2. Backend: Abschnitte A–D funktionieren mit dem heutigen Produktivstand. Abschnitt E (Freunde, Gruppen, Chats,
   Profilbild, Blockieren/Melden, Export, Konto löschen) braucht die sechs Migrationen aus
   [SUPABASE_ROLLOUT.md](SUPABASE_ROLLOUT.md) – sie werden erst nach ausdrücklicher Freigabe eingespielt. Bis dahin
   zeigt die App dort einen ehrlichen Hinweis („… auf dem Server noch nicht eingerichtet“).
3. App auf dem iPhone starten (nicht im Simulator – dort gibt es keine echten Schritte).

## A. Grundgerüst, Darstellung, Sprache

- [ ] Tab-Leiste: Home · Rankings · Social · Profil; der aktive Tab zeigt Symbol **und** Text in einer mint Fläche.
- [ ] Profil → Darstellung → Automatisch / Hell / Dunkel wirkt sofort und bleibt nach einem Neustart erhalten.
- [ ] Profil → Darstellung → App-Icon → **Dunkel**: iOS zeigt seinen Hinweis „Du hast das Symbol … geändert“, das
      Icon ist danach mint auf dunklem Grund. **Hell** und **Automatisch** ebenso.
- [ ] Profil → Sprache → English bzw. Русский: alle Tabs wechseln sofort (Zahlen 8,432 bzw. 8 432, Datumsangaben,
      russische Pluralformen). Zurück auf Deutsch bzw. „Wie iPhone“.
- [ ] Unterseiten haben überall denselben Kopf: „‹ Zurück“ → pace → Titel; nichts wird abgeschnitten.

## B. Home, Anpassen-Modus, Widget-Galerie (Bilder 6, 7, 9)

- [ ] Home: vier Regionskarten in **einer** Reihe, „Deine Schritte heute“, „Deine Woche“, Umfeld mit
      „Noch x Schritte bis Platz #n“. Werte stimmen mit der Health-App überein (ohne manuell eingetragene Schritte).
- [ ] Glocke: Mitteilungen nur aus echten Daten (Anfragen, Einladungen, ungelesene Chats), sonst „Alles gelesen“.
- [ ] „Anpassen“: Widgets wackeln dezent, X entfernt (mit „Rückgängig“), „Deine Schritte heute“ hat kein X.
- [ ] „Größe auswählen“: Klein / Mittel / Groß / Max – das Widget ändert sich sofort.
- [ ] Widget am Griff (sechs Punkte) halten und verschieben; Ablegen außerhalb beendet das Ziehen sauber.
- [ ] „+ Widget hinzufügen“ → Galerie: Kategorie, Auswahl (z. B. zwei verschiedene Freunde-Widgets), Live-Vorschau,
      Größe → „Widget hinzufügen“. „Fertig“ beendet den Modus. Nach App-Neustart ist alles gespeichert.
- [ ] Profil → „In regionalen Rankings erscheinen“ aus: Ranking-Widgets zeigen unscharfe Platzhalter mit
      „Ranking ausgeschaltet“; „Ranking-Sichtbarkeit aktivieren“ schaltet es nach Bestätigung wieder ein.

## C. Kalender, Tagesdetails, Statistik, Serie (Bilder 8, 9)

- [ ] Home → Kalender-Symbol: Monat mit Mo–So, erreichte Tage grün gefüllt, sonst Ring mit Fortschritt, heute
      umrandet, Zukunft neutral mit „–“. Pfeile blättern zurück, nicht über den aktuellen Monat hinaus.
- [ ] Tag antippen → Karte darunter; Karte antippen → **Tagesdetails**: Ring, Schritte, „Tagesziel an diesem Tag“,
      Distanz, Aktiv-kcal, Stockwerke, Trainingsminuten, Aktivität im Tagesverlauf, Serie, letzte 7 Tage.
- [ ] Tagesdetails → „Puls aus Apple Health anzeigen“: iOS fragt einmalig nach Ruhepuls/Geh-Puls; danach erscheinen
      die Werte (nur wenn Apple Health welche hat). Beim normalen App-Start wird nie danach gefragt.
- [ ] Home → Schrittkarte bzw. Woche → Statistik Tag/Woche/Monat; ohne Apple Watch bzw. Stockwerk-Daten steht dort
      „nicht verfügbar“, nicht „0“.
- [ ] Ein Schritt-Eintrag von Hand in der Health-App zählt **nicht** für Ziel, Serie und Rankings.
- [ ] Tagesziel ändern: gilt ab heute; Kalender und Serie bewerten Vortage weiter mit dem damaligen Ziel.
- [ ] Serie: Ist das Ziel heute noch offen, bleibt die bisherige Serie stehen; nach Erreichen steigt sie um 1.

## D. Rankings, Profil, Mitteilungen

- [ ] Rankings: Stadt, Landkreis, Bundesland, Deutschland, Freunde, Gruppen; eigene Zeile dezent grün.
- [ ] Profil → Mitteilungen → „Erinnerung an dein Tagesziel“ zu einer Uhrzeit: iOS fragt nach Erlaubnis; die
      Erinnerung kommt nur, wenn das Ziel an dem Tag noch offen ist.
- [ ] Profil → Region ändern, Tagesziel, Hilfe & Feedback, Rechtliches (Entwürfe, vom Betreiber zu ergänzen).

## E. Erst nach Freigabe und Einspielen der Migrationen (zwei Geräte oder zwei Testkonten)

- [ ] Social → „Freund hinzufügen“: Benutzernamen tippen (Treffer ab drei Zeichen), „Hinzufügen“; auf dem
      zweiten Gerät unter „Freundschaftsanfragen“ annehmen bzw. ablehnen.
- [ ] Freund öffnen → „Nachricht schreiben“: Text, Foto und GIF aus der Mediathek senden; auf dem zweiten Gerät
      erscheint alles ohne Neuladen, der Ungelesen-Zähler im Social-Tab steigt und fällt beim Öffnen.
- [ ] „Gruppe erstellen“ mit Bild, Typ, Privatsphäre, Einladungen (höchstens 30) und Tagesziel → Gruppendetails mit
      Gruppen-Streak und Ranking → Gruppenchat. Beitritt per Einladung bzw. Code auf dem zweiten Gerät.
- [ ] „…“-Menü: Profil teilen (an einen Chat oder per iOS-Teilen), Nutzer blockieren (Privatchat danach
      schreibgeschützt, Gruppennachrichten eingeklappt), Nutzer, Gruppe bzw. Nachricht melden.
- [ ] Profil → Konto & Profil: Name und Profilbild ändern; Profil-Link `pace://u/…` öffnet auf dem zweiten Gerät das
      Profil.
- [ ] Profil → Privatsphäre: Auffindbarkeit aus → das Profil fehlt in der Suche nach Namensanfängen; mit dem
      exakten Benutzernamen bleibt es auffindbar.
- [ ] Profil → Datenschutz & Daten → „Export erstellen“ (JSON-Datei über iOS-Teilen). „Konto löschen“ nur mit einem
      **Testkonto** – es löscht wirklich alles.

## F. Aktualisierung und Akku

- [ ] App offen lassen und gehen: Die Schrittzahl steigt ohne Pull-to-Refresh (iOS liefert iPhone-Schritte
      gebündelt, meist alle paar Minuten; Apple-Watch-Schritte teils später).
- [ ] App in den Hintergrund und zurück: Schritte, Platzierungen und Chats werden aktualisiert.

## Bekannte Grenzen

- Schritte kommen vom Gerät; das System ist nicht vollständig manipulationssicher (siehe `docs/SOCIAL.md`).
- Das Pace-Konto ist an das iPhone gebunden (anonyme Anmeldung, „Mit Apple anmelden“ ist nicht eingebaut). Serie,
  Rekord, Tagesziel und Home-Layout liegen nur auf dem Gerät.
- Push-Mitteilungen bei neuen Chatnachrichten gibt es nicht (dafür wäre ein APNs-Schlüssel nötig); neue Nachrichten
  erscheinen, solange Pace geöffnet ist, und als Zähler beim nächsten Öffnen.
- Lesebestätigungen („gelesen“) werden nicht angezeigt.
