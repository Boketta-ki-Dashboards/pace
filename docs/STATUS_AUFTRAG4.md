# Auftrag 4 (24./25.10.2026) – Abschlussbericht

Branch `claude/gallant-brahmagupta-hvvp13`, Ausgangsstand 359abfa. Pace wurde stabilisiert und erweitert, nicht neu
aufgebaut. **Im produktiven Supabase-Projekt wurde nichts verändert, keine neue Migration.** Signing, Bundle
Identifier, Entitlements, `Pace.xcodeproj/project.pbxproj` und die lokale Konfiguration (`Config/Pace.xcconfig`, von
Git ausgeschlossen) sind unverändert. Kein Schlüssel im Repository.

**Wichtig – Gerätetests:** Alles unten ist mit automatisierten Tests (Linux-Unit-Tests, iOS-Simulator in der CI,
Fenster-Snapshots) geprüft, aber **noch nicht auf einem echten iPhone**. Nichts davon gilt als gerätegetestet. Die
Abnahme auf dem iPhone beschreibt [IPHONE_TEST.md](IPHONE_TEST.md) (33 Testfälle).

## 1. Behobene P0-Fehler

| P0 | Stand | Nachweis |
|---|---|---|
| 1. Endlose Navigation Gruppe → Flamme → Chat | im Code behoben | `SocialNavigator` als einzige Quelle des Social-Pfads; eine schon offene Seite (Identität inkl. Gruppen-ID) wird nicht erneut aufgelegt, sondern es geht zu ihr zurück. Tests: 50 Wechsel Flamme ↔ Chat (Pfad bleibt kurz), Einstieg über Chatliste, zwei Gruppen nicht verwechselt, Doppeltippen, Deep Link, höchstens ein Echtzeit-Abo. Home bekam dieselbe Regel (`HomeRoute`). Gerätetest offen |
| 2. Spiegelverkehrte Tab-Wischrichtung | im Code behoben | Normales Paging (Finger nach links → nächster Tab rechts), interaktives Paging, Zwischenstände und Abbruch erhalten. Simulator-Tests prüfen die sichtbare Bewegung für alle 6 Übergänge, Abbruch, Startseite und gesperrtes Paging. Gerätetest offen |
| 3. Chat-Eingabe von der Tastatur verdeckt | im Code behoben | Die sichtbare Seite endet an der Tastaturkante (gemessen über `UIKeyboardLayoutGuide`). Simulator-Test mit simulierter Tastatur: Eingabe rückt **genau 300 pt** nach oben (755 → 455). Mit echter Tastatur nur auf dem Gerät prüfbar (der CI-Simulator zeigt keine) |
| 4. Sprachaufnahme bricht nach ~1 s ab | im Code behoben | Ursache gefunden (Audio-Sitzung, Geste); Sitzung gehört dem, der sie aktiviert; Mikrofon-Geste in globalen Koordinaten. Tests der Sitzungs-Zuständigkeit. Aufnahme selbst nur auf dem Gerät prüfbar |
| 5. Widget-Drag instabil | im Code behoben | Reihenfolge bleibt während des Ziehens fest, andere Widgets weichen nur sichtbar aus, Übernahme einmal beim Loslassen, weiches Einrasten; Abbruch durch System/zweiten Finger/Hintergrund beendet sauber. Rechenregeln getestet, Geste Gerätetest offen |
| 6. Stabilität, Speicher, „Pace ist nicht mehr verfügbar“ | Speicherursachen behoben; Meldung: Hypothese | Siehe 2. und 3. Die Meldung passt zum Ablauf des 7-Tage-Profils eines kostenlosen Personal Teams – **nicht bestätigt**, Prüfweg in IPHONE_TEST.md |

## 2. Tatsächliche Ursachen

