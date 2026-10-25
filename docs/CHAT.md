# Chats

Private Chats zwischen Freunden und Gruppenchats für Pace-Gruppen – im Social-Bereich, ohne eigenen Tab.
Gestaltung nach Referenzbild 5 (Chat) und Bild 9 (Chatliste auf der Social-Hauptseite).

Die App spricht ausschließlich über die Verträge `ChatRepository` und `MediaRepository`
(`Packages/PaceKit/Sources/PaceCore/Chat/Chat.swift`, `…/Media/Media.swift`). Zugriffsregeln, Rate Limits und
Validierung prüft der Server (siehe `docs/BACKEND.md` bzw. die Supabase-Dokumentation des Backend-Pakets); die App
zeigt Fehler ehrlich an und täuscht nichts vor.

## Dateien

| Datei (`Sources/SocialFeature/Chat/`) | Inhalt |
|---|---|
| `ChatListViewModel.swift` | `ChatTarget`, Chatliste: Laden, Filter, Suche, Ungelesen, Echtzeit/Polling, `chat(for:)`, `shareProfile(_:with:)` |
| `ChatViewModel.swift` | Ein Chat: Verlauf, Pagination, optimistisches Senden, Bilder/GIFs, Lesestand, Löschen, Melden, Blockieren |
| `ChatTimeline.swift` | `PendingChatMessage`, Tages-Trenner und Nachrichtenblöcke (`ChatTimeline.build`) |
| `ChatFormatting.swift` | Zeiten (heute/gestern/Wochentag/Datum), Vorschau der letzten Nachricht, Streak- und Mitgliedertexte |
| `ChatTexts.swift`, `ChatUIText.swift` | Fehler, Hinweise, Beschriftungen und VoiceOver-Texte in DE/EN/RU |
| `ChatMediaSupport.swift` | GIF-Erkennung (Dateisignatur), Größen- und Qualitätsregeln für Fotos |
| `ChatViews.swift` | Öffentliche Views `ChatListSection` und `ChatView` (Rahmen, Dialoge, Bildauswahl, Vollbild) |
| `ChatListViews.swift` | `ChatListContent`, Zeilen, Gruppen-Avatar |
| `ChatScreen.swift` | `ChatContent` (Kopf, Gruppen- bzw. Profilkopf, Zustände), Streak-Karte, Navigationslinks |
| `ChatMessageViews.swift` | Verlauf, Sprechblasen, Profilkarten, ausstehende und eingeklappte Nachrichten, Kontextmenüs |
| `ChatMediaViews.swift` | Bild-/GIF-Vorschau, animierte GIFs, Vollbild mit Zoom, Foto-Aufbereitung (JPEG) |
| `ChatInputBar.swift` | Eingabeleiste („+“, Textfeld, Mikrofon/Senden, Antwort-/Bearbeiten-Vorschau, Aufnahme-Geste) bzw. Hinweis, wenn nicht geschrieben werden kann |
| `ChatVoice.swift` | `ChatVoiceRecorder` (Aufnahme AAC/.m4a), `ChatVoicePlayer` (Wiedergabe), Sprachnachrichten-Blase, Aufnahme-Zeile |
| `ChatFavoritesView.swift` | Favoritenliste des Chats (Stern im Chat-Kopf) |

Alles ohne SwiftUI (ViewModels, Texte, Verlauf, Medienregeln) wird auf Linux gebaut und getestet.

## Chatliste (Bild 9)

- `SocialContent` zeichnet die Überschrift „Chats“ und bettet `ChatListSection(viewModel: social.chats, onOpen:)` ein.
- Filter Alle/Freunde/Gruppen (`PaceSegmentedControl`), Sortierung nach `updatedAt` (neueste zuerst),
  `unreadCount` als Summe über alle Unterhaltungen (`SocialViewModel` bzw. Tab-Badge können ihn anzeigen).
