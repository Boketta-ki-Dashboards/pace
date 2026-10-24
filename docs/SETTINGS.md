# Profil und Einstellungen

Pace hat keinen eigenen Einstellungen-Tab. Der Profil-Tab (`ProfileFeature`) enthält oben das Profil und darunter
die Einstellungen als Kategorien mit eigenen Unterseiten. Alle Unterseiten verwenden den einheitlichen Kopf
`PaceSubpageHeader` (Zurück → pace → Titel) mit `.paceSubpage()`; die Tab-Leiste bleibt sichtbar.

## Aufbau des Profil-Tabs

| Bereich | Inhalt | Speicherung |
|---|---|---|
| Kopf | Wortmarke + „Profil“ | – |
| Profilkarte | Profilbild, Anzeigename, @Benutzername, Teilen-Knopf (`pace://u/<name>`) | Server (`profiles`) |
| Deine Aktivität | Tagesziel, Serie und Rekord, Statistik (Tag · Woche · Monat) | nur Gerät |
| Deine Region | Gemeinde, Kreis, Bundesland, „Region ändern“ | Server (nur Gemeinde-ID) |
| Sichtbarkeit in Rankings | „In regionalen Rankings erscheinen“ | Server, serverseitig durchgesetzt |
| Darstellung | Automatisch · Hell · Dunkel, Zugang zum App-Icon | nur Gerät (`pace.preferences`) |
| Konto | Konto & Profil, Sprache | – |
| Privatsphäre & Mitteilungen | Privatsphäre, Social-Einstellungen, Mitteilungen | – |
| Daten & Hilfe | Datenschutz & Daten, Hilfe & Feedback, Rechtliches | – |
| Fußzeile | App-Version (`AppDependencies.appVersion`) | – |

Navigation: `ProfileRoute` (Wert-basiert) in `ProfileViewModel.path`. Von außen öffnet
`MainViewModel.openProfileSettings(_:)` eine Unterseite direkt (z. B. die Social-Einstellungen im Social-Tab →
Privatsphäre über `SocialViewModel.openPrivacySettings`).

## Unterseiten

### Konto & Profil (`AccountSettingsViewModel`, `NameEditViewModel`)
- **Namen ändern:** gleiche Regeln wie im Onboarding (`UsernameRules`, `DisplayNameRules`), Prüfung beim Tippen,
  Verfügbarkeit des Benutzernamens nach 400 ms Pause (`ProfileRepository.isUsernameAvailable`). Gesendet wird nur,
  was sich geändert hat (`ProfileStore.updateNames`); der Server entscheidet verbindlich (eindeutig ohne
  Groß-/Kleinschreibung). Alte Profil-Links mit dem früheren Benutzernamen funktionieren danach nicht mehr.
- **Profilbild:** Foto aus der Mediathek (`photosPicker`), mittig quadratisch zugeschnitten, höchstens
  1.024 × 1.024 Pixel, JPEG ≤ 5 MB (`AvatarImageProcessing`). Ablauf: Upload über `MediaRepository` (`.avatar`) →
  `ProfileStore.updateAvatar(path:)` → altes Bild löschen. Scheitert das Speichern im Profil, wird das neue Bild
  wieder gelöscht. „Entfernen“ setzt `avatar_path` auf `nil` und löscht die Datei. Ohne Medien-Backend ist die
  Auswahl ausgegraut und erklärt.
- **Profil teilen:** iOS-Teilen mit `PaceLink.profile(username:).url` und einem kurzen Text. „In Pace teilen“ gibt es
  im Profil-Tab nicht (keine Verbindung zu den Chats aus `ProfileFeature`); das Teilen in Chats bietet der Social-Tab.
- **Kontoinformationen:** Konto-Art (ohne Anmeldung, an dieses iPhone gebunden), „Dabei seit“, öffentliche ID klein.
- **Anmeldung & Sicherheit:** ehrlicher Hinweis, dass das Konto an dieses iPhone gebunden ist. Eine dauerhafte
  Anmeldung (z. B. „Mit Apple anmelden“) braucht eine zusätzliche Capability und wurde bewusst nicht eingebaut – die
  Seite zeigt sie als „In Vorbereitung“ ohne Knopf.