1. **Navigation:** Der Social-Tab nutzte einen append-only `NavigationPath`; Gruppe, Flamme und Chat legten sich
   gegenseitig immer wieder neu auf. Gruppenchat über die Gruppe und über die Chatliste galten nicht als derselbe
   Chat; ein `NavigationLink`-Rückfall im Chat umging jede Prüfung.
2. **Wischrichtung:** Ein Richtungs-Flag aus Auftrag 3 kehrte die Seitenfolge um.
3. **Tastatur:** Die waagerechte Seitenleiste (ScrollView) verbrauchte die Tastatur als eigenen Scroll-Abstand und gab
   sie nicht an die Seiten weiter. Der erste Fix (Safe Area) kam im eingebetteten NavigationStack nicht an – das zeigte
   der CI-Test mit simulierter Tastatur; jetzt verkleinert ein echter Abstand die Seite.
4. **Sprachaufnahme:** Beim Start der Aufnahme sperrte der Chat die Wiedergabe; das Sperren rief `stop()` auf, das die
   gemeinsame Audio-Sitzung deaktivierte – die Aufnahme endete nach etwa einer Sekunde. Zusätzlich verschob das
   Schließen der Tastatur die Leiste unter dem Finger, was als „nach oben wischen = sperren“ galt.
5. **Widget-Drag:** Kein Abbruchpfad (DisplayLink und Auto-Scroll liefen weiter), Versatz gegen eine veraltete
   Messung (Springen), Umsortieren und Speichern bei jedem Platztausch.
6. **Speicher:** Bildspeicher ohne Kostenlimit, GIFs mit bis zu 300 Vollbildern in Originalgröße dekodiert, Chat-
   ViewModels und hochgeladene Mediendaten unbegrenzt im Speicher.

## 3. Speicherprobleme

Festgestellt (durch Code-Analyse und unabhängige Prüfung, nicht mit Instruments auf einem Gerät) und behoben:

| Wo | Problem | Behebung |
|---|---|---|
| `PaceImageLoader` | `NSCache` ohne Kostenlimit, GIFs in voller Größe mit allen Bildern | Dekodieren in Anzeigegröße (Profilbild 96–512 px, Blase, Vollbild), Byte-Budget je GIF (16 MB, Vollbild 40 MB), Bildspeicher 96 MB, komprimierte Daten getrennt (32 MB), gemeinsame Downloads, nie auf dem Main Thread |
| Chat-Blasen | Jede Blase hielt ihr dekodiertes Bild | Blasen geben Bilder außer Sicht frei |
| `ChatListViewModel` | Alle je geöffneten Chats blieben im Speicher | Höchstens 8 nicht offene Chats (LRU), offene/sendende bleiben |
| `ChatViewModel.uploadedMedia` | Hochgeladene Daten unbegrenzt | `ChatMediaDataCache`, 24 MB je Chat |
| Navigation | Endlos wachsender Pfad (P0 1) | siehe oben |
| GIF-Suche (neu) | – | Raster nur mit Standbildern, höchstens 150 Treffer, nur das gewählte GIF animiert |

## 4. Durchgeführte Messungen

- **Automatisiert:** Navigationspfad nach 50 Wechseln (bleibt kurz), Chat-Cache-Freigabe (LRU, Pfad, Zurück-Geste),
  GIF-Dekodierung (100 Bilder à 520 px → in Blasengröße innerhalb des Byte-Budgets), Mediendaten-Speicher nach Bytes,
  Tastatur-Versatz im echten Fenster (genau 300 pt), sichtbare Pager-Bewegung (Farbseiten).
- **Nicht durchgeführt:** Speicher- und Zeitmessungen mit Instruments auf einem echten iPhone – mangels Gerätezugriff.
  Anleitung für eine einfache Messung mit dem Xcode-Debug-Navigator: IPHONE_TEST.md, Fälle 12 und 20.

## 5. Neue Funktionen