- Zeile: Profilbild bzw. Gruppenbild (ohne Bild: Gruppensymbol auf Mint), Name, letzte Nachricht („Foto“, „GIF“,
  „Profil geteilt“, in Gruppen „Name: Text“, eigene „Du: …“), Zeit relativ in der App-Sprache, Ungelesen-Badge,
  Pfeil. Zustände: Laden, leer (je Filter eigener Text), Fehler mit „Erneut versuchen“, nicht verfügbar.
- Aktualisierung: `observe()` läuft, solange die Liste sichtbar ist und die App aktiv ist
  (`.task(id: scenePhase == .active)`): Echtzeit über `conversationEvents()`, als Rückfall alle 25 s, und beim
  Zurückkehren in die App (älter als 20 s → neu laden). Gleichzeitige Ladeaufrufe werden gebündelt: nie zwei
  Abfragen parallel, höchstens eine frische direkt danach.
- Suche: `conversations(matching:)` (Name, Benutzername mit/ohne „@“, ohne Akzente). Die Social-Hauptseite nutzt
  derzeit `SocialViewModel.matchingConversations`.

## Chat (Bild 5)

- Kopf: `PaceSubpageHeader` („‹ Social“ → Wortmarke mit Info- und Einstellungen-Knopf → Titel).
  - Gruppe: Avatarreihe (höchstens 6 Mitglieder aus dem heutigen Gruppenranking, „+“ zum Einladen), „n Mitglieder“,
    Streak-Karte („12 Tage Streak“, Häkchen bei gesicherter Flamme, „Flamme gesichert“ bzw. „Noch 2 Ziele heute“).
    Info → Gruppendetails, Zahnrad → Gruppeneinstellungen, Avatare/„+“ → Mitglieder (dort Einladen), Streak-Karte →
    Gruppendetails.
  - Privatchat: Profil-Kopf (Profilbild, @Benutzername, „Profil ansehen“). Info → Profil, Zahnrad → Menü
    „Profil ansehen“, „Person melden“, „Person blockieren“.
- Verlauf: Tages-Trenner („Heute“, „Gestern“, Wochentag, Datum), Blöcke aufeinanderfolgender Nachrichten derselben
  Person (Name und Profilbild einmal oben, Uhrzeit einmal unten), fremde links (hellgrau), eigene rechts (mint,
  `selectionFill`). Bilder als abgerundete Vorschau (antippen → Vollbild mit Zoom und Schließen), GIFs animiert mit
  „GIF“-Kennzeichnung (bei „Bewegung reduzieren“ erst nach Antippen), geteilte Profile als Karte → Profil.
  Lesestatus-Haken gibt es nicht, weil der Vertrag keine Lesebestätigungen anderer liefert.
- Kontextmenü: Text kopieren; eigene Nachricht löschen (mit Rückfrage); fremde Nachricht melden (Grund wählen →
  `report(.message(id:))`), Profil ansehen, in Gruppen Person blockieren. Für VoiceOver gibt es die wichtigsten
  Aktionen zusätzlich als Bedienhilfen-Aktionen.
- Eingabeleiste: „+“ öffnet die Mediathek (Fotos und GIFs), mehrzeiliges Textfeld (höchstens
  `ChatRules.maximumTextLength` Zeichen; ab 90 % zeigt die Leiste die Restzeichen), Senden-Knopf (dunkelgrüner
  Kreis, deaktiviert ohne gültigen Text). Kann nicht geschrieben werden (`canSend == false`, Blockierung, kein
  Mitglied mehr), steht dort stattdessen eine Erklärung.

## Senden und Empfangen

- Eigene Nachrichten erscheinen sofort als `PendingChatMessage` mit Status „Wird hochgeladen …“, „Wird gesendet …“
  bzw. „Nicht gesendet“ (Grund, „Erneut senden“, „Verwerfen“). „Erneut senden“ nutzt dieselbe `clientID`; ein bereits
  hochgeladenes Bild wird nicht noch einmal hochgeladen.
