# Backend (Supabase)

Pace nutzt ein **eigenes, separates Supabase-Projekt** (`https://bnkrenfvfiaapsbkeejq.supabase.co`,
Project Ref `bnkrenfvfiaapsbkeejq`). Andere Supabase-Projekte des Nutzers werden nicht verändert.

Grundsätze:

- In die App gelangt **nur der Publishable Key** (`sb_publishable_…`). Er ist laut Supabase für Apps gedacht und
  allein kein Schutz. Die Sicherheit entsteht durch **Auth + Row Level Security + serverseitige SQL-Funktionen**.
- **Secret Keys (`sb_secret_…`) und `service_role`-Keys kommen nie in die App oder ins Repository.** Drei Sperren:
  1. Der Build bricht ab, wenn ein solcher Schlüssel in `Config/Pace.xcconfig` steht (Build-Phase „Check Supabase
     Key“ → `Config/check_supabase_key.sh`), damit er nie in einer Info.plist, einem Archiv oder TestFlight landet.
  2. Die App verweigert zusätzlich den Start mit einem solchen Schlüssel (`BackendConfiguration`).
  3. Die CI (`backend.yml`, Job „Secret scan“) sucht bei Pushes auf `main` und `claude/**` sowie in Pull Requests
     nach Schlüsseln und prüft, dass `Config/Pace.xcconfig` nicht committet ist. Pushes auf andere Branches ohne
     Pull Request werden nicht gescannt.
- Das Backend speichert nur, was Social- und Wettbewerbsfunktionen brauchen. Gesundheitsdaten: ausschließlich die
  täglichen Competition Steps (siehe [HEALTH_DATA.md](HEALTH_DATA.md)).
- Supabase wird nur im Modul `PaceBackend` angesprochen, nie aus Views oder ViewModels.

## Lokale Konfiguration

| Datei | In Git | Inhalt |
|---|---|---|
| `Config/Base.xcconfig` | ja | leere Standardwerte, bindet `Pace.xcconfig` optional ein (`#include?`) |
| `Config/Pace.xcconfig.example` | ja | nur Platzhalter |
| `Config/Pace.xcconfig` | **nein** (`.gitignore`) | deine echten Werte |
| `Config/Info.plist` | ja | reicht `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` als `PaceSupabaseURL` / `PaceSupabasePublishableKey` an die App weiter |

Einrichten:

```sh
cp Config/Pace.xcconfig.example Config/Pace.xcconfig
```

In `Config/Pace.xcconfig` genau diese zwei Zeilen anpassen:

```
SUPABASE_URL = bnkrenfvfiaapsbkeejq.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_…   ← dein Publishable Key aus Supabase → Project Settings → API Keys
```

Die URL steht **ohne** `https://`, weil `//` in `.xcconfig`-Dateien einen Kommentar beginnt. Die App ergänzt
`https://` selbst und erkennt, wenn eine URL abgeschnitten wurde.

Prüfen, dass die Datei nicht committet wird:

```sh
git check-ignore -v Config/Pace.xcconfig   # zeigt die passende .gitignore-Zeile
git status --short Config/                 # Pace.xcconfig darf hier NICHT auftauchen
git ls-files Config/                       # listet nur Base.xcconfig, Info.plist, Pace.entitlements, Pace.xcconfig.example
```

Ohne `Config/Pace.xcconfig` (z. B. in der CI) baut die App normal; Unit-Tests verwenden Test-Doubles und brauchen
keine Zugangsdaten.

## Aufbau des Repositories