| Punkt | Umsetzung |
|---|---|
| 7 Tab-Leiste unten kompakter | 14 pt weniger Leerraum über dem Home-Indikator, Symbole/Texte gleich; springt beim Wiedereinblenden nicht |
| 8 Messenger | „Du“ im Verweis auf eigene, nicht geladene Nachrichten; geänderter Spitzname sofort in Rankings (Freunde, Gruppen, regional) |
| 9 GIF-Picker | „+“ → Menü (Foto aus Mediathek, GIF suchen, Profil teilen); GIF-Suche über GIPHY (Suchfeld, echte Treffer, Vorschau, Senden/Abbrechen, Laden, keine Treffer, offline, Kontingent, „nicht eingerichtet“). Gesendet wird eine geprüfte Kopie über den geschützten Chat-Speicher. Schlüssel nur über `Config/Pace.xcconfig` |
| 10 Einstellungen | Profil → Einstellungen in sieben Kategorien, ohne Doppelsysteme und Schleifen |
| 11 Flammen-Widget | Eigene Seite „Deine Flamme“: Serie, Rekord, Beginn, letzter Erfolg, Flammenkalender mit Tagesdetails, frühere Serien, Regeln; kein Weg zu Gruppe/Chat |
| 12 Widget-Optionen | „Inhalte“ je Widget (Schritte, Flamme, Freunde, Gruppe, Umfeld), passend zur Größe; eigene Namen für alle Widgets |
| 13 Diagramm-Wischen | Statistik Tag/Woche/Monat: Finger nach rechts = vorher, nach links = nächster; gleiche Geste im Kalender und Flammenkalender |
| 14 Kalorienschätzung | Größe/Gewicht/Schalter, ACSM-Gehmodell, „≈ … kcal“ + „Geschätzte aktive Kalorien“, Messung hat Vorrang, nie addiert, nur auf dem Gerät |
| 15 Bestwerte | Statistik: bester Tag der Woche (Kachel), bester Tag und beste Woche des Monats, bester Tag/Woche/Monat der letzten 12 Monate, längste und aktuelle Serie, Ø pro Tag, weiteste Strecke; Kalender: „Deine Bestwerte“ (bester Tag der Woche, des Monats, der 12 Monate, längste Serie). Geschätzte Kalorien mit „≈“ |
| 16 Anfragen-Symbol | Briefumschlag mit Person, Zahl am Symbol, öffnet die Anfragen |
| 17 Gruppenkalender/-flamme | Geprüft: unverändert, durch die pgTAP-Tests `16_group_calendar` (40 Prüfungen) und `08_social_group_streak` in jeder Backend-CI abgedeckt (Rechte, Zeitraumgrenzen in der Zeitzone der Gruppe, historische Mitglieder und Ziele, ⌈n/3⌉, Gleichstände, leere Tage, Blockierte, Übereinstimmung mit der Streak) |
| 18 Benachrichtigungen | Unverändert (bis 6 Erinnerungszeiten, lokale Chat-Hinweise nur bei geöffneter App). **Kein APNs** |

Nicht umgesetzt (ehrlich): Video im Chat (Backend erlaubt nur Bilder, GIFs, Sprache – bräuchte eine Migration);
Platzierungsänderung, Tagesbeste und Position einer Gruppe als Widget-Inhalt (Daten fehlen, keine erfundenen Werte).

## 6. Unverändert erhalten

Onboarding, Region, regionale Rankings und Sichtbarkeitsschalter, Freunde, Anfragen, Gruppen (Erstellen, Details,
Einstellungen, Einladungen, Bilder), Blockieren/Melden, Chats (Senden, Bilder, Profilkarten, Antworten, Bearbeiten,
Favoriten, Pins, Sprachnachrichten), Gruppenkalender, Home-Widgets (Hinzufügen, Entfernen, Verschieben, Größen,
Konfiguration), Statistik, Tagesdetails, Kalender, Live-Schritte, Tagesziel und Zielverlauf, Erinnerungen, App-Icons,
Darstellung, Sprache, Datenexport, Kontolöschung. Regel „manuell eingetragene Schritte zählen nicht für Rankings“
unverändert (auch für Tagesbestwert, Serie und Kalorienschätzung).

