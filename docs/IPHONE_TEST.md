# Nächster iPhone-Test – einfache Anleitung (Auftrag 4)

Diese Anleitung setzt voraus, dass Pace schon einmal aus Xcode auf deinem iPhone lief (Personal Team, eigene
`Config/Pace.xcconfig` mit den Supabase-Werten). Daran ändert sich nichts: Signing, Bundle Identifier
(`com.boketta.pace.ios` auf deinem iPhone) und deine lokale Konfiguration bleiben, wie sie sind.
`Config/Pace.xcconfig` ist von Git ausgeschlossen und wird beim Aktualisieren nicht überschrieben.

Wichtig: Alle Punkte unten wurden bisher nur automatisch (Unit-Tests, Simulator in der CI) geprüft – **nicht auf
einem echten iPhone**. Genau dafür ist diese Liste da.

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

## 2. Optional: GIF-Suche einrichten (GIPHY)

Die GIF-Suche im Chat braucht einen eigenen, kostenlosen GIPHY-Schlüssel. Ohne Schlüssel funktioniert alles andere;
„GIF suchen“ zeigt dann ehrlich „Die GIF-Suche ist in dieser App-Version nicht eingerichtet“.

1. Auf <https://developers.giphy.com> anmelden → **Create an App** → Typ **API** wählen → Namen „Pace“ eingeben.
   Der angezeigte **API Key** ist ein Beta-Schlüssel mit begrenztem Kontingent (für deine Tests reicht das).
2. Öffne `Config/Pace.xcconfig` (dieselbe Datei mit deinen Supabase-Werten) in einem Texteditor und ergänze eine
   Zeile:
   ```
   GIPHY_API_KEY = dein_schlüssel_ohne_anführungszeichen
   ```
3. Speichern. Die Datei bleibt lokal (von Git ausgeschlossen) – der Schlüssel kommt nie ins Repository.

## 3. Xcode öffnen

1. Doppelklick auf **Pace.xcodeproj** im Pace-Ordner.
2. Warte, bis unten rechts „Resolving Packages“ fertig ist. Falls Xcode meldet, dass Pakete fehlen: Menü
   **File → Packages → Resolve Package Versions**.
3. Einmal **Product → Clean Build Folder** (⇧ ⌘ K) ausführen.

## 4. iPhone auswählen und installieren

1. iPhone per Kabel verbinden und entsperren.
2. Oben in der Mitte der Xcode-Leiste dein **iPhone** auswählen (nicht „iPhone … Simulator“).
3. Unter **Signing & Capabilities** muss weiter dein Personal Team stehen. Nur falls Xcode es zurückgesetzt hat,
   wieder auswählen – sonst nichts ändern.
4. **Play-Knopf** (▶) oder ⌘ R. Deine Daten (Profil, Tagesziel, Home-Layout, Widget-Einstellungen) bleiben erhalten.

Dieses Update fragt nach **keinen neuen Berechtigungen**.

### „Pace ist nicht mehr verfügbar“

Mit einem kostenlosen Personal Team ist eine aus Xcode installierte App nur **7 Tage** gültig. Danach öffnet iOS sie
nicht mehr und meldet „Pace ist nicht mehr verfügbar“ – das ist sehr wahrscheinlich die Ursache der Meldung (nicht
bestätigt; bitte so prüfen):

1. iPhone-Einstellungen → **Allgemein → VPN & Geräteverwaltung** → unter „Entwickler-App“ deine Apple-ID antippen.
   Steht dort kein Eintrag mehr oder lässt sich die App nicht vertrauen, ist das Profil abgelaufen.
2. Lösung: iPhone verbinden, in Xcode erneut ▶ drücken. Die App wird neu signiert, Daten bleiben erhalten.
3. Notiere das Installationsdatum. Kommt die Meldung **vor** Ablauf der 7 Tage, schick mir bitte Datum und
   Uhrzeit sowie (falls vorhanden) einen Absturzbericht: Einstellungen → Datenschutz & Sicherheit → Analyse &
   Verbesserungen → Analysedaten → Einträge, die mit „Pace“ beginnen.

## 5. Testfälle

Hake ab, was klappt. Bei einem Fehler bitte Screenshot und die Nummer des Testfalls schicken. Für die Fälle mit zwei
Personen brauchst du einen Freund mit Pace oder ein zweites Gerät.

