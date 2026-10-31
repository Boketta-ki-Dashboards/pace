# Rollout der Social-, Chat-, Medien- und Konto-Migrationen (Produktivprojekt)

> **Status: Nichts davon wurde ausgeführt.** Alle Migrationen sind bisher nur lokal (Docker) und in der CI gegen
> einen frischen lokalen Stack gelaufen. Jeder Schritt unten ist vom Nutzer selbst auszuführen und freizugeben.
> Ziel ist ausschließlich das Pace-Projekt `bnkrenfvfiaapsbkeejq` – kein anderes Supabase-Projekt.

## 1. Was eingespielt wird

In genau dieser Reihenfolge (die Supabase CLI sortiert nach Zeitstempel):

| # | Migration | Inhalt | Voraussetzung |
|---|---|---|---|
| 1 | `20261018100000_social.sql` | Freunde, Anfragen, Gruppen, Einladungen, Gruppen-Streak ([SOCIAL.md](SOCIAL.md)) | Basis-Migrationen `20261016100000`–`20261016100500` |
| 2 | `20261019100000_profiles_blocks_search.sql` | Profilbild, Auffindbarkeit, Präfixsuche, öffentliches Profil, Blockieren, Rate Limits für Benutzernamen | 1 |
| 3 | `20261019100100_groups_privacy_images.sql` | Gruppen-Privatsphäre, Einladungen beim Erstellen, Gruppenbild | 1, 2 |
| 4 | `20261019100200_chat.sql` | Privat- und Gruppenchats, Lesestand, Echtzeit-Hinweise | 1–3 |
| 5 | `20261019100300_storage_realtime_access.sql` | Buckets `avatars`, `group-images`, `chat-media`; Policies auf `storage.objects` und `realtime.messages` | 1–4, Storage und Realtime im Projekt aktiv |
| 6 | `20261019100400_moderation_account.sql` | Meldungen, Rückmeldungen, Auskunft, Konto löschen | 1–5 |

Alle sechs sind **additiv**: neue Tabellen und Spalten (mit Standardwerten), neue bzw. ersetzte Funktionen mit
unveränderten Signaturen. Es werden keine Daten gelöscht und keine Tabellen neu angelegt, die schon Daten enthalten.
Bestehende Gruppen erhalten `privacy = 'code'` und behalten damit den Beitritt per Code. Ältere App-Versionen laufen
weiter (alte Signatur von `social_create_group` bleibt erhalten).

Einzeln eingespielt sind die Migrationen nicht sinnvoll lauffähig – bitte immer alle zusammen mit
`supabase db push`.

## 2. Vorbereitung im Dashboard (vor dem Einspielen)

1. **Authentication → Sign In / Providers:** „Allow anonymous sign-ins“ ist aktiv (bereits für Milestone 2 nötig).
2. **Project Settings → Data API → Exposed schemas:** nur `public` (und `graphql_public`). Die Schemas `private`
   und `pace_access` dürfen **nicht** exponiert sein.
3. **Storage:** Der Dienst ist im Projekt aktiv (Standard). Unter *Storage → Settings* muss das globale
   „Upload file size limit“ mindestens **10 MB** betragen (Standard 50 MB), sonst greift es vor den Bucket-Grenzen
   (5 MB bzw. 10 MB). Die Buckets selbst legt Migration 5 an – **nicht** vorher von Hand anlegen.
4. **Realtime:** Der Dienst ist aktiv (Standard). Unter *Project Settings → Realtime* „Allow public access“
   **ausschalten** (nur private Kanäle). Die App nutzt ausschließlich private Broadcast-Kanäle; die Berechtigung prüft
   die Policy aus Migration 5. Prüfen, dass die Funktion `realtime.send(jsonb, text, text, boolean)` existiert
   (SQL Editor: `select to_regprocedure('realtime.send(jsonb, text, text, boolean)');` → nicht `null`). Fehlt sie,
   speichert der Server Nachrichten trotzdem; die App fällt dann auf regelmäßiges Aktualisieren zurück.

