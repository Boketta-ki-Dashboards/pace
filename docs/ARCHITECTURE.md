# Architektur

## Grundprinzip

Die App ist ein **dünnes Xcode-App-Target** plus ein **lokales Swift Package (`PaceKit`)** mit klar getrennten
Modulen. Modulgrenzen werden vom Compiler erzwungen: Ein Feature kann nur verwenden, was es in `Package.swift`
als Abhängigkeit deklariert.

```
Pace (App-Target)            Composition Root: erzeugt HealthKitService + SupabaseBackend, startet RootView
 ├── AppFeature              Routing (AppRouter), Tabs Home · Rankings · Social · Profil (MainTabView)
 │    ├── HealthPermissionFeature   Health-Permission-Flow
 │    ├── HomeFeature               anpassbares Home-Dashboard → ActivityFeature
 │    │    └── ActivityFeature      Detail-Statistiken (Swift Charts)
 │    ├── OnboardingFeature         Profil anlegen, Region wählen → RegionFeature
 │    ├── LeaderboardFeature        Regionale Daily Rankings
 │    ├── SocialFeature             Freunde, Anfragen, Gruppen mit Gruppen-Streak, Einladungen
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
            vollständig → Main App (Tabs: Home · Rankings · Social · Profil)
  → Konto gelöscht (Profil → Datenschutz & Daten) → Hinweis „Konto gelöscht“ → „Neu beginnen“
            → neue anonyme Sitzung → Onboarding
```

- Ein vollständiges Profil wird lokal zwischengespeichert (`UserDefaultsProfileCache`). Ist es vorhanden, startet
  die App auch offline direkt in die Main App und gleicht das Profil im Hintergrund ab.
- `AppRoute` besitzt das ViewModel des aktuellen Screens. Die Main App teilt einen `ProfileStore` (Profil + Region)
  zwischen Home, Rankings und Profil.
- Deep Links: `pace://u/<benutzername>` (URL-Schema in `Config/Info.plist`). `RootView.onOpenURL` → `AppRouter.open(_:)`
  → `PaceLink(url:)` → `MainViewModel.open(_:)` (Social-Tab, `SocialViewModel.showProfile(username:)`). Kommt der Link
  vor dem Start der Main App (Kaltstart, Onboarding), merkt sich der Router ihn (`pendingLink`) und führt ihn danach
  aus. Ob das Profil sichtbar ist, entscheidet der Server.
- Weitere Tabs kommen als zusätzlicher Fall in `MainViewModel.Tab` mit eigenem Feature-Modul hinzu. Home wechselt
  über Callbacks in andere Tabs (z. B. eine Ranking-Karte → Rankings mit dieser Ebene), ohne die Main App zu kennen.

## Home-Dashboard

- `HomeDashboardViewModel` setzt das Dashboard aus Modulen (`HomeModule`) zusammen: Platzierungen, Schritte heute,
  Woche, Serie, Umfeld, Freunde, Gruppen. Jedes Modul hat eine Größe (klein, mittel, groß); „Dein Umfeld“ zusätzlich
  eine Ebene (Gemeinde, Kreis, Bundesland, Deutschland) und darf mehrfach vorkommen. Über „Anpassen“ lassen sich
  Module hinzufügen, entfernen, verschieben und einstellen (`HomeSettings`, lokal in den `UserDefaults`). „Deine
  Schritte heute“ bleibt immer erhalten und ist nie klein. Ein neues Modul ist eine neue `HomeModuleKind` plus View.
- Gespeichert wird Version 2 (`modules`). Einstellungen der Version 1 (`sections` mit Sichtbarkeit) werden beim Laden
  übernommen: sichtbare Bereiche in derselben Reihenfolge, dazu die neue Serie nach der Woche. Module unbekannter Art
  (z. B. aus einer neueren Version) werden übersprungen statt das Layout zu verwerfen.
- Größen ändern nur die Darstellung vorhandener Daten – zusätzliche HealthKit-Abfragen entstehen dadurch nicht.
  Umfeld-Module bestimmen, wie viele Plätze je Ebene geladen werden (`neighborhoodRadii`: klein 1, mittel 2, groß 4);
  die Platzierungs-Karten brauchen nur den eigenen Platz. Gibt es eine gewählte Ebene für die Region nicht als eigenes
  Ranking (kreisfreie Stadt ohne Kreis, Berlin/Hamburg), zeigt das Modul die nächst kleinere vorhandene Ebene; „Anpassen“
  bietet nur vorhandene Ebenen an.
