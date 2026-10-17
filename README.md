# Pace

Native iOS-App, die tägliche Bewegung zu einem Social Game macht: **Wer bewegt sich heute am meisten?**

## Stand: Milestone 2

- Bewegungsdaten aus Apple Health (nur lesen): Schritte, Distanz, aktive Kalorien, Stockwerke, Trainingsminuten
- **Health Steps vs. Competition Steps**: manuell eingetragene Schritte zählen nicht für Rankings
- Home-Dashboard (Competition Steps groß, kcal und km klein) und Detail-Statistiken (heute, letzte 7 Tage, Swift Charts)
- Supabase-Backend: anonyme MVP-Identität, Profile, deutsches Regionensystem nach amtlichem Gemeindeverzeichnis,
  Sync der täglichen Competition Steps, regionale Daily Rankings (Gemeinde, Kreis, Bundesland, Deutschland)
- Onboarding (Profil + Region mit ausdrücklicher Zustimmung zu Regionalrankings), Tabs Heute · Rankings · Profil

Noch nicht enthalten: Freunde, Gruppen, Challenges, Streaks, Widgets, Benachrichtigungen, Karte, Chat.

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

## Tests

- Xcode: Schema **Pace**, ⌘U (alle Tests aus `Packages/PaceKit/Tests`).
- Datenbank (Docker nötig): `supabase start` und `supabase test db` im Repository-Wurzelverzeichnis.
- CI: `.github/workflows/ios.yml` (Build, Warnungsprüfung, Unit-Tests) und `.github/workflows/backend.yml`
  (Secret-Scan, lokaler Supabase-Stack, pgTAP-Tests, Swift-Integrationstests). Die CI braucht keine Zugangsdaten.

## Dokumentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) – Module, Ablauf, Datenfluss
- [docs/BACKEND.md](docs/BACKEND.md) – Supabase, Schema, RLS, Regionen, Rankings, Produktionshinweise
- [docs/HEALTH_DATA.md](docs/HEALTH_DATA.md) – welche Gesundheitsdaten wofür genutzt werden
