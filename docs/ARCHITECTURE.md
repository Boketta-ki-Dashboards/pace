# Architektur

## Grundprinzip

Die App ist ein **dünnes Xcode-App-Target** plus ein **lokales Swift Package (`PaceKit`)** mit klar getrennten
Modulen. Modulgrenzen werden vom Compiler erzwungen: Ein Feature kann nur verwenden, was es in `Package.swift`
als Abhängigkeit deklariert.

```
Pace (App-Target)            Composition Root: erzeugt konkrete Services, startet RootView
 ├── AppFeature              Routing (AppRouter), RootView, AppDependencies
 │    ├── HealthPermissionFeature   Health-Permission-Flow
 │    ├── HomeFeature               Home-Screen mit heutiger Schrittzahl
 │    ├── DesignSystem              Farben, Typografie, Abstände, Komponenten
 │    └── PaceCore                  Modelle, Service-Protokolle, Use Cases (nur Foundation)
 └── PaceHealth              HealthKitService (einzige Stelle mit `import HealthKit`)
      └── PaceCore
```

Regeln:

- **Features kennen nur Protokolle** aus `PaceCore` (`HealthAuthorizationProviding`, `StepCountProviding`),
  nie konkrete Services. Konkrete Services werden ausschließlich in `Pace/AppDependencies+Live.swift` erzeugt.
- **Keine Business-Logik in Views.** Jedes Feature hat ein `@Observable`-ViewModel ohne SwiftUI-Import.
  Views rendern nur Zustand und leiten Aktionen weiter.
- **Jeder Systemdienst bekommt ein eigenes Modul** (heute: `PaceHealth`; später z. B. `PaceBackend` für Supabase,
  `PaceNotifications`, `PaceMotion`, `PaceWidgetData`).
- **Gemeinsame UI gehört ins `DesignSystem`**, nicht in Features.
- **Swift 6 Sprachmodus** mit vollständiger Concurrency-Prüfung, Deployment Target **iOS 17**.

## Dateistruktur

```
pace/
├── Pace.xcodeproj/                     Xcode-Projekt (synchronisierte Ordner, geteiltes Schema „Pace“)
├── Pace/                               App-Target – nur Einstieg und Komposition
│   ├── PaceApp.swift                   @main, hält den AppRouter
│   ├── AppDependencies+Live.swift      Composition Root (erzeugt HealthKitService)
│   └── Resources/Assets.xcassets       App-Icon, Akzentfarbe
├── Config/
│   └── Pace.entitlements               HealthKit-Entitlement
├── Packages/PaceKit/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── PaceCore/
│   │   │   ├── Health/                 HealthAuthorizationProviding, HealthDataError
│   │   │   └── Steps/                  DailyStepCount, StepCountProviding, TodayStepsLoader
│   │   ├── PaceHealth/
│   │   │   └── HealthKitService.swift
│   │   ├── DesignSystem/
│   │   │   ├── Tokens/                 PaceColor, PaceFont, PaceSpacing/PaceRadius
│   │   │   └── Components/             Buttons, PaceCard, PaceStatusView, PaceLoadingView
│   │   ├── HealthPermissionFeature/
│   │   │   ├── HealthPermissionViewModel.swift
│   │   │   └── Views/HealthPermissionView.swift
│   │   ├── HomeFeature/
│   │   │   ├── HomeViewModel.swift
│   │   │   └── Views/                  HomeView, HomeContentView, TodayStepsCard
│   │   └── AppFeature/
│   │       ├── AppDependencies.swift, AppRoute.swift, AppRouter.swift
│   │       └── Views/                  RootView, HealthDataUnavailableView
│   └── Tests/
│       ├── PaceTestSupport/            HealthServiceStub, Fixtures (nur für Tests)
│       ├── PaceCoreTests/
│       ├── HealthPermissionFeatureTests/
│       ├── HomeFeatureTests/
│       └── AppFeatureTests/
├── .github/workflows/ios.yml           CI: Build + Tests auf macOS mit Xcode
└── docs/ARCHITECTURE.md
```

Neue Swift-Dateien im Ordner `Pace/` erkennt Xcode automatisch (synchronisierte Ordner). Neue Dateien in
`Packages/PaceKit/Sources/<Modul>/` gehören automatisch zum jeweiligen Modul.

## Routing

`AppRouter` (in `AppFeature`) besitzt die aktuelle `AppRoute` und das ViewModel des jeweiligen Screens:

| Route                   | Wann                                                                 |
|-------------------------|----------------------------------------------------------------------|
| `launching`             | App-Start, bis der Health-Status ermittelt ist                       |
| `healthDataUnavailable` | Gerät unterstützt kein HealthKit                                     |
| `healthPermission`      | Nutzer wurde noch nicht gefragt (oder Status unbekannt)              |
| `home`                  | Zugriffsabfrage wurde bereits angezeigt                              |

Nach Abschluss des Permission-Dialogs wechselt der Router zu `home`.

## HealthKit: Datenschutz und Zugriffserkennung

- Pace fordert **nur Lesezugriff auf `stepCount`** an und schreibt nichts in Health.
- Die Tagessumme kommt aus einer `HKStatisticsQuery` mit `.cumulativeSum`. HealthKit dedupliziert dabei
  überlappende Quellen (iPhone + Apple Watch), der Wert entspricht also dem der Health-App.
- **HealthKit verrät nicht, ob Lesezugriff verweigert wurde.** Ohne Zugriff sind schlicht keine Daten sichtbar.
  `TodayStepsLoader` behandelt das so:
  1. Heute gibt es Samples → Schrittzahl anzeigen.
  2. Heute keine Samples, aber irgendwann gab es welche → **0 Schritte** anzeigen.
  3. Überhaupt keine Samples lesbar → Zustand **„Keine Schrittdaten lesbar“** mit Anleitung, wie man den Zugriff
     in der Health-App aktiviert (und Hinweis auf „Fitness-Tracking“, falls der Zugriff bereits erlaubt ist).
- Aktualisierung: beim Erscheinen, per Pull-to-Refresh, bei Rückkehr in den Vordergrund und live über eine
  `HKObserverQuery`, solange der Home-Screen sichtbar ist.
- Für das Backend (spätere Milestones) gilt: nur aggregierte Tageswerte (`DailyStepCount`), keine Rohdaten.

## Tests

Die Tests nutzen Swift Testing und laufen gegen `HealthServiceStub` statt HealthKit:

- `TodayStepsLoaderTests` – Tagesintervall (inkl. Sommerzeitwechsel), 0 Schritte vs. kein Zugriff, Fehler
- `HealthPermissionViewModelTests` – Erfolg, Fehler, erneuter Versuch
- `HomeViewModelTests` – alle Zustände, Retry, Live-Aktualisierung, Beenden der Beobachtung
- `AppRouterTests` – Routing je nach Health-Status, Übergang Permission → Home

In Xcode: Schema **Pace**, ⌘U. Der HealthKit-Service selbst ist nur auf echten Geräten bzw. im Simulator
sinnvoll prüfbar.
