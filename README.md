# Pace

Native iOS-App, die tägliche Schritte zu einem Social Game macht.

## Stand: Milestone 1

- Xcode-Projekt mit modularer Struktur (App-Target + lokales Swift Package `PaceKit`)
- App-Routing (Start → Health-Permission → Home)
- Basis-Design-System
- `HealthKitService` (liest nur `stepCount`, schreibt nichts)
- Health-Permission-Flow
- Home-Screen mit der echten heutigen Schrittzahl aus Apple Health
- Lade-, Fehler- und „Kein Zugriff“-Zustände

Noch nicht enthalten: Freunde, Challenges, Leaderboards, Widgets, Karte, Chat, Backend.

## Voraussetzungen

- Xcode 16 oder neuer
- iOS 17 oder neuer
- Für echte Schrittdaten ein iPhone. Im Simulator gibt es keine Schritte – dort in der Health-App unter
  „Schritte“ → „Daten hinzufügen“ manuell Werte anlegen.

## Starten

1. `Pace.xcodeproj` in Xcode öffnen.
2. Target **Pace** → *Signing & Capabilities*: eigenes Team wählen und ggf. die Bundle-ID `app.pace.ios` anpassen.
   Das HealthKit-Entitlement ist bereits in `Config/Pace.entitlements` eingetragen.
3. Schema **Pace** auf einem iPhone oder Simulator ausführen.

## Tests

- Xcode: Schema **Pace**, ⌘U (führt alle Tests aus `Packages/PaceKit/Tests` aus).
- Kommandozeile:
  ```sh
  xcodebuild test -project Pace.xcodeproj -scheme Pace \
    -destination 'platform=iOS Simulator,name=iPhone 16'
  ```
- CI: `.github/workflows/ios.yml` baut und testet bei jedem Push auf macOS.

## Architektur

Siehe [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