### P0 – zuerst

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 1 | Social → eine Gruppe → Flamme → „Chat“ → im Chat-Kopf wieder zur Flamme → wieder zum Chat. Das **20-mal** wiederholen, danach mit „‹“ ganz zurück. | Es entstehen keine neuen Ebenen: Nach höchstens zwei, drei „‹“ bist du wieder in der Gruppe bzw. auf Social. Kein Ruckeln, kein seitliches Zucken. Danach dieselbe Gruppe erneut öffnen – alles normal. |
| 2 | Auf Home, Rankings, Social und Profil seitlich wischen. | Finger von rechts nach links → nächster Tab rechts (Home → Rankings → Social → Profil). Finger von links nach rechts → vorheriger Tab. Die Seiten folgen dem Finger, die mintgrüne Fläche unten gleitet in dieselbe Richtung. An Home und Profil endet die Reihe. |
| 3 | Wischen anfangen, auf halbem Weg anhalten, zurückziehen, loslassen. | Der Wechsel wird abgebrochen, der bisherige Tab bleibt; die Hervorhebung gleitet sauber zurück. |
| 4 | Eine Unterseite öffnen (Kalender, Statistik, Chat, Einstellungen) und seitlich wischen. | Kein Tab-Wechsel – nur die normale Zurück-Geste vom linken Rand. |
| 5 | Chat öffnen, ins Eingabefeld tippen. | Das Eingabefeld sitzt **direkt über der Tastatur** (kein Spalt, nichts verdeckt), die Tab-Leiste ist weg. Tastatur nach unten wischen → Eingabe gleitet mit. |
| 6 | Nachricht gedrückt halten → „Antworten“, dann ins Feld tippen. | Antwortvorschau und Eingabe sind beide über der Tastatur sichtbar. |
| 7 | Mikrofon gedrückt halten und **10 Sekunden** sprechen, dann loslassen. | Die Aufnahme läuft die ganze Zeit (Zeit zählt weiter, kein Abbruch nach 1 s). Danach Vorschau mit Abspielen, Papierkorb, Senden. |
| 8 | Wieder halten, Finger nach oben wischen (gesperrt), 15 s weiterreden, Senden. | Sprachnachricht mit ca. 0:15 Dauer erscheint und lässt sich abspielen. |
| 9 | Halten und nach links wischen. | Aufnahme verworfen, nichts gesendet. |
| 10 | Home → „Anpassen“, ein Widget am Griff (sechs Punkte) langsam nach unten ziehen, dann schnell nach oben, zwischendurch anhalten. | Die anderen Widgets weichen ruhig aus, das gezogene Widget bleibt unter dem Finger, kein Flackern oder Springen. Am Rand scrollt die Seite mit. Loslassen → das Widget rastet weich ein und bleibt nach Neustart dort. |
| 11 | Beim Ziehen einen zweiten Finger auflegen bzw. während des Ziehens die App verlassen. | Das Ziehen endet sauber, nichts scrollt weiter, nichts hängt. |
| 12 | Den Ablauf aus Nr. 1 mit **50 Wiederholungen** machen und dabei in Xcode links den **Debug-Navigator** (⌘ 7) → „Memory“ beobachten. | Der Speicher steigt nicht immer weiter an (kurze Spitzen sind normal), die App bleibt flüssig. Wert vorher/nachher bitte notieren. |

### Messenger und Social

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 13 | Unten die Tab-Leiste ansehen (iPhone mit Home-Balken). | Unter den Symbolen ist weniger Leerraum als vorher; Symbole und Texte sind gleich groß wie bisher. |
| 14 | Weit nach oben scrollen (eigene, alte Nachricht noch nicht geladen) und auf diese antworten lassen bzw. eine Antwort darauf ansehen. | Im Verweis steht „Du“, nicht dein eigener Name. |
| 15 | Freund → Spitzname ändern, dann Rankings → Freunde. | Der neue Spitzname steht dort sofort. |
| 16 | Chat → „+“. | Kleines Menü: „Foto aus Mediathek“, „GIF suchen“, „Profil teilen“. „Foto aus Mediathek“ funktioniert wie bisher (auch GIFs aus Fotos). |
| 17 | „+“ → „GIF suchen“ (mit Schlüssel aus Abschnitt 2), „laufen“ suchen, ein GIF antippen, „Senden“. | Raster mit echten GIFs (Standbilder), Antippen zeigt das GIF animiert; nach „Senden“ erscheint es animiert im Chat, nicht riesig. Unten „Powered by GIPHY“. Ohne Schlüssel: Hinweis „nicht eingerichtet“. |
| 18 | Flugmodus an, „GIF suchen“. | Hinweis „Keine Internetverbindung“ mit „Erneut versuchen“. |
| 19 | Den Chat schließen und wieder öffnen; dasselbe in einem Gruppenchat; auf dem zweiten Gerät ansehen. | Das GIF ist weiter da und läuft – in Privat- und Gruppenchat, auch beim Gegenüber. |
| 20 | Einen Chat mit vielen GIFs lange auf und ab scrollen (Debug-Navigator → Memory). | Flüssig, der Speicher wächst nicht immer weiter. |
| 21 | „+“ → „Profil teilen“ → „Mein Profil“ bzw. einen Freund. | Eine antippbare Profilkarte erscheint im Chat. |
| 22 | Social oben: Symbol für Freundschaftsanfragen (Briefumschlag mit Person). | Mit offener Anfrage eine Zahl am Symbol; Antippen öffnet die Anfragen. In heller und dunkler Darstellung gut erkennbar. |
| 23 | Gruppendetails → Gruppenkalender; einen vergangenen Tag antippen. | Gesicherte Tage mintgrün, Tagesbester mit Pokal; Tagesrangliste mit echten Schritten, „x von n Mitgliedern“. Namen und Zahlen nicht abgeschnitten. |

