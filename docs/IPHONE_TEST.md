# Nächster iPhone-Test – einfache Anleitung (Auftrag 7)

Diese Anleitung setzt voraus, dass Pace schon einmal aus Xcode auf deinem iPhone lief (Personal Team, eigene
`Config/Pace.xcconfig` mit den Supabase-Werten). Daran ändert sich nichts: Signing, Bundle Identifier
(`com.boketta.pace.ios` auf deinem iPhone), Berechtigungen und deine lokale Konfiguration bleiben, wie sie sind.
`Config/Pace.xcconfig` ist von Git ausgeschlossen und wird beim Aktualisieren nicht überschrieben. Deine anonyme
Pace-Identität bleibt erhalten, es gibt keine neue Anmeldung.

Wichtig: Alle Punkte unten wurden bisher nur automatisch geprüft (Unit-Tests unter Linux, lokale Docker-Datenbank,
Simulator in der CI) – **nicht auf einem echten iPhone**. Besonders die Wischgeste in der Statistik und der
Abstand der Knöpfe im Home-Anpassen-Kopf zeigen sich erst auf dem Gerät wirklich.

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

**GIF-Suche (GIPHY) und Support-E-Mail für den Pace-Bot:** unverändert gegenüber Auftrag 6 (Einträge in
`Config/Pace.xcconfig` bleiben, nichts Neues nötig).

**Datenbank-Update für Interessen 2.0:** Der größere Interessenkatalog, eigene Interessen, mehr als fünf Interessen,
gesprochene Sprachen und Land brauchen die neue Migration `20261102100000_profile_interests.sql`. Sie ist **nicht**
eingespielt – das entscheidest du selbst, nach der Anleitung in [SUPABASE_ROLLOUT.md](SUPABASE_ROLLOUT.md) (Abschnitt
„Auftrag 7“). Ohne Migration zeigt „Profil bearbeiten“ wie bisher höchstens fünf Interessen aus dem ursprünglichen
Katalog und den Hinweis „Mehr Interessen, eigene Begriffe und Sprachen kommen mit dem nächsten Server-Update.“ Alle
anderen Testfälle funktionieren auch ohne Migration. Die Profil-2.0-Migration aus Auftrag 6 bleibt, wie sie ist.

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

Dieses Update fragt nach **keinen neuen Berechtigungen**. Für Profilbild und Banner öffnet sich die Fotoauswahl von
iOS – dort wählst du nur einzelne Fotos aus, Pace bekommt keinen Zugriff auf die ganze Mediathek.

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

Bitte bei jedem Punkt kurz notieren: ✅ passt / ❌ Problem (mit Screenshot, wenn möglich). Am besten einmal in Hell und
einmal in Dunkel prüfen, dazu einmal mit größerer Schrift (Einstellungen → Anzeige & Helligkeit → Textgröße).

### A. Home-Anpassen-Kopf

1. Home → **Anpassen**. Oben rechts steht „Fertig“, darunter rechts „+ Widget hinzufügen“ (oder in einer Zeile neben
   der Begrüßung, wenn genug Platz ist). Die beiden mintfarbenen Knöpfe dürfen sich **nicht berühren oder
   überlappen**, keiner ist abgeschnitten.
2. Beide Knöpfe antippen: „+ Widget hinzufügen“ öffnet die Galerie, „Fertig“ beendet den Modus.
3. Im Anpassen-Modus nach unten scrollen, ein Widget am Griff verschieben: funktioniert wie bisher, die Seite
   verrutscht nicht seitlich, die Tab-Leiste unten ist unverändert.
4. App-Sprache auf Englisch und Russisch stellen (Profil → Sprache) und Punkt 1 wiederholen.

### B. Pace-Bot in der Chatliste

1. Social → Chats („Alle“): Hast du den Bot noch nie gefragt, steht er **ganz unten**, gekennzeichnet mit „Bot“.
2. Bot öffnen, eine Frage antippen, zurück: Der Bot steht jetzt an der Stelle seiner letzten Frage (meist oben).
3. Lass dir von einem zweiten Konto eine Nachricht in eine Gruppe oder privat schicken: Dieser Chat steht danach
   **über** dem Bot.
4. App beenden und neu starten, Social erneut öffnen, Sprache wechseln: Der Bot springt dabei **nicht** nach oben.
5. Filter „Freunde“ und „Gruppen“: Der Bot erscheint dort nicht; unter „Alle“ genau einmal. Kein Ungelesen-Zähler.
6. Suche oben: „Pace-Bot“, „Bot“ oder „Hilfe“ eingeben → der Bot erscheint als Treffer.
7. Flugmodus an, Social öffnen: Hinweis „Keine Verbindung“ und darunter **eine** Bot-Karte – der Bot antwortet weiter.
8. Willkommensmitteilung (Glocke) → „Pace-Bot öffnen“ öffnet den Bot.