## 3. Sicherung

- **Pro-Plan oder höher:** *Database → Backups* – Zeitpunkt des letzten täglichen Backups notieren; mit
  Point-in-Time-Recovery zusätzlich die aktuelle Uhrzeit notieren.
- **Zusätzlich (oder im Free-Plan zwingend)** eine eigene Sicherung auf dem eigenen Rechner:

  ```sh
  supabase login
  supabase link --project-ref bnkrenfvfiaapsbkeejq     # fragt nach dem Datenbank-Passwort des Pace-Projekts
  supabase projects list                               # die verknüpfte Zeile (●) muss bnkrenfvfiaapsbkeejq zeigen
  supabase db dump --linked -f pace_schema_$(date +%Y%m%d).sql
  supabase db dump --linked --data-only -f pace_data_$(date +%Y%m%d).sql
  supabase db dump --linked --role-only -f pace_roles_$(date +%Y%m%d).sql
  ```

  Die Dateien enthalten personenbezogene Daten: nicht ins Repository legen, sicher aufbewahren.

## 4. Dry Run (durch den Nutzer)

```sh
supabase migration list --linked     # erwartet: 20261016100000 … 20261016100500 „remote“, die sechs oben nur „local“
supabase db push --dry-run           # muss genau die sechs Migrationen aus Abschnitt 1 auflisten, ändert nichts
```

Abbrechen, wenn

- der Dry Run andere oder zusätzliche Migrationen nennt,
- die verknüpfte Projekt-Ref nicht `bnkrenfvfiaapsbkeejq` ist,
- die Basis-Migrationen auf dem Server fehlen (dann zuerst deren Rollout nach [BACKEND.md](BACKEND.md) klären).

## 5. Einspielen (nach Freigabe)

```sh
supabase db push                     # NIE mit --include-seed, nie --include-all ohne Prüfung
```

Der Push läuft je Migration in einer Transaktion. Bricht er ab, bleiben bereits eingespielte Migrationen bestehen;
die fehlgeschlagene ist vollständig zurückgerollt. Fehlermeldung sichern und nicht „mit Gewalt“ wiederholen.

## 6. Prüfungen danach

Im SQL Editor (alle Abfragen nur lesend):

```sql
-- Neue Tabellen mit RLS
select tablename, rowsecurity from pg_tables
 where schemaname = 'public'
   and tablename in ('user_blocks', 'conversations', 'chat_messages', 'conversation_reads', 'reports', 'feedback');
-- erwartet: 6 Zeilen, rowsecurity = true

-- Buckets mit Grenzen
select id, public, file_size_limit, allowed_mime_types from storage.buckets
 where id in ('avatars', 'group-images', 'chat-media');
-- erwartet: 3 Zeilen, public = false, 5242880 / 5242880 / 10485760

-- Policies
select schemaname, tablename, policyname from pg_policies
 where policyname like 'pace\_%' and schemaname in ('storage', 'realtime') order by 1, 3;
-- erwartet: 9 auf storage.objects (je Bucket select/insert/delete), 1 auf realtime.messages

-- Bestehende Gruppen behalten den Code-Beitritt
select privacy, count(*) from public.groups group by privacy;   -- nur 'code' direkt nach dem Rollout

-- Keine neuen Rechte für anon
select count(*) from information_schema.role_table_grants
 where grantee = 'anon' and table_schema = 'public';           -- erwartet: 0
```

Danach:

1. **Database → Advisors** (Security und Performance): keine neuen Warnungen.
2. **App (TestFlight/Gerät) mit zwei Konten:** Präfixsuche → Freundschaftsanfrage → Annahme → Privatchat in beide
   Richtungen (Nachricht erscheint ohne manuelles Aktualisieren = Realtime funktioniert) → Bild im Chat senden →
   Gruppe „nur auf Einladung“ mit Einladung erstellen → Beitritt → Gruppenchat → Profilbild setzen → Blockieren und
   Aufheben → Melden → Datenexport.
