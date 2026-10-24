# Auftrag 3 (23.10.2026) – Abschlussbericht

Branch `claude/gallant-brahmagupta-hvvp13`, Ausgangsstand b3518ce. Alle Änderungen sind Weiterentwicklungen des
bestehenden Projekts „Pace“; nichts wurde neu aufgebaut. **Im produktiven Supabase-Projekt wurde nichts verändert.**
Signing, Bundle Identifier, Entitlements und die lokale Konfiguration (`Config/Pace.xcconfig`, von Git ausgeschlossen)
sind unverändert.

„Gerätetest offen“ heißt: Die Logik ist automatisiert getestet und die Oberfläche in Simulator-Snapshots geprüft, auf
einem echten iPhone aber noch nicht ausprobiert (Anleitung: [IPHONE_TEST.md](IPHONE_TEST.md), 22 Testfälle).

## 24.1 Umsetzung

| Bereich | Stand | Hinweise |
|---|---|---|
| **P0** Chat-Layout privat und Gruppe (Kopf oben links, Eingabe immer erreichbar, Tastatur, Scrollen) | vollständig | Fester Kopf, Verlauf beginnt oben bzw. öffnet am Ende, Eingabe direkt über Tastatur/Tab-Leiste; im echten Fenster gerendert. Gerätetest offen |
| **P0** Tab-Leiste verdeckt nichts | vollständig | Inhalt und Leiste untereinander; bei Tastatur ausgeblendet; „Ende der Seite“ im Fenster geprüft |
| **P0** Widget-Verschieben am Griff mit Auto-Scroll | vollständig | Eigene Geste statt System-Drag & Drop, Rand-Scrollen bis 1.150 pt/s; Rechenregeln getestet, Geste Gerätetest offen |
| **P1** Live-Schritte (Core Motion + HealthKit) | vollständig | `LiveStepEstimator` verhindert Doppelzählung; Rankings/Sync/Serie nur HealthKit. Gerätetest offen |
| **P1** Kalorien | vollständig | Drei Zustände (gemessen, gemessene 0, „Nicht verfügbar“), keine erfundenen Nullen |
| **P1** Mehrere Tagesziel-Erinnerungen | vollständig | Bis 6 Uhrzeiten, situative Texte, keine veralteten Restschritte, „Geschafft!“ einmal am Tag; iOS-Grenzen erklärt |
| **P1** Chat-Benachrichtigungen | teilweise | Lokale Hinweise auf neue Nachrichten, solange Pace geöffnet ist (mit Schalter): vollständig. **Push bei geschlossener App: nicht umgesetzt** – braucht APNs (Push-Capability, Server-Versand), mit kostenlosem Personal Team nicht möglich; ehrlich so erklärt |
| **P1** Social-Kopf (Anfragen-Button mit Badge), Top-Freunde nur Freunde/kompakt, Chats höher | vollständig | |
| **P1** Private Spitznamen (überall) | vollständig – aktiv nach Migration | Bearbeiten im Freundesprofil, Anzeige in allen Listen, Rankings, Chats, Gruppen, Hinweisen; serverseitig gespeichert, nur für dich sichtbar. Bis zum Einspielen der Migration „auf dem Server noch nicht eingerichtet“ |
| **P1** Wischen zwischen den 4 Haupttabs | vollständig | Fingergeführt, Tab-Fläche gleitet mit, Abbruch durch Zurückziehen, nur auf Startseiten; Richtung laut Vorgabe (Finger nach rechts → nächster Tab). Startseite folgt dem gewählten Tab (auch beim Kaltstart über Links). Gerätetest offen |
| **P1** Sprachnachrichten | vollständig – Senden aktiv nach Migration | Halten, nach oben sperren, nach links verwerfen, Vorschau, Senden erst nach Bestätigung, Wiedergabe mit Springen, Unterbrechungen. Aufnahme/Wiedergabe mit AVFoundation: Gerätetest offen |
| **P1** Nachrichtenaktionen (Antworten, Kopieren, Bearbeiten, Favoriten, Anpinnen) | vollständig – aktiv nach Migration | Kontextmenü nur mit möglichen Aktionen, Sprung mit Hervorhebung, „Bearbeitet“, private Favoritenliste, Pin-Hinweis; Rechte serverseitig |
| **P1** Gruppenkalender mit Tagesranglisten | vollständig – aktiv nach Migration | Historisch korrekt (Mitglieder/Ziel des Tages, ⌈n/3⌉), echte Werte, eigene Zeile hervorgehoben, leere/zukünftige Tage ehrlich |
| **P2** Tab-Leiste kompakter | vollständig | |
| **P2** Scrollindikatoren aus | vollständig | |
| **P2** Ausgewählter Kalendertag im Dark Mode | vollständig | Akzentrahmen außen – auch um gefüllte Tage sichtbar, Auswahl ≠ Ziel erreicht |
| **P2** Aktiven Tab erneut tippen → nach oben | vollständig | Auf Unterseiten zurück zur Startseite |
| **P2** Feinschliff (Abstände, Safe Areas, keine Worttrennung, kleine iPhones, DE/EN/RU) | teilweise | In Snapshots (393 pt, Hell/Dunkel, DE/EN/RU) geprüft und Abschneidungen behoben; kleine iPhones (SE) und große Schriftgrößen nur stichprobenhaft |