## 7. Geänderte Komponenten

- **Navigation:** `SocialNavigator` (neu), `SocialView`, `SocialViewModel`, `ChatListViewModel` (Zuordnung, LRU),
  `PaceNavigationRules`, `HomeRoute`/`HomeView`, `ProfileViewModel`.
- **Gesten/Layout:** `PaceTabPaging`, `PaceTabPager` (Tastatur), `PaceTabBar`, `PaceSwipeNavigation` +
  `pacePeriodSwipe` (neu), `HomeReorderController`/`HomeReorderMath`, `HomeEditChrome`, `HomeModuleView`.
- **Messenger/Audio:** `ChatAudioSession`/`ChatAudioSessionOwnership`, `ChatInputBar` (Menü, Mikrofon-Geste),
  `ChatViews`, `ChatViewModel`, `ChatMediaDataCache` (neu), `ChatAttachmentSheets`, `GIFPickerViewModel` (neu).
- **Medien:** `PaceImageLoader` (neu geschrieben), `PaceAvatar`, `ChatMediaImage`.
- **Services:** `GIFSearching` (PaceCore), `GIPHYSearchService` (PaceBackend), `BackendFailure` (Abbruch ≠ Netzwerk-
  fehler), Social-/Chat-/Medien-Repositories.
- **Aktivität:** `CalorieEstimation` (neu), `StatisticsReport`, `StreakDetailReport`/`-ViewModel`/`-View` (neu),
  `PersonalBests` (neu), `CalendarMonth`/`CalendarView`, `StepsTodaySummary`.
- **Home:** `HomeWidgetDetails` (neu), `HomePreferences`, `HomeWidgetGalleryViewModel`/-View, alle Widget-Ansichten.
- **Profil:** `ProfileView`, `ProfileRoute`, `ActivityHealthPages` (neu), `HelpContent`.
- **Rankings:** `LeaderboardViewModel.nicknameDidChange`.
- **Konfiguration:** `Config/Base.xcconfig`, `Config/Pace.xcconfig.example`, `Config/Info.plist` (optionaler
  `GIPHY_API_KEY` → `PaceGIPHYAPIKey`, leer im Repository), `Pace/AppDependencies+Live.swift`.

## 8. Migrationen

**Keine neue Migration.** Alle neuen Funktionen nutzen die bestehenden Tabellen, RPCs und Storage-Policies (GIFs
laufen über den vorhandenen privaten Bucket `chat-media` mit `image/gif`). Die drei Migrationen aus Auftrag 3 wurden
vom Nutzer am 24.10.2026 eingespielt und nicht erneut ausgeführt.

## 9. iOS-Berechtigungen

Keine neuen. Weiterhin: Apple Health (Lesen), Bewegung & Fitness (Live-Schritte), Mikrofon (Sprachnachrichten),
Mitteilungen (Erinnerungen). Die Fotoauswahl nutzt `PhotosPicker` (keine Berechtigung). Die GIF-Suche braucht keine
Berechtigung; Suchbegriffe gehen an GIPHY (Hinweis in der Auswahl und in Hilfe → Datenschutz).

## 10. Erfolgreiche Tests

Stand f839baa (alle grün):

| Wo | Was | Ergebnis |
|---|---|---|
| iOS-CI (macOS 15, Simulator) | App-Build ohne Compiler-Warnungen, Info.plist-, App-Icon- und Schlüsselprüfung; 14 Testläufe (Unit, ViewModel, Snapshot, Fenster-Tests für Pager-Richtung und Tastatur) | **1.018 Tests bestanden, 0 fehlgeschlagen** |
| Backend-CI (frisches lokales Supabase) | pgTAP, Datenbank-Lint, Security-/Performance-Advisors, Realtime-Ende-zu-Ende, Swift-Integrationstests, Secret-Scan (inkl. GIPHY) | **965/965 pgTAP**, 21 Integrationstests, alle Schritte grün |
| Linux (lokal, plattformunabhängige Teile) | PaceCore und alle Feature-ViewModels | **824 Tests** bestanden |
| Linux (lokal) | PaceBackend (u. a. GIPHY-Anbindung) | **114 Tests** bestanden |