### Neue Funktionen

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 24 | Profil → Einstellungen. | Sieben Bereiche: Konto & Profil, Privatsphäre & Sicherheit, Mitteilungen, Aktivität & Gesundheit, Darstellung & Sprache, Social & Gruppen, Daten/Hilfe/Rechtliches. Jeder öffnet sich, „‹“ führt immer zurück – keine Schleifen. „Social & Gruppen → Meine Gruppen“ wechselt zum Social-Tab. |
| 25 | Einstellungen → Aktivität & Gesundheit → Kalorienschätzung: Größe (z. B. 180) und Gewicht (z. B. 75) eintragen, einschalten. | Ungültige Werte (z. B. 20 kg) werden abgelehnt. Gibt es für heute **keine** gemessenen Kalorien in Apple Health, zeigt Home „≈ … kcal“ und „Geschätzte aktive Kalorien“. Mit Apple Watch (gemessene Werte) bleibt der gemessene Wert – nie beides addiert. Ausschalten → wieder „Nicht verfügbar“ bzw. der gemessene Wert. |
| 26 | Home → Flammen-Widget antippen. | Eigene Seite „Deine Flamme“: aktuelle Serie, Rekord, Beginn, Flammenkalender des Monats, frühere Serien, Erklärung. Kein Weg in eine Gruppe oder einen Chat. |
| 27 | Im Flammenkalender seitlich wischen und einen Tag antippen. | Finger nach rechts → vorheriger Monat, nach links → nächster. Unter dem Kalender: Schritte des Tages, damaliges Ziel, ob die Serie weiterging. |
| 28 | Home → Statistik (Schritte) → Tag: über Wert oder Diagramm seitlich wischen; dasselbe bei Woche und Monat. | Finger nach rechts → vorheriger Tag/Woche/Monat, nach links → nächster. Werte, Diagramm, Distanz, Kalorien und Vergleich wechseln zusammen. Nach heute geht es nicht weiter (federt zurück). Senkrechtes Scrollen bleibt normal, kein Tab-Wechsel. |
| 29 | Statistik → Woche bzw. Monat ganz nach unten; Home → Kalender → Tag antippen. | Bestwerte des Zeitraums (bester Tag, beste Woche des Monats, weiteste Strecke, aktuelle Serie) und „Deine Bestwerte“ im Kalender – nur aus deinen echten Schritten. |
| 30 | Home → Anpassen → Flammen-Widget → Bearbeiten → „Inhalte“: „Nächster Meilenstein“ wählen, Größe ändern, eigenen Namen eintragen, sichern. | Das Widget zeigt z. B. „Noch 2 Tage bis zu 7 Tagen in Folge“ und den neuen Namen. „Mittel“ zeigt höchstens zwei Zusatzinhalte (Hinweis in der Auswahl). |
| 31 | Ebenso: Schritte-Widget → „Persönlicher Tagesbestwert“; Freunde-Widget → „Abstand zum Platz davor“; Gruppen-Widget (eine Gruppe gewählt) → Inhalte; Umfeld → Abstand aus. | Jedes Widget zeigt genau die gewählten Inhalte; nach Neustart unverändert. Ohne eigene Auswahl sehen alle Widgets aus wie vorher. |
| 32 | Profil → Mitteilungen: Erinnerungen wie bisher (bis 6 Uhrzeiten). | Unverändert funktionsfähig. |
| 33 | Sprache auf English bzw. Русский stellen und die neuen Seiten (Flamme, GIF-Suche, Widget-Inhalte, Kalorienschätzung) ansehen. | Alles übersetzt, nichts abgeschnitten. |

**Grenzen (ehrlich):** Mitteilungen zu neuen Chatnachrichten kommen nur, solange Pace geöffnet ist. Push-Mitteilungen
über Apple (APNs) sind nicht eingerichtet und mit einem kostenlosen Personal Team nicht möglich. Videos lassen sich im
Chat nicht senden (der Server erlaubt Bilder, GIFs und Sprachnachrichten). Die Kalorienschätzung ist eine Schätzung
fürs Gehen (Steigungen und Laufen werden nicht eigens berücksichtigt).

Wenn etwas nicht klappt: Screenshot und eine kurze Beschreibung (welcher Schritt, was passiert ist) an mich.
