# Nächster iPhone-Test – einfache Anleitung (Auftrag 5)

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

Dieses Update fragt nach **keinen neuen Berechtigungen** (kein Standort; „Bewegung & Fitness“ gibt es schon seit Auftrag 3).

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

## 5. Live-Schritte: 5-Minuten-Gehprobe

Das ist der wichtigste Test dieses Updates. Die Live-Schritte wurden bisher **nur mit simulierten Sensorwerten**
geprüft (100 Schritte pro Minute über 5 Minuten, 14 Szenarien) – nicht mit dem echten Bewegungssensor deines iPhones.

**Vorbereitung**

1. Pace aus Xcode starten (▶). Beim ersten Start fragt iOS nach **„Bewegung & Fitness“** – bitte erlauben. (Das ist
   keine neue Berechtigung, Pace nutzt sie seit Auftrag 3 für die Live-Anzeige. Standort wird nicht verwendet.)
2. Profil → **Aktivität & Gesundheit** → ganz unten **„Live-Schritte · Diagnose“**. Diese Seite gibt es nur in
   Builds aus Xcode (Entwicklung), nie im normalen Home-Design. Dort **„Leeren“** tippen.
3. Zurück zu Home. Die Zahl unter „Deine Schritte heute“ notieren und die Uhrzeit dazu.

**Gehen**

4. iPhone in die Hosentasche oder in die Hand, Pace bleibt **geöffnet und entsperrt** (Bildschirm-Sperre kurz
   abschalten oder das Display ab und zu antippen). Ruhig und gleichmäßig gehen – etwa 100 Schritte pro Minute.
5. Alle **30 Sekunden** stehen bleiben (oder im Gehen ablesen) und den Wert auf Home notieren:

| Zeit | Wert auf Home | Zuwachs seit Start | erwartet (≈ 100/min) |
|---|---|---|---|
| 0:00 | | 0 | 0 |
| 0:30 | | | ≈ 50 |
| 1:00 | | | ≈ 100 |
| 1:30 | | | ≈ 150 |
| 2:00 | | | ≈ 200 |
| 2:30 | | | ≈ 250 |
| 3:00 | | | ≈ 300 |
| 3:30 | | | ≈ 350 |
| 4:00 | | | ≈ 400 |
| 4:30 | | | ≈ 450 |
| 5:00 | | | ≈ 500 |

6. Nach 5 Minuten: Diagnose-Seite öffnen und einen Screenshot machen (Zustand des Sensors, Anzahl der Messwerte,
   „Ø Abstand“ zwischen den Messwerten, bestätigte und vorläufige Schritte, Protokoll).
7. Etwa **10 Minuten später** die Health-App öffnen → Schritte → heutiger Wert. Mit dem Wert auf Home vergleichen.

**Was soll passieren**

- Der Wert steigt **während des Gehens** gleichmäßig (alle paar Sekunden), nicht nur um ein paar Dutzend Schritte
  in mehreren Minuten. Abweichungen von ±10 % zur eigenen Zählung sind normal (Schrittlänge, Tempo).
- Beim Stehenbleiben bleibt der Wert stehen.
- Später trägt Apple Health die Schritte selbst nach. Der Wert auf Home springt dann nicht zusätzlich nach oben
  (keine Doppelzählung). Mit Apple Watch kann Health etwas höher liegen – dann gilt der höhere Wert.
- Bestätigt Apple Health **weniger**, als das iPhone gezählt hat (z. B. weil Health die Watch bevorzugt), fällt der
  Wert etwa **20 Minuten nach dem letzten Schritt** auf den Health-Wert zurück. Das ist Absicht: Die Anzeige soll nicht
  bis Mitternacht über Apple Health stehen. Bitte notieren, ob und wann das passiert (Diagnose-Seite: „Unbestätigte
  Schritte verfallen“).
- Erreichen nur die Live-Schritte dein Tagesziel, steht „Ziel erreicht – Bestätigung aus Apple Health folgt“.
  „Tagesziel erreicht!“ erscheint erst, wenn Apple Health die Schritte bestätigt hat (wie bei der Serie).
- Rankings, Freunde-Vergleich und Serie ändern sich erst, wenn Apple Health die Schritte bestätigt hat – die
  Live-Anzeige ist nur vorläufig.