3. *Storage → Buckets:* Die drei Buckets sind privat; hochgeladene Dateien liegen in Ordnern mit UUIDs.
4. *Realtime → Inspector* (optional): Kanäle `chat:<uuid>` / `user:<uuid>` erscheinen als privat.

## 7. Rücknahme

- **Bevorzugt: vorwärts korrigieren.** Fehler in einer Funktion mit einer neuen Migration beheben
  (`create or replace function …`). Das ist ohne Datenverlust möglich, weil alle Änderungen additiv sind.
- **Funktionen der App abschalten ohne Datenbankänderung:** Ältere App-Versionen nutzen die neuen Funktionen nicht.
  Die aktuelle App zeigt bei fehlenden Funktionen einen gestalteten „Noch nicht verfügbar“-Zustand (`PGRST202` →
  `.unavailable`).
- **Vollständig zurück:** nur über die Sicherung aus Abschnitt 3 (PITR bzw. Wiederherstellung der Dumps). Achtung:
  Alles, was nach dem Rollout entstanden ist (Nachrichten, Blockierungen, Meldungen, Bilder), geht dabei verloren.
  Dateien in Storage sind nicht Teil eines Datenbank-Backups; vor einer Wiederherstellung die Buckets im Dashboard
  sichern oder bewusst verwerfen.
- **Nicht tun:** `supabase db reset --linked` (löscht alle Daten), Tabellen von Hand löschen, `storage.objects`
  per SQL löschen (Supabase verbietet das; Dateien nur über die Storage-API bzw. das Dashboard entfernen).

## 8. Nach dem Rollout

- `Config/Pace.xcconfig` bleibt lokal (nie committen); in die App gelangt nur der Publishable Key.
- Moderation: offene Meldungen regelmäßig im Dashboard sichten (Ablauf in [BACKEND.md](BACKEND.md), „Moderation“).
- Diese Datei um Datum, ausführende Person und Ergebnis der Prüfungen ergänzen.

---

# Auftrag 3: drei neue Migrationen (Spitznamen, Nachrichtenaktionen, Gruppenkalender)

> **Status: NICHT ausgeführt – Freigabe durch den Nutzer nötig.** Die drei Migrationen sind nur lokal (Docker:
> pgTAP 965 Prüfungen, `db lint`, `db advisors`, Realtime-Skript, Swift-Unit- und Integrationstests) gelaufen.
> Ziel ist ausschließlich das Pace-Projekt `bnkrenfvfiaapsbkeejq`. Die sechs Migrationen aus dem ersten Teil
> (`20261018100000` … `20261019100400`) sind laut Nutzer bereits produktiv eingespielt und bleiben unverändert.

## A. Was eingespielt wird

| # | Migration | Inhalt | Voraussetzung |
|---|---|---|---|
| 7 | `20261023100000_friend_nicknames.sql` | Tabelle `friend_nicknames`, `social_set_friend_nickname`, `nickname` in Profil-/Ranking-/Einladungsausgaben, `account_export` mit Spitznamen | 1–6 produktiv |
| 8 | `20261023100100_chat_message_actions.sql` | Spalten `reply_to_id`, `edited_at`, `media_duration_ms` und Art `voice` in `chat_messages`; Tabellen `chat_message_favorites`, `chat_message_pins`; `chat_send` mit zwei neuen Parametern (Standard `null`), `chat_edit_message`, `chat_set_favorite`, `chat_favorites`, `chat_set_pinned`, `chat_pins`; Bucket `chat-media` mit `audio/mp4`, `audio/x-m4a`, `audio/aac` (Vereinigung); Storage-Policy `pace_chat_media_select` ersetzt (Lesen nur Uploader bzw. sichtbare Nachricht), Index `chat_messages_media_path_idx` | 7 |
| 9 | `20261023100200_group_calendar.sql` | `social_group_calendar` | 7 |

