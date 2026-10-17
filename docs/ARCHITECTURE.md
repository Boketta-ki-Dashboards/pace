# Architektur

## Grundprinzip

Die App ist ein **dünnes Xcode-App-Target** plus ein **lokales Swift Package (`PaceKit`)** mit klar getrennten
Modulen. Modulgrenzen werden vom Compiler erzwungen: Ein Feature kann nur verwenden, was es in `Package.swift`
als Abhängigkeit deklariert.

```
Pace (App-Target)            Composition Root: erzeugt HealthKitService + SupabaseBackend, startet RootView
 ├── AppFeature              Routing (AppRouter), Tab-Navigation (MainTabView), AppDependencies
 │    ├── HealthPermissionFeature   Health-Permission-Flow
 │    ├── HomeFeature               Dashboard (Competition Steps, kcal, km) → ActivityFeature
 │    │    └── ActivityFeature      Detail-Statistiken (Swift Charts)
 │    ├── OnboardingFeature         Profil anlegen, Region wählen → RegionFeature
 │    ├── LeaderboardFeature        Regionale Daily Rankings
 │    ├── ProfileFeature            Profil/Einstellungen → RegionFeature
 │    │    └── RegionFeature        Gemeindesuche (wiederverwendbar)
 │    ├── DesignSystem              Farben, Typografie, Abstände, Komponenten
 │    └── PaceCore                  Modelle, Protokolle, Use Cases (nur Foundation + Observation)
 ├── PaceHealth              HealthKitService (einziges Modul mit `import HealthKit`)
 └── PaceBackend             Supabase (einziges Modul mit `import Auth`/`PostgREST`)
```

Regeln:

- **Features kennen nur Protokolle** aus `PaceCore` (`ActivityDataProviding`, `AuthProviding`,
  `ProfileRepository`, `RegionRepository`, `ActivitySyncRepository`, `LeaderboardRepository`), nie konkrete
  Services. Konkrete Services entstehen ausschließlich in `Pace/AppDependencies+Live.swift`.
- **Keine Business-Logik in Views.** Jedes Feature hat `@Observable`-ViewModels ohne SwiftUI-Import. Views rendern
  nur Zustand und leiten Aktionen weiter. Supabase wird nie aus Views oder ViewModels angesprochen.
- **Jeder Systemdienst hat ein eigenes Modul** (`PaceHealth`, `PaceBackend`; später z. B. `PaceNotifications`,
  `PaceMotion`, `PaceWidgetData`).
- **Gemeinsame UI gehört ins `DesignSystem`**, nicht in Features.
- **Swift 6 Sprachmodus**, vollständige Concurrency-Prüfung, iOS 17. `@unchecked Sendable` nur mit Begründung im Code
  (`HKHealthStore` ist threadsicher; Test-Doubles schützen ihren Zustand mit einem Lock).

## App-Ablauf

```
App-Start
  → Health verfügbar? (sonst Hinweis)
  → Health-Abfrage nötig? → Permission-Screen
  → Backend konfiguriert? (sonst Hinweis für Entwickler)
  → Sitzung: gespeicherte nutzen, sonst anonym anmelden        (SessionBootstrapper)
  → Profil: fehlt → Onboarding Profil → Onboarding Region
            ohne Region → Onboarding Region
            vollständig → Main App (Tabs: Heute · Rankings · Profil)
```

- Ein vollständiges Profil wird lokal zwischengespeichert (`UserDefaultsProfileCache`). Ist es vorhanden, startet
  die App auch offline direkt in die Main App und gleicht das Profil im Hintergrund ab.
- `AppRoute` besitzt das ViewModel des aktuellen Screens. Die Main App teilt einen `ProfileStore` (Profil + Region)
  zwischen Rankings und Profil.
- Weitere Tabs (z. B. Social) kommen als zusätzlicher Fall in `MainViewModel.Tab` mit eigenem Feature-Modul hinzu.

## Datenfluss Bewegung → Ranking

```
HealthKit ──▶ HealthKitService (Tagessummen, dedupliziert)
          ──▶ ActivitySummaryLoader (7 Tage → heute/gestern/Woche/7 Tage, nil statt Fake-0)
          ──▶ HomeViewModel ──▶ Home + Statistiken
                    └──▶ ActivitySyncCoordinator (nur Competition Steps, nur geänderte Tage, gedrosselt)
                              └──▶ SupabaseActivitySyncRepository ──▶ daily_activity (Upsert)
LeaderboardViewModel ──flush──▶ ActivitySyncCoordinator
                     ──▶ LeaderboardLoader (Top 50 + eigene Position ± 1) ──▶ RPCs leaderboard_page/neighborhood
```

Details zu Gesundheitsdaten: [HEALTH_DATA.md](HEALTH_DATA.md). Backend, Schema, RLS und Regionen:
[BACKEND.md](BACKEND.md).

## Dateistruktur