- Keine Doppelanzeige: Server-Nachrichten werden nach `id` zusammengeführt; ausstehende Nachrichten verschwinden,
  sobald eine Server-Nachricht mit ihrer `clientID` da ist – egal ob über die Antwort des Sendens, ein
  Echtzeit-Ereignis oder ein Neuladen.
- Neueste Seite (`ChatRules.pageSize`) beim Öffnen; ältere beim Hochscrollen über `messages(before:limit:)`.
  Beim Aktualisieren ersetzt die neueste Seite den abgedeckten Zeitraum, sodass anderswo gelöschte Nachrichten
  verschwinden; bereits geladene ältere Seiten bleiben.
- Echtzeit über `messageEvents(in:)`, Polling-Rückfall alle 25 s, solange der Chat sichtbar und die App aktiv ist.
  Ohne Verbindung beim Öffnen versucht der Chat es im selben Takt erneut.
- `markRead(_:through:)` beim Öffnen und bei neuen Nachrichten – nur solange der Chat sichtbar ist; die Chatliste
  setzt den Zähler sofort zurück.
- Fehler bleiben sichtbar und erholbar: Laden (Karte mit „Erneut versuchen“), Aktualisieren (Hinweis über dem
  Verlauf), ältere Nachrichten („Ältere Nachrichten laden“), Senden/Hochladen (an der Nachricht).

## Anhangsmenü am „+“ (Auftrag 4)

Das „+“ öffnet ein natives Menü (`ChatInputBar` → `ChatAttachmentActions`): **Foto aus Mediathek** (wie bisher, auch
GIFs aus Fotos), **GIF suchen** (`GIFPickerSheet`) und **Profil teilen** (`ChatProfileShareSheet`). Videos werden
nicht angeboten – das Backend erlaubt in Chats nur Bilder, GIFs und Sprachnachrichten (eine Erweiterung bräuchte eine
neue Migration).

### GIF-Suche (GIPHY)

- Schnittstelle `GIFSearching` (PaceCore), Umsetzung `GIPHYSearchService` (PaceBackend), Zustand
  `GIFPickerViewModel` (SocialFeature). Verdrahtet über `AppDependencies.gifSearch` → `ChatListViewModel.gifSearch`.
- Schlüssel: `GIPHY_API_KEY` in `Config/Pace.xcconfig` (von Git ignoriert) → `PaceGIPHYAPIKey` in der Info.plist.
  `Config/Base.xcconfig` und `Pace.xcconfig.example` enthalten nur leere Werte. Ohne Schlüssel zeigt die Auswahl
  „nicht eingerichtet“ – keine Platzhalter-GIFs.
- Anfragen: `v1/gifs/search` bzw. `v1/gifs/trending` (ohne Suchbegriff), `rating=pg`, Sprache der App, 30 je Seite,
  höchstens 150 Treffer. Suche erst 350 ms nach der letzten Eingabe.
- Raster mit kleinen Standbildern (`fixed_width_still`), animiert wird nur das gewählte GIF (Vorschau über
  `PaceImageLoader.decoded(_:size:)` mit Byte-Budget, außerhalb des Main Threads).
- Senden: Die Datei („downsized“ < 2 MB, sonst „fixed_width“) wird über eine eigene, flüchtige Sitzung (ohne Cookies,
  ohne dauerhaften Cache) heruntergeladen – nur HTTPS von `giphy.com` und Subdomains, auch nach Weiterleitungen, geprüft
  auf GIF-Signatur und 10-MB-Grenze – und wie ein GIF aus der Mediathek über
  `ChatViewModel.sendMedia(_:contentType: "image/gif")` in den privaten Bucket `chat-media` hochgeladen. Es wird nie
  ein fremder Link gespeichert; das GIF bleibt verfügbar und ist nur für die Teilnehmer lesbar. Storage-Policies
  bleiben unverändert, keine Migration.