```
supabase/
├── config.toml                 lokale CLI-Konfiguration (anonyme Anmeldung an, Dev-Seed nur lokal)
├── migrations/                 versionierte Migrationen – einzige Quelle des Schemas
│   ├── 20261016100000_base.sql                       Schema private, pg_trgm, Enum region_level, Hilfsfunktionen
│   ├── 20261016100100_regions.sql                    Tabelle regions, Suche, Hierarchie
│   ├── 20261016100200_profiles.sql                   Tabelle profiles, Benutzernamen-Regeln
│   ├── 20261016100300_daily_activity.sql             Tabelle daily_activity (nur Competition Steps)
│   ├── 20261016100400_leaderboards.sql               Ranking-RPCs
│   └── 20261016100500_region_data_gv100ad_20260930.sql   generierte Regionsdaten (GV100AD)
├── seed/dev_seed.sql           DEV ONLY: erfundene dev_…-Nutzer für lokale Rankings
├── scripts/import_regions.py   Importer GV100AD → Migration (+ test_import_regions.py)
└── tests/*.test.sql            pgTAP-Tests (Rechte, RLS, Profile, Sync, Rankings, Regionen)
```

Die Swift-Seite liegt in `Packages/PaceKit/Sources/PaceBackend` (Repositories hinter den Protokollen aus `PaceCore`)
und `Packages/PaceBackendIntegrationTests` (Tests gegen einen echten lokalen Supabase-Stack).

## Datenmodell

### `public.regions`

Amtliche Gebietseinheiten in einer Hierarchie **Gemeinde → Kreis/kreisfreie Stadt → Bundesland → Land**.

| Spalte | Bedeutung |
|---|---|
| `id` | feste ID: `DE`, `DE:06` (Land), `DE:06432` (Kreis), `DE:06432018` (Gemeinde, AGS) |
| `level` | `municipality`, `district`, `state`, `country` |
| `code` | amtlicher Schlüssel (Landes-, Kreis-, Gemeindeschlüssel) bzw. ISO-Code |
| `name` / `official_name` | Anzeigename („Pfungstadt“) / amtliche Bezeichnung („Pfungstadt, Stadt“) |
| `kind` | Textkennzeichen: `landkreis`, `kreis`, `kreisfreie_stadt`, `stadtkreis`, `regionalverband`, `stadt`, `gemeinde`, `markt`, `grosse_kreisstadt`, … |
| `parent_id`, `district_id`, `state_id`, `country_id` | Hierarchie (vorberechnet, Constraint `regions_hierarchy_complete`) |
| `municipality_count` | Anzahl Gemeinden in der Region – daraus ergeben sich die Ranking-Ebenen |
| `is_active` | `false` für Regionen, die in einem neueren Gebietsstand fehlen (nie löschen) |
| `source` | z. B. `GV100AD Stand 30.09.2026` |
| `search_name` | generiert: normalisierter Name für die Suche (Umlaute, ß, Diakritika, Satzzeichen) |

Regionen werden nie über Namen identifiziert und nie als Freitext gespeichert.

### `public.profiles`

| Spalte | Bedeutung |
|---|---|
| `id` | = `auth.users.id` (nie öffentlich) |
| `public_id` | zufällige öffentliche ID für Rankings |
| `username` | 3–20 Zeichen `[A-Za-z0-9_]`, eindeutig **ohne Beachtung der Groß-/Kleinschreibung** (`unique index on lower(username)`), reservierte Namen gesperrt |
| `display_name` | 1–30 Unicode-Codepoints, ohne Steuer- und unsichtbare Formatzeichen (z. B. Zero-Width Space, Richtungswechsel), ohne Leerzeichen am Rand |
| `municipality_id` | gewählte Gemeinde (Fremdschlüssel; Trigger lässt nur aktive Gemeinden zu) |
| `regional_leaderboard_enabled` | ausdrückliche Zustimmung zu öffentlichen Regionalrankings, Standard `false` |
| `created_at`, `updated_at` | vom Server gesetzt |

Kreis, Bundesland und Land werden nicht im Profil gespeichert, sondern über die Gemeinde abgeleitet.

### `public.daily_activity`

