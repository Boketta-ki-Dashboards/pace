# Pace

Native iOS-App, die tägliche Bewegung zu einem Social Game macht: **Wer bewegt sich heute am meisten?**

## Stand: Funktions-Update (Statistik, Serien, Module, Freunde & Gruppen)

- Bewegungsdaten aus Apple Health (nur lesen): Schritte, Distanz, aktive Kalorien, Stockwerke, Trainingsminuten
- **Health Steps vs. Competition Steps**: manuell eingetragene Schritte zählen nicht für Rankings
- Home-Dashboard aus Modulen (klein/mittel/groß, hinzufügen, entfernen, verschieben) und Statistik für Tag, Woche
  und Monat (Schritte, Distanz, Kalorien, Zieltage, Bestwerte, Vergleich zum Vorzeitraum, Tagesdetails)
- Persönliche Serie (Tagesziel in Folge erreicht, mit Zielverlauf) und Rekord
- Supabase-Backend: anonyme MVP-Identität, Profile, deutsches Regionensystem nach amtlichem Gemeindeverzeichnis,
  Sync der täglichen Competition Steps, regionale Daily Rankings (Gemeinde, Kreis, Bundesland, Deutschland)
- Onboarding (Profil + Region mit ausdrücklicher Zustimmung zu Regionalrankings)
- Freunde (Suche per Benutzername, Anfragen, Freundesranking, Profil) und Gruppen (erstellen, Code, Einladungen,
  Gruppenranking, Gruppen-Streak nach der Ein-Drittel-Regel) – serverseitig geprüft, siehe `docs/SOCIAL.md`
- Pace-Design (grüne Markenidentität, Light/Dark); Tabs Home · Rankings · Social · Profil; App-Icon wählbar
  (Automatisch, Hell, Dunkel)

Noch nicht enthalten: Gruppenchat, Challenges, Widgets, Benachrichtigungen, Karte, Kontoübertragung auf andere
Geräte.

App-Icons, Startbildschirm-Logo und Wortmarke entstehen aus `Branding/source/pace-wordmark.jpg`:
`python3 -I Branding/generate_assets.py` (benötigt Pillow).

## Voraussetzungen

- Xcode 16.3 oder neuer (CI: neueste stabile Xcode-Version des GitHub-Runners `macos-15`)
- iOS 17 oder neuer
- Für echte Schrittdaten ein iPhone. Im Simulator in der Health-App unter „Schritte“ → „Daten hinzufügen“ Werte
  anlegen. Achtung: Das sind manuelle Einträge – sie erscheinen als Health Steps, aber nicht als Competition Steps.

## Starten

1. `Pace.xcodeproj` in Xcode öffnen.
2. Lokale Konfiguration anlegen (wird nie committet):
   ```sh
   cp Config/Pace.xcconfig.example Config/Pace.xcconfig
   ```
   In `Config/Pace.xcconfig` die Project URL **ohne** `https://` und den Publishable Key des Pace-Supabase-Projekts
   eintragen. Details: [docs/BACKEND.md](docs/BACKEND.md#lokale-konfiguration).
3. Target **Pace** → *Signing & Capabilities*: eigenes Team wählen und ggf. die Bundle-ID `app.pace.ios` anpassen.
4. Schema **Pace** ausführen.

Ohne `Config/Pace.xcconfig` baut die App trotzdem und zeigt nach der Health-Abfrage den Hinweis
„Backend nicht konfiguriert“.

## Aktualisieren (Änderungen auf den Mac holen)

Xcode speichert dein Signing-Team in `Pace.xcodeproj/project.pbxproj`. Damit ein Pull deine lokalen Einstellungen
nicht überschreibt oder blockiert:

```sh
git status                                  # zeigt lokale Änderungen, z. B. project.pbxproj (Signing)
git stash push -m signing Pace.xcodeproj/project.pbxproj   # nur falls dort Änderungen stehen
git pull origin claude/gallant-brahmagupta-hvvp13
git stash pop                               # Signing wiederherstellen
```

`Config/Pace.xcconfig` ist von Git ausgenommen und bleibt beim Pull unverändert. Danach in Xcode
**Product → Clean Build Folder** (neue App-Icons) und unter *Signing & Capabilities* kurz prüfen, ob dein Personal
Team gewählt ist. Dieses Update ändert `project.pbxproj` nicht; die alternativen App-Icons stehen in
`Config/Base.xcconfig`.

## Tests

- Xcode: Schema **Pace**, ⌘U (alle Tests aus `Packages/PaceKit/Tests`).
- Datenbank (Docker nötig): `supabase start` und `supabase test db` im Repository-Wurzelverzeichnis.
- CI: `.github/workflows/ios.yml` (Build, Warnungsprüfung, Unit-Tests) und `.github/workflows/backend.yml`
  (Secret-Scan, lokaler Supabase-Stack, pgTAP-Tests, Swift-Integrationstests). Die CI braucht keine Zugangsdaten.

## Dokumentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) – Module, Ablauf, Datenfluss
- [docs/BACKEND.md](docs/BACKEND.md) – Supabase, Schema, RLS, Regionen, Rankings, Produktionshinweise
- [docs/HEALTH_DATA.md](docs/HEALTH_DATA.md) – welche Gesundheitsdaten wofür genutzt werden
- [docs/SOCIAL.md](docs/SOCIAL.md) – Freunde, Gruppen, Gruppen-Streak, Limits und Datenschutz
- [docs/MANUAL_TESTS.md](docs/MANUAL_TESTS.md) – Checkliste für den Test auf dem iPhone
