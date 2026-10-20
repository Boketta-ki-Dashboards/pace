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

## 5. Was du testen kannst

### Sofort (ohne Server-Änderung)

- **Tab-Leiste:** Der aktive Tab zeigt Symbol und Text in einer mint Fläche.
- **Home:** Vier Regionskarten in einer Reihe; Kalender-Symbol öffnet den **Kalender** (erreichte Tage grün
  gefüllt, sonst Ring). Ein Tag wird beim ersten Antippen ausgewählt (Karte darunter); erneutes Antippen oder die
  Karte öffnet die **Tagesdetails**. In den Tagesdetails kannst du optional den Puls aus
  Apple Health freigeben.
- **Anpassen:** „Anpassen“ antippen → Widgets wackeln, X entfernt, „Größe auswählen“ (Klein/Mittel/Groß/Max),
  Widgets per Ziehgriff verschieben, „+ Widget hinzufügen“ öffnet die Galerie. Nach App-Neustart bleibt alles so.
- **Ranking ausgeschaltet:** Profil → „In regionalen Rankings erscheinen“ ausschalten → Home und Rankings zeigen
  eine unscharfe Karte „Ranking ausgeschaltet“; Antippen → „Ranking-Sichtbarkeit aktivieren“.
- **Profil:** Darstellung (Automatisch/Hell/Dunkel), **Sprache** (Deutsch/English/Русский – wirkt sofort),
  App-Icon, Mitteilungen (Erinnerung an das Tagesziel zu einer Uhrzeit), Hilfe & Feedback (Häufige Fragen).
- **Rankings:** Ebenen Stadt, Landkreis, Bundesland, Deutschland. „Freunde“ und „Gruppen“ sind schon zu sehen,
  funktionieren aber erst nach den Migrationen.

### Erst nach Freigabe und Einspielen der Supabase-Migrationen

Freunde, Gruppen, Chats, die Freunde- und Gruppen-Rankings, die Glocke, Profilbilder, Auffindbarkeit,
Blockieren/Melden, „Problem melden“/„Feedback senden“, Datenexport und Konto löschen brauchen die neuen
Server-Funktionen. Bis sie eingespielt sind, zeigt die App dort einen Hinweis, z. B. „Freunde, Gruppen und Chats sind
auf dem Server noch nicht eingerichtet.“ oder „Diese Funktion ist auf dem Server noch nicht eingerichtet.“ Die Schritte zum Einspielen stehen in `docs/SUPABASE_ROLLOUT.md` – ich führe sie erst nach deiner
ausdrücklichen Freigabe aus bzw. begleite dich dabei.

Danach am besten mit **zwei iPhones** (oder einem zweiten Testkonto auf einem zweiten Gerät):

- [ ] Social → „Freund hinzufügen“: Benutzernamen eintippen, „Hinzufügen“; auf dem zweiten Gerät unter
      „Freundschaftsanfragen“ annehmen.
- [ ] Freund öffnen → „Nachricht schreiben“ → Text, Foto und GIF (aus der Mediathek) senden; auf dem zweiten Gerät
      erscheinen sie ohne Neuladen.
- [ ] „Gruppe erstellen“ mit Bild, Typ, Privatsphäre, Einladung und Tagesziel → Gruppendetails mit Streak →
      Gruppenchat.
- [ ] „…“-Menü in der Suche: Profil teilen (an einen Chat), Nutzer blockieren.
- [ ] Profil → Konto & Profil: Name und Profilbild ändern, Profil-Link teilen (`pace://u/…` öffnet das Profil).
- [ ] Profil → Datenschutz & Daten: Datenexport (JSON-Datei). „Konto löschen“ nur mit einem Testkonto ausprobieren –
      es löscht wirklich alles.

Wenn etwas nicht klappt: Screenshot und eine kurze Beschreibung (welcher Schritt, was passiert ist) an mich.