```
pace/
├── Pace.xcodeproj/                     Xcode-Projekt (synchronisierter Ordner Pace/, geteiltes Schema „Pace“)
├── Pace/                               App-Target – nur Einstieg und Komposition
│   ├── PaceApp.swift
│   ├── AppDependencies+Live.swift      Composition Root
│   └── Resources/Assets.xcassets
├── Config/
│   ├── Base.xcconfig                   committet; bindet optional Pace.xcconfig ein
│   ├── Pace.xcconfig.example           committet; nur Platzhalter
│   ├── Pace.xcconfig                   lokal, gitignored (Supabase-URL + Publishable Key)
│   ├── Info.plist                      reicht die xcconfig-Werte an die App weiter
│   └── Pace.entitlements               HealthKit
├── Packages/PaceKit/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── PaceCore/
│   │   │   ├── Time/                   LocalDate, ActivityCalendar
│   │   │   ├── Activity/               DailyActivitySummary, Zeiträume, ActivitySummaryLoader
│   │   │   ├── Health/                 HealthAuthorizationProviding, HealthDataError
│   │   │   ├── Identity/               AuthProviding, UserID
│   │   │   ├── Profile/                UserProfile, Regeln, Repository, Cache, Bootstrap, ProfileStore
│   │   │   ├── Region/                 Region, RegionHierarchy, RegionRepository
│   │   │   ├── Leaderboard/            Modelle, Repository, LeaderboardLoader
│   │   │   └── Sync/                   DailyCompetitionSteps, ActivitySyncCoordinator
│   │   ├── PaceHealth/                 HealthKitService, HealthMetricMapping
│   │   ├── PaceBackend/                SupabaseBackend, Repositories, DTOs, BackendConfiguration
│   │   ├── DesignSystem/
│   │   ├── HealthPermissionFeature/
│   │   ├── ActivityFeature/
│   │   ├── HomeFeature/
│   │   ├── RegionFeature/
│   │   ├── OnboardingFeature/
│   │   ├── LeaderboardFeature/
│   │   ├── ProfileFeature/
│   │   └── AppFeature/
│   └── Tests/                          ein Test-Target pro Modul mit Logik + PaceTestSupport (Test-Doubles);
│                                       DesignSystem (reine Darstellung) hat keine eigenen Tests
├── Packages/PaceBackendIntegrationTests/   Swift-Tests gegen einen echten (lokalen) Supabase-Stack
├── supabase/
│   ├── config.toml                     lokale Supabase-CLI-Konfiguration
│   ├── migrations/                     versionierte SQL-Migrationen (inkl. Regionsdaten)
│   ├── seed/dev_seed.sql               NUR Entwicklung – wird nie in Produktion ausgeführt
│   ├── scripts/import_regions.py       Import des amtlichen Gemeindeverzeichnisses
│   └── tests/                          pgTAP-Tests (RLS, Profile, Sync, Rankings, Suche)
├── .github/workflows/
│   ├── ios.yml                         Xcode-Build, Warnungsprüfung, Tests
│   └── backend.yml                     Secret-Scan, lokaler Supabase-Stack, pgTAP, Integrationstests
└── docs/
    ├── ARCHITECTURE.md
    ├── BACKEND.md
    └── HEALTH_DATA.md
```

Neue Swift-Dateien im Ordner `Pace/` erkennt Xcode automatisch. Neue Dateien in
`Packages/PaceKit/Sources/<Modul>/` gehören automatisch zum jeweiligen Modul.

## Routing

| Route | Wann |
|---|---|
| `launching` | App-Start |
| `healthDataUnavailable` | Gerät unterstützt kein HealthKit |
| `healthPermission` | Health-Abfrage nötig (erstmals oder weil neue Datentypen hinzugekommen sind) |
| `backendUnavailable` | `Config/Pace.xcconfig` fehlt oder ist ungültig (nur Entwicklung) |
| `connecting` | Sitzung und Profil werden geprüft |
| `connectionFailed` | keine Verbindung beim ersten Start (ohne Profil-Cache) – mit „Erneut versuchen“ |
| `onboarding` | Profil oder Region fehlen |
| `main` | Tabs Heute · Rankings · Profil |

## Tests

- Swift Testing, Test-Doubles in `Tests/PaceTestSupport` (keine echten Services in Unit-Tests).
- `PaceCore` und `PaceBackend` bauen auch unter Linux und auf macOS (Integrationstests in der CI). Die Feature-Module
  enthalten SwiftUI-Views und werden deshalb im iOS-Simulator getestet; `PaceHealthTests` prüft dort die
  HealthKit-Abfragen (u. a. den Filter gegen manuell eingetragene Schritte).
- `ios.yml` baut die App mit Xcode, führt alle Unit-Tests im iOS-Simulator aus, baut die Integrationstests auf macOS
  und bricht bei Compiler-Warnungen in App-, Paket- oder Test-Code ab. CI benötigt keine Zugangsdaten.
- `backend.yml` startet einen lokalen Supabase-Stack (keine Produktionsdaten, keine Zugangsdaten) und führt
  pgTAP-Tests und Swift-Integrationstests aus.
- HealthKit selbst lässt sich nur auf echten Geräten bzw. im Simulator mit eingetragenen Daten sinnvoll prüfen.
