# Nächster iPhone-Test – einfache Anleitung

Diese Anleitung setzt voraus, dass Pace schon einmal aus Xcode auf deinem iPhone lief (Personal Team, eigene
`Config/Pace.xcconfig` mit den Supabase-Werten). Daran ändert sich nichts: Signing, Bundle Identifier und deine
lokale Konfiguration bleiben, wie sie sind. `Config/Pace.xcconfig` ist von Git ausgeschlossen und wird beim
Aktualisieren nicht überschrieben.

## 1. Letzten Stand herunterladen

1. Öffne das Programm **Terminal** (Spotlight: ⌘ + Leertaste, „Terminal“ tippen, Enter).
2. Wechsle in deinen Pace-Ordner. Beispiel – passe den Pfad an, falls dein Ordner woanders liegt:
   ```
   cd ~/Developer/pace
   ```
3. Hole den neuen Stand (diese drei Zeilen nacheinander, jeweils mit Enter):
   ```
   git fetch origin
   git checkout claude/gallant-brahmagupta-hvvp13
   git pull origin claude/gallant-brahmagupta-hvvp13
   ```
   Meldet Git „Your local changes would be overwritten“, hast du lokal etwas geändert. Dann nicht weitermachen und
   mir die Meldung schicken – nichts löschen.

## 2. Xcode öffnen

1. Doppelklick auf **Pace.xcodeproj** im Pace-Ordner.
2. Xcode lädt beim ersten Öffnen neue Bausteine (unten rechts „Resolving Packages“). Warte, bis das fertig ist.
   Falls Xcode meldet, dass Pakete fehlen: Menü **File → Packages → Resolve Package Versions**.
3. Einmal **Product → Clean Build Folder** (⇧ ⌘ K) ausführen.

## 3. iPhone auswählen

1. iPhone per Kabel verbinden und entsperren (oder WLAN-Verbindung wie beim letzten Mal).
2. Oben in der Mitte der Xcode-Leiste auf den Gerätenamen klicken und dein **iPhone** auswählen (nicht
   „iPhone … Simulator“).
3. Unter **Signing & Capabilities** muss weiter dein Personal Team stehen. Nur falls Xcode es zurückgesetzt hat,
   wieder auswählen – sonst nichts ändern.

## 4. Update installieren

1. Auf den **Play-Knopf** (▶) oben links klicken oder ⌘ R drücken.
2. Die App startet auf dem iPhone. Deine bisherigen Daten (Profil, Tagesziel, Home-Layout) bleiben erhalten; das
   Home-Layout wird automatisch ins neue Format übernommen.

## 5. Neue Abfragen beim ersten Start

Dieses Update fragt einmalig nach zwei neuen Berechtigungen. Beide sind nur Einträge in der Info.plist – Signing,
Bundle Identifier und Capabilities bleiben unverändert:

- **Bewegung & Fitness** (beim ersten Öffnen von Home): Damit zählt die Schrittanzeige live mit, während Pace offen
  ist. Ohne Erlaubnis zeigt Pace wie bisher die Werte aus Apple Health.
- **Mikrofon** (beim ersten Halten des Mikrofon-Knopfs im Chat): nur für Sprachnachrichten. Nach der Erlaubnis
  nimmt das nächste Halten auf.

Bestehende Einstellungen, Home-Layout, Tagesziel und die Erinnerung an das Tagesziel bleiben erhalten (die alte
Erinnerungszeit wird übernommen).

## 6. Die 22 Testfälle

Hake ab, was klappt. Bei einem Fehler bitte Screenshot und die Nummer des Testfalls schicken.

**A = sofort testbar.** **B = erst nach Freigabe und Einspielen der drei neuen Migrationen** (Spitznamen,
Nachrichtenaktionen, Gruppenkalender – siehe `docs/SUPABASE_ROLLOUT.md`, Abschnitt „Auftrag 3“). Vorher zeigt die
App an diesen Stellen ehrlich „auf dem Server noch nicht eingerichtet“. Freunde, Gruppen und Chats selbst
funktionieren schon (die bisherigen sechs Migrationen sind eingespielt).