- Pflichtangabe „Powered by GIPHY“ und Datenschutzhinweis in der Auswahl und in Hilfe → Datenschutz: Schon beim Öffnen
  lädt die Auswahl beliebte GIFs und Standbilder von GIPHY; GIPHY erhält dabei IP-Adresse und Suchbegriffe.
- Die CI (Secret-Scan) schlägt fehl, wenn `GIPHY_API_KEY` in einer versionierten `.xcconfig`/`.example` einen Wert hat.
  Für eine veröffentlichte App wäre ein Produktionsschlüssel von GIPHY nötig (der Beta-Schlüssel ist begrenzt).
- Fehler: `notConfigured` (kein/abgelehnter Schlüssel), `offline`, `rateLimited`, `unsuitableFile`, `failed` – je
  mit eigenem Hinweis und (außer „nicht eingerichtet“) „Erneut versuchen“.

### Profil teilen aus dem Chat

`ChatProfileShareSheet` listet das eigene Profil („Mein Profil“) und die Freunde (`SocialViewModel` →
`ChatListViewModel.shareableProfiles`). Gesendet wird über `ChatViewModel.shareProfile(_:)` →
`ChatListViewModel.shareProfile(_:with:)` – derselbe Weg wie von einer Profilseite (Server prüft Sichtbarkeit und
Blockierungen).

## Bilder und GIFs aus der Mediathek

- Auswahl per `PhotosPicker` (`matching: .images`, `preferredItemEncoding: .current`).
- GIF (Mediathek-Typ `com.compuserve.gif`, erkannt an der Dateisignatur `GIF87a`/`GIF89a`): unverändert als
  `image/gif` hochladen. Fotos: auf höchstens 2.048 px verkleinern und als JPEG (Qualität 0,85 → 0,45) unter die
  Grenze von `MediaRules` (10 MB für Chats) bringen. Format und Größe prüft das ViewModel vor dem Hochladen.
- Hochladen nach `MediaUploadTarget.chat(conversationID:)`, danach `ChatMessageDraft(kind: .image/.gif, mediaPath:)`.
  Das gerade hochgeladene Bild kommt direkt in den Cache des `PaceImageLoader` (keine zweite Übertragung).
- Anzeige über den gemeinsamen `PaceImageLoader` (Environment `\.paceImageLoader`, privater Bucket `chat-media`).

## Profil teilen

`ChatListViewModel.shareProfile(_:with:)` (aufgerufen von `ShareProfileViewModel`): Für jedes Ziel (doppelte
entfernt) wird die Unterhaltung gefunden bzw. geöffnet (`openDirectConversation`, `groupConversation`) und
`ChatMessageDraft(kind: .profile, sharedProfileID:)` gesendet. Schlägt es bei einzelnen Zielen fehl, wird bei den
anderen trotzdem gesendet und danach `ProfileShareError` (gesendet an n Chats, nicht gesendet an …) geworfen.

## Blockieren und Melden

- Blockieren über `SocialRepository.block` (Privatchat: Gegenüber im Menü; Gruppe: Absender im Kontextmenü).
  Danach ist der Privatchat schreibgeschützt; in Gruppen erscheinen Nachrichten blockierter Personen eingeklappt
  („Nachricht einer blockierten Person“, „Anzeigen“). Die Liste blockierter Personen kommt aus `blockedUsers()`.
- Melden über `SocialRepository.report`: Nachricht (`.message(id:)`), Person (`.user(publicID:)`) bzw. Gruppe
  (`.group(id:)`) mit Grund aus `ReportReason`.
- Ohne verdrahtetes `SocialRepository` zeigen diese Aktionen ehrlich „nicht verfügbar“; der Chat selbst funktioniert.

## Schnittstellen zur Social-Navigation

