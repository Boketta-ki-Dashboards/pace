# Nächster iPhone-Test – einfache Anleitung (Auftrag 6)

Diese Anleitung setzt voraus, dass Pace schon einmal aus Xcode auf deinem iPhone lief (Personal Team, eigene
`Config/Pace.xcconfig` mit den Supabase-Werten). Daran ändert sich nichts: Signing, Bundle Identifier
(`com.boketta.pace.ios` auf deinem iPhone), Berechtigungen und deine lokale Konfiguration bleiben, wie sie sind.
`Config/Pace.xcconfig` ist von Git ausgeschlossen und wird beim Aktualisieren nicht überschrieben. Deine anonyme
Pace-Identität bleibt erhalten, es gibt keine neue Anmeldung.

Wichtig: Alle Punkte unten wurden bisher nur automatisch geprüft (Unit-Tests unter Linux, Simulator in der CI) –
**nicht auf einem echten iPhone**. Gerade der Fehler „Home verschiebt sich im Anpassen-Modus seitlich“ ließ sich im
Simulator nicht nachstellen; ob er auf deinem iPhone weg ist, zeigt erst dieser Test (Abschnitt 5 A).

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

## 2. Optionale Einstellungen

**GIF-Suche (GIPHY):** unverändert – wenn du schon einen `GIPHY_API_KEY` in `Config/Pace.xcconfig` hast, bleibt er.
Ohne Schlüssel zeigt „GIF suchen“ ehrlich, dass die Suche nicht eingerichtet ist.

**Support-E-Mail für den Pace-Bot:** Nur wenn es eine **offizielle** Support-Adresse gibt, kannst du sie in
`Config/Pace.xcconfig` eintragen:
```
PACE_SUPPORT_EMAIL = support@deine-domain.de
```
Ohne Eintrag bietet der Bot unter „Hilfe kontaktieren“ nur die bestehende Rückmeldung „Problem melden“ an. Es wird
keine Adresse erfunden.

**Datenbank-Update für Profil 2.0:** Bio, Interessen, Banner und Auszeichnungen brauchen die neue Migration
`20261030100000_profile_details.sql`. Sie ist **nicht** eingespielt – das entscheidest du selbst, nach der Anleitung in
[SUPABASE_ROLLOUT.md](SUPABASE_ROLLOUT.md) (Abschnitt „Auftrag 6“). Ohne Migration zeigt „Profil bearbeiten“: „Bio,
Interessen und Banner stehen bald zur Verfügung. Bis dahin funktioniert dein Profil wie gewohnt.“ Alles andere
funktioniert normal; die Testfälle 5 D lassen sich dann nur bis zu diesem Hinweis prüfen.

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

Dieses Update fragt nach **keinen neuen Berechtigungen**. Für das Profilbanner öffnet sich die Fotoauswahl von iOS –
dort wählst du nur einzelne Fotos aus, Pace bekommt keinen Zugriff auf die ganze Mediathek.

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

Hake ab, was klappt. Bei einem Fehler bitte Screenshot (oder kurze Bildschirmaufnahme) und die Nummer des
Testfalls schicken.

### A. Home im Anpassen-Modus verschiebt sich nicht mehr seitlich (wichtigster Test)