| Nr. | Was tun | Was soll passieren | |
|---|---|---|---|
| 1 | Home offen lassen und 100 Schritte gehen. | „Deine Schritte heute“ zählt beim Gehen mit (alle paar Sekunden), ohne Sprünge zurück. Nach dem Schließen und Öffnen stimmt der Wert mit Apple Health überein (manuell eingetragene Schritte zählen nicht). | A |
| 2 | Apple Health → Aktivität → Aktive Energie von heute ansehen, dann Pace. | Pace zeigt denselben Wert (kcal) an. Hat Health für heute keine Werte, steht „Nicht verfügbar“ – nie eine erfundene 0. | A |
| 3 | Einen Chat öffnen, Nachricht schreiben, senden. | Kopf mit „‹ Social“ oben links, die Nachricht erscheint sofort unten; das Eingabefeld ist immer sichtbar. | A |
| 4 | Ins Eingabefeld tippen, Tastatur wieder schließen (nach unten wischen). | Das Eingabefeld sitzt direkt über der Tastatur, die Tab-Leiste verschwindet solange; nichts wird verdeckt. | A |
| 5 | Auf Home, Rankings, Social und Profil seitlich wischen. | Die Seiten folgen dem Finger, die helle Tab-Fläche gleitet mit. Finger nach rechts → nächster Tab. | A |
| 6 | Wischen anfangen und auf halbem Weg zurückziehen. | Der Wechsel wird abgebrochen, der bisherige Tab bleibt. | A |
| 7 | Eine Unterseite öffnen (z. B. Kalender oder ein Chat) und seitlich wischen. | Kein Tab-Wechsel – nur die normale Zurück-Geste vom linken Rand. | A |
| 8 | Home → „Anpassen“, ein Widget am Griff (sechs Punkte) festhalten und weit nach unten ziehen. | Die Seite scrollt am Rand mit, das Widget lässt sich über mehrere Bildschirmhöhen verschieben und bleibt nach dem Neustart dort. | A |
| 9 | Freund öffnen → „Spitzname vergeben“ → z. B. „Laufpartner“ → Speichern. | Überall (Freunde, Top-Freunde, Rankings, Chatliste, Chat) steht sofort der Spitzname; im Profil darunter der echte Anzeigename. Nur du siehst ihn. | B |
| 10 | Gruppenchat öffnen, in dem dieser Freund schreibt. | Über seinen Nachrichten steht dein Spitzname für ihn. | B |
| 11 | Im Chat bei leerem Feld das Mikrofon gedrückt halten und sprechen. | Roter Punkt, Zeit läuft, leichtes Vibrieren. Loslassen → Vorschau mit Abspielen, Papierkorb und Senden. Gesendet wird noch nichts. | A (Aufnahme) |
| 12 | Wieder halten und den Finger nach links wischen (oder in der Vorschau den Papierkorb). | Aufnahme verworfen, nichts wird hochgeladen. | A |
| 13 | Aufnehmen, Finger nach oben wischen (gesperrt), weiterreden, dann Senden. | Die Sprachnachricht erscheint mit Dauer; Antippen spielt sie ab, Ziehen auf dem Balken springt. In der Chatliste steht „Sprachnachricht · 0:12“. | B |
| 14 | Eine Nachricht gedrückt halten → „Antworten“ → Text senden. | Über der Eingabe „Antwort auf …“; die neue Nachricht zeigt einen Verweis. Antippen des Verweises springt zur Original-Nachricht und hebt sie kurz hervor. | B |
| 15 | Eigene Textnachricht gedrückt halten → „Bearbeiten“ → Text ändern → Haken. | Der Text ändert sich, darunter „Bearbeitet“. Auf dem zweiten Gerät erscheint der neue Text. | B |
| 16 | Nachricht gedrückt halten → „Als Favorit speichern“; dann Stern oben im Chat. | Kleiner Stern an der Nachricht; die Liste „Favoriten“ zeigt sie. Andere sehen das nicht. | B |
| 17 | In einer eigenen Gruppe (du bist Owner) Nachricht gedrückt halten → „Anpinnen“. | Oben im Chat erscheint „Angepinnte Nachricht“ mit Vorschau; Antippen springt hin. Mitglieder ohne Recht sehen „Anpinnen“ gar nicht im Menü. | B |
| 18 | Gruppendetails → „Gruppenkalender“. | Monat mit Montag als erstem Tag; gesicherte Tage mintgrün, Pokal beim Tagesbesten; Vor/Zurück und „Heute“. | B |
| 19 | Einen vergangenen Tag antippen. | Darunter die vollständige Tagesrangliste mit echten Schritten, deine Zeile hervorgehoben, „x von n Mitgliedern haben das Tagesziel erreicht“, benötigte Mitglieder und Flamme. Tage ohne Daten: „Keine Daten verfügbar.“ | B |
| 20 | Profil → Mitteilungen → Tagesziel-Erinnerungen einschalten, „Uhrzeit hinzufügen“, Zeiten ändern und eine entfernen. | Bis zu 6 Uhrzeiten; sie bleiben nach dem Neustart. Zur Zeit kommt eine Mitteilung, morgens allgemein, später mit den fehlenden Schritten (wenn Pace kurz vorher offen war). Ist das Ziel erreicht, kommen heute keine „fehlen noch“-Mitteilungen mehr. | A |
| 21 | Dunkle Darstellung, Home → Kalender, verschiedene Tage antippen. | Der ausgewählte Tag hat einen deutlichen mintgrünen Rahmen außen – auch um grün gefüllte Tage. Auswahl sieht nie wie „Ziel erreicht“ aus. | A |
| 22 | Auf Home, Rankings, Social und Profil ganz nach unten scrollen. | Das Letzte ist vollständig über der Tab-Leiste sichtbar; keine Scrollleiste am Rand. Den aktiven Tab erneut antippen → die Seite scrollt nach oben. | A |

**Grenzen (ehrlich):** Mitteilungen zu neuen Chatnachrichten kommen nur, solange Pace geöffnet ist. Bei
geschlossener App bräuchte es Push-Mitteilungen über Apple (APNs) – mit einem kostenlosen Personal Team nicht möglich
und nicht eingerichtet. Erinnerungen werden im Voraus geplant: Ist Pace länger nicht offen, kennen sie den aktuellen
Schrittstand nicht und erinnern ohne Zahl.

Wenn etwas nicht klappt: Screenshot und eine kurze Beschreibung (welcher Schritt, was passiert ist) an mich.