- `ChatListSection(viewModel:onOpen:)` – unverändert.
- `ChatView(viewModel:backTitle:onOpenRoute:onOpenProfile:)` – `backTitle` (Standard „Social“) und `onOpenRoute`
  sind optional. Ohne `onOpenRoute` öffnet der Chat Gruppendetails, -einstellungen und -mitglieder per
  `NavigationLink(value: SocialRoute…)`; der Social-Tab registriert diese Ziele bereits.
- `ChatListViewModel.chat(for:)` liefert je Unterhaltung immer dieselbe Instanz (auch wenn sie einmal über die Liste,
  einmal über ein Profil oder eine Gruppe geöffnet wird) – Verlauf und Entwurf bleiben beim Zurücknavigieren.
- `ChatListViewModel(repository:media:social:calendar:now:pollInterval:sleep:)` – `social` liefert Gruppenkopf,
  blockierte Personen, Blockieren und Melden; ohne Angabe fehlen nur diese Teile.

## Nachrichtenaktionen und Sprachnachrichten in der App

- **Kontextmenü** (Nachricht gedrückt halten, natives iOS-Menü: reagiert sofort, wird nicht abgeschnitten, schließt
  beim Tippen daneben, öffnet nicht beim Scrollen, VoiceOver-Aktionen): nur Aktionen, die gerade möglich sind
  (`ChatViewModel.actions(for:)`): Antworten und Bearbeiten nur mit Schreibrecht, Kopieren nur bei Text, Bearbeiten nur
  bei eigenen Texten, Favorit immer (privat), Anpinnen nur mit `canPin`. Dazu wie bisher Löschen/Melden/Blockieren.
- **Antworten:** Vorschau über der Eingabe („Antwort auf Mia“ + Ausschnitt, ✕ bricht ab), die ausstehende Nachricht
  trägt den Verweis schon vor der Server-Antwort. In der Blase ein kompakter Verweis; Antippen springt zur Nachricht
  (`jump(to:)` lädt ältere Seiten nach, höchstens 10) und hebt sie 1,6 s hervor; nicht mehr vorhandene Originale:
  „Nachricht nicht verfügbar“.
- **Bearbeiten:** Text kommt ins Eingabefeld (der bisherige Entwurf wird aufbewahrt und danach zurückgelegt), Haken
  speichert (`editMessage` → gleiche Nachricht ersetzt, nichts doppelt), ✕ bricht ab. Bei einem Fehler bleibt der Text
  im Feld. Kennzeichen „Bearbeitet“ unter der Blase.
- **Favoriten:** sofort umgeschaltet, bei Fehler zurückgenommen; kleiner Stern an der Nachricht (nur für mich); Liste
  über den Stern im Chat-Kopf (Antippen springt zur Nachricht, Kontextmenü „Favorit entfernen“).
- **Pins:** Hinweis oben unter dem Kopf („Angepinnt 1 von 3“ + Vorschau); Antippen springt hin und zeigt danach den
  nächsten Pin; Kontextmenü „Lösen“ (mit Recht). Verborgene Pins erscheinen als „Nachricht nicht verfügbar“ und lassen
  sich so lösen. Pins anderer kommen per Echtzeit (`pinsChanged`).
- **Sprachnachrichten:** Mikrofon bei leerem Feld, sonst Senden (beide Knöpfe liegen übereinander, damit eine
  laufende Geste nicht abreißt). Gedrückt halten nimmt auf (roter Punkt mit Pegel, Zeit, Haptik); nach oben wischen
  sperrt (dann Stopp, Verwerfen, Senden), nach links wischen verwirft (Datei gelöscht, nichts hochgeladen). Nach dem
  Loslassen bzw. Stopp folgt eine Vorschau zum Anhören – hochgeladen und gesendet wird erst mit „Senden“. Kürzer als
  1 s gilt als Antippen („Zum Aufnehmen gedrückt halten.“). Erste Nutzung: iOS fragt nach dem Mikrofon, aufgenommen
  wird beim nächsten Halten. Unterbrechungen: Anruf (Audio-Unterbrechung) und Wechsel in den Hintergrund beenden eine
  Aufnahme als Vorschau; Verlassen des Chats verwirft sie. Wiedergabe-Blase mit Abspielen/Pause, Fortschritt (antippen
  springt), Dauer bzw. „0:05 / 0:18“; immer nur eine Wiedergabe gleichzeitig. Eine fehlgeschlagene,
  schon hochgeladene Sprachnachricht wird beim Verwerfen auch im Speicher gelöscht.

