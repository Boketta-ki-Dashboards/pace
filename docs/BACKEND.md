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
│   ├── 20261016100500_region_data_gv100ad_20260930.sql   generierte Regionsdaten (GV100AD)
│   ├── 20261018100000_social.sql                     Freunde, Gruppen, Einladungen, Gruppen-Streak (docs/SOCIAL.md)
│   ├── 20261019100000_profiles_blocks_search.sql     Profilbild, Auffindbarkeit, Präfixsuche, öffentliches Profil, Blockieren
│   ├── 20261019100100_groups_privacy_images.sql      Gruppen-Privatsphäre, Einladungen beim Erstellen, Gruppenbild
│   ├── 20261019100200_chat.sql                       Privat- und Gruppenchats, Lesestand, Echtzeit-Hinweise
│   ├── 20261019100300_storage_realtime_access.sql    Buckets, Storage-Policies, Realtime-Policy
│   └── 20261019100400_moderation_account.sql         Meldungen, Rückmeldungen, Auskunft, Konto löschen
├── seed/dev_seed.sql           DEV ONLY: erfundene dev_…-Nutzer für lokale Rankings
├── scripts/import_regions.py   Importer GV100AD → Migration (+ test_import_regions.py)
├── scripts/realtime_smoke_test.mjs   Echtzeit-Kanäle Ende-zu-Ende gegen den lokalen Stack (Node ≥ 22)
└── tests/*.test.sql            pgTAP-Tests (Rechte, RLS, Profile, Sync, Rankings, Regionen, Freunde, Gruppen,
                                Gruppen-Streak, Suche/Blockieren, Gruppen-Privatsphäre, Chats, Storage/Realtime,
                                Moderation/Konto)
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
| `avatar_path` | Profilbild im privaten Bucket `avatars` (`<public_id>/<Name>.<Endung>`), `null` = Initialen (ab `20261019100000`) |
| `is_discoverable` | erscheint in der Präfixsuche anderer, Standard `true`; exakt und für Freunde immer auffindbar (ab `20261019100000`) |
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
  `username`, `display_name`, `municipality_id`, `regional_leaderboard_enabled` schreiben und zusätzlich
  `avatar_path`, `is_discoverable` ändern (nicht `public_id`, Zeitstempel) und in `daily_activity` nur `user_id`, `activity_date`, `competition_steps`. Die Migrationen setzen
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

## Social-Erweiterungen, Chats, Medien und Konto (Migrationen ab 20261019100000)

Fünf Migrationen bauen auf `20261018100000_social.sql` auf (Freunde, Gruppen, Gruppen-Streak – siehe
[SOCIAL.md](SOCIAL.md)). Sie sind **rein additiv**: neue Tabellen, neue Spalten mit Standardwerten, neue bzw.
ersetzte Funktionen (gleiche Signaturen, damit ältere App-Versionen weiterlaufen). Bestehende Daten bleiben
unverändert; bestehende Gruppen behalten den Beitritt per Code (`privacy = 'code'`).

| Migration | Inhalt |
|---|---|
| `20261019100000_profiles_blocks_search.sql` | `profiles.avatar_path`, `profiles.is_discoverable`, Präfixsuche, öffentliches Profil, `user_blocks`, Blockier-Wirkung in allen Freundes-RPCs, Rate Limits für Namensprüfung und Namensänderung |
| `20261019100100_groups_privacy_images.sql` | `groups.privacy`, `groups.image_path`, Gruppe mit Einladungen in einer Transaktion, Details/Privatsphäre ändern, Gruppenbild, Code-Beitritt nur bei `privacy = 'code'` |
| `20261019100200_chat.sql` | `conversations`, `chat_messages`, `conversation_reads`, `chat_*`-RPCs, Echtzeit-Hinweise per Trigger |
| `20261019100300_storage_realtime_access.sql` | Buckets `avatars`, `group-images`, `chat-media`, Policies auf `storage.objects` und `realtime.messages`, Prüffunktionen im Schema `pace_access` |
| `20261019100400_moderation_account.sql` | `reports`, `feedback`, `social_report`, `submit_feedback`, `account_export`, `account_own_media`, `account_delete` |

### Tabellen

| Tabelle | Zweck | Clientzugriff |
|---|---|---|
| `profiles` (+2 Spalten) | `avatar_path` (Pfad im Bucket `avatars`, Ordner = eigene `public_id`, Datei muss existieren – Trigger), `is_discoverable` (Standard `true`) | nur eigene Zeile; `update` auf `username`, `display_name`, `avatar_path`, `is_discoverable` (Spalten-Grants, Constraints und Trigger greifen) |
| `user_blocks` | `blocker_id`, `blocked_id`, `created_at`; PK beide, kein Selbst-Block | keiner (nur RPCs) |
| `groups` (+2 Spalten) | `privacy` (`invite_only` \| `code`, Standard `code`), `image_path` (Ordner = `group_id`, Datei muss existieren – Trigger) | keiner (nur RPCs) |
| `conversations` | `kind` `direct` (genau eine je Paar, `user_a < user_b`) oder `group` (eine je Gruppe, per Trigger); `last_message_at` | keiner |
| `chat_messages` | `kind` `text`/`image`/`gif`/`profile`, `body` ≤ 2000, `media_path` (`chat-media/<conversation_id>/…`), `shared_profile_id`, `client_id` (eindeutig je Absender → idempotentes Wiederholen), `sender_id` `on delete set null`, `deleted_at` | keiner |
| `conversation_reads` | Lesestand je Teilnehmer (`last_read_at`) | keiner |
| `reports` | `reporter_id`, `target_type` (`user`/`message`/`group`), `target_id`, `reason` (wie `ReportReason`), `details` ≤ 1000, `status` (`open`, `reviewing`, `resolved`, `dismissed`), `target_snapshot` (Zustand beim Melden), `created_at` | keiner – auch kein Lesen |
| `feedback` | `kind` (`problem`/`idea`), `message` ≤ 2000, `app_version`; keine E-Mail-Adressen | keiner |
| `private.auth_rate_limit_events` | Rate Limits, die schon **vor** dem Profil greifen (an `auth.users` gebunden) | keiner |

Alle neuen Tabellen haben RLS ohne Policies und keine Tabellenrechte für `anon`/`authenticated`; gelesen und
geschrieben wird ausschließlich über die RPCs (`security definer`, `set search_path = ''`, `execute` nur für
`authenticated`).

### RPCs

| Funktion | Zweck |
|---|---|
| `social_search_profiles(p_query)` | Präfixsuche über Benutzernamen: ab 3 Zeichen (`@` am Anfang erlaubt), nur `[a-z0-9_]` (damit keine LIKE-Platzhalter), max. 20 Treffer, exakte und Freunde zuerst; ohne mich und ohne Blockierte (beide Richtungen); nicht auffindbare Profile nur bei exakter Eingabe oder unter Freunden. Index `profiles_username_prefix_idx` (`lower(username) text_pattern_ops`). Liefert Profilfelder inkl. `avatar_path`, `relationship`, `request_id` |
| `social_find_profile(p_username)` | exakter Benutzername; respektiert Blockierungen (beide Richtungen). Exakt ist ein Profil auch bei `is_discoverable = false` auffindbar (Vertrag `UserProfile.isDiscoverable`) |
| `social_public_profile(p_public_id, p_date)` | Felder von `PublicProfile`; Schritte heute/Woche und „Freunde seit“ **nur unter Freunden**; `is_blocked_by_me`. Wer mich blockiert hat: `not_found` |
| `social_block_user`, `social_unblock_user`, `social_blocked_users` | Blockieren/Aufheben/Liste (Profilfelder + `blocked_at`) |
| `social_create_group(…, p_privacy, p_invitee_public_ids)` | Gruppe samt Einladungen in **einer** Transaktion; nur Freunde einladbar (sonst `not_found`), höchstens 30 Eingeladene (wie in der App); das Einladungs-Kontingent wird vorab für alle Einladungen gemeinsam geprüft. Die alte Signatur ohne die beiden Parameter bleibt erhalten (`privacy = 'code'`) |
| `social_update_group_details(p_group_id, p_name, p_description, p_kind, p_privacy)` | Name, Beschreibung, Art, Privatsphäre (nur owner) |
| `social_set_group_image(p_group_id, p_path)` | Gruppenbild setzen oder mit `null` entfernen (nur owner; Pfad im Ordner der Gruppe, Datei muss existieren) |
| `social_join_group(p_invite_code)` | ersetzt: nur `privacy = 'code'`; bei `invite_only` dieselbe Antwort wie bei falschem Code (`invalid_invite_code`) |
| `chat_conversations()` | eigene Unterhaltungen mit letzter Nachricht, Ungelesen-Zähler, `can_send`, Gegenüber bzw. Gruppe (max. 200) |
| `chat_open_direct(p_public_id)` | Privatchat öffnen bzw. **nur unter Freunden** anlegen; selbst blockiert → `blocked`, blockiert worden → `not_found` |
| `chat_group_conversation(p_group_id)` | Gruppenchat (nur aktuelle Mitglieder) |
| `chat_messages(p_conversation_id, p_before, p_limit)` | Seite vor `p_before` (aufsteigend sortiert, Limit 1–100, Standard 40); Nachrichten von Personen, die ich blockiert habe, werden nicht ausgeliefert |
| `chat_send(p_conversation_id, p_client_id, p_kind, p_body, p_media_path, p_shared_profile_id)` | Senden; idempotent je `client_id`. Text 1–2000 Zeichen ohne Steuerzeichen; Bild/GIF nur eigene, bereits hochgeladene Datei im Ordner der Unterhaltung (GIF = `image/gif`); Profil per `public_id` (nicht blockiert) |
| `chat_mark_read(p_conversation_id, p_through)` | Lesestand vorwärts setzen |
| `chat_delete_message(p_message_id)` | nur eigene; Inhalt wird entfernt, Rückgabe `media_path`, damit die App die Datei löscht |
| `social_report(p_target_type, p_target_id, p_reason, p_details)` | Person (jede bekannte außer mir), Nachricht (anderer, in Unterhaltungen, die ich lesen darf) oder Gruppe (Mitglied oder eingeladen); eine offene Meldung je Ziel |
| `submit_feedback(p_kind, p_message, p_app_version)` | Rückmeldung ohne Kontaktdaten |
| `account_export()` | jsonb mit allen personenbezogenen Serverdaten (siehe „Konto und Datenschutz“) |
| `account_own_media()` | `[{bucket, path}]` – eigene Dateien und Bilder eigener Gruppen |
| `account_delete()` | eigenes Konto löschen (auch ohne Profil) |
| `is_username_available(p_username)` | ersetzt: jetzt `volatile` mit Rate Limit, das schon vor dem Anlegen des Profils greift |

Fehler kommen als Text-Token in der Meldung (`not_found`, `not_allowed`, `blocked`, `read_only`, `invalid_message`,
`invalid_input`, `invalid_invite_code`, `invalid_image_path`, `self_request`, `rate_limited`, …) und werden in
`BackendErrorMapping` auf `SocialError`, `ProfileError`, `MediaError` bzw. `AccountError` abgebildet. Fehlt eine
Funktion auf dem Server (Migration noch nicht eingespielt: `PGRST202`), wird daraus `.unavailable`; die DTOs lesen
neue Felder optional, und Profilabfragen fallen bei fehlenden Spalten (`42703`) auf die alten Spalten zurück.

### Rate Limits

Gleitende Fenster je Nutzer und Aktion (`private.consume_rate_limit`, Advisory-Lock gegen parallele Anfragen).

| Aktion | Limit |
|---|---|
| `is_username_available` | 60 je 10 Minuten (je Auth-Nutzer, auch ohne Profil) |
| Benutzername ändern | 5 je 24 Stunden |
| exakte Suche / Präfixsuche | 30 bzw. 120 je 10 Minuten (jede Anfrage zählt, auch zu kurze) |
| Freundschaftsanfragen | 20 je 24 Stunden |
| Blockieren | 50 je 24 Stunden |
| Gruppen erstellen / Einladungen / Code-Beitritt | 5 je 24 h / 30 je 24 h / 20 Versuche je Stunde |
| Nachrichten senden | 30 je Minute und 2000 je 24 Stunden |
| Meldungen / Rückmeldungen | je 10 je 24 Stunden |
| Datenexport | 5 je Stunde |

### Blockieren

- Blockieren beendet sofort eine bestehende Freundschaft, offene Freundschaftsanfragen und offene
  Gruppeneinladungen zwischen beiden (in beide Richtungen).
- Danach in **beide** Richtungen: keine neuen Anfragen, keine Einladungen, keine Privatchats und kein Senden; beide
  finden sich weder in der Präfix- noch in der exakten Suche; das öffentliche Profil der blockierenden Person ist für
  die blockierte nicht abrufbar; die blockierte Person sieht das Profilbild der blockierenden nicht.
- **Privatchat:** solange eine Blockierung besteht, ist er für beide unsichtbar (`not_found`). Nach dem Aufheben ist
  der alte Verlauf wieder lesbar, aber schreibgeschützt (`can_send = false`), bis beide wieder befreundet sind.
- **Gemeinsame Gruppen bleiben bestehen.** Der Gruppenchat bleibt für beide nutzbar; der Server liefert der
  blockierenden Person die Nachrichten der blockierten nicht aus (Listen-Vorschau und Verlauf). Rankings und
  Gruppen-Streak zählen weiter alle Mitglieder – sonst könnte eine Blockierung die Gruppenwertung verfälschen.
- Aufheben stellt nichts wieder her (keine Freundschaft, keine Anfragen).

### Öffentliches Profil und Auffindbarkeit

- `social_public_profile` ist begrenzt (120 Abrufe je 10 Minuten). Nicht auffindbare Profile (`is_discoverable =
  false`) liefert es ohne Freundschaft nur mit Kontext: gemeinsame oder frühere Gruppe, Gruppeneinladung,
  Privatchat, ein im Chat geteiltes Profil oder ein exakter Benutzernamen-Fund in den letzten 24 Stunden – sonst wie
  „nicht gefunden“. So lassen sich Profile nicht über `public_id`s (z. B. aus Speicherpfaden) durchzählen.
- `chat_send` teilt nur Profile, die die sendende Person selbst sehen darf.

### Storage

Private Buckets (keine öffentlichen URLs); Upload, Download und Löschen laufen über die authentifizierte Storage-API
mit dem Access Token. Dateinamen sind zufällig (`<Ordner>/<UUID>.<Endung>`), Überschreiben ist nicht vorgesehen.

| Bucket | Grenze | Lesen | Schreiben | Löschen |
|---|---|---|---|---|
| `avatars` | 5 MB | Fremde nur das **aktuelle** Profilbild (`profiles.avatar_path`), nicht wenn die Besitzerin sie blockiert hat; die Besitzerin ihren ganzen Ordner | nur Ordner der eigenen `public_id` | nur eigener Ordner, außer Dateien unter offener Meldung |
| `group-images` | 5 MB | Mitglieder und Personen mit offener Einladung | owner der Gruppe (Ordner = `group_id`) | owner oder wer die Datei hochgeladen hat |
| `chat-media` | 10 MB | wer die Unterhaltung lesen darf | wer in ihr senden darf (Ordner = `conversation_id`) | wer die Datei hochgeladen hat, außer Dateien unter offener Meldung |

Erlaubte Formate (`allowed_mime_types`, wie `MediaRules`): `image/jpeg`, `image/png`, `image/gif`, `image/heic`,
`image/webp`. Die Policies rufen `security definer`-Funktionen im Schema `pace_access` auf (nicht über die Data API
erreichbar; `authenticated` darf nur diese Prüffunktionen ausführen). Die App prüft Größe und Format schon vor dem
Upload (`SupabaseMediaRepository`), der Server erzwingt dieselben Grenzen.

### Echtzeit (Chats)

- Nach jeder neuen oder gelöschten Nachricht sendet ein Trigger per `realtime.send` einen **privaten Broadcast ohne
  Inhalt** (`{conversation_id, event}`) an `chat:<conversation_id>` (Ereignis `message`) und an
  `user:<public_id>` jedes Teilnehmers (Ereignis `conversation`). Die App lädt daraufhin über die RPCs.
- Policy `pace_realtime_receive` auf `realtime.messages`: Empfangen nur, wer die Unterhaltung lesen darf bzw. nur die
  Person selbst (`pace_access.can_receive_topic`). Clients können keine Broadcasts senden (keine insert-Policy).
- Die App (`RealtimeEvents`) abonniert mit dem Access Token. Ist Realtime nicht erreichbar oder wird der Beitritt
  abgelehnt, endet der Stream sofort und die App aktualisiert regelmäßig (Polling-Rückfall im Chat-Feature).
- Der Realtime-Client teilt Kanäle je Topic (z. B. `user:<public_id>` für Chat-Liste und Ungelesen-Zähler).
  `TopicUsage` zählt die Streams je Topic: Erst der letzte entfernt den Kanal, und ein neuer Stream desselben Topics
  wartet, bis dieses Entfernen abgeschlossen ist (sonst übernähme er einen Kanal, der danach nicht mehr im Client
  eingetragen ist und nie wieder Hinweise erhielte).
- Fehlt `realtime.send` (Realtime nicht eingerichtet), werden Nachrichten trotzdem gespeichert.

### Konto und Datenschutz

- **Auskunft** (`account_export`): Profil, Tageswerte, Freundschaften, Anfragen, Blockierungen, Gruppen mit Rolle,
  Mitgliedszeiträume, Einladungen, eigene Nachrichten, Lesestände, eigene Meldungen, Rückmeldungen und eigene
  Dateien (Pfade). Keine Daten anderer außer den öffentlichen Profilfeldern der Gegenüber.
- **Löschen** (`AccountRepository.deleteAccount`): Die App löscht zuerst alle Pfade aus `account_own_media` über die
  Storage-API (direktes Löschen in `storage.objects` erlaubt Supabase nicht), dann ruft sie `account_delete` auf.
  Das löscht die eigenen Nachrichten, entfernt Verweise auf gelöschte Gruppenbilder und löscht `auth.users`; über
  Kaskaden verschwinden Profil, Tageswerte, Freundschaften, Anfragen, Blockierungen, Einladungen, Meldungen,
  Rückmeldungen und Lesestände. Gruppen gehen über die vorhandenen Trigger an das dienstälteste Mitglied, leere
  Gruppen werden gelöscht. Privatchats bleiben für das Gegenüber lesbar (Absender `null`, schreibgeschützt).

### Moderation

Meldungen landen in `public.reports` mit Status `open` und einem Schnappschuss des Ziels (`target_snapshot`), damit
eine spätere Löschung die Prüfung nicht verhindert. **Beweissicherung:** Dateien, auf die eine offene Meldung
(`open`/`reviewing`) zeigt (gemeldetes Profilbild, Chat-Bild, Gruppenbild), lassen sich über die Storage-Policies
nicht löschen; `chat_delete_message` gibt sie nicht zur Löschung frei, und `account_own_media` lässt sie bei der
Kontolöschung aus. Sie bleiben bis zur Moderationsentscheidung erhalten (Rechtsgrundlage etwa Art. 17 Abs. 3 lit. e
DSGVO – **vom Betreiber zu prüfen**, ebenso die Aufbewahrungsfrist). Clients können Meldungen weder lesen noch ändern. Ablauf bis zu
einem Moderationswerkzeug:

1. Offene Meldungen sichtet eine berechtigte Person im Supabase-Dashboard (SQL Editor bzw. Table Editor mit
   Projektrechten): `select * from public.reports where status = 'open' order by created_at;`
2. Bewertung anhand von `reason`, `details` und `target_snapshot`; bei Nachrichten zusätzlich der Verlauf der
   Unterhaltung (`conversation_id` im Schnappschuss).
3. Maßnahmen (manuell, per SQL im Dashboard): Nachricht entfernen (`update public.chat_messages set body = null,
   media_path = null, deleted_at = now() where id = …`; Datei im Storage-Bereich des Dashboards löschen),
   Gruppenname/-bild zurücksetzen, bei schweren Verstößen das Konto über *Authentication → Users* löschen.
4. Status setzen: `update public.reports set status = 'resolved' where id = …` (bzw. `dismissed`).
5. Rückmeldungen (`public.feedback`) werden genauso nur im Dashboard gelesen.

Die Sichtung ist bewusst nicht in der App: Es gibt keine Admin-Rolle im Client.

### Tests

- **pgTAP** (`supabase/tests/09_…`–`13_…`, zusammen mit 01–08: 705 Prüfungen): Spalten und Rechte, Präfixsuche
  (Escaping, Mindestlänge, Limit, Auffindbarkeit, Blockierungen, Rate Limit), öffentliches Profil, Blockier-Wirkung,
  Gruppen-Privatsphäre und Einladungen beim Erstellen, Gruppenbild-Pfade, Chats (fremde Chats, Nicht-Mitglied,
  Austritt, Blockierung, Idempotenz, Pagination, Lesestand, Löschen, Rate Limit), Storage-Policies je Bucket,
  Realtime-Policy auf `realtime.messages`, Meldungen, Rückmeldungen, Export, eigene Dateien, Konto löschen.
- **Swift-Integrationstests** (`Packages/PaceBackendIntegrationTests`, 16 Tests): Zwei-Nutzer-Szenario (Präfixsuche →
  Anfrage → Annahme → Status bei beiden → Privatchat → Empfang → Antwort → Verlauf → Gruppe mit Einladung →
  Beitritt → Gruppenchat → Gruppen-Streak bei beiden gleich → Austritt entzieht Zugriff → Blockierung greift),
  Medien (Upload/Download/Verbot, Ordnerregeln, Größen- und Formatgrenzen direkt gegen Storage), Auskunft,
  Rückmeldung, Konto löschen, Präfixsuche mit Auffindbarkeit, Melden, Rate Limit der Namensprüfung.
- **Echtzeit:** Unter Linux kann der Swift-Client keine WebSockets öffnen (libcurl in Ubuntu 24.04 ohne
  WebSocket-Unterstützung); der Swift-Test `newChatMessagesArriveOverRealtime` läuft daher nur auf Apple-Plattformen.
  Stattdessen prüft `supabase/scripts/realtime_smoke_test.mjs` (Node ≥ 22) gegen denselben lokalen Stack den echten
  Realtime-Server: Teilnehmer dürfen abonnieren, Fremde werden abgewiesen, Hinweise kommen auf beiden Kanälen an und
  enthalten keinen Inhalt. Das läuft auch in der CI.
- **Unit-Tests** (`Packages/PaceKit/Tests/PaceBackendTests`): Anfrageform und Fehlerabbildung jeder Methode über
  `StubURLProtocol`.

## Spitznamen, Nachrichtenaktionen, Sprachnachrichten, Gruppenkalender (Migrationen ab 20261023100000)

Drei weitere Migrationen (Auftrag 3), wieder **rein additiv und rückwärtskompatibel**: neue Tabellen, neue
nullable Spalten, erweiterte Prüfregeln (Obermengen der alten), neue RPCs, ersetzte Funktionen mit gleicher
Signatur. Einzige Signaturänderung: `chat_send` bekommt zwei Parameter **mit Standardwert** – die alte Fassung wird
entfernt, damit PostgREST nicht zwischen zwei Überladungen wählen muss; Aufrufe älterer App-Versionen (bisherige
sechs Parameter) funktionieren unverändert. Neue Felder in den Antworten ignorieren ältere Versionen. Rollout:
[SUPABASE_ROLLOUT.md](SUPABASE_ROLLOUT.md), Abschnitt „Auftrag 3“ (**nicht ausgeführt, Freigabe nötig**).

| Migration | Inhalt |
|---|---|
| `20261023100000_friend_nicknames.sql` | `friend_nicknames`, `social_set_friend_nickname`, `nickname` in `profile_json`, Rankings (Freunde, Gruppe, Region) und Einladungen; `account_export` mit eigenen Spitznamen; `social_report` ohne Spitznamen im Schnappschuss |
| `20261023100100_chat_message_actions.sql` | `chat_messages.reply_to_id`/`edited_at`/`media_duration_ms`, Art `voice`; `chat_send` (Antwort, Sprachnachricht), `chat_edit_message`, `chat_set_favorite`/`chat_favorites`, `chat_set_pinned`/`chat_pins`; `chat_message_favorites`, `chat_message_pins`; Bucket `chat-media` mit AAC-Audio; Echtzeit `message_updated`, `pins_changed` |
| `20261023100200_group_calendar.sql` | `social_group_calendar` |

### Tabellen und Spalten

| Tabelle | Zweck | Clientzugriff |
|---|---|---|
| `friend_nicknames` | `owner_id`, `target_id`, `nickname` (1–30 Zeichen wie Anzeigenamen, getrimmt, keine Steuer-/Formatzeichen), `updated_at`; PK `(owner_id, target_id)`, kein Spitzname für sich selbst | keiner (nur RPCs) |
| `chat_messages` (+3 Spalten) | `reply_to_id` (→ `chat_messages`, `on delete set null`), `edited_at`, `media_duration_ms` (1–300 000, nur `voice`); `kind` zusätzlich `voice`; `media_path` auch `.m4a`/`.aac` | keiner |
| `chat_message_favorites` | `user_id`, `message_id`, `created_at`; privat je Person, höchstens 1000 | keiner |
| `chat_message_pins` | `conversation_id`, `message_id`, `pinned_by` (`on delete set null`), `pinned_at`; höchstens 5 je Unterhaltung | keiner |

RLS ohne Policies, keine Tabellenrechte für `anon`/`authenticated`. Trigger: Endet eine Freundschaft (Entfernen,
Blockieren, Konto löschen) oder entsteht eine Blockierung, werden die Spitznamen beider Seiten gelöscht. Wird eine
Nachricht gelöscht (`chat_delete_message`), verliert sie Pins, Favoriten und die Dauer (ein entfernter Pin meldet
`pins_changed`).

### Ausgabe von Spitznamen

`private.profile_json` liefert zusätzlich `nickname` – ausschließlich den Spitznamen, den **der Aufrufer**
(`auth.uid()`) vergeben hat, sonst `null`. Damit tragen alle Profile anderer Personen ihn: Freundesliste, Anfragen,
Suche, öffentliches Profil, Freundesprofil, ausgehende Einladungen, Chat-Absender, Gegenüber in der Chatliste,
geteilte Profile, Antwort-Vorschau, Pins, Gruppenkalender, Auskunft. Rankings bauen ihre Einträge selbst und
ergänzen `nickname` ausdrücklich (`social_friend_ranking`, `social_group_ranking`, `leaderboard_page`,
`leaderboard_neighborhood`); `social_group_invitations` liefert `inviter_nickname`, `chat_conversations`
`last_message.sender_nickname`. `title` bzw. `display_name`/`sender_name` bleiben der echte Anzeigename (ältere
App-Versionen); die App zeigt `shownName`/`shownTitle`/`shownSenderName`. Fremde Spitznamen gibt der Server nie aus.
Meldungen: `social_report` (in dieser Migration ersetzt, sonst unverändert) entfernt `nickname` aus dem
Schnappschuss (`reports.target_snapshot`, nur für das Moderationsteam) – der private Spitzname der meldenden Person
gelangt nicht in die Moderation.

### RPCs

| Funktion | Zweck |
|---|---|
| `social_set_friend_nickname(p_public_id, p_nickname)` | eigenen Spitznamen für einen **aktuellen Freund** setzen (Leerraum zusammengefasst), leer/`null` entfernt; Antwort = Profil mit `nickname`. `not_found` ohne Freundschaft, `invalid_nickname`, 30 je 10 min |
| `chat_send(…, p_reply_to_id = null, p_media_duration_ms = null)` | zusätzlich Antworten (nur auf sichtbare, nicht gelöschte Nachricht **derselben** Unterhaltung, sonst `not_found`) und `voice` (eigene, hochgeladene Datei im Ordner der Unterhaltung mit `audio/mp4`, `audio/x-m4a` oder `audio/aac`, Dauer 1–300 000 ms, sonst `invalid_input`). Bilder müssen jetzt `image/*`, GIFs `image/gif` sein. Eine Dauer bei anderen Arten → `invalid_input` |
| `chat_edit_message(p_message_id, p_text)` | eigene, nicht gelöschte **Textnachricht** bearbeiten (Regeln wie Senden, `invalid_message`); andere Arten `invalid_input`, fremde/gelöschte `not_found`, ohne Schreibrecht `read_only`; gleicher Text ändert nichts; setzt `edited_at`; 30 je Minute; Echtzeit `message_updated` |
| `chat_set_favorite(p_message_id, p_favorite)` | privaten Favoriten setzen (nur sichtbare Nachrichten lesbarer Unterhaltungen, sonst `not_found`; max. 1000 → `limit_reached`; 60 je Minute) bzw. entfernen (immer, idempotent) |
| `chat_favorites(p_conversation_id)` | eigene Favoriten einer lesbaren Unterhaltung (Form wie `chat_messages`), neueste zuerst, max. 500 |
| `chat_set_pinned(p_message_id, p_pinned)` | anpinnen/lösen (idempotent), Antwort = alle Pins. Gruppenchat nur Owner (`not_allowed`), Privatchat beide mit Schreibrecht (`read_only`); max. 5 (`pin_limit_reached`); 30 Änderungen je Minute; Lösen auch für verborgene Nachrichten; Echtzeit `pins_changed` |
| `chat_pins(p_conversation_id)` | `[{message, pinned_by, pinned_at}]`, zuletzt angepinnte zuerst. Verborgene Nachrichten (gelöscht bzw. von Personen, die ich blockiert habe) zählen weiter zur Höchstzahl: Wer anpinnen darf (`can_pin`), bekommt sie als Platzhalter (`message` mit `id`, `conversation_id`, `kind`, `created_at`, `is_pinned`, `is_deleted: true`, Inhalt/Absender `null`; `pinned_by: null`) und kann sie lösen; alle anderen sehen sie nicht |
| `social_group_calendar(p_group_id, p_first_day, p_last_day)` | nur aktuelle Mitglieder (`not_found`); höchstens 42 Tage (`invalid_date`); begrenzt auf Gründung … heute (Gruppenzeitzone). Antwort `{group_id, time_zone, group_today, first_group_day, days:[{day, daily_goal, member_count, required_count, reached_count, secured, has_data, is_today, ranking:[Profil + rank, competition_steps, reached, is_current_user]}]}` – Kennzahlen aus `private.group_day_stats` (identisch mit Streak und `social_group_days`), Rangliste über `private.social_step_ranking`; ehemalige Mitglieder, die mich blockiert haben, ohne Profilfelder (`null`), Zählwerte bleiben; Tage ab Gründung auch vor dem eigenen Beitritt |

Neue JSON-Felder in bestehenden Antworten: Nachricht (`chat_messages`, `chat_send`, …) `media_duration_ms`,
`reply_to` (`{id, sender, kind, text ≤ 200 Zeichen, media_duration_ms, is_deleted}`; gelöschtes oder verborgenes
Original nur mit `id`, `kind`, `is_deleted: true`), `edited_at`, `is_favorite` (nur für den Aufrufer), `is_pinned`;
Unterhaltung `can_pin`, `last_message.sender_nickname`, `last_message.media_duration_ms`; Profile `nickname`;
Ranking-Einträge `nickname`; Einladungen `inviter_nickname`; Auskunft `friend_nicknames`, `chat_message_favorites`,
`chat_message_pins`, Nachrichten mit `reply_to_id`, `edited_at`, `media_duration_ms`.

Neue Fehler-Tokens: `invalid_nickname` → `SocialError.invalidNickname`, `pin_limit_reached` →
`SocialError.pinLimitReached` (vor `limit_reached` geprüft).

### Sprachnachrichten (Speicher)

- Bucket `chat-media`: `allowed_mime_types` zusätzlich `audio/mp4`, `audio/x-m4a`, `audio/aac` (Vereinigung mit
  den vorhandenen Typen, Reihenfolge bleibt, nichts doppelt; `null` = alle erlaubt bleibt unverändert); Grenze bleibt
  10 MB (5 Minuten AAC liegen weit darunter), die Dauer begrenzt der Server auf 5 Minuten.
- Pfade `<conversation_id>/<UUID>.m4a` (bzw. `.aac`). `pace_access.chat_media_folder` akzeptiert dafür zusätzlich
  die Audio-Endungen; `can_read_chat_media`/`can_write_chat_media` nutzen sie – gleiche Regeln wie für Bilder
  (lesen: wer die Unterhaltung lesen darf; schreiben: wer senden darf; löschen: wer hochgeladen hat). Profil- und
  Gruppenbilder bleiben bei Bildendungen.
- Beweissicherung wie bei Chat-Bildern: Eine gemeldete Sprachnachricht hält ihre Datei über
  `reports.evidence_path` (= `media_path` im Schnappschuss); `chat_delete_message` gibt sie dann nicht zur Löschung
  frei, die Delete-Policy sperrt sie.
- App: Upload über `MediaUploadTarget.chat(conversationID:)` mit `MediaRules.voiceContentType` (`audio/mp4`), dann
  `ChatMessageDraft.voice(mediaPath:duration:)`. Löschen der Nachricht entfernt auch die Datei.

### Echtzeit

Zusätzlich zu `message` an `chat:<conversation_id>`: `message_updated` (Bearbeitung; außerdem `conversation` an
`user:<public_id>`, weil sich die Vorschau ändern kann) und `pins_changed` (nur `chat:`-Topic). Weiterhin ohne
Inhalt (`{conversation_id, event}`). Die App hört über `ChatRepository.conversationActivity(in:)` auf alle drei
Ereignisse in **einem** Kanal (`RealtimeEvents.stream(topic:events:)`); `messageEvents(in:)` bleibt unverändert
(nur `message`).

### Rate Limits (neu)

| Aktion | Limit |
|---|---|
| Spitznamen setzen/entfernen | 30 je 10 Minuten |
| Nachricht bearbeiten | 30 je Minute |
| Favorit setzen | 60 je Minute (höchstens 1000 Favoriten) |
| Pin setzen/lösen | 30 je Minute (höchstens 5 Pins je Unterhaltung) |

### Tests (Auftrag 3)

- **pgTAP:** `14_friend_nicknames` (59), `15_chat_message_actions` (111), `16_group_calendar` (33); bestehende
  Tests 04, 06, 07, 09, 11, 12, 13 an die neuen Felder angepasst – zusammen 16 Dateien, 908 Prüfungen.
- **Realtime-Skript:** prüft zusätzlich `message_updated` und `pins_changed` (ohne Inhalt, nicht für Fremde).
- **Swift:** `PaceBackendTests/MessageActionsNicknameCalendarTests.swift` (Request-Körper, Dekodierung mit und ohne
  neue Felder, Fehler-Tokens, Audio-Upload), `PaceBackendIntegrationTests/…/MessageActionsIntegrationTests.swift`
  (Spitzname privat, Antworten/Bearbeiten/Favoriten/Pins, Audio nur für Teilnehmer, Gruppenkalender gegen
  `groupDays`), `PaceCoreTests/SocialChatContractTests.swift`, `SocialFeatureTests/ChatVoiceFormattingTests.swift`.

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
# Lokaler Stack inkl. Migrationen und Dev-Seed (nur lokal). Storage und Realtime werden gebraucht (Buckets und
# Policies auf storage.objects / realtime.messages); nicht benötigte Dienste bleiben aus.
supabase start -x imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor
supabase test db          # pgTAP (01–13)
supabase db lint --local --fail-on error
supabase db advisors --local --fail-on warn
python3 -I supabase/scripts/test_import_regions.py

# Echtzeit-Kanäle (privater Broadcast + Policy) gegen den lokalen Stack:
eval "$(supabase status -o env)"
PACE_SUPABASE_URL="$API_URL" PACE_SUPABASE_PUBLISHABLE_KEY="${PUBLISHABLE_KEY:-$ANON_KEY}" \
  node supabase/scripts/realtime_smoke_test.mjs

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

> **Für die Migrationen ab `20261018100000_social.sql` gilt die ausführliche, freizugebende Anleitung
> [SUPABASE_ROLLOUT.md](SUPABASE_ROLLOUT.md)** (Reihenfolge, Backup, Dry Run, Dashboard-Einstellungen für Storage
> und Realtime, Prüfungen, Rücknahme). Der folgende Abschnitt beschreibt das grundsätzliche Vorgehen.

Die Migrationen wurden bisher **nur lokal und in der CI** ausgeführt, nicht gegen das echte Projekt. So geht es
sicher – ausschließlich gegen das Pace-Projekt `bnkrenfvfiaapsbkeejq`:

```sh
supabase login
supabase link --project-ref bnkrenfvfiaapsbkeejq   # fragt nach dem Datenbank-Passwort des Pace-Projekts
supabase projects list                             # die verknüpfte Zeile (●) muss Ref bnkrenfvfiaapsbkeejq zeigen
supabase db push --dry-run                         # listet die noch fehlenden Migrationen, ändert nichts
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
- **Freunde und Gruppen:** Ist `20261018100000_social.sql` noch nicht eingespielt, zeigt die App im Social-Tab und in
  den Home-Modulen „Freunde und Gruppen sind auf dem Server noch nicht eingerichtet“; alles andere funktioniert.
  Nach `supabase db push` sind die Funktionen sofort verfügbar (Details: `docs/SOCIAL.md`).
- Erst danach `Config/Pace.xcconfig` lokal anlegen (siehe oben) und die App starten.

Nicht tun: `supabase db reset --linked` (löscht alle Daten), `--include-seed`, Secret Keys in die App oder ins
Repository.

## Offene Punkte für den Produktivbetrieb

- CAPTCHA für anonyme Anmeldungen und ggf. strengere Rate Limits.
- Sign in with Apple (Kontoübertragung auf andere Geräte). Konto- und Datenlöschung sowie Auskunft sind serverseitig
  vorhanden (`account_*`).
- Moderationswerkzeug statt manueller Sichtung im Dashboard (siehe „Moderation“); automatische Inhaltsprüfung von
  Bildern gibt es nicht.
- Verwaiste Dateien: Ersetzt jemand sein Profil- oder Gruppenbild, bleibt die alte Datei liegen, bis die App sie
  löscht oder das Konto gelöscht wird; eine regelmäßige Bereinigung (Dateien ohne Verweis) fehlt noch.
- Bereinigung verwaister anonymer Nutzer (z. B. ohne Profil nach 30 Tagen).
- Plausibilitätsprüfungen über das harte Limit hinaus (Anti-Cheat), falls Rankings missbraucht werden.
- Wartezeit für Regionswechsel (verhindert das Durchwechseln von Regionen, siehe Zugriffsregeln der Rankings).
- Bei stark wachsender Nutzerzahl: Rankings materialisieren statt pro Anfrage berechnen.