### Darstellung
- Automatisch / Hell / Dunkel über `AppSettings.appearance`; `RootView` setzt `.preferredColorScheme`. Wirkt sofort
  und bleibt nach dem Neustart erhalten. Pace ändert nie die Bildschirmhelligkeit des iPhones.
- App-Icon: Automatisch / Hell / Dunkel mit den vorhandenen Original-Icons (`AppIconSetting`). Unterstützt das Gerät
  keine alternativen Icons, ist die Auswahl ausgegraut und erklärt.

### Sprache
- „Wie iPhone“, Deutsch, English, Русский über `AppSettings.language`. Die Sprache wird sofort auf
  `PaceLocalization.shared` angewendet (alle Texte sind beobachtbar) und gespeichert. Zahlen und Datumsangaben folgen
  der Sprache (`paceFormatted`, `Date.FormatStyle.pace`); Systemsteuerelemente bekommen `\.locale` in `RootView`.
- „Wie iPhone“ wertet `Locale.preferredLanguages` aus (dazu gehört auch die in den iOS-Einstellungen nur für Pace
  gewählte Sprache); ohne Treffer Deutsch. `Config/Info.plist` enthält `CFBundleLocalizations` (de, en, ru), damit
  iOS die Sprachen anbietet. `Pace/Resources/InfoPlist.xcstrings` übersetzt die Health-Begründung.
- Nach einem Sprachwechsel wird die Tagesziel-Erinnerung neu geplant (Text in der neuen Sprache).

### Privatsphäre (`PrivacySettingsViewModel`, `BlockedUsersViewModel`)
- Regionale Rankings: derselbe Schalter wie auf der Profilseite (`profiles.regional_leaderboard_enabled`).
- **Auffindbarkeit** (`ProfileStore.setDiscoverable` → `ProfileRepository.updateDiscoverable`): Nicht auffindbare
  Profile fehlen in der Präfixsuche; über den exakten Benutzernamen (z. B. aus einem geteilten Link) bleibt man
  auffindbar. Durchgesetzt auf dem Server.
- „Wer was sieht“: Freunde und Gruppen sehen Namen, Profilbild und tägliche Wettbewerbsschritte; regionale Rankings
  nur mit Zustimmung; andere Gesundheitsdaten verlassen das iPhone nicht.
- **Blockierte Personen:** Liste über `SocialRepository.blockedUsers()`, „Aufheben“ über `unblock`.
- Anfragen und Einladungen: nur erklärt und mit dem Social-Tab verlinkt – es gibt keine Schalter ohne Server-Regel.

### Social-Einstellungen
Kleine Unterseite mit denselben Bausteinen und Daten wie „Privatsphäre“ (Anfragen & Einladungen, blockierte Personen,
Hinweis zu Chats und Chat-Mitteilungen, Weg zur Auffindbarkeit). Der Social-Tab hat zusätzlich eigene
Social-Einstellungen; beide nutzen dieselbe Server-Logik (`SocialRepository`), keine zweite Einstellung.

### Mitteilungen (`NotificationSettingsViewModel`)
- Status der iOS-Erlaubnis; „Mitteilungen erlauben“ (Abfrage) bzw. „iOS-Einstellungen öffnen“
  (`UIApplication.openNotificationSettingsURLString`). Beim Zurückkehren in die App wird der Status neu gelesen.
- **Tagesziel-Erinnerungen** (lokal, `UserNotificationScheduler`): an/aus und **bis zu 6 Uhrzeiten** (hinzufügen,
  ändern, entfernen; die letzte bleibt), gespeichert in `AppSettings.streakReminder` (`StreakReminderSettings.times`,
  zusätzlich `hour`/`minute` der ersten Uhrzeit, damit ältere Versionen lesen können; die frühere einzelne Uhrzeit wird
  übernommen). Die Profilzeile zeigt „Aus“, die Uhrzeit oder „3 Erinnerungen“.