## Nachrichtenaktionen und Sprachnachrichten (Verträge, Migration 20261023100100)

- **Antworten:** `ChatMessageDraft.text(_:replyTo:)` bzw. `ChatMessageDraft(…, replyToID:)`. Der Server nimmt nur
  sichtbare, nicht gelöschte Nachrichten derselben Unterhaltung (`notFound`). Jede Nachricht trägt
  `replyPreview: ChatReplyPreview?` (`id` zum Springen, `sender` mit Spitzname, `kind`, `text` ≤ 200 Zeichen,
  `mediaDuration`, `isDeleted` für gelöschte bzw. verborgene Originale) – auch für Sprachnachricht, Bild und Profil.
- **Bearbeiten:** `editMessage(_:text:)` nur für eigene Textnachrichten (`ChatMessage.canEdit`); Antwort mit
  `editedAt` („Bearbeitet“, `isEdited`). Andere Teilnehmer bekommen `ChatConversationEvent.messageUpdated`.
- **Favoriten:** `setFavorite(_:isFavorite:)`, `favorites(conversationID:)` (Übersicht in den Chat-Einstellungen);
  `ChatMessage.isFavorite` gilt nur für mich. `withFavorite(_:)` für sofortiges Umschalten. Höchstens
  `ChatRules.maximumFavorites` (1000, sonst `favoriteLimitReached` mit eigenem Text); Entfernen geht immer.
- **Anpinnen:** `ConversationSummary.canPin` (Gruppe: Owner; Privatchat: beide mit Schreibrecht),
  `setPinned(_:isPinned:)` → alle Pins, `pins(conversationID:)` → `[ChatPin]` (zuletzt angepinnte zuerst),
  `ChatMessage.isPinned`; höchstens `ChatRules.maximumPinnedMessages` (5, sonst `pinLimitReached`), Nicht-Owner
  `notAllowed`. Änderungen kommen als `ChatConversationEvent.pinsChanged`. Pins auf Nachrichten, die für mich
  verborgen sind (Absender blockiert), zählen weiter zur Höchstzahl: Wer anpinnen darf, bekommt sie als
  `ChatPin.isHidden` (Platzhalter ohne Text, Medien, Absender und `pinnedBy`) und löst sie mit
  `setPinned(pin.id, isPinned: false)`; Anzeige z. B. „Nachricht nicht verfügbar“, ohne Sprung (im Verlauf fehlt sie).
  Wer nicht anpinnen darf, bekommt verborgene Pins gar nicht.
- **Echtzeit:** `conversationActivity(in:)` liefert `.message`, `.messageUpdated`, `.pinsChanged` über einen Kanal
  (endet sofort ohne Realtime → Polling wie bisher). `messageEvents(in:)` bleibt für neue/gelöschte Nachrichten.
- **Sprachnachrichten:** Aufnahme als AAC in `.m4a`, Upload `media.upload(data, contentType:
  MediaRules.voiceContentType, to: .chat(conversationID:))` (privat im Bucket `chat-media`; lesen darf die
  hochladende Person sofort, alle anderen erst über die gesendete, sichtbare Nachricht – gilt auch für Bilder/GIFs),
  danach `ChatMessageDraft.voice(mediaPath:duration:replyTo:)`. Dauer 1 ms bis `ChatRules.maximumVoiceDuration`
  (5 min, `ChatRules.validVoiceMilliseconds`), Datei ≤ 10 MB. Am besten erst nach der Vorschau beim Senden
  hochladen; wurde schon hochgeladen und dann verworfen, die Datei mit `media.delete(_:)` entfernen (kein
  Upload-Rest). Löschen der Nachricht entfernt die Datei wie bei Bildern.
  `ChatMessage.mediaDuration`, Chatliste `ChatMessagePreview.mediaDuration` → `ChatFormatting.content(kind:text:duration:)`
  („Sprachnachricht · 0:18“).
