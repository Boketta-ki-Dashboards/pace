# Social (Freunde und Gruppen)

App und Serverseite der Social-Funktionen: Freundschaften, Freundesranking, Gruppen mit Einladungen, Gruppenranking und
Gruppen-Streak. Schema und Funktionen stehen in `supabase/migrations/20261018100000_social.sql`, die Tests in
`supabase/tests/06_social_friends.test.sql`, `07_social_groups.test.sql` und `08_social_group_streak.test.sql`.
Allgemeine Backend-Regeln (Auth, RLS, Rechte, lokale Entwicklung) stehen in [BACKEND.md](BACKEND.md).

Grundsätze:

- **Kein direkter Tabellenzugriff.** Alle Social-Tabellen haben RLS ohne Policies; `anon` und `authenticated` haben
  keinerlei Tabellenrechte. Die App nutzt ausschließlich die RPCs unten. Sie sind `security definer` mit
  `set search_path = ''`, nur für `authenticated` ausführbar und prüfen selbst `auth.uid()` und ein vorhandenes
  Profil.
- **Nur öffentliche Felder.** Antworten enthalten ausschließlich `public_id`, `username`, `display_name` und
  Schrittzahlen (dazu Gruppendaten). Nie Auth-IDs, nie Gemeinden, nie andere Gesundheitsdaten.
- **Existenz bleibt verborgen.** `not_found` bedeutet „gibt es nicht“ *oder* „ist für dich nicht sichtbar“. Fremde
  Anfragen, Einladungen und Gruppen lassen sich nicht ertasten.
- **Alles wird beim Lesen berechnet** (Rankings, Gruppentage, Streaks) – es gibt keine Hintergrundjobs.

## App (SocialFeature)

Der Social-Tab ist ein eigener `NavigationStack` mit `NavigationPath` (`SocialView`). Alle Seiten zeigen echte Daten
über `SocialRepository`; ohne Backend oder vor der Server-Einrichtung (`SocialError.unavailable`) erscheinen
gestaltete, ehrliche Zustände statt Funktionen. Alle Texte stehen in `SocialText` (Deutsch, Englisch, Russisch;
Pluralformen über `PaceLocalization.plural`). Unterseiten verwenden `PaceSubpageHeader` + `.paceSubpage()`
(„‹ Social“ → Wortmarke → Titel); die Gruppendetails zeigen wie Referenzbild 4 statt eines Titels den Gruppenkopf.

| Seite | Route | ViewModel | Inhalt |
|---|---|---|---|
| Hauptseite (Bild 9) | – | `SocialViewModel` | Wortmarke, oben rechts Freundschaftsanfragen (Person-Plus mit Zähler) neben den Einstellungen, „Freund hinzufügen“/„Gruppe erstellen“, Suche (Freunde inkl. Spitznamen und Chats lokal), Top-Freunde (kompakt: Profilbild, Spitzname bzw. Name, Schritte, Platz – nur Freunde), Chats (`ChatListSection`, Überschrift mit Link „Meine Gruppen“ und Einladungszähler) |
| Freund hinzufügen (Bild 1) | `.addFriend` | `FriendSearchViewModel` | Präfixsuche ab 3 Zeichen mit Verzögerung (350 ms), nur die neueste Antwort zählt; Hinzufügen / Anfrage gesendet / Bereits befreundet / Annehmen; Menü: Profil teilen, Nachricht schreiben (nur Freunde), Nutzer blockieren (mit Bestätigung) |
| Freundschaftsanfragen (Bild 2) | `.requests` | `SocialViewModel` | Eingegangen (Annehmen/Ablehnen), Gesendet (Ausstehend/Zurückziehen) |
| Profil | `.profile` | `UserProfileViewModel` | `publicProfile`: Aktionen je Beziehung, Schritte nur unter Freunden, Nachricht, Spitzname vergeben/ändern/entfernen (nur Freunde; darunter bleibt der Anzeigename sichtbar), Teilen, Freund entfernen, Blockieren/Aufheben, Melden |
| Profil teilen | `.shareProfile` | `ShareProfileViewModel` | Empfänger (Freunde, eigene Gruppen) → `ChatListViewModel.shareProfile`; Link `pace://u/<name>` über `ShareLink` |
| Melden | `.report` | `ReportViewModel` | Grund aus `ReportReason`, Details (max. 500 Zeichen) → `report` |
| Gruppe erstellen (Bild 3) | `.createGroup` | `CreateGroupViewModel` | Bild (PhotosPicker, auf 1.024 px verkleinert, JPEG ≤ 5 MB), Name, Beschreibung, Typ, Privatsphäre, Einladungen, Tagesziel (500er-Stufen), Drittel-Regel; danach öffnen sich die Details |
| Gruppen | `.groups` | `SocialViewModel` | eigene Gruppen, Einladungen annehmen/ablehnen, Beitritt per Code, neue Gruppe |
| Gruppendetails (Bild 4) | `.group` | `GroupDetailViewModel` | Kopf, Streak-Karte, Fortschritt (Pillen je Mitglied, „x von y benötigten Zielen“, Flamme), Gruppenchat/Mitglieder/Einstellungen, Zeile „Gruppenkalender“, „Heute in der Gruppe“ mit `PaceRankingRow` |
| Gruppenkalender | `.groupCalendar` | `GroupCalendarViewModel` | Monat ab Montag (Vor/Zurück in der Gruppenzeit, „Heute“), Zellen: gesichert mintgrün, Pokal für Tagesbeste, ohne Daten gestrichelt, Zukunft/vor Gründung neutral; ausgewählter Tag: Flamme, Gruppenziel je Mitglied, „x von n erreicht“, benötigt ⌈n/3⌉, vollständige Rangliste (eigene Zeile hervorgehoben, „Ehemaliges Mitglied“ ohne Profil) |
| Mitglieder | `.groupMembers` | `GroupDetailViewModel` | Rollen, Entfernen (nur Verwaltung), offene Einladungen zurückziehen (Verwaltung), Freunde einladen |
| Gruppeneinstellungen | `.groupSettings` | `GroupDetailViewModel` | Bild, Name, Beschreibung, Typ, Privatsphäre (`updateGroupDetails`), Tagesziel ab morgen, Einladungscode teilen/erneuern, verlassen, löschen (Verwaltung), melden |
| Freundesranking | `.friendsRanking` | `FriendsRankingViewModel` | heute / diese Woche |
| Social-Einstellungen | `.settings` | `SocialSettingsViewModel` | Anfragen, Gruppeneinladungen, Sichtbarkeit in der Suche (öffnet die Profil-Einstellung), blockierte Nutzer |