| Spalte | Bedeutung |
|---|---|
| `user_id`, `activity_date` | Primärschlüssel – ein Wert je Nutzer und **lokalem Kalendertag** des Geräts |
| `competition_steps` | 0 … 200 000, ohne manuell eingetragene Schritte |
| `synced_at` | vom Server gesetzt (letzter Sync) |
| `steps_changed_at` | vom Server gesetzt, wenn sich die Schrittzahl ändert – Tiebreaker im Ranking |

Mehr speichert Pace nicht: keine Health-Schritte, Distanz, Energie, Stockwerke, Trainingszeit, keine Rohdaten,
keine Quellen, keine Standorte.

## Sicherheit

- **RLS ist auf allen Tabellen aktiv.** Richtlinien verwenden `(select auth.uid())`.
  - `regions`: lesen für `authenticated`.
  - `profiles`: nur die eigene Zeile lesen, anlegen, ändern. Fremde Profile sind nur über die Ranking-RPCs und nur
    mit öffentlichen Feldern sichtbar.
  - `daily_activity`: nur eigene Zeilen; anlegen/ändern nur für Tage im Fenster *heute (UTC) − 8* bis *+ 1*. Ältere
    Tage lassen sich nachträglich nicht mehr ändern. Nutzer und Tag einer Zeile sind unveränderlich (Trigger), damit
    sich alte Werte nicht in das Fenster verschieben lassen.
- **Explizite, spaltengenaue Rechte.** `anon` hat auf keine Tabelle Zugriff. `authenticated` darf in `profiles` nur
  `username`, `display_name`, `municipality_id`, `regional_leaderboard_enabled` schreiben (nicht `public_id`,
  Zeitstempel) und in `daily_activity` nur `user_id`, `activity_date`, `competition_steps`. Die Migrationen setzen
  alle Rechte selbst und hängen nicht von Supabase-Standardrechten ab (Supabase vergibt für neue Tabellen ab dem
  30.10.2026 keine Data-API-Rechte mehr automatisch).
- **Funktionen**: öffentliche RPCs sind `security definer` mit `set search_path = ''` und geben nur öffentliche Felder
  zurück. `execute` haben nur angemeldete Nutzer (`authenticated`); für `public`/`anon` ist es entzogen. Die
  Ranking-RPCs prüfen zusätzlich `auth.uid()`, die Zugehörigkeit zur eigenen Region und das Datumsfenster; Suche,
  Hierarchie und Namensprüfung liefern nur nicht personenbezogene bzw. ja/nein-Daten. Interne Funktionen liegen im
  Schema `private`, das über die Data API nicht erreichbar ist.
- **Fehlercodes**: `42501` ohne Anmeldung, `22023` für unbekannte bzw. fremde Region, ungültigen Zeitraum oder
  Stichtag, `23505` vergebener
  Benutzername, `23514` ungültige Werte (z. B. `invalid_municipality`).
- CI: `supabase db lint --fail-on error` und `supabase db advisors --fail-on warn` gegen den lokalen Stack.

## RPCs (Data API, nur `authenticated`)

| Funktion | Zweck |
|---|---|
| `search_municipalities(p_query text, p_limit int = 20)` | Gemeindesuche: Teilstring im normalisierten Namen (Trigramm-Index), sortiert nach exakt, Präfix, Wortanfang, Einwohnerzahl; max. 50 Treffer, mit Hierarchie |
| `get_region_hierarchy(p_municipality_id text)` | Gemeinde mit Kreis, Bundesland, Land |
| `is_username_available(p_username text)` | Verfügbarkeit ohne Beachtung der Groß-/Kleinschreibung (verbindlich ist der Unique-Index) |
| `leaderboard_page(p_region_id, p_period, p_date, p_limit = 50, p_offset = 0)` | Plätze `offset+1 … offset+limit` (Limit max. 100) und `total_participants` |
| `leaderboard_neighborhood(p_region_id, p_period, p_date, p_radius = 1)` | eigener Platz ± Radius (max. 10); leer, wenn man nicht im Ranking ist |