- **Spitznamen:** Absender, Gegenüber und Antwort-Vorschau tragen den eigenen Spitznamen
  (`SocialProfile.shownName`, `ConversationSummary.shownTitle`, `ChatMessagePreview.shownSenderName`); die
  Gruppen-Vorschau der Chatliste nutzt ihn bereits.

## Tests

- `Tests/SocialFeatureTests/ChatListViewModelTests.swift`, `ChatViewModelTests.swift`, `ChatFormattingTests.swift`
  (Linux und iOS): Zustände, Filter, Sortierung, Ungelesen, gebündeltes Laden, Echtzeit, Polling-Rückfall mit
  steuerbarem Warten (`ManualTicker`), Pagination, optimistisches Senden, Wiederholen mit gleicher `clientID`, keine
  Duplikate bei Ereignis + Neuladen, Lesestand nur sichtbar, schreibgeschützte Chats, Bild-/GIF-Upload inklusive
  Fehlern, Profil teilen an mehrere Ziele, Blockieren, Melden, Löschen, Datums-Trenner, Sprachen.
- Test-Doubles: `Tests/PaceTestSupport/ChatAndMediaStubs.swift` (`ChatRepositoryStub`, `MediaRepositoryStub`,
  `ManualTicker`, `ChatFixtures`).
- `ChatMessageActionsTests.swift`: Menü je Lage, Antworten (Verweis vor und nach der Server-Antwort), Sprung mit
  Nachladen, Bearbeiten (Entwurf, Fehler, nur eigene), Favoriten (Liste, Rücknahme), Pins (Hinweis, Sprung, Limit,
  Echtzeit, verborgene lösen), Sprachnachrichten (Upload erst beim Senden, Dauer, ungültige, Verwerfen löscht Datei).
  `ChatListViewModelTests.swift` → `ChatIncomingHintTests`: Hinweise auf neue Nachrichten.
- Snapshots (`Tests/PaceSnapshotTests/ChatSnapshotTests.swift`, nur mit `PACE_SNAPSHOT_DIR`): `chat-list`
  (DE/EN/RU), `group-chat` (wie Bild 5, DE/EN/RU), `direct-chat` (DE/EN/RU), `chat-actions` (Pin, Antwort, Bearbeitet,
  Favorit, Sprachnachricht, Antwort-Vorschau; DE/EN/RU), `chat-states`, `chat-read-only`,
  `chat-unavailable` – jeweils Hell und Dunkel, mit Kopfzeile. Das Textfeld erscheint im Snapshot als Platzhalter
  (Grenze des `ImageRenderer`).

## Nur auf dem iPhone prüfbar

Mediathek-Auswahl inkl. GIFs aus „Fotos“, Upload und Anzeige aus dem privaten Bucket, Echtzeit zwischen zwei
Konten, Scrollverhalten (unten beginnen, ältere Nachrichten nachladen, Mitscrollen bei neuen Nachrichten), Tastatur
mit der globalen Tab-Leiste, Kontextmenüs, Vollbild-Zoom, VoiceOver und „Bewegung reduzieren“ bei GIFs.
**Nicht auf einem Gerät getestet:** Aufnahme-Geste (Halten, Sperren, Verwerfen), Mikrofon-Abfrage, Aufnahme und
Wiedergabe mit AVFoundation, Unterbrechungen durch Anrufe, Haptik, Sprung mit Hervorhebung, lokale Chat-Hinweise.