- **Planung** (`GoalReminderPlanner`, PaceCore): 14 Tage im Voraus, bei vielen Uhrzeiten weniger (höchstens 60
  geplante Mitteilungen – iOS behält 64 je App). Texte passend zur Situation:
  - vor 11 Uhr: „Vergiss dein Tagesziel nicht!“ (ohne Zahl),
  - später mit den fehlenden Schritten („Dir fehlen noch 2.400 Schritte …“) – nur, wenn der bekannte Stand bei der
    Zustellung höchstens 90 Minuten alt ist, sonst ein allgemeiner Text ohne Zahl (nie eine veraltete Restzahl),
  - „Nur noch 700 Schritte!“, wenn höchstens max(500, Ziel/10) fehlen,
  - ist das Ziel heute erreicht, entfallen die heutigen Erinnerungen,
  - „Geschafft!“ höchstens einmal am Tag (`AppSettings.goalReachedNotifiedOn`) und nur, wenn Pace den Wechsel von
    offen zu erreicht selbst gesehen hat (kein „Geschafft!“ für einen beim Start schon erreichten Tag).
  Neu geplant wird beim Start, bei geänderten Uhrzeiten/Sprache, beim Erreichen des Ziels und bei neuen Schrittwerten
  aus Apple Health (gedrosselt auf höchstens alle 5 Minuten). Zeitzone und Sommerzeit: Uhrzeiten sind Ortszeit; eine
  in der Umstellungsnacht nicht existierende Uhrzeit wird an diesem Tag übersprungen.
  Grenzen (auch so in der App erklärt): iOS plant im Voraus, Pace kann Apple Health nicht unmittelbar vor der Zustellung
  lesen; ohne HealthKit-Hintergrundzustellung (eigene Capability, bewusst nicht ergänzt) wirkt ein erreichtes Ziel erst,
  wenn Pace danach geöffnet war. Mitteilungen erscheinen auch bei geöffneter App als Banner
  (`ForegroundNotificationPresenter`).
- **Chatnachrichten** – Schalter „Hinweis bei neuen Nachrichten“ (`AppSettings.chatMessageHints`, Standard an): Solange
  Pace geöffnet ist, meldet `ChatListViewModel.onIncomingMessage` neue Nachrichten anderer in einem nicht offenen Chat
  als lokalen Hinweis (Titel = Chatname bzw. eigener Spitzname, Text = Vorschau wie in der Chatliste; je Chat ersetzt
  ein neuer Hinweis den vorigen). Kein Hinweis beim ersten Laden, nach der Rückkehr aus dem Hintergrund (Abstand zum
  vorigen Stand > 2 Minuten), für eigene Nachrichten oder den offenen Chat.
- **Push-Mitteilungen bei geschlossener App** (Anfragen, Einladungen, Chat) bräuchten APNs mit Push-Capability und
  einen Server-Versand. Mit einem kostenlosen Personal Team ist das nicht möglich; es wird ehrlich erklärt und nicht als
  Schalter angeboten. Eine lokale Mitteilung wird nirgends als Push ausgegeben.

### Datenschutz & Daten (`DataPrivacyViewModel`)
- Erklärungen zu Gesundheitsdaten, Wettbewerbsschritten, Profil-/Gruppen-/Chatdaten und Aufbewahrung – sichtbar als
  „Entwurf – vom Betreiber zu prüfen“ gekennzeichnet.
- **Datenexport:** `AccountRepository.exportData()` (RPC `account_export`) plus lokale Daten
  (`LocalAccountDataStoring`: alle `UserDefaults`-Schlüssel mit Präfix `pace.` – Einstellungen, Tagesziel-Verlauf,
  Rekord, Home-Aufbau, Profil-Zwischenspeicher) → `AccountExport.document` → JSON-Datei
  `pace-export-JJJJ-MM-TT.json` → iOS-Teilen („In Dateien sichern“ möglich). Die Datei wird beim Verlassen der Seite
  gelöscht. Daten aus Apple Health speichert Pace nicht; sie sind deshalb nicht enthalten.