Neu in dieser Runde unter anderem: Social-Navigator (50 Wechsel, Gruppen-IDs, Deep Link), Pager-Richtung im Fenster
(alle 6 Übergänge, Abbruch), Tastatur mit simulierter Höhe (mit und ohne Antwortvorschau genau 300 pt),
Audio-Sitzung, Widget-Ausweichen und Speichern, Chat-Freigabe (LRU), Mediendaten-Speicher, GIF-Dekodierung,
Kalorienschätzung (Modell, Vorrang, Grenzen, keine Doppelzählung), Serienseite und Flammenkalender, persönliche
Bestwerte, Statistik-Bestwerte und „≈“, Wischregeln, Widget-Inhalte (Standard, Größe, Speicherformat), GIF-Suche
(Anfragen, Fehler, Weiterleitung, Download, Picker-Zustände, Senden als Kopie), Profil teilen aus dem Chat,
regionaler Spitzname, Snapshots der neuen Seiten (Hell/Dunkel, DE/EN/RU).

## 11. Fehlgeschlagene Tests

Während der Runde (alle behoben, nichts übersprungen oder deaktiviert):

| Lauf | Test | Ursache | Behebung |
|---|---|---|---|
| CI b6cd366 | `KeyboardLayoutTests.chatInputMovesUpByExactlyTheKeyboardOverlap` | **echter Fehler**: Die als Safe Area weitergegebene Tastaturhöhe kam im Chat innerhalb des NavigationStack nicht an | 8e31541 (Abstand statt Safe Area) |
| CI b2b47fe | Snapshot-Testziel kompilierte nicht | Test nutzte noch die alte `ChatInputBar(onPickMedia:)` | bbc227d |
| CI 83681c5 | `TabPagerDirectionTests` (Rankings → Social, vollständig) | Testaufbau: feste Wartezeit von 250 ms auf die asynchron gemeldete Scroll-Position; Seite war sichtbar, Meldung kam auf dem ausgelasteten CI-Rechner später | f839baa (Warten auf die Bedingung, höchstens 3 s) |
| lokal | `StreakDetailReportTests` kompilierte nicht | `#expect` mit Funktionsverweis | vor dem Push behoben |
| lokal | regionaler Spitznamen-Test | Testdaten ohne Rangliste | vor dem Push behoben |

Im letzten Lauf (f839baa): **keine** fehlgeschlagenen Tests.

## 12. Unabhängige Prüfungen

Drei unabhängige Prüfungen (je ein eigener Prüf-Agent ohne Schreibzugriff, Berichte mit Fundstelle und Szenario):

| Prüfung | Umfang | Befunde |
|---|---|---|
| 1. Navigation und Speicher | Teil A (fba78f0 … c539d99) | 4 mittel, 8 leicht |
| 2. Messenger, Audio, Tastatur, Tab-Pager, Widget-Drag | Teil A/B (359abfa … c539d99) | 1 schwer, 2 mittel, 6 leicht, 5 spekulativ (Gerät prüfen) |
| 3. Neue Funktionen und Regressionen | Teil B/C (62113bb … bbc227d) | 1 schwer, 2 mittel, 11 leicht |

Keine Prüfung fand eine Verletzung der harten Regeln (keine Schlüssel im Repository, GIFs nur als Kopie im privaten
Speicher, manuelle Schritte zählen nirgends, Körperdaten verlassen das Gerät nicht in Richtung Server/Freunde/Gruppen,
keine endlosen Stapel, keine Umgehung von Blockierungen und Gruppenrechten, alle Texte DE/EN/RU).