Alle drei sind **additiv**: neue Tabellen, nullable Spalten ohne Standardwert (sofort, ohne Umschreiben der Tabelle),
neue Funktionen, ersetzte Funktionen mit gleicher Signatur. Die Prüfregeln von `chat_messages` werden als `not
valid` neu angelegt und anschließend validiert (kurze Sperre, bestehende Zeilen erfüllen sie: Obermengen bzw. nur
neue Spalten). Einzige Signaturänderung: `chat_send` (alte Fassung entfernt, neue mit zwei zusätzlichen
Parametern **mit Standardwert**) – ältere App-Versionen rufen sie mit den bisherigen Parametern auf und laufen
unverändert. Keine Daten werden gelöscht. Neue Antwortfelder ignorieren ältere Versionen. Die Storage-Policy
`pace_chat_media_select` wird enger (Lesen nur für die hochladende Person bzw. über eine sichtbare Nachricht); ältere
Versionen laden ohnehin nur solche Medien. Der neue Index `chat_messages_media_path_idx` wird ohne `concurrently`
angelegt (Migration in einer Transaktion) und sperrt Schreibzugriffe auf `chat_messages` kurz – bei der aktuellen
Datenmenge unkritisch.

## B. Vorbereitung

1. Sicherung wie in Abschnitt 3 oben (Backup-Zeitpunkt notieren bzw. `supabase db dump --linked …`).
2. *Storage → Settings:* globales Upload-Limit weiterhin ≥ 10 MB (Sprachnachrichten nutzen den Bucket `chat-media`
   mit 10 MB).
3. Realtime unverändert (private Kanäle, „Allow public access“ aus) – neue Ereignisse `message_updated` und
   `pins_changed` laufen über dieselben Topics und dieselbe Policy.
4. Keine Dashboard-Änderungen an Buckets von Hand: Migration 8 setzt `allowed_mime_types` von `chat-media` selbst.

## C. Probelauf (durch den Nutzer)

```sh
supabase link --project-ref bnkrenfvfiaapsbkeejq
supabase migration list --linked     # erwartet: alles bis 20261019100400 „remote“, die drei neuen nur „local“
supabase db push --dry-run           # muss genau 20261023100000, 20261023100100, 20261023100200 nennen
```

Abbrechen, wenn andere oder zusätzliche Migrationen erscheinen oder die Projekt-Ref nicht stimmt.

## D. Einspielen (nur nach ausdrücklicher Freigabe)

```sh
supabase db push                     # NIE mit --include-seed
```

Jede Migration läuft in einer Transaktion; bei einem Abbruch bleiben die vorherigen bestehen, die fehlerhafte ist
vollständig zurückgerollt.

## E. Prüfung danach (SQL Editor, nur lesend)

```sql
-- Neue Tabellen mit RLS und ohne Policies
select tablename, rowsecurity from pg_tables
 where schemaname = 'public' and tablename in ('friend_nicknames', 'chat_message_favorites', 'chat_message_pins');
-- erwartet: 3 Zeilen, rowsecurity = true
select count(*) from pg_policies
 where schemaname = 'public' and tablename in ('friend_nicknames', 'chat_message_favorites', 'chat_message_pins');
-- erwartet: 0

-- Genau eine Fassung von chat_send (8 Parameter) und die neuen RPCs nur für authenticated
select oid::regprocedure from pg_proc where proname = 'chat_send';
select proname, has_function_privilege('anon', oid, 'execute') as anon,
       has_function_privilege('authenticated', oid, 'execute') as authenticated
  from pg_proc
 where pronamespace = 'public'::regnamespace
   and proname in ('social_set_friend_nickname', 'social_group_calendar', 'chat_edit_message', 'chat_set_favorite',
                   'chat_favorites', 'chat_set_pinned', 'chat_pins');
-- erwartet: 7 Zeilen, anon = false, authenticated = true

-- Bucket chat-media mit Audio, Grenze unverändert
select file_size_limit, allowed_mime_types from storage.buckets where id = 'chat-media';
-- erwartet: 10485760, … image/webp, audio/mp4, audio/x-m4a, audio/aac

-- Lese-Policy für Chat-Medien: hochladende Person oder sichtbare Nachricht
select polname, pg_get_expr(polqual, polrelid) from pg_policy
 where polrelid = 'storage.objects'::regclass and polname = 'pace_chat_media_select';
-- erwartet: … owner_id = (SELECT auth.uid())::text OR pace_access.can_read_chat_media(name) …

-- Bestehende Nachrichten unverändert gültig
select count(*) from public.chat_messages where kind not in ('text', 'image', 'gif', 'profile');   -- direkt danach 0
```