- **Konto löschen:** zweistufig – Unterseite mit allen Folgen, Benutzername eintippen, dann Bestätigungsdialog.
  Reihenfolge:
  1. `AccountRepository.ownMedia()` und jede Datei über `MediaRepository.delete` entfernen (fehlende Dateien werden
     übersprungen, ohne Bilder-Speicher entfällt der Schritt);
  2. `AccountRepository.deleteAccount()` (RPC `account_delete`);
  3. erst danach auf dem Gerät: geplante Erinnerungen entfernen, `AppSettings.reset()`, lokale Daten löschen,
     `AuthProviding.signOut()` (Schlüsselbund);
  4. `AppRouter` zeigt „Dein Konto wurde gelöscht“; „Neu beginnen“ startet mit einer neuen anonymen Sitzung im
     Onboarding.
  Schlägt Schritt 1 oder 2 fehl, bleibt auf dem iPhone alles erhalten und die Seite erklärt, dass das Konto weiter
  besteht.

### Hilfe & Feedback, Rechtliches
- Häufige Fragen (statisch, lokalisiert, nur zu vorhandenen Funktionen: `HelpContent.faq`).
- „Problem melden“ / „Feedback senden“ über `AccountRepository.submitFeedback` (RPC `submit_feedback`), 10 bis
  2.000 Zeichen, mit App-Version. Keine E-Mail-Adressen, keine erfundenen Empfänger; ohne Server ehrlich nicht
  verfügbar.
- Datenschutzerklärung, Impressum, Nutzungsbedingungen: Entwürfe bzw. „vom Betreiber zu ergänzen“ – ohne erfundene
  Adressen (`PrivacyContent`).

## App-Rahmen

- Deep Link `pace://u/<benutzername>`: siehe `docs/ARCHITECTURE.md` (App-Ablauf).
- Social-Tab zeigt die Zahl ungelesener Nachrichten (`PaceTabItem.badge`, Summe aus `ChatListViewModel.unreadCount`).
- Alle Texte des App-Rahmens (Startfehler, Status-Screens, Tab-Titel, App-Icon- und Profilfehler) gibt es auf
  Deutsch, Englisch und Russisch.

## Tests

- `ProfileFeatureTests`: Namen ändern (Regeln, Verfügbarkeit, Serverfehler), Profilbild (Upload, Aufräumen, Entfernen,
  ohne Backend), Teilen-Link, Kontoinfo, Auffindbarkeit, blockierte Personen, Mitteilungen (Erlaubnis, Planen,
  Abbrechen, Ziel erreicht, neuer Tag), Export, Konto löschen (Reihenfolge und Fehlerfälle), Feedback, Sprache und
  Darstellung, Navigation, Texte in Englisch und Russisch.
- `AppFeatureTests/AppRouterSettingsTests`: Deep Link vor und nach dem Start, ungültige Links, Privatsphäre aus dem
  Social-Tab, Erinnerung beim Start, Löschen → Hinweis → Onboarding mit neuer Identität, lokalisierte Startfehler.
- `PaceCoreTests/AccountDataTests`: Exportdatei, lokale Daten exportieren und löschen, Einstellungen speichern,
  anwenden und zurücksetzen.
- `PaceSnapshotTests/ProfileSnapshotTests`: Profil (DE/EN/RU), Konto & Profil, Darstellung, Sprache, Privatsphäre,
  Social-Einstellungen, Mitteilungen, Datenschutz & Daten, Konto löschen, Hilfe, Feedback, Datenschutzerklärung.

## Nur auf einem echten iPhone prüfbar

- Wechsel des App-Icons (iOS-Hinweis) und Darstellung des Share-Sheets.
- Mitteilungs-Erlaubnis, Zustellung der Erinnerung und Sprung in die iOS-Einstellungen.
- Öffnen eines `pace://`-Links aus Nachrichten/Safari (Kalt- und Warmstart).
- Foto-Auswahl, Zuschnitt und Upload des Profilbilds.
- Sprachwahl „Wie iPhone“ zusammen mit der App-Sprache in den iOS-Einstellungen.