## 13. Behobene Befunde

- **Prüfung 1** (behoben in b6cd366 bzw. c1dbaae): Bildspeicher lief über und dekodierte je Größe neu; Dekodieren
  auf dem Main Thread; dekodierte Bilder in jeder Blase; Test der Chat-Freigabe lief die Freigabe gar nicht; doppelte
  Chat-ViewModels nach `touched()`; Abbruch beim Verlassen erschien als Netzwerkfehler; Abschlüsse nach dem Warten
  ersetzten die gerade oberste Seite; Freigabe vergaß gerade vorbereitete Fotos; hochgeladene Mediendaten unbegrenzt;
  Vollbild nutzte das verkleinerte Blasenbild; Home ohne Schutz vor doppelten Seiten.
- **Prüfung 2** (b6cd366, 8e31541, f5ca08a): **Schwer** – Halten des Mikrofons bei offener Tastatur sperrte die Aufnahme
  ungewollt (Geste jetzt in globalen Koordinaten). **Mittel** – Tastatur-Test prüfte nichts (jetzt Test mit simulierter
  Tastatur; er deckte einen echten Fehler auf, behoben in 8e31541); Ziehen blieb nach zweitem Finger hängen. Leicht –
  Tab-Leiste sprang beim Wiedereinblenden, Abstand auf allen Seiten statt nur der sichtbaren, Pause gab die Audio-
  Sitzung nicht frei, Spitzname im regionalen Ranking erst nach Neuladen, Doku-Kommentar. Spekulativ, im Code
  adressiert: mögliche 34-pt-Lücke (Seite endet jetzt an der Tastaturkante), Springen beim Ziehen (Ausweich-Ansatz),
  Zustand aus `layoutSubviews` (asynchron), Hilfslinie nach Fensterwechsel (`didMoveToWindow`).
- **Prüfung 3** (83681c5): **Schwer** – Nullbalken in der Tagesstatistik geschätzter Kalorien. **Mittel** – „≈“ fehlte
  außerhalb der großen Zahl; veralteter Text „Pace rechnet keine Kalorien hoch“. Leicht – Widget-Beschriftung, GIF-
  Download (eigene Sitzung, Weiterleitungen, Größe), Datenschutzhinweis GIF, CI-Prüfung des GIPHY-Schlüssels, Felder
  unter der Tastatur (Kalorien, Widget-Name), Übernahme von Größe/Gewicht beim Tippen, doppelte Wochen-Bestwertkarte,
  weiteste Strecke mit manuellen Schritten, wiederholte Schätzung, Pluralformen und russische Texte, Aufräumen.

## 14. Offene Punkte

| Punkt | Schwere | Stand |
|---|---|---|
| Alle Funktionen auf einem echten iPhone | – | **offen** – nur automatisiert geprüft (siehe 15) |
| „Pace ist nicht mehr verfügbar“ | – | Hypothese (7-Tage-Profil), Prüfweg in IPHONE_TEST.md |
| Speicher-/Zeitmessung mit Instruments | – | nicht durchgeführt (kein Gerät) |
| GIF-Suche braucht einen GIPHY-Schlüssel des Nutzers | – | ohne Schlüssel ehrlich „nicht eingerichtet“; für eine Veröffentlichung wäre ein Produktionsschlüssel nötig, der Schlüssel steckt technisch bedingt in der App |
| Video im Chat | – | nicht umgesetzt (bräuchte Migration) |
| APNs / Push bei geschlossener App | – | nicht umgesetzt (kostenloses Personal Team) |
| Tastatur in einem Sheet verkleinert auch die Seite dahinter | leicht | offen, bei großen Sheets unsichtbar |
| Tab-Leiste und Seitenabstand gleiten mit unterschiedlicher Kurve | leicht | offen (kosmetisch) |
| Audio: kurzes Aufblitzen anderer Apps beim Wechsel Wiedergabe → Aufnahme; Zuständigkeit je Rolle | leicht | offen |
| Eingabefelder in weiteren Scrollseiten (außer Kalorien und Widget-Name) | leicht | auf dem Gerät prüfen; dort, wo nötig, gleiches Hinscrollen ergänzen |
| GIF: Größe wird erst nach dem Laden geprüft; Standbilder laufen über die gemeinsame Sitzung | leicht | offen (Quelle ist GIPHYs CDN, Größen vorab gefiltert) |
| Manuell eingetragene Strecke ohne manuelle Schritte zählt in Distanz und Schätzung | leicht | teilweise (Bestwert ohne Tage mit manuellen Schritten); vollständig nur über eine geänderte HealthKit-Abfrage |
| Zurück-Wischen vom Rand über einer Wisch-Fläche | – | auf dem Gerät prüfen |
| Rückgang zu einer offenen Seite kann mehrere Ebenen schließen | Design | so gewollt (keine Doppelseiten) |