Wichtige Abläufe:

- **Gruppe erstellen:** `createGroup` mit Privatsphäre und Einladungen; fehlende Einladungen und eine abweichende
  Privatsphäre holt die App nach, erst danach wird das Bild hochgeladen (`MediaUploadTarget.groupImage(groupID:)`,
  dann `setGroupImage`). Scheitert ein Folgeschritt, gibt es die Gruppe trotzdem; der Hinweis nennt, was fehlt.
- **Gruppen-Streak:** Erreichte, benötigte Ziele und „Flamme gesichert“ kommen vom Server
  (`todayReachedCount`, `todayRequiredCount`, `todayComplete`); die App rechnet die ⅓-Regel nicht neu.
- **Aktionen** laufen über `SocialViewModel.perform`: Während einer Aktion ist die betroffene ID gesperrt, danach
  stehen Erfolg oder Fehler im gemeinsamen Hinweis (`notice`), und der Stand wird neu geladen – Anfragenzähler,
  Listen und Hauptseite sind damit synchron.
- **Profil-Links:** `showProfile(username:)` setzt `requestedProfile`; der Social-Tab sucht das Profil über
  `findProfile` und öffnet es oder zeigt einen Hinweis. Gruppen von außen öffnet `showGroup(_:)`.
- **Chats:** `navigationDestination(for: ChatTarget.self)` öffnet `ChatView(viewModel: chats.chat(for:))`.
  Gruppenchat aus den Details: `.group(id:name:)`, Privatchat aus Profil und Suche: `.direct(profile)`.
- **Sichtbarkeit in der Suche:** keine eigene Einstellung im Social-Bereich; `SocialViewModel.openPrivacySettings`
  (vom App-Rahmen gesetzt) öffnet die Profil-Einstellung.
- **Spitznamen:** `UserProfileViewModel.saveNickname` (Prüfung beim Tippen über `NicknameRules`, leer = entfernen)
  → `setFriendNickname`; danach `SocialViewModel.nicknameDidChange` (Freunde, Ranking, Top-Freunde sofort) und
  `ChatListViewModel.profileDidChange` (Chatliste und offene Chats neu laden). Angezeigt wird überall `shownName`
  bzw. `shownTitle`; Freundschaftsanfragen und Blockierte zeigen den Anzeigenamen (dort gibt es keinen Spitznamen).

Tests: `Tests/SocialFeatureTests` (Suche mit Verzögerung und veralteten Antworten, Anfragen, Blockieren/Melden,
Gruppe erstellen mit Einladungen, Privatsphäre und Bild, Gruppendetails/Mitglieder/Einstellungen, Profile, Teilen,
Einstellungen, Freundesranking, Sprache). Snapshots: `Tests/PaceSnapshotTests/SocialSnapshotTests.swift`
(`social`, `add-friend`, `friend-requests`, `create-group`, `group-detail`, `user-profile` in DE/EN/RU sowie
`group-members`, `group-settings`, `social-groups`, `friends-ranking`, `social-settings`, `share-profile`, `report`,
`social-unavailable`).

## Datenmodell

### Freundschaften

`public.friend_requests` – Anfragen mit Verlauf:

| Spalte | Bedeutung |
|---|---|
| `id` | UUID der Anfrage (`request_id` in der API) |
| `requester_id`, `addressee_id` | Absender und Empfänger (→ `profiles`, `on delete cascade`), nie gleich |
| `status` | `pending`, `accepted`, `declined`, `cancelled` |
| `created_at`, `responded_at` | `responded_at` ist genau dann gesetzt, wenn die Anfrage nicht mehr offen ist |

Höchstens eine offene Anfrage je Paar, unabhängig von der Richtung (eindeutiger Teilindex auf
`least/greatest(requester_id, addressee_id) where status = 'pending'`).

`public.friendships` – bestätigte Freundschaften, ein Eintrag je Paar (`user_a < user_b`, Primärschlüssel
`(user_a, user_b)`, beide → `profiles` mit Cascade), `created_at` = „befreundet seit“.

### Gruppen

| Tabelle | Inhalt |
|---|---|
| `public.groups` | `id`, `name` (3–40 Zeichen), `description` (0–200), `kind` (`friends`, `class`, `work`, `club`, `other`), `time_zone` (Standard `Europe/Berlin`), `invite_code` (eindeutig), `created_by` (→ `profiles`, `on delete set null`), `created_at`, `updated_at` |
| `public.group_members` | aktuelle Mitglieder: `group_id`, `user_id`, `role` (`owner`/`member`), `joined_at`; genau ein `owner` je Gruppe (eindeutiger Teilindex + Lösch-Trigger) |
| `public.group_membership_periods` | Historie für die Streak: je Mitgliedschaft `joined_at` bis `left_at` (offen = aktuelles Mitglied). Wird ausschließlich per Trigger auf `group_members` gepflegt (Beitritt öffnet, Austritt schließt eine Periode) |
| `public.group_goal_history` | Tagesziele mit Gültigkeitsbeginn: `(group_id, effective_from)` → `daily_goal` (1000–100000) |
| `public.group_invitations` | Einladungen mit Verlauf: `inviter_id`, `invitee_id`, `status` wie bei Freundschaftsanfragen; höchstens eine offene Einladung je `(group_id, invitee_id)` |