Merke dir vor dem Test, wo der „pace“-Schriftzug, „Anpassen“ und der linke Rand des ersten Widgets stehen.

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 1 | Home normal öffnen. | Alles wie gewohnt. |
| 2 | „Anpassen“ tippen. | Widgets wackeln leicht, „Fertig“ und „+ Widget hinzufügen“ erscheinen. Nichts rutscht zur Seite. |
| 3 | Langsam mit dem Finger nach **links** ziehen (mitten auf einem Widget und auf freier Fläche). | Die Seite bewegt sich **nicht** seitlich – weder Schriftzug, Überschrift, Buttons noch Widget-Ränder. Es erscheint kein anderer Tab. |
| 4 | Schnell nach links wischen. | Wie 3. |
| 5 | Langsam nach **rechts** ziehen. | Wie 3. |
| 6 | Schnell nach rechts wischen. | Wie 3. |
| 7 | Schräg nach unten ziehen (gleichzeitig etwas seitlich). | Die Seite scrollt nur senkrecht, seitlich bleibt sie fest. |
| 8 | Schräg nach oben ziehen. | Wie 7. |
| 9 | Ein Widget am Griff (≡) nach unten ziehen. | Das Widget wandert mit, die anderen rücken nach. Kein seitliches Verrutschen. |
| 10 | Widget ablegen, dann bei einem Widget die Größe ändern, eines entfernen („Rückgängig“ testen) und eines hinzufügen. | Alles funktioniert wie bisher. |
| 11 | „Fertig“ tippen. | Normale Ansicht, alles an seinem Platz. |
| 12 | Jetzt auf Home nach links wischen (Finger nach links). | Rankings kommt von **rechts** herein – das Tab-Wischen funktioniert außerhalb des Anpassen-Modus wie bisher. |
| 13 | Dasselbe seitliche und schräge Ziehen auf: Galerie („+ Widget hinzufügen“), Statistik, Kalender, Flammenkalender, Rankings-Unterseiten, Social, Gruppe (Info, Mitglieder, Gruppenkalender), Chats, Profil, Einstellungen, fremdes Profil. | Keine Seite verschiebt sich seitlich. Gewollte Gesten bleiben: Tabs wechseln (auf den Hauptseiten), Monat/Zeitraum wechseln (Kalender, Statistik), Karussells, Zurück-Wischen vom linken Rand. |

Bitte bei 3–8 zusätzlich auf einem **kleinen** iPhone-Bildschirm prüfen, falls du eines hast (im Simulator war der
Inhalt dort im Anpassen-Modus einen halben Punkt breiter als die Seite – der Inhalt ist jetzt genau so breit wie die
Seite, zusätzlich hält eine Sperre die Seite waagerecht fest).

### B. Profil- und Gruppenbilder

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 14 | Social → Freunde: schnell durch die Liste scrollen, hoch und runter. | Jede Person zeigt **ihr** Bild bzw. ihre Initialen. Kein Bild springt zu einer anderen Person, kein Flackern zwischen zwei Bildern. |
| 15 | Freunde-Ranking, Home-Widget „Freunde“ und ein Chat mit derselben Person. | Überall dasselbe, richtige Bild. |
| 16 | Eigenes Profilbild ändern (Profil → Konto). | Danach überall das neue Bild (Profil, Ranking, Chats) – nirgends das alte. |
| 17 | Eigenes Profilbild entfernen. | Überall Initialen, kein altes Bild. |
| 18 | Flugmodus an, Pace neu öffnen, Freunde und Chats ansehen. | Schon geladene Bilder erscheinen weiter; noch nie geladene zeigen Initialen statt endlosem Laden. Flugmodus aus → nach erneutem Öffnen der Seite laden sie. |
| 19 | Zwei Gruppen mit unterschiedlichen Bildern nacheinander öffnen, schnell hin und her. | Jede Gruppe zeigt nur ihr Bild, nie kurz das der vorigen. |
| 20 | Gruppenbild ändern (als Owner). | Neues Bild in Gruppeninfo, Chatliste und Home-Widget. |
| 21 | Chat mit Fotos und GIFs öffnen, schnell zu einem anderen Chat wechseln, zurück. Pace beenden und neu öffnen. | Bilder/GIFs laden zuverlässig, nicht doppelt, kein Bild aus dem anderen Chat. Schlägt eines fehl, steht dort „Erneut versuchen“. |

### C. Darstellung

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 22 | Profil → Darstellung (und die kleine Auswahl direkt im Profil). | Drei Kacheln mit Symbolen: Automatisch (Sonne und Mond zusammen), Hell (Sonne), Dunkel (Mond). Die gewählte ist mint hervorgehoben. Wechsel wirkt sofort. |
| 23 | Mit VoiceOver (Einstellungen → Bedienungshilfen) über die Kacheln streichen. | Vorgelesen werden „Automatisch“, „Hell“, „Dunkel“ und welche ausgewählt ist. |