**Zusatzprobe (optional):** Während des Gehens kurz die App verlassen (Home-Bildschirm), 30 Sekunden weitergehen,
zurück zu Pace. Die Schritte aus der Pause sollten sofort dazukommen.

**Im Simulator:** Der Simulator hat keinen Schrittzähler. Auf der Diagnose-Seite lässt sich „100 Schritte/min
simulieren“ einschalten (gilt ab dem nächsten App-Start) – nur zum Ansehen der Anzeige, kein Ersatz für die Gehprobe.
Der Schalter bleibt gespeichert: Vor der Gehprobe auf dem iPhone prüfen, dass die Diagnose-Seite nicht „Simuliert“
zeigt.

## 6. Testfälle

Hake ab, was klappt. Bei einem Fehler bitte Screenshot und die Nummer des Testfalls schicken.

### Neu in Auftrag 5

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 1 | Home langsam und schnell nach oben scrollen, auch im Anpassen-Modus; Tab wechseln und zurück. | Uhrzeit und Symbole der Statusleiste liegen nie über Inhalten wie „Deine Schritte heute“ oder „Tagesziel ändern“. Oben bleibt kein großer Leerraum, nichts springt, Home lässt sich bis zum Ende scrollen. In Hell und Dunkel prüfen. |
| 2 | Dasselbe auf Rankings, Social, Profil und einer Unterseite (z. B. Statistik). | Auch dort läuft nichts unter die Statusleiste. |
| 3 | Gehprobe aus Abschnitt 5. | Siehe dort. |
| 4 | Home → Anpassen → „Deine Positionen in der Region“ → Bearbeiten. | Oben steht „4 von 4 Ebenen sichtbar“. Eine Ebene abwählen → „3 von 4“ und „Alle vier zeigen“; damit kommen alle vier zurück. Auf Home stehen nach dem Sichern und nach einem Neustart vier Karten (außer du hast bewusst eine abgewählt – dann zeigt der Anpassen-Modus „3 von 4 Ebenen sichtbar“). |
| 5 | Schritte-Widget nacheinander auf Klein, Mittel, Groß, Max stellen. | Klein: Zahl, Prozent, Balken. Mittel: wie bisher mit Ring, Ziel, „Noch … bis zu deinem Ziel“, Distanz, Kalorien. Groß: zusätzlich Stockwerke und Training. Max: zusätzlich „Letzte 7 Tage“ als kleines Diagramm mit Ziellinie und der Vergleich gestern/Ø 7 Tage. Kein Text abgeschnitten. |
| 6 | Einen Gruppenchat öffnen und in den Nachrichten scrollen. | Unter dem Kopf steht fest eine Leiste: links kleine Profilbilder, „12 Mitglieder“ und „+“, rechts nur 🔥 und eine Zahl. Sie scrollt nicht mit. |
| 7 | In dieser Leiste: Bilder antippen, „+“ antippen, Flamme antippen, jeweils zurück. | Bilder/Anzahl → Mitgliederliste. „+“ → Mitglieder mit „Freunde einladen“. Flamme → Gruppenkalender. „‹“ führt jeweils zurück in den Chat, keine Schleife. |
| 8 | Eine Nachricht anpinnen: einen Text, ein Foto, ein GIF, eine Sprachnachricht, ein geteiltes Profil. | Oben im Chat zeigt der Pin den Inhalt: Textanfang mit Absender, kleines Vorschaubild (GIF mit „GIF“), Sprachnachricht mit Dauer, Profilbild mit @Name. Antippen springt zur Nachricht und hebt sie kurz hervor; bei mehreren Pins zeigen Striche links, welcher gerade dran ist, Antippen wechselt zum nächsten. |
| 9 | Gruppe öffnen (Gruppeninfo). | Eine Karte: „x von n Mitgliedern haben das Tagesziel erreicht“, rechts nur 🔥 + Zahl, darunter ein Balken mit Strich an der Flammen-Schwelle und z. B. „Noch 1 Mitglied bis zur heutigen Gruppenflamme“. Kein Pfeil, kein eigener „Gruppenkalender“-Eintrag mehr. Antippen der Karte öffnet den Gruppenkalender. |
| 10 | Statistik → Tag/Woche/Monat schnell hintereinander wischen. | Die Balken wechseln ruhig: keine schmalen oder verschobenen Balken, nichts überlagert sich, die Höhe der Karte springt nicht, Achsen passen. |
| 11 | Auf Statistik, Kalender, Flamme, Gruppenkalender, Gruppeninfo, Chat, Freundesprofil, Einstellungen vom **linken Rand** nach rechts wischen. | Die Seite geht zurück. In Statistik/Kalender wechselt dabei nicht zusätzlich der Zeitraum. |
| 12 | Zwischen den vier Tabs wischen und auf die Kopfzeilen achten. | „pace“-Schriftzug und Titel stehen in allen Tabs auf derselben Höhe, nichts springt. |
| 13 | Home → Anpassen → „+ Widget hinzufügen“. | Kategorien in drei Abschnitten: **Aktivität**, **Motivation**, **Social**. Neu: Tagesvergleich, Aktivitätszeiten, Serie diese Woche, Persönliche Rekorde, Gruppenfortschritt. |
| 14 | „Tagesvergleich“ hinzufügen (Mittel). | „… Schritte mehr/weniger als gestern um diese Zeit“, Balken heute/gestern. Kurz nach dem Hinzufügen ein Ladekreis (nicht „kein Vergleich“). Ohne Werte von gestern: „Noch kein Vergleich verfügbar“. Antippen → Tagesstatistik. |
| 15 | „Aktivitätszeiten“ hinzufügen, Größe Max. | Balken für Nachts, Morgens, Mittags, Nachmittags, Abends und darunter 24 Stunden; z. B. „Am aktivsten nachmittags“. Ohne Stundenwerte ein Hinweis, keine ausgedachte Verteilung. |
| 16 | „Serie diese Woche“ hinzufügen, antippen. | Mo–So mit erreichten Tagen (damaliges Ziel), optional Serie, Rekord, Meilenstein; Antippen öffnet deine Flammen-Seite. |
| 17 | „Persönliche Rekorde“ hinzufügen, Rekord z. B. „Beste Woche“ wählen, Größe Groß. | Rekordauswahl einspaltig, auch auf Russisch nichts abgeschnitten. Der gewählte Rekord groß, darunter zwei weitere; Begriffe wie in der Statistik („Längste Serie“, „Weiteste Strecke“). Zeitraum „Letzte 12 Monate“ nur bei Tag/Woche/Monat/Strecke. Ohne Wert (z. B. noch keine Serie) ein ehrlicher Hinweis. |
| 18 | „Gruppenfortschritt“ hinzufügen, eine Gruppe wählen; danach in Social die Gruppe verlassen (oder auf einem Testkonto). | Name, Mitglieder, Fortschritt, 🔥 + Zahl; Antippen → Gruppe, Flamme → Gruppenkalender. Nach dem Verlassen: Hinweis, dass du nicht mehr in der Gruppe bist. |
| 19 | App beenden und neu starten. | Alle neuen Widgets mit Größe und Optionen sind unverändert da. |
| 20 | Sprache auf English bzw. Русский stellen und Fälle 4–18 grob durchsehen. | Alles übersetzt („12 участников“, „1 участник“ usw.), nichts abgeschnitten. |