Danach *Database → Advisors* (keine neuen Warnungen) und mit zwei Konten in der App: Spitzname setzen (nur bei
mir sichtbar), Antworten, eigene Nachricht bearbeiten (erscheint beim anderen als „Bearbeitet“), Favorit, Pin
(Gruppe nur Owner), Sprachnachricht senden und beim anderen abspielen, Bild senden und beim anderen laden,
Gruppenkalender öffnen.

## F. Rücknahme

Vorwärts korrigieren (neue Migration mit `create or replace function …`). Ältere App-Versionen nutzen die neuen
Funktionen nicht; die aktuelle App zeigt bei fehlenden Funktionen „noch nicht eingerichtet“ (`PGRST202` →
`.unavailable`). Ein vollständiges Zurück geht nur über die Sicherung (Daten seit dem Rollout gehen verloren).

---

# Auftrag 6: eine neue Migration (Social-Profil 2.0)

> **Status: NICHT ausgeführt – Freigabe durch den Nutzer nötig.** Die Migration ist nur lokal bzw. in der CI
> (Job „Backend“: Docker-Supabase, pgTAP inkl. `17_profile_details.test.sql` mit 32 Prüfungen, `db lint`) gelaufen.
> Ziel ist ausschließlich das Pace-Projekt `bnkrenfvfiaapsbkeejq`. Alle bisherigen Migrationen bleiben unverändert und
> werden nicht erneut ausgeführt. Kein `db reset`, keine Daten werden gelöscht.

## A. Was eingespielt wird

| # | Migration | Inhalt | Voraussetzung |
|---|---|---|---|
| 10 | `20261030100000_profile_details.sql` | Spalten `bio`, `interests`, `banner_path`, `shows_achievements`, `achievements` in `profiles` (mit Prüfregeln und Validierungs-Trigger); Spaltenrecht `update` darauf für `authenticated`; `pace_access.can_read_avatar` liest zusätzlich das aktuelle Banner; neue RPC `social_profile_details(uuid)` | 1–9 produktiv |

**Additiv und rückwärtskompatibel:**

- `bio` und `banner_path` sind nullable ohne Standardwert; `interests`, `achievements` (`'{}'`) und
  `shows_achievements` (`false`) haben konstante Standardwerte – PostgreSQL legt sie ohne Umschreiben der Tabelle an.
- Die vier Prüfregeln (`profiles_bio_valid`, `profiles_interests_valid`, `profiles_banner_path_format`,
  `profiles_achievements_valid`) prüfen beim Anlegen die bestehenden Zeilen: Dort stehen nur `null` bzw. die
  Standardwerte, die Regeln sind erfüllt. Bei der aktuellen Datenmenge ist die kurze Sperre unkritisch.
- Bio: 1–160 Zeichen, ohne führende/folgende Leerzeichen, höchstens 4 Zeilen, keine Steuer- oder unsichtbaren
  Zeichen (Emoji mit Zero-Width-Joiner bleiben erlaubt). Kein HTML – die App zeigt die Bio als reinen Text.
- Interessen (≤ 5) und Auszeichnungen (≤ 7) nur aus festen Katalogen mit stabilen IDs, ohne Doppelte (Trigger
  `private.validate_profile_details`).