- Das Tagesziel ist eine lokale Einstellung und beeinflusst keine Rankings.
- Platzierungen und Umfeld (`RegionalStandingsViewModel`) nutzen die bestehenden Ranking-RPCs (eigene Position
  ± Nachbarn je Ebene); es gibt dafür keine neue Backend-Funktion.
- Darstellung: Komponenten in `HomeFeature/Views/Dashboard/`, gemeinsame Bausteine im `DesignSystem` (Karten, Kacheln,
  Fortschrittsring, Avatar, Wortmarke, Flamme der Serie).

## Social (Freunde und Gruppen)

- Backend: Migration `20261018100000_social.sql`, Regeln und RPC-Vertrag in `docs/SOCIAL.md`. Clients haben keinen
  Tabellenzugriff; alle Prüfungen (Zugriff, Limits, Gruppen-Streak) laufen in `security definer`-Funktionen.
- App: `SocialRepository` (PaceCore) → `SupabaseSocialRepository` (PaceBackend). `SocialViewModel` hält Freunde,
  Anfragen, Freundesranking, Gruppen und Einladungen (ein gemeinsamer Ladevorgang, höchstens einmal pro Minute
  automatisch) und wird von Social-Tab und Home-Modulen geteilt. `GroupDetailViewModel` und
  `FriendProfileViewModel` für die Detailansichten.
- Fehlt die Migration auf dem Server (PostgREST `PGRST202`), zeigen Social-Tab und Module einen ehrlichen Hinweis
  statt scheinbar funktionierender Oberflächen. Einen Gruppenchat gibt es bewusst nicht (keine Moderation).

## Profil und Einstellungen

- Es gibt keinen eigenen Einstellungen-Tab: Der Profil-Tab zeigt oben Wortmarke, Titel und die Profilkarte
  (Profilbild, Namen, Teilen-Knopf), darunter Aktivität (Tagesziel, Serie, Rekord, Statistik), Region,
  Ranking-Sichtbarkeit, Darstellung und die Kategorien der Einstellungen als eigene Unterseiten
  (`ProfileRoute`, `NavigationStack(path: $viewModel.path)`). Details, Datenflüsse und Grenzen: `docs/SETTINGS.md`.
- `ProfileViewModel` bekommt die Dienste über `ProfileSettingsServices` (Einstellungen, Mitteilungen, Konto, Medien,
  Social, Anmeldung, lokale Daten, App-Version) und besitzt die Unter-ViewModels (`AccountSettingsViewModel`,
  `PrivacySettingsViewModel`, `NotificationSettingsViewModel`, `DataPrivacyViewModel`).
- „App-Icon“: Automatisch, Hell, Dunkel (alternative App-Icons über `AppIconSetting`; die App zeigt keine eigene
  Erfolgsmeldung, iOS bestätigt den Wechsel selbst).

## Statistik, Zielverlauf und Streak

- `StatisticsView` (ActivityFeature) zeigt Tag, Woche (ISO, Mo–So) und Monat für Schritte, Distanz und aktive
  Kalorien. Die Berechnung steckt vollständig in `StatisticsReport` (rein, ohne SwiftUI, getestet); das ViewModel
  wählt nur Zeitraum, Kennzahl und Tag und lädt Stundenwerte für die Tagesansicht.
- Regeln der Berechnung: Der Vergleich mit Vorwoche/Vormonat nutzt den Tagesschnitt der **abgeschlossenen** Tage (der
  laufende Tag würde ihn drücken; am ersten Tag des Zeitraums gibt es noch keinen Vergleich). Prozent zum Ziel werden
  abgerundet (99,6 % erscheinen nicht als 100 %). Eine Ziellinie gibt es nur, wenn das Ziel im ganzen Zeitraum gleich
  war. Nicht lesbare Kennzahlen zeigen „nicht verfügbar“ statt 0 – auch keine leeren Stundenbalken.
- Navigation von Home: Schrittzahl → Tagesansicht von heute, Distanz/Kalorien → Wochenstatistik der Kennzahl,
  „Deine Woche“ → Wochenstatistik, ein Wochentag → Tagesansicht dieses Tags (`StatisticsRoute`, wertbasiert).
- `ActivityHistoryStore` hält den Verlauf (12 Monate) für alle Ansichten und ergänzt die live aktualisierten letzten
  7 Tage aus Home. `StepStreakTracker` berechnet daraus die persönliche Streak (`StepStreakCalculator`, PaceCore)
  und speichert den Rekord. Das Serien-Modul auf Home lädt den Verlauf beim Erscheinen und bei Rückkehr in die App
  (nur, wenn er veraltet ist); der Rekord wird gespeichert, sobald die längste Serie ihn übertrifft.