Zusätzlich behoben: alle Befunde zweier unabhängiger Prüfungen (Backend: 1 mittel, 6 leicht; App: 1 schwer, 7 mittel,
mehrere leicht – u. a. verlorene 5-Minuten-Aufnahme, Lücke im Chatverlauf, Chat galt nach Tab-Wechsel als offen,
veraltete Restschritte in Erinnerungen). Bewusst offen (leicht): siehe 24.5.

## 24.2 Backend

Drei neue, additive Migrationen – **nur im Repository, nicht produktiv eingespielt** (Freigabe nötig, Ablauf in
[SUPABASE_ROLLOUT.md](SUPABASE_ROLLOUT.md), Abschnitt „Auftrag 3“). Die sechs bereits produktiven Migrationen
(20261018100000 … 20261019100400) sind unverändert.

| Migration | Inhalt |
|---|---|
| `20261023100000_friend_nicknames.sql` | **Tabelle** `friend_nicknames` (RLS an, keine Client-Policies); **RPC** `social_set_friend_nickname`; Hilfsfunktionen `private.friend_nickname`, Aufräumen bei Ende der Freundschaft/Blockieren; ersetzte Funktionen (1:1 plus Spitzname): `profile_json`, `social_friend_ranking`, `social_group_ranking`, `leaderboard_page`, `leaderboard_neighborhood`, `social_group_invitations`, `account_export`, `social_report` (Meldung ohne privaten Spitznamen) |
| `20261023100100_chat_message_actions.sql` | **Spalten** `chat_messages.reply_to_id`, `edited_at`, `media_duration_ms`, Art `voice` (Constraints); **Tabellen** `chat_message_favorites`, `chat_message_pins` (RLS an, keine Client-Policies); **RPCs** `chat_edit_message`, `chat_set_favorite`, `chat_favorites`, `chat_set_pinned`, `chat_pins`, `chat_send` (mit Antwort/Dauer, alte Aufrufe bleiben gültig); Echtzeit-Hinweise „bearbeitet“/„Pins“; **Storage**: Bucket `chat-media` erlaubt zusätzlich `audio/mp4`, `audio/x-m4a`, `audio/aac` (Vereinigung, nichts überschrieben); SELECT-Policy `pace_chat_media_select` ersetzt: lesen nur Uploader oder wer die nicht gelöschte Nachricht sehen darf; Index `chat_messages_media_path_idx` |
| `20261023100200_group_calendar.sql` | **RPC** `social_group_calendar` (Monatsraster ≤ 42 Tage, nur Mitglieder, historische Mitglieder und Ziele, ehemalige Mitglieder, die dich blockiert haben, ohne Profil) |

Alle neuen `security definer`-Funktionen: `search_path = ''`, `revoke` von `public`/`anon`, `grant` nur an
`authenticated`, Rate-Limits für Favoriten/Pins. **Noch erforderlich in Produktion:** die drei Migrationen nach
ausdrücklicher Freigabe einspielen (vorher Sicherung; der neue Index sperrt Schreibzugriffe auf `chat_messages` kurz).
Ältere App-Versionen zeigen Sprachnachrichten als leere Blase – vor der Nutzung das App-Update installieren.

## 24.3 Berechtigungen