### D. Social-Profil 2.0 (nur mit eingespielter Migration, siehe Abschnitt 2)

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 24 | Profil → neben dem Profilbild „Bearbeiten“ (VoiceOver: „Profil bearbeiten“). | Kurz eine Ladeanzeige, dann Profilbanner, Bio (mit deinem bisherigen Text), Interessen, Auszeichnungen und „Speichern“ (ohne Änderung grau). Offline: Hinweis mit „Erneut versuchen“. Der Knopf ist auch auf Russisch nicht abgeschnitten. |
| 25 | „Banner hinzufügen“ → Foto wählen → Ausschnitt verschieben → „Verwenden“. | Das Banner erscheint oben im Profil (Querformat). |
| 26 | Banner ändern, danach „Banner entfernen“. | Neues Banner überall; nach dem Entfernen ein neutraler Pace-Hintergrund. |
| 27 | Bio schreiben, auch mit Emojis; über 160 Zeichen tippen; mehr als 4 Zeilen. | Zähler „x/160“; über der Grenze (oder mit mehr als 4 Zeilen) ein Hinweis und „Speichern“ ist aus. |
| 27a | Bio ändern, ohne zu speichern „Profilbild & Namen“ öffnen und zurück; dann „Speichern“. | Der Text ist nach dem Zurückkommen noch da. Nach dem Speichern erscheint „Gespeichert“. |
| 28 | Interessen wählen. | Höchstens 5 („5 von 5 ausgewählt“), weitere lassen sich erst nach dem Abwählen wählen. |
| 29 | Auszeichnungen einschalten, speichern. | Nur echte Stufen (z. B. „7 Tage in Folge“, „Tag mit 10.000+ Schritten“), keine genauen Schrittzahlen; der Hinweis sagt, dass alle sie sehen, die dein Profil sehen können. Ohne erreichte Stufe ein Hinweis. Ausschalten → verschwinden. Erreichst du später eine höhere Stufe, wird sie beim Öffnen des Profils nachgetragen. |
| 30 | Mit einem zweiten Konto (oder auf dem Gerät eines Freundes) dein Profil öffnen. | Banner, Bio, Interessen; Auszeichnungen nur, wenn eingeschaltet. Alle Aktionen da: Anfrage/Annehmen, Nachricht, Spitzname, Teilen, Blockieren, Melden. |
| 31 | Das andere Konto blockieren und das Profil erneut öffnen. | Keine Bio, kein Banner, keine Interessen mehr. |
| 31a | Ein Profil mit Bio und Banner melden („Nutzer melden“), danach beim gemeldeten Konto das Banner entfernen. | Melden klappt wie bisher. (Für die Moderation bleiben Bio, Interessen und Banner der Meldung erhalten – in der App nicht sichtbar.) |
| 32 | Ein Profil ohne neue Angaben ansehen (älteres Profil). | Sieht aus wie bisher, ohne Lücken oder Fehlermeldung. |

### E. Willkommensmitteilung

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 33 | Nach dem Update Home öffnen. | Die Glocke zeigt eine ungelesene Mitteilung. Darin „Willkommen bei Pace! 👋“ von „Pace Team“. |
| 34 | Mitteilung öffnen. | Detailseite mit Abschnitten (Schritte, Ziele, Rankings, Freunde, Gruppen, Flamme, Home, Hilfe). Zähler an der Glocke sinkt auf 0. |
| 35 | Buttons nacheinander: „Home entdecken“, „Rankings ansehen“, „Freunde hinzufügen“, „Pace-Bot öffnen“. | Zurück zu Home · Rankings-Tab · „Freund hinzufügen“ im Social-Tab · Pace-Bot. Kein Button ohne Wirkung. |
| 36 | Pace beenden und neu öffnen. | Die Mitteilung ist weiter da und gelesen – keine zweite Kopie. |
| 37 | Mitteilung löschen (lange drücken → löschen), Pace neu öffnen. | Sie kommt nicht wieder. |