Namen und Beschreibungen werden vor dem Speichern am Rand von Leerzeichen, Tabs und Zeilenumbrüchen befreit. Für
Gruppennamen gelten dieselben Regeln wie für Anzeigenamen (keine Steuer- und unsichtbaren Formatzeichen wie
Zero-Width Space oder Richtungswechsel); Beschreibungen dürfen zusätzlich Zeilenumbrüche (`\n`) enthalten. Die Regeln
stehen nur in den Constraints der Tabellen; die RPCs übersetzen eine Verletzung in das passende Fehler-Token.

Einladungscodes: 8 Zeichen aus `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (ohne I, O, 0, 1), kryptographisch zufällig
(`extensions.gen_random_bytes`, gleichverteilt). Beim Beitritt wird die Eingabe normalisiert: Großbuchstaben,
Leerzeichen und `-` entfernt – `abcd-efgh` findet `ABCDEFGH`.

### Intern

`private.rate_limit_events (user_id, action, created_at)` zählt Aktionen für die Rate Limits;
`private.consume_rate_limit(p_user_id, p_action, p_limit, p_window)` prüft, zählt und löscht dabei veraltete
Einträge. Alle Hilfsfunktionen liegen im Schema `private` und sind für Clients nicht ausführbar.

## Datenschutz und Zustimmung

- **Freundschaft = gegenseitige Zustimmung.** Wer eine Anfrage sendet und wer sie annimmt, teilt seine
  Wettbewerbsschritte mit dieser Person – **unabhängig von `regional_leaderboard_enabled`** (das gilt nur für die
  öffentlichen Regionalrankings). Freunde sehen: Anzeigename, Benutzername, „befreundet seit“, Schritte eines Tages
  und einer ISO-Woche im Stichtagsfenster (heute (UTC) − 14 bis + 1), Platz im Freundesranking.
- **Gruppenbeitritt = Zustimmung gegenüber allen Mitgliedern.** Mitglieder sehen voneinander Anzeigename,
  Benutzername, Rolle und Schritte des Gruppentags bzw. der laufenden ISO-Woche – auch ohne Freundschaft.
- **Profilsuche** nur per exaktem Benutzernamen (ohne Groß-/Kleinschreibung), keine Teilstringsuche, keine Listen.
  Ein Treffer zeigt Anzeigename und Benutzername (die beim Annehmen ohnehin sichtbar würden).
- **Einladungen** gibt es nur unter Freunden. Endet eine Freundschaft, werden offene Einladungen zwischen beiden
  zurückgezogen; verlässt die einladende Person die Gruppe oder wird sie entfernt, ebenso ihre offenen Einladungen
  in diese Gruppe. Eingeladene sehen vor dem Annehmen nur Name, Art und Mitgliederzahl der Gruppe sowie die einladende
  Person – nicht den Einladungscode und keine Mitglieder.
- Der Einladungscode ist für alle Mitglieder sichtbar und weitergebbar (wie ein Gruppenlink). Der Eigentümer kann
  ihn jederzeit neu erzeugen; der alte wird sofort ungültig.
- **Löschen eines Profils** entfernt Anfragen, Freundschaften, Einladungen, Mitgliedschaften und deren Historie
  (Cascade). Vergangene Gruppentage werden danach ohne diese Person berechnet.

## Gruppentag und Gruppen-Streak

- **Gruppentag** = Kalendertag in der Zeitzone der Gruppe, für alle Mitglieder gleich:
  heute = `(now() at time zone groups.time_zone)::date`. Sommer-/Winterzeit wird berücksichtigt (das Tagesende ist
  Mitternacht Ortszeit, auch an 23- und 25-Stunden-Tagen).
- **Schritte** eines Mitglieds am Gruppentag *d* = `daily_activity.competition_steps` mit `activity_date = d`
  (lokaler Tag des Geräts, nur Competition Steps ohne manuelle Einträge). Der Primärschlüssel erlaubt einen Wert je
  Person und Tag – jedes Mitglied zählt pro Tag höchstens einmal.
- **Mitglieder des Tages *d***: wer am Tagesende Mitglied war, also eine Periode mit `joined_at` < Beginn von *d* + 1
  und `left_at` leer oder ≥ Beginn von *d* + 1 (jeweils in der Gruppenzeitzone). Wer am selben Tag beitritt und
  wieder austritt, zählt nicht; wer abends beitritt, zählt schon. Für den laufenden Tag sind das genau die
  aktuellen Mitglieder.
- **Ziel des Tages *d***: Eintrag der Zielhistorie mit dem größten `effective_from` ≤ *d*. Beim Erstellen gilt das
  Ziel ab dem Erstellungstag; `social_set_group_goal` gilt ab dem **nächsten** Gruppentag – Vergangenheit und
  laufender Tag ändern sich nie.
- **Erreicht** ist ein Tag, wenn es Mitglieder gibt (*n* > 0) und mindestens **⌈*n* / 3⌉** von ihnen das Ziel
  erreicht haben (Schritte ≥ Ziel):

  | Mitglieder *n* | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 10 | 12 | 20 | 50 |
  |---|---|---|---|---|---|---|---|---|---|---|---|
  | benötigt | 1 | 1 | 1 | 2 | 2 | 2 | 3 | 4 | 4 | 7 | 17 |

- **Berücksichtigte Tage**: vom Erstellungstag (Ortszeit) bis heute, höchstens die letzten 730 Gruppentage
  (einschließlich heute).
- **`current_streak`**: Ist heute schon erreicht, zählt heute plus alle lückenlos erreichten Tage direkt davor.
  Sonst die lückenlos erreichten Tage bis gestern – **der laufende Tag bricht die Streak nie vorzeitig**. Ein nicht
  erreichter vergangener Tag beendet sie.
- **`best_streak`**: längste Folge erreichter Tage im berücksichtigten Zeitraum (inkl. heute, falls erreicht).
- **Verspätete Synchronisation** (Tageswerte bis 8 Tage zurück, siehe BACKEND.md) fließt automatisch ein, weil beim
  Lesen berechnet wird – ein nachgereichter Wert kann eine Lücke schließen.
- Tage ohne Mitglieder (z. B. vor dem ersten Beitritt in einer zurückdatierten Gruppe) sind nie erreicht.

Berechnet wird mengenbasiert in `private.group_day_stats` (eine Zeile je Tag aus `generate_series`, Perioden,
Zielhistorie; Tageswerte je Mitglied über einen Bereichszugriff auf den Primärschlüssel von `daily_activity`) und
`private.group_summary` (Inseln aufeinanderfolgender erreichter Tage). Messung lokal mit 1,6 Mio. Tageswerten:
eine Gruppe mit 50 Mitgliedern und 730 vollen Tagen ≈ 40 ms; `social_my_groups` mit 20 solchen Gruppen ≈ 0,9 s
(theoretischer Höchstfall).

## Gruppen-JSON „summary“

Überall gleich (`social_create_group`, `social_update_group`, `social_set_group_goal`, `social_my_groups`,
`social_group`, `social_regenerate_invite_code`, `social_join_group`, `social_respond_group_invitation`):

```json
{
  "group_id": "uuid",
  "name": "Lauftreff Nord",
  "description": "Jeden Morgen\nam See",
  "kind": "club",
  "role": "owner",
  "member_count": 4,
  "daily_goal": 10000,
  "next_daily_goal": 12000,
  "time_zone": "Europe/Berlin",
  "group_today": "2026-10-18",
  "invite_code": "K7MPQ2XA",
  "current_streak": 6,
  "best_streak": 8,
  "today_reached_count": 1,
  "today_required_count": 2,
  "today_complete": false,
  "created_at": "2026-10-01T08:00:00.123456+00:00"
}
```

`daily_goal` ist das heutige Ziel; `next_daily_goal` ist nur gesetzt, wenn ab morgen ein **abweichendes** Ziel
geplant ist, sonst `null`. `today_*` beziehen sich auf den laufenden Gruppentag.

## RPCs (Data API, nur `authenticated`)

Alle Funktionen werfen `not_authenticated` (42501) ohne Nutzer-ID und `profile_required` ohne Profil. Datumswerte
sind `date` (`"YYYY-MM-DD"`), Zeitstempel `timestamptz` (ISO 8601).

### Freunde

| Funktion | Antwort | Fehler |
|---|---|---|
| `social_find_profile(p_username text)` | `{"public_id","username","display_name","relationship","request_id"}` oder `null` (ungültiges Format oder kein Treffer); `relationship` ∈ `self`, `friend`, `outgoing_request`, `incoming_request`, `none`; `request_id` nur bei offener Anfrage | `rate_limited` |
| `social_send_friend_request(p_public_id uuid)` | `{"status","request_id"}`; `requested` (neu), `accepted` (offene Gegenanfrage wurde angenommen, `request_id` = deren ID), `already_friends` (`request_id` null), `already_requested` | `not_found`, `self_request`, `cooldown`, `limit_reached`, `rate_limited` |
| `social_respond_friend_request(p_request_id uuid, p_accept boolean)` | `{"status"}` ∈ `accepted`, `declined` | `not_found` (nicht Empfänger, nicht offen, `p_accept` null), `limit_reached` |
| `social_cancel_friend_request(p_request_id uuid)` | – | `not_found` (nicht Absender oder nicht offen) |
| `social_remove_friend(p_public_id uuid)` | – | `not_found` (nicht befreundet) |
| `social_friend_requests()` | `[{"request_id","direction","public_id","username","display_name","created_at"}]`, offene Anfragen, `direction` ∈ `incoming`, `outgoing`, neueste zuerst | – |
| `social_friends()` | `[{"public_id","username","display_name","friends_since"}]`, nach Anzeigename (ohne Groß-/Kleinschreibung), dann Benutzername | – |
| `social_friend_ranking(p_period text, p_date date)` | wie `leaderboard_page`: `{"total_participants","entries":[{"rank","public_user_id","username","display_name","competition_steps","is_current_user"}]}` | `invalid_date`, `invalid_period` |
| `social_friend_profile(p_public_id uuid, p_date date)` | `{"public_id","username","display_name","friends_since","steps_today","steps_week"}` | `not_found` (kein Freund), `invalid_date` |

Freundesranking: Teilnehmer sind ich und alle Freunde, auch ohne Tageswert (dann 0). `daily` = Tag `p_date`,
`weekly` = ISO-Woche (Montag–Sonntag) von `p_date`. Reihenfolge: Schritte absteigend, dann wer den Wert zuerst hatte
(`steps_changed_at`, Teilnehmer ohne Tageswert zuletzt), dann `public_id`. Stichtag wie bei den Leaderboards nur von
heute (UTC) − 14 bis + 1. Höchstens 201 Einträge (ich + 200 Freunde). `steps_today`/`steps_week` im Freundesprofil:
Tag `p_date` bzw. Summe der ISO-Woche von `p_date`.

Annehmen ist idempotent: Ein wiederholtes `p_accept = true` auf eine bereits angenommene Anfrage liefert erneut
`accepted`, solange die Freundschaft besteht; parallele Aufrufe erzeugen nie doppelte Zeilen.

### Gruppen

Nichtmitglieder erhalten für fremde Gruppen immer `not_found`; Mitglieder ohne Eigentümerrechte bei
Eigentümer-Aktionen `not_allowed`.

| Funktion | Antwort | Fehler |
|---|---|---|
| `social_create_group(p_name text, p_description text, p_kind text, p_daily_goal integer, p_time_zone text)` | summary (Ersteller ist `owner`); `p_time_zone` null → `Europe/Berlin`, sonst ein Name aus `pg_timezone_names`; `p_description` null → leer | `invalid_name`, `invalid_description`, `invalid_kind`, `invalid_goal`, `invalid_time_zone`, `limit_reached`, `rate_limited` |
| `social_update_group(p_group_id uuid, p_name text, p_description text, p_kind text)` | summary; `null` lässt den jeweiligen Wert unverändert | `not_found`, `not_allowed`, `invalid_name`, `invalid_description`, `invalid_kind` |
| `social_set_group_goal(p_group_id uuid, p_daily_goal integer)` | summary; gilt ab dem nächsten Gruppentag | `not_found`, `not_allowed`, `invalid_goal` |
| `social_my_groups()` | `[summary]`, nach Name (ohne Groß-/Kleinschreibung) | – |
| `social_group(p_group_id uuid)` | summary | `not_found` |
| `social_group_ranking(p_group_id uuid, p_period text)` | `{"total_participants","group_today","daily_goal","entries":[{"rank","public_user_id","username","display_name","competition_steps","is_current_user","role","reached_goal_today"}]}` | `not_found`, `invalid_period` |
| `social_group_days(p_group_id uuid, p_days integer = 14)` | `[{"day","member_count","required_count","reached_count","daily_goal","reached","is_today"}]`, neueste zuerst; `p_days` wird auf 1–60 begrenzt, nie vor dem Erstellungstag | `not_found` |
| `social_regenerate_invite_code(p_group_id uuid)` | summary mit neuem Code | `not_found`, `not_allowed` |
| `social_join_group(p_invite_code text)` | summary; bereits Mitglied → summary (idempotent); eine offene Einladung dieser Gruppe an mich wird `accepted` | `invalid_invite_code` (siehe unten), `limit_reached`, `rate_limited` |
| `social_leave_group(p_group_id uuid)` | – | `not_found` |
| `social_remove_group_member(p_group_id uuid, p_public_id uuid)` | – | `not_found` (auch: Person ist kein Mitglied), `not_allowed` (kein Eigentümer oder sich selbst) |
| `social_delete_group(p_group_id uuid)` | – | `not_found`, `not_allowed` |
| `social_invite_to_group(p_group_id uuid, p_public_id uuid)` | `{"status","invitation_id"}`; `invited`, `already_member` (`invitation_id` null; auch für sich selbst), `already_invited` (ID der offenen Einladung) | `not_found` (keine Gruppe/kein Mitglied, Person unbekannt oder nicht mit mir befreundet), `limit_reached` (Gruppe voll), `rate_limited` |
| `social_group_invitations()` | `[{"invitation_id","group_id","group_name","group_kind","member_count","inviter_username","inviter_display_name","created_at"}]`, offene eingehende Einladungen, neueste zuerst | – |
| `social_group_outgoing_invitations(p_group_id uuid)` | `[{"invitation_id","public_id","username","display_name","created_at"}]`; Eigentümer sieht alle offenen Einladungen der Gruppe, Mitglieder nur ihre eigenen | `not_found` |
| `social_respond_group_invitation(p_invitation_id uuid, p_accept boolean)` | `{"status":"accepted"\|"declined","group": summary oder null}` | `not_found` (nicht Empfänger, nicht offen, `p_accept` null), `limit_reached` |
| `social_cancel_group_invitation(p_invitation_id uuid)` | – | `not_found` (weder einladende Person noch Eigentümer, oder nicht offen) |

Gruppenranking: alle aktuellen Mitglieder (ohne Tageswert 0); `daily` = heutiger Gruppentag, `weekly` = ISO-Woche,
die den heutigen Gruppentag enthält. `reached_goal_today` = Schritte heute ≥ heutiges Ziel (auch bei `weekly`).
Reihenfolge wie beim Freundesranking.

**Eigentümerwechsel und leere Gruppen** (Trigger auf `group_members`, greift auch beim Löschen eines Profils):
Verlässt der Eigentümer die Gruppe, wird das am längsten beigetretene verbleibende Mitglied Eigentümer (bei
Gleichstand entscheidet die interne ID). Verlässt die letzte Person die Gruppe, wird sie samt Historie gelöscht.
Wird die Gruppe selbst gelöscht, laufen die Trigger ins Leere und scheitern nicht.

### `invalid_invite_code`: HTTP 400 ohne Exception

Jeder Beitrittsversuch zählt gegen das Versuchslimit – auch mit falschem Code, sonst ließen sich Codes durchprobieren.
Eine Exception würde aber die ganze Transaktion samt gezähltem Versuch zurückrollen. Deshalb wirft
`social_join_group` bei unbekanntem Code **keine** Exception, sondern setzt `response.status = 400` und liefert:

```json
{"code": "P0001", "message": "invalid_invite_code", "details": null, "hint": null}
```

Über die Data API ist das nicht von einer geworfenen Exception zu unterscheiden (HTTP 400, gleiches JSON wie bei
`raise exception`; supabase-swift wirft einen `PostgrestError` mit dieser `message`), der Versuch bleibt aber
gespeichert. Nur wer die Funktion direkt in SQL aufruft (pgTAP), sieht ein normales Ergebnis.

### Spitznamen (Migration 20261023100000)

| Funktion | Antwort | Fehler |
|---|---|---|
| `social_set_friend_nickname(p_public_id uuid, p_nickname text)` | Profil (`public_id`, `username`, `display_name`, `avatar_path`, `nickname`); leer/`null` entfernt | `not_found` (kein aktueller Freund, ich selbst), `invalid_nickname`, `rate_limited` (30 je 10 min) |

Spitznamen sind privat je Person: Gespeichert in `friend_nicknames` (RLS ohne Policies), ausgegeben nur an die
Person, die sie vergeben hat (`nickname` in allen Profilausgaben, Rankings und Einladungen, siehe
[BACKEND.md](BACKEND.md)). Sie enden mit der Freundschaft (Entfernen, Blockieren, Konto löschen). App:
`SocialRepository.setFriendNickname(publicID:nickname:)`, `NicknameRules`, `SocialProfile.shownName`,
`LeaderboardEntry.shownName`, `GroupInvitation.inviterShownName`.

### Gruppenkalender (Migration 20261023100200)

| Funktion | Antwort | Fehler |
|---|---|---|
| `social_group_calendar(p_group_id uuid, p_first_day date, p_last_day date)` | `{"group_id","time_zone","group_today","first_group_day","days":[{"day","daily_goal","member_count","required_count","reached_count","secured","has_data","is_today","ranking":[{Profil…,"rank","competition_steps","reached","is_current_user"}]}]}`, Tage aufsteigend | `not_found` (kein aktuelles Mitglied), `invalid_date` (fehlend, Ende vor Anfang, mehr als 42 Tage) |

- Der Zeitraum wird auf Gründungstag … heute (Gruppenzeitzone) begrenzt; davor/danach fehlen Tage. Die App leitet
  daraus ehrliche Zustände ab: `GroupCalendar.state(of:)` → `beforeGroup`, `future`, `notLoaded`, `noData`,
  `secured`, `open` (heute, noch nicht gesichert), `missed`.
- Kennzahlen kommen unverändert aus `private.group_day_stats` – dieselbe Berechnung wie Streak, `social_group` und
  `social_group_days` (Mitglieder laut Mitgliedschaftsperioden zum Tagesende, historisches Ziel, ⌈n/3⌉).
- Die Tagesrangliste enthält alle Mitglieder dieses Tages (auch später Ausgetretene) mit den Wettbewerbsschritten
  des Tages; Reihenfolge wie alle Social-Rankings (`private.social_step_ranking`: Schritte, wer zuerst,
  `public_id` – Plätze eindeutig). `best` = Platz 1 mit mehr als 0 Schritten (Indikator in der Kalenderzelle).
- Blockierungen: Aktuelle Mitglieder stehen wie im Gruppenranking immer in der Liste. **Ehemalige Mitglieder, die
  mich blockiert haben, sind anonymisiert:** Zeile mit Platz, Schritten und `reached`, aber alle Profilfelder
  `null` (wie `can_view_profile`, das ihr Profil für mich verbirgt). So bleiben `member_count` = Zeilenzahl und
  `reached_count` = Zeilen mit `reached`. App: `GroupCalendarEntry.profile == nil` (`isHidden`), Anzeige über
  `shownName` („Ehemaliges Mitglied“), ohne Bild und ohne Profil-Link; `id` ist der Platz.
- Mitglieder sehen alle Tage ab der Gründung, auch vor ihrem eigenen Beitritt (Gruppenhistorie, wie Streak und
  `social_group_days`).
- App: `SocialRepository.groupCalendar(groupID:from:to:)` → `GroupCalendar`; Monatsansicht mit Montag als
  Wochenbeginn über `GroupCalendarRules.monthGrid(containing:calendar:)` (4–6 Wochen, passt in einen Abruf).

### Social-Profil 2.0 (Migration 20261030100000, Auftrag 6)

Optionale Angaben im eigenen Profil (alle freiwillig, ältere Profile zeigen einfach nichts davon):

| Angabe | Regeln | Wo geprüft |
|---|---|---|
| Banner | Querformat 3:1 (Zuschnitt in der App), JPEG ≤ 5 MB, längste Kante ≤ 1500 px, Ordner `<public_id>/` im Bucket `avatars`; ohne Banner ein neutraler Pace-Verlauf | App (`BannerImageProcessing`), Trigger `private.validate_profile_banner`, Lese-Policy über `pace_access.can_read_avatar` |
| Bio | 1–160 Zeichen, höchstens 4 Zeilen, Emojis erlaubt, keine Steuer-/unsichtbaren Zeichen, kein HTML (Anzeige als reiner Text) | App (`ProfileBioRules`, Zähler), Prüfregel `profiles_bio_valid` |
| Interessen | bis zu 5 aus einem festen Katalog mit stabilen IDs (`walking`, `running`, `hiking`, `fitness`, `cycling`, `football`, `outdoor`, `everyday_movement`, `challenges`, `wellbeing`), Titel DE/EN/RU | App (`ProfileInterest`), Prüfregel + Trigger |
| Auszeichnungen | nur auf Wunsch (Schalter, Standard aus); nur echte Werte aus Serie und Bestwert (`streak_7/30/100/365`, `best_day_10k/20k/30k`, je Art die höchste Stufe) – keine genauen Schrittzahlen | App (`ProfileAchievement.earned`), Prüfregel + Trigger |

`social_profile_details(p_public_id)` liefert diese Angaben mit derselben Sichtbarkeit wie `social_public_profile`
(`not_found`). Bei Blockierung (beide Richtungen) bleiben sie leer, Auszeichnungen fremder Profile kommen nur bei
Freigabe. Gespeichert wird per `update` auf die fünf Spalten des eigenen Profils (Spaltenrecht). Ohne Migration zeigt
die App „noch nicht eingerichtet“ und Profile wie bisher. Alle Aktionen auf fremden Profilen (Anfrage, Annehmen,
Nachricht, Spitzname, Teilen, Blockieren, Melden) bleiben unverändert.

### Pace-Bot (Auftrag 6)

Fester Eintrag oben in der Chatliste. **Keine KI, kein Server, keine Kosten:** 15 vorgefertigte Fragen und Antworten
(DE/EN/RU, `PaceHelpTopic`), optional einfache Stichwortsuche; ist sie nicht eindeutig, antwortet der Bot ehrlich
„Dazu habe ich leider noch keine passende Antwort …“ und bietet Hilfe an. Der Verlauf liegt nur auf dem Gerät
(UserDefaults `pace.helpBot.history`, höchstens 60 Nachrichten, zurücksetzbar) – keine Supabase-Tabelle, kein
Realtime, keine Ungelesen-Zähler. „Hilfe kontaktieren“ öffnet die bestehende Rückmeldung „Problem melden“; eine
Support-E-Mail erscheint nur, wenn `PACE_SUPPORT_EMAIL` in der lokalen `Config/Pace.xcconfig` gesetzt ist (es gibt
keine offizielle Adresse im Repository, es wird keine erfunden). Die Mail-Vorlage enthält keine Kennungen oder
Gesundheitsdaten und wird nie automatisch gesendet.

## Fehler

Fehler sind stabile Tokens als Meldung; die App prüft `message.contains(token)`. errcode ist `P0001`, nur
`not_authenticated` hat `42501`.

| Token | Bedeutung |
|---|---|
| `not_authenticated` | keine Nutzer-ID im JWT (42501) |
| `profile_required` | angemeldet, aber noch kein Profil |
| `not_found` | Ziel existiert nicht **oder** ist nicht sichtbar (nie Existenz verraten) |
| `not_allowed` | Mitglied, aber Aktion nur für den Eigentümer; Eigentümer entfernt sich selbst |
| `invalid_name`, `invalid_description`, `invalid_kind`, `invalid_goal`, `invalid_time_zone` | ungültige Gruppenangaben |
| `invalid_period` | Zeitraum nicht `daily`/`weekly` |
| `invalid_date` | Stichtag fehlt oder liegt außerhalb von heute (UTC) − 14 bis + 1 |
| `self_request` | Freundschaftsanfrage an sich selbst |
| `rate_limited` | Rate Limit erreicht (siehe unten) |
| `cooldown` | erneute Anfrage innerhalb von 7 Tagen nach Ablehnung |
| `limit_reached` | Mengenlimit erreicht (siehe unten) |
| `invalid_invite_code` | unbekannter Einladungscode (HTTP 400, siehe oben) |
| `invalid_nickname` | Spitzname zu lang (über 30 Zeichen) oder mit Steuer-/Formatzeichen |
| `pin_limit_reached` | bereits 5 Pins in der Unterhaltung (`SocialError.pinLimitReached`) |
| `favorite_limit_reached` | bereits 1000 eigene Favoriten (`SocialError.favoriteLimitReached`) |

Ohne Anmeldung (nur Publishable Key, Rolle `anon`) antwortet PostgREST mit `42501 permission denied for function`.

## Limits und Missbrauchsschutz

| Aktion | Limit | Fehler |
|---|---|---|
| neue Freundschaftsanfragen | 20 je 24 h | `rate_limited` |
| offene ausgehende Freundschaftsanfragen | 50 | `limit_reached` |
| Freunde | 200, beim Annehmen bzw. Auto-Annehmen für beide Seiten geprüft | `limit_reached` |
| erneute Anfrage an dieselbe Person nach Ablehnung | 7 Tage Pause | `cooldown` |
| Profilsuchen (jede, auch ungültige und erfolglose) | 30 je 10 min | `rate_limited` |
| Mitglieder je Gruppe | 50 (Beitritt, Annehmen, Einladen) | `limit_reached` |
| Gruppenmitgliedschaften je Nutzer | 20 (Beitritt, Annehmen, Erstellen) | `limit_reached` |
| Gruppen als Eigentümer | 10 beim Erstellen (durch Eigentümerwechsel kann es mehr werden) | `limit_reached` |
| Gruppen erstellen | 5 je 24 h | `rate_limited` |
| neue Gruppeneinladungen | 30 je 24 h | `rate_limited` |
| Beitrittsversuche per Code (alle, auch falsche) | 20 je Stunde | `rate_limited` |

Rate Limits zählen nur, was committet wird: Bricht eine RPC mit einem Fehler ab, verfällt der gezählte Eintrag.
Bewusst gezählt werden deshalb auch erfolglose Suchen (Antwort `null`) und falsche Einladungscodes (siehe oben).
Der Codebereich hat 32⁸ ≈ 1,1 · 10¹² Möglichkeiten. Das Versuchslimit gilt je Konto; da anonyme Konten leicht
entstehen, begrenzt zusätzlich Supabase die anonymen Anmeldungen (standardmäßig 30 je Stunde und IP). Selbst mit
vielen Konten bleibt das Erraten eines Codes bei diesem Codebereich praktisch aussichtslos; wer einen Code für
weitergegeben hält, erzeugt einen neuen.

**Nebenläufigkeit:** Gruppenzeilen werden vor Mitgliedschaftsänderungen mit `select … for update` gesperrt, Nutzer
(Freundschafts- und Mitgliedschaftslimits) und Rate Limits mit Transaktions-Advisory-Locks – immer in der
Reihenfolge Gruppe → Nutzer → Rate Limit, beim Löschen eines Profils werden seine Gruppen vorab gesperrt. Doppeltes
oder paralleles Annehmen, gleichzeitige Gegenanfragen, doppelte oder parallele Beitritte an der Mitgliedergrenze und
parallele Einladungen erzeugen dadurch weder doppelte Zeilen noch überschrittene Limits noch `unique_violation`.
Einladen sperrt beide Personen wie das Beenden einer Freundschaft – eine gleichzeitig beendete Freundschaft
hinterlässt deshalb keine offene Einladung.

## Nicht umgesetzt

- **Gruppenchat, Blockieren, Melden, Gruppenbild, Privatsphäre:** Die App nutzt dafür die Vertragsmethoden
  (`ChatRepository`, `block`/`unblock`/`blockedUsers`, `report`, `setGroupImage`, `updateGroupDetails`). Ob der
  Server sie schon anbietet, entscheidet die jeweilige Migration; bis dahin antworten sie mit `unavailable`, und die
  App zeigt „Diese Funktion ist auf dem Server noch nicht eingerichtet.“ (siehe BACKEND.md und CHAT.md). Wer aus
  einer Gruppe entfernt wurde, kann mit dem bekannten Code wieder beitreten, bis der Eigentümer einen neuen Code
  erzeugt. Abgelehnte Personen können nach 7 Tagen erneut anfragen.
- **Benachrichtigungen** (Push) zu Anfragen, Einladungen und Nachrichten – die Social-Einstellungen sagen das offen.
- **Änderung der Gruppenzeitzone** nach dem Erstellen.

## Grenzen

- **Nicht vollständig manipulationssicher.** Die Schrittzahlen kommen vom Gerät (HealthKit) und werden nur auf
  0 … 200 000 und das Sync-Fenster begrenzt. Wer seinen Client verändert, kann innerhalb dieser Grenzen falsche Werte
  senden – das betrifft Freundes- und Gruppenrankings ebenso wie die Gruppen-Streak.
- Der Gruppentag ist der Kalendertag in der Gruppenzeitzone, die Schritte stammen aber vom lokalen Kalendertag des
  Geräts. Mitglieder in anderen Zeitzonen tragen ihren eigenen Kalendertag gleichen Datums bei. Für Mitglieder
  westlich der Gruppenzeitzone läuft ihr Tag noch, wenn der Gruppentag schon vorbei ist: Der gestrige Gruppentag
  kann dann zunächst als nicht erreicht gelten und nach ihrer Synchronisation doch noch erreicht werden – die
  Streak wird bei jedem Lesen neu berechnet und korrigiert sich damit von selbst.
- Die Streak wird bei jedem Lesen über bis zu 730 Tage neu berechnet (Messwerte oben). Bei sehr vielen alten,
  großen Gruppen wären materialisierte Tageswerte der nächste Schritt.

## Tests

```sh
supabase test db   # u. a. 06_social_friends, 07_social_groups, 08_social_group_streak
```

- **06** – Struktur (RLS auf allen Social-Tabellen, keine Policies, keine Tabellenrechte, alle 26 RPCs `security
  definer` mit leerem `search_path` und Kommentar, nicht für `anon`, private Helfer gesperrt), Anmeldung/Profil,
  Profilsuche, Anfragen (senden, annehmen idempotent, ablehnen, zurückziehen, Gegenanfrage, Cooldown, Sichtbarkeit),
  Entfernen, alle Freundes-Limits, Freundesranking (0-Werte, Gleichstand, Woche, Datumsfenster), Freundesprofil.
- **07** – Gruppen erstellen (Validierung), Beitritt per Code (Normalisierung, falscher Code mit HTTP 400,
  Versuchslimit), Nichtmitglieder (`not_found`), Mitglieder (`not_allowed`), Ändern, Ziel, Code, Ranking,
  Einladungen (auch Rückzug bei Austritt bzw. Entfernen der einladenden Person), Eigentümerwechsel, Entfernen,
  letzte Person, Profillöschung, Löschen, alle Gruppen-Limits.
- **14** – Spitznamen: Rechte, Validierung, Ausgabe an allen Stellen, Privatsphäre (fremde Spitznamen nie
  sichtbar, auch nicht im Meldungs-Schnappschuss), Rate Limit, Aufräumen bei Ende der Freundschaft, Blockieren und
  Kontolöschung.
- **16** – Gruppenkalender: Rechte, Zeitraumgrenzen (42 Tage, Gründung … heute), historische Mitglieder und Ziele,
  ⌈n/3⌉, Gleichstände, leere Tage, Spitznamen, Blockierte (aktuelle sichtbar, Ex-Mitglieder, die mich blockiert
  haben, anonymisiert), Tage vor dem eigenen Beitritt, Übereinstimmung mit `social_group_days`.
- **08** – Rundung 1/2/3/4/6/10/12/20, laufender Tag, Lücke, `best_streak`, Zieländerung ab morgen,
  Beitritt/Austritt an einem Tag, überlappende Perioden, verspätete Synchronisation, Tage ohne Mitglieder,
  Zeitzonen (Kiritimati/Pago Pago) und Sommer-/Winterzeit (29.03.2026, 26.10.2025).
