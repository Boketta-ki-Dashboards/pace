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