### F. Pace-Bot

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 38 | Social → Chats. | Oben fest „Pace-Bot“ mit Kennzeichen „Automatisch“, ohne Ungelesen-Zähler. |
| 38a | Flugmodus an, Pace neu starten, Social öffnen. | Social zeigt einen Fehler bzw. lädt – darunter trotzdem die Karte „Pace-Bot“, die sich öffnen lässt. |
| 39 | Pace-Bot öffnen. | Begrüßung links (Bot), darunter Fragen zum Antippen. |
| 40 | „Wie funktioniert eine Gruppenflamme?“ antippen. | Die Ansicht springt nach oben zu deiner Frage (rechts) und der Antwort (links): mindestens ein Drittel der Mitglieder (aufgerundet) muss das Tagesziel erreichen. Die Antwort ist sofort zu sehen, ohne Suchen. |
| 41 | Selbst tippen: „wie werden schritte gezählt“. | Passende Antwort: Rankings zählen nur bestätigte Schritte aus Apple Health, Live-Schritte sind vorläufig. |
| 42 | Selbst tippen: „Wie wird das Wetter morgen?“, danach „How do I delete my account?“ und „Wie entferne ich einen Freund?“. | Jeweils die ehrliche Antwort „Dazu habe ich leider noch keine passende Antwort …“ und das Angebot, Hilfe zu kontaktieren – keine falsche Antwort. |
| 43 | „Hilfe kontaktieren“. | Eine Karte erklärt ehrlich: „Problem melden“ speichert deine Nachricht mit Konto und App-Version, eine persönliche Antwort ist derzeit nicht möglich. „Problem melden“ öffnet die bestehende Rückmeldung (Tastatur geht zu, Tabs bleiben bedienbar). Eine E-Mail-Option erscheint nur, wenn `PACE_SUPPORT_EMAIL` gesetzt ist; die Mail wird nie automatisch gesendet. |
| 44 | Oben rechts das Pfeil-Symbol (Verlauf zurücksetzen) → bestätigen. Pace neu öffnen. | Nur die Begrüßung bleibt. Vorher: Der Verlauf bleibt nach einem Neustart erhalten. |
| 45 | Flugmodus an, Fragen antippen. | Funktioniert ohne Internet (alles auf dem Gerät, keine KI, kein Server). |
| 46 | Sprache auf English bzw. Русский stellen, Bot öffnen. | Fragen und Antworten in der gewählten Sprache. |

### G. Regressionen (bitte kurz prüfen)

| Nr. | Was tun | Was soll passieren |
|---|---|---|
| 47 | Kurze Gehprobe (2–3 Minuten, Pace geöffnet). | Live-Schritte steigen während des Gehens; „Unbestätigte Schritte verfallen“ erst etwa 20 Minuten nach dem letzten Schritt (wie Auftrag 5). |
| 48 | Social → Gruppe → Chat → Flamme → Chat … 20-mal, dann „‹“ ganz zurück. | Keine Schleife, keine neuen Ebenen. |
| 49 | Zwischen den vier Tabs wischen, abbrechen, zurückziehen. | Richtung wie bisher: Finger nach links → nächster Tab von rechts. |
| 50 | Home → Anpassen → Widgets ziehen, Größe ändern, entfernen, Rückgängig, hinzufügen. | Wie bisher. |

**Grenzen (ehrlich):** Alle Punkte sind nur automatisch geprüft (Unit-Tests, Simulator-Tests in der CI). Die
seitliche Verschiebung trat im Simulator nicht auf; die Sperre ist mehrfach abgesichert, bestätigt ist sie erst mit
Testfall A auf deinem iPhone. Der Pace-Bot ist ein fester Fragenkatalog ohne KI. Push-Mitteilungen über Apple (APNs)
sind nicht eingerichtet; die Willkommensmitteilung ist eine interne Mitteilung in der App.

Wenn etwas nicht klappt: Screenshot und eine kurze Beschreibung (welcher Schritt, was passiert ist) an mich.