### Regressionen (Auftrag 3/4 – bitte kurz prüfen)

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 21 | Social → Gruppe → Chat → Flamme → Chat … **50-mal**, danach „‹“ ganz zurück. | Keine neuen Ebenen, kein Ruckeln (wie Auftrag 4, Fall 1). |
| 22 | Zwischen den Tabs wischen, abbrechen, zurückziehen. | Richtung und Abbruch wie bisher. |
| 23 | Chat: Eingabe über der Tastatur, Antworten, Sprachnachricht (10 s), GIF senden. | Wie bisher. |
| 24 | Home → Anpassen → Widget ziehen, Größe ändern, entfernen, Rückgängig. | Wie bisher, nichts springt. |
| 25 | Tab-Leiste unten, Hell/Dunkel. | Unverändert. |

**Grenzen (ehrlich):** Die Live-Schritte und die neuen Widgets sind nur automatisch geprüft (Unit-Tests mit simulierten
Sensorwerten, Simulator-Tests in der CI). Mitteilungen zu neuen Chatnachrichten kommen nur, solange Pace geöffnet ist;
Push über Apple (APNs) ist nicht eingerichtet und mit einem kostenlosen Personal Team nicht möglich.

Wenn etwas nicht klappt: Screenshot und eine kurze Beschreibung (welcher Schritt, was passiert ist) an mich.