Ranking-Einträge enthalten ausschließlich `rank`, `public_user_id`, `username`, `display_name`,
`competition_steps`, `is_current_user`.

Zugriffsregeln der Ranking-RPCs (`private.assert_leaderboard_access`):

- Abrufbar sind nur die Rankings der **eigenen Regionen** – Gemeinde, Kreis, Bundesland und Land der eigenen
  Gemeinde. Sonst ließe sich durch Abfragen aller Gemeinden ermitteln, wo andere Teilnehmer wohnen. Fremde Regionen:
  `22023 region_not_allowed`; ohne gewählte Gemeinde gibt es keine Rankings.
- Stichtag nur von *heute (UTC) − 14* bis *+ 1* (`22023 invalid_date`), damit keine vollständige Schritt-Historie
  anderer abrufbar ist.
- Bekannte Grenze: Wer seine Gemeinde wechselt, sieht danach die Rankings der neuen Region. Ein massenhaftes
  Durchwechseln ist möglich, aber aufwendig; eine Wartezeit für Regionswechsel ist ein offener Punkt.

## Anmeldung (Milestone 2)

- Die App meldet sich beim ersten Start **anonym** an (`signInAnonymously`) – ohne Login-Screen. Nutzern wird das
  nie als „anonymes Konto“ angezeigt. Es gibt keinen Logout.
- Die Sitzung liegt im **Keychain** (`KeychainLocalStorage`, Service `app.pace.auth`) und wird beim nächsten Start
  ohne Netz wiederhergestellt. Tokens werden vom SDK automatisch erneuert.
- **Einschränkung:** Diese Identität ist an das Gerät gebunden. Sie ist **nicht geräteübergreifend
  wiederherstellbar**; geht der Keychain-Eintrag verloren (z. B. neues iPhone ohne verschlüsseltes Backup), entsteht
  ein neuer Nutzer und das alte Profil ist verwaist.
- **Später: Sign in with Apple** ohne Umbau: `AuthProviding` bekommt eine zusätzliche Methode; die Implementierung
  verknüpft die bestehende anonyme Identität per `auth.linkIdentityWithIdToken(credentials:)` mit Apple (dafür im
  Projekt *Manual Linking* aktivieren, lokal `enable_manual_linking`). User-ID, Profil und Tageswerte bleiben
  erhalten, weil alles an `auth.users.id` hängt.
- Rate Limit: Supabase erlaubt standardmäßig 30 anonyme Anmeldungen pro Stunde und IP. Für die Produktion ist
  zusätzlich CAPTCHA (Turnstile/hCaptcha) für anonyme Anmeldungen zu erwägen.

## Synchronisierung der Tageswerte

- Quelle: `ActivitySyncCoordinator` (PaceCore) erhält jede erfolgreich geladene `ActivityOverview` vom Home-Screen.
- Anlässe: App-Start, Rückkehr in den Vordergrund, Pull-to-Refresh, HealthKit-Update (Observer) sowie Tageswechsel
  bzw. Zeitzonenwechsel (`significantTimeChangeNotification`), damit „heute“ stimmt. **Kein Polling.**
  HealthKit-Updates werden gedrosselt (höchstens einmal pro Minute), zurückgehaltene Werte werden spätestens vor dem
  Laden eines Rankings gesendet (`flush`).
- Gesendet werden nur geänderte Tage der letzten 7 Tage: `upsert` auf `(user_id, activity_date)` mit
  `competition_steps`. Doppelte Einträge sind dadurch ausgeschlossen; erneutes Senden ist unschädlich.
- Werte werden auf 0 … 200 000 begrenzt. Schlägt der Upload fehl, bleiben die Werte ausstehend und werden beim
  nächsten Anlass erneut gesendet. Ältere Stände, die verspätet eintreffen, werden verworfen.

## Rankings

- Teilnehmer: Profile mit `regional_leaderboard_enabled = true`, aktiver Gemeinde im Scope und mindestens einem
  Tageswert im Zeitraum.