- `StepGoalSettings` (PaceCore) speichert das Tagesziel als Verlauf (`StepGoalHistory`): Eine Änderung gilt ab
  heute, vergangene Tage behalten ihr Ziel – Zieltage und Streak ändern sich dadurch nicht rückwirkend. Das Ziel
  älterer Versionen (in den Home-Einstellungen) wird beim ersten Start einmalig übernommen.

## Aktualisierung der Schritte

- HealthKit-Observer (`HKObserverQuery`) für alle gelesenen Typen: neue Samples lösen sofort ein Neuladen aus.
- Zusätzlich, solange die App im Vordergrund ist, alle 15 Sekunden eine Abfrage aus Apple Health, falls Meldungen
  verzögert oder gebündelt ankommen. Das Lesen ist lokal; geänderte Schritte gehen wie sonst gedrosselt (höchstens
  einmal pro Minute) an das Backend, und die Platzierungen auf Home werden höchstens einmal pro Minute nachgeladen.
  Unveränderte Werte lösen weder ein Neuzeichnen noch einen Upload aus.
- Sofortiges Neuladen bei Rückkehr in die App sowie bei Tages-, Zeitzonen- und Sommerzeitwechsel.
- Grenze: iOS schreibt die Schritte des iPhones gebündelt nach Apple Health. Schneller als Health selbst kann Pace die
  Werte daher nicht anzeigen. Echtes Live-Zählen ginge nur über CoreMotion (eigene Berechtigung) und ist bewusst nicht
  eingebaut.
- Die Auslöser hängen an der ganzen Main App (`activityUpdates(_:)`), nicht an einem Tab.

## Datenfluss Bewegung → Ranking

```
HealthKit ──▶ HealthKitService (Tagessummen, dedupliziert)
          ──▶ ActivitySummaryLoader (7 Tage → heute/gestern/Woche/7 Tage, nil statt Fake-0)
          ──▶ HomeViewModel ──▶ Home + Statistiken
                    └──▶ ActivitySyncCoordinator (nur Competition Steps, nur geänderte Tage, gedrosselt)
                              └──▶ SupabaseActivitySyncRepository ──▶ daily_activity (Upsert)
LeaderboardViewModel ──flush──▶ ActivitySyncCoordinator
                     ──▶ LeaderboardLoader (Top 50 + eigene Position ± 1) ──▶ RPCs leaderboard_page/neighborhood
RegionalStandingsViewModel (Home) ──flush──▶ ActivitySyncCoordinator
                     ──▶ je Ebene RPC leaderboard_neighborhood (eigener Platz ± 2 in der Gemeinde, sonst ± 0)
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
│   │   │   ├── Settings/               AppSettings, Mitteilungen, lokale Kontodaten, Datenexport
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
│   │   ├── SocialFeature/
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
├── Branding/                           Wortmarke (Quelle) + Generator für App-Icon, Startbildschirm, Wortmarke
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
| `main` | Tabs Home · Rankings · Social · Profil |
| `accountDeleted` | Konto gelöscht – „Neu beginnen“ startet mit einer neuen anonymen Identität (Onboarding) |

## Tests

- Swift Testing, Test-Doubles in `Tests/PaceTestSupport` (keine echten Services in Unit-Tests).
- `PaceCore` und `PaceBackend` bauen auch unter Linux und auf macOS (Integrationstests in der CI). Die Feature-Module
  enthalten SwiftUI-Views und werden deshalb im iOS-Simulator getestet; `PaceHealthTests` prüft dort die
  HealthKit-Abfragen (u. a. den Filter gegen manuell eingetragene Schritte).
- `ios.yml` baut die App mit Xcode, führt alle Unit-Tests im iOS-Simulator aus, baut die Integrationstests auf macOS
  und bricht bei Compiler-Warnungen in App-, Paket- oder Test-Code ab. CI benötigt keine Zugangsdaten.
- `backend.yml` startet einen lokalen Supabase-Stack (keine Produktionsdaten, keine Zugangsdaten) und führt
  pgTAP-Tests und Swift-Integrationstests aus.
- `PaceSnapshotTests` rendert Home, Rankings, Social, Profil und die Einstellungs-Unterseiten mit Beispieldaten in Hell
  und Dunkel (Hauptscreens zusätzlich auf Englisch und Russisch) als PNG – nur,
  wenn `PACE_SNAPSHOT_DIR` gesetzt ist. `ios.yml` lädt die Bilder als Artefakt „snapshots“ hoch (visuelle Kontrolle,
  kein Pixelvergleich).
- HealthKit selbst lässt sich nur auf echten Geräten bzw. im Simulator mit eingetragenen Daten sinnvoll prüfen.