- Banner: nur ein Pfad im eigenen Ordner des Buckets `avatars` (`<public_id>/<datei>`), geprüft vom Trigger
  `private.validate_profile_banner` – wie beim Profilbild. Keine neue Bucket-Konfiguration, keine neue
  Storage-Policy: Die bestehende Lese-Policy ruft `pace_access.can_read_avatar` auf; die Funktion wird mit gleicher
  Signatur ersetzt (Blockierung wird wie beim Profilbild beachtet).
- `social_profile_details` liefert nichts an `anon`, hat dieselbe Sichtbarkeit wie `social_public_profile`
  (`not_found`), gibt bei Blockierung (beide Richtungen) leere Angaben zurück und Auszeichnungen fremder Profile nur,
  wenn die Person sie freigegeben hat. Rate Limit: 120 Aufrufe je 10 Minuten.
- Ältere App-Versionen lesen die neuen Spalten nicht und rufen die RPC nicht auf. Die neue App zeigt ohne Migration
  „noch nicht eingerichtet“ auf „Profil bearbeiten“ und Profile ohne Bio/Interessen/Banner (`PGRST202`/`42703` →
  `.unavailable`) – sonst unverändert.

## B. Vorbereitung

1. Sicherung wie in Abschnitt 3 oben (Backup-Zeitpunkt notieren bzw. `supabase db dump --linked …`).
2. *Storage → Settings:* keine Änderung nötig. Banner werden als JPEG ≤ 5 MB in den bestehenden Bucket `avatars`
   hochgeladen (Grenze und MIME-Typen des Buckets bleiben).

## C. Probelauf (durch den Nutzer)

```sh
supabase migration list --linked     # erwartet: alles bis 20261023100200 „remote“, nur 20261030100000 „local“
supabase db push --dry-run           # muss genau 20261030100000 nennen
```

Abbrechen, wenn andere oder zusätzliche Migrationen erscheinen oder die Projekt-Ref nicht stimmt.

## D. Einspielen (nur nach ausdrücklicher Freigabe)

```sh
supabase db push                     # NIE mit --include-seed
```

Die Migration läuft in einer Transaktion; bei einem Fehler wird sie vollständig zurückgerollt.

## E. Prüfung danach (SQL Editor, nur lesend)

```sql
-- Neue Spalten mit Standardwerten
select column_name, data_type, is_nullable, column_default from information_schema.columns
 where table_schema = 'public' and table_name = 'profiles'
   and column_name in ('bio', 'interests', 'banner_path', 'shows_achievements', 'achievements');
-- erwartet: 5 Zeilen

-- Prüfregeln vorhanden und gültig
select conname, convalidated from pg_constraint
 where conrelid = 'public.profiles'::regclass
   and conname in ('profiles_bio_valid', 'profiles_interests_valid', 'profiles_achievements_valid', 'profiles_banner_path_format');
-- erwartet: profiles_bio_valid, profiles_interests_valid, profiles_achievements_valid, profiles_banner_path_format – convalidated = true

-- RPC nur für authenticated
select has_function_privilege('anon', 'public.social_profile_details(uuid)', 'execute') as anon,
       has_function_privilege('authenticated', 'public.social_profile_details(uuid)', 'execute') as authenticated;
-- erwartet: anon = false, authenticated = true

-- Bestehende Profile unverändert
select count(*) from public.profiles where bio is not null or banner_path is not null or interests <> '{}';
-- direkt danach: 0
```

Danach *Database → Advisors* (keine neuen Warnungen) und mit zwei Konten in der App: Bio, Interessen und Banner
setzen, Auszeichnungen ein- und ausschalten; beim anderen Konto das fremde Profil öffnen (Banner lädt, Auszeichnungen
nur bei Freigabe); nach Blockieren keine Bio/kein Banner mehr.

## F. Rücknahme

Vorwärts korrigieren (neue Migration). Die Spalten können bleiben – ältere App-Versionen ignorieren sie. Die vorige
Fassung von `pace_access.can_read_avatar` steht in `20261019100300_storage_realtime_access.sql` (nur ohne
`banner_path`). Ein vollständiges Zurück geht nur über die Sicherung.