| Neu | Wo | Signing/Provisioning |
|---|---|---|
| Bewegung & Fitness (`NSMotionUsageDescription`) | `Config/Info.plist`, DE/EN/RU in `InfoPlist.xcstrings` | keine Änderung (keine Capability) |
| Mikrofon (`NSMicrophoneUsageDescription`) | `Config/Info.plist`, DE/EN/RU | keine Änderung (keine Capability) |
| Lokale Mitteilungen | bestehende Abfrage | keine Änderung |

Nicht hinzugefügt: Push Notifications (APNs – bräuchte Capability, Zertifikat bzw. Schlüssel und kostenpflichtiges
Developer-Programm) und HealthKit-Hintergrundzustellung (eigene Entitlement-Änderung). `project.pbxproj` und
Entitlements sind unverändert; die App installiert sich über die vorhandene Version.

## 24.4 Tests

| Prüfung | Ergebnis |
|---|---|
| Swift-Tests Linux (PaceCore, ViewModels) | 728 bestanden, 0 fehlgeschlagen |
| iOS-CI (Build ohne Warnungen, alle Tests im Simulator, Snapshots) | grün; Stand ea87234: rund 890 Tests bestanden, 0 fehlgeschlagen; Endstand siehe 24.6 |
| Backend-CI (pgTAP, Lint, Advisors, Integrationstests) | grün |
| Lokale Backend-Prüfung (Docker-Supabase) | 965 pgTAP-Tests in 16 Dateien, Lint ohne Fehler, Advisors ohne Befund, Realtime-Skript bestanden, 128 Swift-Backend-Tests |
| Snapshots | 260 Bilder (Hell/Dunkel, Hauptscreens DE/EN/RU) als CI-Artefakt; gesichtet u. a. Chat-Aktionen, Gruppenkalender, Spitzname, Kalender-Auswahl, Fenster-Layouts (Chat, Home-Ende, Anpassen, Pager halb) |
| Gerätetests | **offen** – alle 22 Testfälle in [IPHONE_TEST.md](IPHONE_TEST.md); insbesondere Live-Schritte, Aufnahme/Wiedergabe, Gesten (Wischen, Widget-Ziehen, Mikrofon), Haptik, Mitteilungen, Echtzeit zwischen zwei Geräten |

## 24.5 Bekannte Grenzen

- HealthKit aktualisiert sich nicht sekündlich (iOS schreibt gebündelt). Die Live-Anzeige über Core Motion ist nur
  Anzeige, solange Pace offen ist; sie erzeugt keine Wettbewerbsschritte und zählt nicht doppelt.
- Erinnerungen werden im Voraus geplant: Pace kann Apple Health nicht direkt vor der Zustellung lesen. Ohne frischen
  Stand (≤ 90 Minuten) gibt es einen Text ohne Zahl; ein erreichtes Ziel wirkt erst, wenn Pace danach offen war.
- Hinweise auf neue Chatnachrichten nur bei geöffneter App; echtes Push-Messaging braucht APNs.
- Neue produktive Datenbankmigrationen brauchen deine Freigabe; bis dahin zeigen Spitznamen, Nachrichtenaktionen,
  Sprachnachrichten-Versand und Gruppenkalender „noch nicht eingerichtet“.
- Leicht, bewusst offen: Antwort auf eine eigene, nicht geladene Nachricht zeigt den eigenen Namen statt „Du“;
  Rankings → Freunde zeigt einen neuen Spitznamen erst nach dem nächsten Laden; `pinnedBy` sichtbarer Pins kann eine
  Person zeigen, die du blockiert hast.

## 24.6 GitHub

- Branch `claude/gallant-brahmagupta-hvvp13`, alles gepusht, keine offenen Änderungen.
- Letzter Code-Stand und CI-Ergebnis: siehe Abschlussnachricht (CI läuft nach jedem Push; iOS und Backend).

## 24.7 iPhone-Installation

Kurz (ausführlich in [IPHONE_TEST.md](IPHONE_TEST.md)): Im Terminal im Pace-Ordner `git fetch origin`,
`git checkout claude/gallant-brahmagupta-hvvp13`, `git pull origin claude/gallant-brahmagupta-hvvp13`; `Pace.xcodeproj`
öffnen, iPhone oben auswählen, ▶ drücken. Signing, Bundle Identifier und deine `Config/Pace.xcconfig` bleiben, App-Daten
und Einstellungen bleiben erhalten. Beim ersten Start fragt iOS nach „Bewegung & Fitness“, beim ersten Halten des
Mikrofons nach dem Mikrofon.