### C. Statistik: ruhiges Wischen

1. Home → Schritte-Widget → Statistik, Tab „Tag“. Mehrmals schnell nach rechts wischen (Finger nach rechts =
   vorheriger Tag), dann nach links. Karte und Diagramm bewegen sich **gemeinsam**; keine Balken laufen gegenläufig,
   keine Balken außerhalb des Diagramms, nichts rastet nachträglich ein.
2. Eine Geste nur halb ausführen und loslassen: alles gleitet ruhig zurück.
3. Während das Diagramm noch einrastet, gleich weiterwischen: kein Springen.
4. Dasselbe in „Woche“ und „Monat“ sowie für Distanz und Kalorien.
5. Die Zurück-Geste vom linken Rand und das Wechseln der Haupttabs funktionieren wie bisher.

### D. Profilbild und Banner direkt bearbeiten

1. Profil → **Bearbeiten**: Oben steht eine Vorschau mit Banner und Profilbild (kleine Stift-Symbole).
2. Profilbild antippen → (bei vorhandenem Bild „Foto ändern“) → Foto wählen → Ausschnitt verschieben → „Verwenden“:
   Das neue Bild erscheint sofort, auch auf der Profilseite und in Social.
3. Banner antippen → Foto wählen → Ausschnitt (3:1) verschieben → „Verwenden“.
4. Bild und Banner jeweils über „Entfernen“ löschen: Platzhalter bzw. neutraler Pace-Hintergrund erscheint.
5. Während ein Bild hochlädt, sind die anderen Bild-Knöpfe gesperrt (Ladeanzeige).

### E. Interessen, Sprachen, Land (nur mit eingespielter Migration, siehe Abschnitt 2)

1. Profil → Bearbeiten → Interessen: fünf Kategorien (Sport & Bewegung, Musik & Kreativität, Technik & Gaming, Alltag &
   Freizeit, Sprachen & Kultur), auf- und zuklappbar. Mehr als fünf auswählen geht (bis 20).
2. „+ Eigenes Interesse hinzufügen“ → „Musik produzieren“ → „Hinzufügen“ → erscheint unter „Deine Auswahl“.
3. „rap“ eingeben: Pace schlägt den Katalogeintrag „Rap“ vor; „Hinzufügen“ wählt ihn aus. Dasselbe in anderer
   Schreibweise noch einmal → „Schon ausgewählt.“
4. Ein eigenes Interesse auf Russisch und eines mit Emoji anlegen; ein sehr langes (über 30 Zeichen) wird abgelehnt.
5. Gesprochene Sprachen → „Sprachen auswählen“ → suchen (z. B. „Serb“), mehrere wählen → „Fertig“.
6. Land & Kultur → „Land auswählen“ → suchen, wählen; danach „Land entfernen“ testen.
7. Speichern. Profilseite: alle Interessen, darunter Sprachen und Land.
8. Mit einem zweiten Konto dein Profil öffnen: zunächst sechs Interessen und „Alle Interessen ansehen“; Sprachen und
   Land sichtbar. Nach dem Blockieren keine dieser Angaben mehr.
9. App-Sprache wechseln: Katalog-Interessen sind übersetzt, eigene bleiben so, wie du sie geschrieben hast.

### F. Profil-Tab kehrt zur Hauptseite zurück

1. Profil → Einstellungen (z. B. Privatsphäre) öffnen → zu Social wechseln → zurück zu Profil: Die **Hauptseite**
   erscheint, ganz oben.
2. Dasselbe mit Darstellung, Sprache, Aktivität, Konto, Benachrichtigungen, Hilfe.
3. Profil → Bearbeiten → Bio ändern (nicht speichern) → zu Home wechseln → zurück: Die Seite „Profil bearbeiten“ mit
   deiner Änderung ist noch da (ungespeicherte Änderungen gehen nicht verloren). „Änderungen verwerfen“ oder
   „Speichern“ beendet das.
4. Auf der Profil-Hauptseite nach unten scrollen und erneut auf den Profil-Tab tippen: springt nach oben.
5. In einer Unterseite die Zurück-Geste vom linken Rand: geht wie bisher eine Seite zurück.

### G. Regressionen (bitte kurz prüfen)

- Home: Widgets, Schritte, Streak, Kalender, Mitteilungen; Haupttabs per Wischen wechseln.
- HealthKit: Schritte, Distanz, Kalorien aktuell.
- Social: Chats öffnen, Nachrichten, Sprachnachrichten, GIFs, Gruppen, Freunde, Rankings.
- Profil: Darstellung, Sprache, Bio, Auszeichnungen.