- Scope: Region beliebiger Ebene; die Zugehörigkeit ergibt sich aus der Hierarchie der Gemeinde.
- Zeitraum: `daily` (ein lokaler Kalendertag) oder `weekly` (ISO-Woche Montag–Sonntag, Summe). Die App zeigt in
  Milestone 2 nur `daily`.
- Reihenfolge: Schritte absteigend, bei Gleichstand wer den Wert zuerst erreicht hat (`steps_changed_at`), dann
  `public_id`.
- Die App lädt die Top 50 und – falls man nicht darunter ist – die eigene Position mit je einem Nachbarn. Das
  vollständige Ranking wird nie geladen.
- Ebenen in der App: identische Ebenen entfallen (Frankfurt am Main: Gemeinde, Hessen, Deutschland; Berlin: Berlin,
  Deutschland). Pfungstadt hat alle vier Ebenen.

## Regionsdaten: Quelle und Aktualisierung

- **Quelle:** Statistisches Bundesamt (Destatis), Gemeindeverzeichnis **GV100AD**, Quartalsausgabe
  (`GV100AD3Q.zip`, Datensatzdatei `GV100AD_30092026.txt`), **Gebietsstand 30.09.2026**. Download:
  <https://www.destatis.de/DE/Themen/Laender-Regionen/Regionales/Gemeindeverzeichnis/Administrativ/Archiv/GV100ADQ/GV100AD3QAktuell.html>
- Quellenvermerk: © Statistisches Bundesamt (Destatis), 2026 – Vervielfältigung und Verbreitung, auch auszugsweise,
  mit Quellenangabe gestattet.
- Inhalt: 1 Staat, 16 Länder, 401 Kreise, 10 749 Gemeinden. Nicht importiert: 194 unbewohnte gemeindefreie Gebiete
  (Textkennzeichen 66). Bewohnte gemeindefreie Gebiete werden als Gemeinden geführt.
- Korrektur: AGS 14625020 (Bautzen) – im GV100AD gekürzte Bezeichnung, laut `Hinweise.txt` Namensänderung zum
  01.07.2025; siehe `NAME_CORRECTIONS` im Skript.
- Die Migration enthält die SHA-256-Prüfsummen der Eingabedateien und prüft am Ende die erwarteten Anzahlen.
  Der Import ist **bitgenau reproduzierbar**.

Aktualisierung auf einen neuen Gebietsstand:

```sh
# 1. Neue Ausgabe (ZIP) von Destatis herunterladen, z. B. nach ~/Downloads/<datei>.zip
#    Quartalsausgaben gibt es zum 31.03., 30.06. und 30.09.; zum 31.12. erscheint die Jahresausgabe.
# 2. Neue Migration erzeugen (Stand im Namen anpassen)
supabase migration new region_data_gv100ad_TTMMJJJJ
python3 -I supabase/scripts/import_regions.py ~/Downloads/<datei>.zip \
  --source-url "<URL der Download-Seite bei Destatis>" \
  --output supabase/migrations/<timestamp>_region_data_gv100ad_TTMMJJJJ.sql
# 3. Importer-Tests und Datenbanktests
python3 -I supabase/scripts/test_import_regions.py
supabase db reset && supabase test db
```

`--source-url` landet im Kopf der Migration als Quellenangabe. Für Quartalsausgaben leitet das Skript die URL
selbst ab; für die Jahresausgabe (Stand 31.12.) muss sie angegeben werden, sonst bricht das Skript ab.

Neue Regionen werden ergänzt, geänderte aktualisiert (Upsert über die feste ID). Regionen, die im neuen Stand
fehlen (Gemeindefusionen), werden **deaktiviert, nicht gelöscht**, weil Profile auf sie verweisen können. Erwartete
Anzahlen im Prüfblock der Migration passt das Skript automatisch an. Betroffene Nutzer sollten danach ihre Region
neu wählen (Milestone 3).