## 15. Nur auf dem echten iPhone prüfbar

- Wischgefühl der Haupttabs und des Diagramm-Wischens (Finger, Geschwindigkeit, Einrasten).
- Chat-Eingabe mit echter Tastatur (inkl. Vorschlagsleiste, interaktives Ausblenden, Antwortvorschau).
- Sprachaufnahme (Mikrofon, Sperren, Abbrechen, Unterbrechung durch Anruf).
- Widget-Drag mit echtem Finger, Auto-Scroll, zweiter Finger.
- Speicherverlauf bei 50 Navigationswechseln und langen GIF-Chats (Debug-Navigator/Instruments).
- GIF-Suche mit echtem GIPHY-Schlüssel und Netz, Senden an ein zweites Gerät.
- Kalorienschätzung mit echten Health-Daten (mit und ohne Apple Watch).
- „Pace ist nicht mehr verfügbar“ (Profil-Ablauf nach 7 Tagen).
- Haptik, Light/Dark auf dem Gerät, kleine iPhones (SE) und große Schriftgrößen.

## 16.–19. Commit, Branch, Push, CI

| | |
|---|---|
| Branch | `claude/gallant-brahmagupta-hvvp13` (kein Pull Request) |
| Letzter geprüfter Code-Stand | **f839baa** – iOS-CI und Backend-CI grün (Lauf 40177357360 bzw. 40177357325) |
| Dieser Bericht | eigener Doku-Commit direkt danach |
| Push-Status | alles gepusht, keine lokalen Änderungen |
| Commits der Runde | fba78f0, aa00595, c539d99, 62113bb, 5557586, b6cd366, c1dbaae, 8e31541, 4d1ae40, 2fcb3bb, b2b47fe, bbc227d, f5ca08a, 62abc19, 83681c5, f839baa |

## 20. Kurze iPhone-Abnahme

1. Stand holen: `git pull origin claude/gallant-brahmagupta-hvvp13`, Xcode öffnen, Clean Build Folder, ▶ auf dem
   iPhone (Signing nicht ändern). Optional vorher `GIPHY_API_KEY` in `Config/Pace.xcconfig` eintragen.
2. P0 zuerst: Gruppe → Flamme → Chat 20× wechseln und ganz zurück; Tabs in beide Richtungen wischen und abbrechen;
   Chat-Eingabe mit Tastatur; 10 s Sprachaufnahme, gesperrt und verworfen; Widget langsam/schnell ziehen.
3. Danach: „+“-Menü (GIF, Profil teilen), Flammenseite und Flammenkalender, Statistik wischen, Widget-Inhalte,
   Kalorienschätzung, Einstellungen (sieben Kategorien), Anfragen-Symbol, Sprachen EN/RU.
4. Fehler mit Testfall-Nummer und Screenshot melden. Vollständige Liste: [IPHONE_TEST.md](IPHONE_TEST.md).