## Lokale Entwicklung und Tests

Voraussetzungen: Docker, Supabase CLI ≥ 2.121, Python 3.

```sh
supabase start            # lokaler Stack inkl. Migrationen und Dev-Seed (nur lokal)
supabase test db          # pgTAP: Rechte, RLS, Profile, Sync, Rankings, Regionen
supabase db lint --fail-on error
supabase db advisors --fail-on warn
python3 -I supabase/scripts/test_import_regions.py

# Integrationstests (Swift) gegen den lokalen Stack – auf dem Mac:
eval "$(supabase status -o env)"
cd Packages/PaceBackendIntegrationTests
PACE_SUPABASE_URL="$API_URL" PACE_SUPABASE_PUBLISHABLE_KEY="${PUBLISHABLE_KEY:-$ANON_KEY}" swift test

# … oder wie in der CI unter Linux im Container (aus dem Repository-Wurzelverzeichnis):
docker run --rm --network host -v "$PWD":/work -w /work/Packages/PaceBackendIntegrationTests \
  -e PACE_SUPABASE_URL="$API_URL" -e PACE_SUPABASE_PUBLISHABLE_KEY="${PUBLISHABLE_KEY:-$ANON_KEY}" \
  swift:6.2 swift test -Xlinker --allow-shlib-undefined
```

Ohne die beiden Umgebungsvariablen werden die Integrationstests übersprungen. Die CI (`.github/workflows/backend.yml`)
führt alles davon gegen einen frischen lokalen Stack aus – **ohne Secrets und ohne Zugriff auf ein echtes Projekt**.

## Migrationen auf das Pace-Projekt anwenden (manuell)

Die Migrationen wurden bisher **nur lokal und in der CI** ausgeführt, nicht gegen das echte Projekt. So geht es
sicher – ausschließlich gegen das Pace-Projekt `bnkrenfvfiaapsbkeejq`:

```sh
supabase login
supabase link --project-ref bnkrenfvfiaapsbkeejq   # fragt nach dem Datenbank-Passwort des Pace-Projekts
supabase projects list                             # die verknüpfte Zeile (●) muss Ref bnkrenfvfiaapsbkeejq zeigen
supabase db push --dry-run                         # listet die 6 Migrationen, ändert nichts
supabase db push                                   # NIE mit --include-seed
```

Vorher im Supabase-Dashboard des Pace-Projekts:

1. **Authentication → Sign In / Providers → „Allow anonymous sign-ins“ aktivieren.** Ohne das zeigt die App
   „Die Anmeldung ist derzeit nicht möglich“.
2. **Project Settings → Data API:** `public` ist exponiert (Standard); `private` darf **nicht** in den exponierten
   Schemas stehen.

Danach prüfen:

- **Database → Advisors** (Security und Performance): keine Warnungen erwartet.
- **Table Editor → regions:** 11 167 Zeilen (1 + 16 + 401 + 10 749).
- Erst danach `Config/Pace.xcconfig` lokal anlegen (siehe oben) und die App starten.

Nicht tun: `supabase db reset --linked` (löscht alle Daten), `--include-seed`, Secret Keys in die App oder ins
Repository.

## Offene Punkte für den Produktivbetrieb

- CAPTCHA für anonyme Anmeldungen und ggf. strengere Rate Limits.
- Sign in with Apple (Kontoübertragung auf andere Geräte) und Konto-/Datenlöschung in der App.
- Bereinigung verwaister anonymer Nutzer (z. B. ohne Profil nach 30 Tagen).
- Plausibilitätsprüfungen über das harte Limit hinaus (Anti-Cheat), falls Rankings missbraucht werden.
- Wartezeit für Regionswechsel (verhindert das Durchwechseln von Regionen, siehe Zugriffsregeln der Rankings).
- Bei stark wachsender Nutzerzahl: Rankings materialisieren statt pro Anfrage berechnen.
