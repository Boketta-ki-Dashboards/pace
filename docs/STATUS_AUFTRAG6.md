# Pace – Abschlussbericht Auftrag 6

Seitliche Verschiebung im Home-Anpassen-Modus, horizontale Überläufe, Profil- und Gruppenbilder, GIF-Restfehler,
Darstellungsauswahl, Social-Profil 2.0, Willkommensmitteilung und Pace-Bot.

**Ehrlicher Rahmen:** Geprüft wurde mit Unit-Tests (Linux), Simulator-Tests und Simulator-Screenshots in der CI
(GitHub Actions, macOS) sowie Datenbanktests in einer lokalen Docker-Supabase in der CI. **Auf einem echten iPhone
wurde in diesem Auftrag nichts getestet** – siehe Punkte 28 und 29. Die neue Migration ist **nicht** auf dem
Produktivprojekt ausgeführt.

## 1. Ausgangs-Commit und Branch

- Ausgangs-Commit: `bc02cf3` (Stand nach Auftrag 5)
- Branch: `claude/gallant-brahmagupta-hvvp13` (kein Pull Request, kein Force-Push)

## 2. Analyse des horizontalen Verschiebungsfehlers

Untersucht wurden `PaceTabPager` (Seitenleiste der vier Haupttabs), `MainTabView`, `HomeView`, `HomeEditChrome`,
`HomeReorderController` und die Scroll-Modifier der senkrechten Seiten.

- Im Anpassen-Modus sperrt `MainTabView` das Tab-Wischen (`isPagingEnabled = false` → `isScrollEnabled = false` der
  Seitenleiste). Das funktioniert: Im Test bewegt sich die Seitenleiste im Anpassen-Modus nie.
- Die senkrechte Scrollansicht von Home ist eine `UIScrollView` (SwiftUI `ScrollView`). Eine solche Scrollansicht
  lässt sich **auch waagerecht** verschieben, sobald ihr Inhalt nur minimal breiter ist als sie selbst oder sie
  waagerecht nachfedert. Im Simulator gemessen: iPhone SE – Scrollansicht 376 pt breit (Bildschirm 375 pt, Rundung in
  der Seitenleiste), Inhalt 375,5 pt; iPhone Pro Max – 430 pt bei 430 pt Inhalt.
- Im Anpassen-Modus wachsen Inhalte kurzzeitig über die Kartenbreite hinaus: Wackeln (Drehung um ±1°), angehobenes
  Widget beim Ziehen (Skalierung, Schatten), die X-Knöpfe zum Entfernen, die über die Kartenecke hinausragen. Jeder
  dieser Effekte kann den Inhalt für einen Moment breiter als die Scrollansicht machen.
- Wurde das Tab-Wischen gesperrt, während die Seitenleiste noch nicht eingerastet war (Anpassen tippen während einer
  auslaufenden Wischbewegung), blieb sie um einen Rest versetzt stehen.
- `HomeReorderController` erkannte „waagerechte Scrollansicht“ an „Inhalt > Breite + 1 pt“ – ein senkrechter Inhalt
  mit Rundungsüberhang wäre fälschlich als Seitenleiste behandelt worden.

## 3. Tatsächliche technische Ursache

Die Verschiebung entsteht in der **senkrechten Scrollansicht der Seite**, nicht in der Tab-Seitenleiste: Sie hatte weder
Richtungssperre noch eine Grenze für den waagerechten Versatz. Sobald ihr Inhalt (Rundung, Wackeln, angehobenes Widget,
X-Knöpfe) breiter war als sie selbst, folgte sie diagonalen und waagerechten Fingerbewegungen auch seitlich – die ganze
Seite wanderte, obwohl das Tab-Wischen gesperrt war. Verstärkend: eine beim Sperren nicht eingerastete Seitenleiste.

**Einschränkung:** Im Simulator ließ sich die Verschiebung mit den Testdaten **nicht** auslösen – auch nicht in der
Gegenprobe ohne Sperre (`diagnosisWithoutLock`, dort ist die Scrollansicht waagerecht unbeweglich). Die Ursache ist
daher aus Code und Messungen abgeleitet, nicht am Gerät beobachtet. Die Lösung setzt deshalb an allen Stellen an, über
die eine senkrechte Seite seitlich wandern kann.

## 4. Implementierte Lösung

- `paceVerticalScrollLock()` (`DesignSystem/Components/PaceVerticalScrollLock.swift`): ein unsichtbarer Marker im
  Inhalt jeder senkrechten Seite findet die umgebende `UIScrollView` und gibt ihr
  - Richtungssperre (`isDirectionalLockEnabled`): überwiegend senkrechte Bewegungen bleiben senkrecht,
  - kein waagerechtes Nachfedern (`alwaysBounceHorizontal = false`),
  - einen festen waagerechten Versatz: Ein Beobachter (KVO auf `contentOffset`/`contentSize`) setzt jede waagerechte
    Verschiebung sofort auf die Ruhelage zurück; die senkrechte Position bleibt.
- Die Tab-Seitenleiste meldet sich als bewusst waagerecht an (`PaceHorizontalScrollRegistrar`) und wird nie gesperrt;
  zusätzlich erkennt `PaceVerticalScrollLockRules.isPager` sie an mehreren Seiten Breite.
- `PaceTabPager`: Wird das Wischen gesperrt, rastet die Leiste ohne Animation genau auf der gewählten Seite ein –
  läuft gerade ein Gleiten zum gewählten Tab (Sprung in einen Tab mit Unterseite), erst danach (Review 1).
- `HomeView`: `.scrollBounceBehavior(.basedOnSize, axes: .horizontal)` und – nach Review 1 – der Inhalt ist mit
  `.containerRelativeFrame(.horizontal)` genau so breit wie die Scrollansicht. Damit kann ein einzelnes zu breites
  Element (im Simulator auf dem iPhone SE gemessen: 375,5 statt 375 pt im Anpassen-Modus) die Seite nicht mehr
  waagerecht verschiebbar machen – die Ursache selbst ist behoben, nicht nur das Symptom.
- Selbstschutz der Sperre (Review 1): Sie hält die Tab-Leiste nie fest, auch wenn ein falsch eingebauter Marker sie
  beobachtet, und löst eine solche Beobachtung wieder.
- `HomeReorderController` nutzt dieselbe Erkennung der Seitenleiste.
- Eingesetzt auf allen senkrechten Seiten: Tab-Wurzeln (`paceTabRoot`: Home, Rankings, Social, Profil), Galerie,
  Statistik, Kalender, Tagesdetails, Flammenkalender, Mitteilungen, Profil-Unterseiten (Einstellungen),
  Social-Unterseiten (Gruppe, Mitglieder, Gruppenkalender, fremdes Profil, Rankings-Unterseiten), Chatverlauf,
  Chat-Favoriten.
- Unverändert: Tab-Wischen außerhalb des Anpassen-Modus (Finger nach links → nächster Tab von rechts),
  Monats-/Zeitraumwechsel, Karussells, Zurück-Wischen vom linken Rand, Widget ziehen/Größe/Entfernen/Hinzufügen.

## 5. Ergebnis der Gestentests

Simulator (CI), `HorizontalDriftTests`: Fingerbewegungen werden so auf die Scrollansichten übertragen, wie UIKit sie
verteilt; danach wird an den Pixeln gemessen, wo Wortmarke, Überschrift, „Fertig“/„+ Widget hinzufügen“ und die
Widget-Ränder liegen (visuelle Position, nicht Tab-Index).

- `editModeStaysHorizontallyFixed` (iPhone SE und Pro Max): die zwölf Schritte des Auftrags – normal, Anpassen, langsam
  und schnell nach links/rechts, diagonal nach unten/oben, Widget verschieben/ablegen, Anpassen beenden, danach
  normales Tab-Wischen. Grün auf beiden Geräten (CI-Lauf zu `8d47dd0`); Protokoll: Home-Inhalt im Anpassen-Modus auf
  dem SE jetzt 375,0 pt bei 375,0 pt Seite (vorher 375,5 pt).
- `verticalPagesNeverDriftSideways`: Home, Statistik, Flammenkalender, Social, Gruppenchat – waagerecht und diagonal.
- `diagnosisWithoutLock`: Gegenprobe ohne Sperre (protokolliert die Scrollansichten mit genauen Maßen).
- `lockResetsHorizontalOffsetButNeverThePager` (nach Review 1): deterministisch – eine Seite mit 1 pt zu breitem
  Inhalt wird mit Sperre waagerecht sofort zurückgesetzt, ohne Sperre nicht (der Test erkennt also eine fehlende
  Sperre); ein falsch eingebauter Marker hält die Tab-Leiste nicht fest.
- Überlaufprüfung in normal und Anpassen: Der Inhalt der Home-Seite ist nicht breiter als die Seite.
- Ehrlich: Die Schritte 3–6 sind im Simulator ein Rauchtest – dort ist im Anpassen-Modus nichts waagerecht
  beweglich, auch ohne Sperre.
- Echte Berührungen lassen sich ohne eigenes UI-Test-Ziel nicht erzeugen; der Gerätetest steht aus
  ([IPHONE_TEST.md](IPHONE_TEST.md), Testfall A 1–13).

## 6. Analyse des Profilbildproblems

`PaceAvatar` hielt das geladene Foto in einem eigenen `@State` und lud per `.task(id: image)`:

- SwiftUI verwendet Ansichten in Listen wieder. Beim Wechsel des Verweises (andere Person in derselben Zeile, neues
  Profilbild) blieb das **alte Foto stehen**, bis das neue geladen war – oder dauerhaft, wenn das neue fehlschlug.
- Ein Download wurde beim Wechsel nicht verworfen: Kam der Download des **vorherigen** Verweises später an, schrieb er
  `photo` trotzdem – die Zeile zeigte die falsche Person.
- Der Speicher wurde nur nach Verweis, nicht nach Größe angefragt; die Aufgabe startete bei geänderter Größe nicht neu.
- Das Freunde-Ranking im Social-Tab übergab das Profilbild gar nicht an seine Zeilen und zeigte immer Initialen
  (im Vorschaubild aufgefallen, behoben in `bd0ae18`); Home-Widget, regionale Rankings und Gruppenranking übergeben
  es.

## 7. Analyse des Gruppenbildproblems

Gruppenbilder laufen über dieselben Ansichten (`PaceAvatar` in Listen und Widgets, `PaceRemoteImage` in der
Gruppeninfo). `PaceRemoteImage` hatte dieselben Schwächen und zusätzlich: Wurde der Verweis `nil` (Bild entfernt),
blieb das alte Bild stehen; ein einmal gesetztes `failed` wurde erst durch einen Erfolg zurückgesetzt, ein Wiederholen
gab es nicht. Beim schnellen Wechsel zwischen Gruppen konnte kurz das Bild der vorigen Gruppe erscheinen.

## 8. Änderungen am Image Loader

- Neuer Baustein `MediaSlot` (`PaceCore/Media/MediaSlot.swift`): Ein Ergebnis gilt nur für den Verweis, für den es
  geladen wurde. `show(_:)` verwirft beim Wechsel sofort das alte Bild (Platzhalter statt fremdem Bild),
  `deliver(_:for:)` ignoriert verspätete Ergebnisse früherer Verweise, ein Fehlschlag gilt nur für seinen Verweis,
  `retry()` setzt ihn zurück.
- `PaceAvatar`, `PaceRemoteImage` und `ChatMediaImage` nutzen `MediaSlot`, laden per `.task(id:)` mit Verweis **und**
  Größe und verwerfen Ergebnisse abgebrochener Aufgaben. `PaceRemoteImage` und Chatmedien haben „Erneut versuchen“.
- Unverändert und bestätigt: `PaceImageLoader` lädt jede Datei nur einmal (geteilte Downloads), hält komprimierte Daten
  (32 MB) und dekodierte Bilder (96 MB) in `NSCache` mit Kostenbegrenzung und dekodiert in Anzeigegröße.
- Cache-Invalidierung: Storage-Pfade sind je Upload eindeutig (`<ordner>/<uuid>.<ext>`, nie überschrieben) – ein
  geändertes Bild hat immer einen neuen Verweis, der Speicher liefert nie ein veraltetes Bild unter einem neuen Verweis.
- Tests: `MediaSlotTests` (5, Linux), `ImageLoadingTests` (5, Simulator: ein Download je Datei, Offline aus dem
  Speicher und Wiederholen, verspäteter Download, Fehlschlag mit Initialen und geteiltem Laden, Gruppenbildwechsel).

## 9. Prüfung der GIF-Darstellung

- GIFs und Fotos im Chat (`ChatMediaImage`) laden über denselben Lader und `MediaSlot`: kein Bild aus einem anderen
  Chat nach dem Wechsel, ein Download je Datei, nach dem Neustart erneut aus Storage, bei Fehlschlag „Erneut
  versuchen“; beim Verschwinden wird der Platz freigegeben.
- Keine externen GIF-URLs als Ersatz: GIFs werden weiter in den Bucket `chat-media` hochgeladen. Der GIPHY-Schlüssel
  bleibt in der lokalen `Config/Pace.xcconfig` (nicht im Repository).
- Bestehende Tests der GIF-Dekodierung (`ImageDecodingTests`: Einzelbilder, Ausdünnen langer GIFs, Größenbegrenzung)
  laufen unverändert grün.

## 10. Neue Darstellungsauswahl

Profil → Darstellung: `AppearanceSelector` mit drei Kacheln und Symbolen – Automatisch (Sonne und Mond zusammen,
nach Review 3; vorher ein Halbkreis), Hell (`sun.max`/`sun.max.fill`), Dunkel (`moon`/`moon.fill`). Die gewählte Kachel ist mint hervorgehoben
(`PaceColor.selectionFill`, bestehende Farben). Eine gemeinsame Quelle (`AppearancePreference`), dieselbe Auswahl im
Profil-Überblick (ohne Titel) und auf der Unterseite. VoiceOver liest Namen und Auswahlzustand.

## 11. Profilbanner

Optional. Fotoauswahl von iOS (`PhotosPicker`, nur einzelne Fotos), Zuschnitt 3:1 mit Verschieben/Schieberegler
(`BannerCropSheet`), Verkleinern auf höchstens 1500 px Breite, JPEG ≤ 5 MB (`BannerImageProcessing`). Hochladen in den
eigenen Ordner des bestehenden Buckets `avatars` über die bestehende Medienarchitektur; das vorige Banner wird nach
dem Speichern gelöscht – erst wenn der Server den neuen Pfad bestätigt hat (Review 2) –, ein Upload bei
fehlgeschlagenem Speichern wieder entfernt (geht nur die Antwort verloren, prüft die App vorher den Serverstand).
Speichern und Banner-Änderungen laufen nacheinander, nie gleichzeitig (Review 2: sonst überschrieben sich die
Anfragen). Ändern und Entfernen möglich; ohne
Banner ein neutraler Pace-Verlauf. Lesen nur über die bestehende Storage-Policy (`pace_access.can_read_avatar`, beachtet
Blockierungen) – keine Umgehung.

## 12. Bio

Bis 160 Zeichen mit Zähler („x/160“), höchstens 4 Zeilen, Emojis erlaubt, keine Steuer- oder unsichtbaren Zeichen
(`ProfileBioRules`; dieselben Regeln als Prüfregel in der Datenbank). Kein HTML/Markdown: Anzeige als reiner Text
(`Text(verbatim:)`). Hinzufügen, Ändern, Entfernen.

## 13. Interessen

Bis zu 5 aus einem festen Katalog mit stabilen IDs (`ProfileInterest`: walking, running, hiking, fitness, cycling,
football, outdoor, everyday_movement, challenges, wellbeing), Titel und Symbole in DE/EN/RU. Nach 5 sind weitere
Chips deaktiviert, bis eines abgewählt wird. Datenbank prüft Katalog, Anzahl und Doppelte.

## 14. Auszeichnungen

Freiwillig, standardmäßig aus. Nur echte Werte aus der bestehenden Serie und dem besten Tag (`ProfileAchievement.earned`
aus `StepStreakTracker` und dem Bewegungsverlauf – keine zweite Statistik-Architektur). Je Art nur die höchste Stufe:
Serie 7/30/100/365 Tage, bester Tag ab 10.000/20.000/30.000 Schritten („Tag mit 10.000+ Schritten“). Keine genauen
Schrittzahlen. Veröffentlicht werden nur erreichte Stufen, und zwar nur aufwertend (`ProfileAchievement.upgraded`):
Eine schon veröffentlichte höhere Stufe – etwa ein Bestwert außerhalb des geladenen Verlaufs – geht nie verloren;
neu erreichte Stufen trägt die App beim Öffnen des Profils nach (Review 2/3). Der Hinweis nennt, wer sie sieht: alle,
die das Profil sehen dürfen. Ausgeschaltet zeigt das fremde Profil keine.

## 15. Änderungen an eigenen und fremden Profilen

- Gemeinsamer Aufbau `PaceProfileShowcase`: Banner, überlappendes Profilbild, Name, @Benutzername, Bio, Interessen,
  freigegebene Auszeichnungen; darunter die bisherigen Angaben.
- Eigenes Profil: „Bearbeiten“ (VoiceOver „Profil bearbeiten“; der lange Text war auf dem Simulatorbild in DE und
  RU abgeschnitten) und Teilen neben dem Profilbild; neue Seite `ProfileEditPage`. Sie zeigt sofort den bekannten
  Stand (nie leere Felder, „Speichern“ ohne Änderung aus), lädt dann neu und übernimmt den Serverstand nur, solange
  nichts geändert wurde; Eingaben bleiben auch beim Wechsel zu „Profilbild & Namen“ und zurück. Ladeanzeige, Fehler
  mit „Erneut versuchen“, Bestätigung „Gespeichert“ (Review 1–3).
- Fremdes Profil: alle bisherigen Aktionen bleiben (Anfrage senden/annehmen, Nachricht, Spitzname, Teilen,
  Blockieren, Melden). Bei Blockierung durch mich zeigt die App keine Angaben; der Server liefert bei Blockierung in
  beiden Richtungen leere Angaben.
- Alte Profile und Server ohne Migration: Profil wie bisher, ohne Lücken und ohne Fehlermeldung (`.unavailable`).

## 16. Willkommensmitteilung

`SystemMessageCenter` (PaceCore): legt „Willkommen bei Pace! 👋“ von „Pace Team“ genau einmal je Profil an – nach dem
Einstieg bzw. für bestehende Nutzer einmalig nach dem Update; kein zweites Mal bei Neustart, Tabwechsel oder neuen
Schritten. Lokal (UserDefaults `pace.systemMessages.<public_id>`), keine Push-Nachricht, kein Server. In der Glocke
mit Vorschautext; Öffnen markiert gelesen (Zähler stimmt), Löschen per Kontextmenü/VoiceOver-Aktion – kommt nicht
wieder. Detailseite mit acht Abschnitten (Schritte, Ziele, Rankings, Freunde, Gruppen, Flamme, Home, Hilfe) und den
Buttons „Home entdecken“ (zurück zu Home), „Rankings ansehen“, „Freunde hinzufügen“ (Social → Freund hinzufügen),
„Pace-Bot öffnen“ – keine toten Links. DE/EN/RU. Lokale Daten mit Präfix `pace.` sind in Export (mit lesbaren Namen) und Löschen enthalten. Der Kurztext
(„… und starte gemeinsame Challenges“) und die Texte der Abschnitte stammen wörtlich aus dem Auftrag; Review 3
merkt an, dass es Challenges in der App noch nicht gibt (Entscheidung beim Auftraggeber, siehe Punkt 26).

## 17. Pace-Bot

Fester Eintrag oben in der Chatliste (`PaceBotChatRow`, Kennzeichen „Automatisch“, kein Ungelesen-Zähler) und als
eigene Karte, solange Social lädt, offline ist oder einen Fehler zeigt (Review 3).
Messenger-Stil: Bot links, eigene Fragen rechts. **Keine KI, keine externen Server, keine Kosten** – keine OpenAI-,
Claude- oder Gemini-API. Begrüßung, Fragenliste zum Antippen – danach stehen Frage und Antwort oben im Bild
(Review 3: vorher scrollte die Ansicht ans Ende der Fragenliste) –, „Weitere Frage“ zurück zur Übersicht, freie
Eingabe (≤ 200 Zeichen) mit einfacher Stichwortsuche: Stichwörter treffen nur Wortanfänge, mit festen Vorrängen und
Ausschlüssen (jede eigene Frage trifft in allen drei Sprachen ihr Thema; „delete my account“, „hello“, „Gruppe
verlassen“ bekommen keine falsche Antwort). Ist die Zuordnung nicht eindeutig: „Dazu habe ich leider noch keine passende
Antwort …“ mit Hilfe-Angebot. Verlauf nur auf dem Gerät (`pace.helpBot.history`, höchstens 60 Nachrichten,
zurücksetzbar); gespeichert werden Themen, nicht Texte – ein Sprachwechsel übersetzt auch den Verlauf. Keine
Supabase-Tabelle, kein Realtime, keine Identität. Funktioniert offline (Einstieg über die Karte im Social-Tab oder
die Willkommensmitteilung). Zurücksetzen über einen Knopf mit Rückfrage.

## 18. FAQ-Inhalte

15 Themen (`PaceHelpTopic`, DE/EN/RU): Wie Pace funktioniert, Wie Schritte gezählt werden, Warum Schritte nicht sofort
übereinstimmen, Rankings, Flamme, Gruppenflamme, Freunde hinzufügen, Gruppe erstellen, Home anpassen, Tagesziel,
Profil bearbeiten, Privatsphäre, Sprache und Design, Nutzer melden, Fehler melden. Pfade und Bezeichnungen wie in der
App („Sichtbarkeit in Rankings“, „Freundschaftsanfragen“, „Einladungscode“, „Nutzer melden“, Profil → Daten, Hilfe &
Rechtliches → Hilfe & Feedback → „Problem melden“; Review 3). Die Datenschutzantwort sagte fälschlich „Deine Schritte
sehen nur deine Freunde“ (Review 3, hoch) und nennt jetzt Freunde, Mitglieder deiner Gruppen und – nur wenn
eingeschaltet – andere in den Rankings deiner Regionen. Mit Tests abgesicherte Fakten:
Gruppenflamme = mindestens ein Drittel der Mitglieder, aufgerundet; Rankings zählen nur bestätigte
Wettbewerbsschritte aus Apple Health, von Hand eingetragene Schritte zählen nicht; die Live-Anzeige ist vorläufig,
bestätigt Apple Health weniger, gilt etwa 20 Minuten nach dem letzten Schritt der Health-Wert.

## 19. Support-Verhalten

Im Repository gibt es **keine offizielle Support-Adresse** – es wurde keine erfunden. „Hilfe kontaktieren“ öffnet die
bestehende Rückmeldung „Problem melden“ (Einstellungen → Feedback). Die Karte sagt ehrlich, dass die Nachricht dort mit
Konto und App-Version gespeichert wird und eine persönliche Antwort derzeit nicht möglich ist (Review 3; vorher hieß
es „Es wird nur gesendet, was du selbst schreibst“). Ohne Adresse erscheint auch kein Hinweis auf eine fehlende
Konfiguration. Die Rückfallantwort („… oder unser Support-Team kontaktieren“) ist wörtlich aus dem Auftrag. Eine E-Mail-Option erscheint nur, wenn
`PACE_SUPPORT_EMAIL` in der lokalen `Config/Pace.xcconfig` gesetzt ist (Info.plist-Schlüssel `PaceSupportEmail` über
`Config/Info.plist`, Platzhalter in `Pace.xcconfig.example`; Plausibilitätsprüfung, unaufgelöste `$(…)`-Werte zählen
nicht). Die Vorlage („Pace – Supportanfrage“, „[Hier Problem beschreiben]“) enthält keine Kennungen oder
Gesundheitsdaten und wird nie automatisch gesendet.

## 20. Sicherheits- und Datenschutzprüfung

- Keine Secrets im Repository; `Config/Pace.xcconfig` unverändert und nicht committed; kein `service_role`-Key.
- Keine Änderungen an Xcode-Projekt, Bundle Identifier, Entitlements, HealthKit-Berechtigungen, GIPHY- oder
  Supabase-Konfiguration; einziger neuer Info.plist-Schlüssel `PaceSupportEmail` über `Config/Info.plist`.
- Anonyme Identität und Auth-Sitzung unverändert, keine neue Anmeldung.
- Pace Life und das Boketta-KI-Website-Projekt wurden nicht berührt.
- Datenbank: neue Spalten nur über Spaltenrecht `update` des eigenen Profils (RLS unverändert), Prüfregeln und
  Trigger gegen ungültige Werte, RPC nur für `authenticated` mit Rate Limit, gleiche Sichtbarkeit wie das öffentliche
  Profil, leere Angaben bei Blockierung, Auszeichnungen nur bei Freigabe. Storage: keine neue Policy; die Lese-Funktion
  für Profilbilder liest zusätzlich nur das **aktuelle** Banner und beachtet Blockierungen.
- Bio als reiner Text (kein HTML); Banner nur JPEG im eigenen Ordner.
- Moderation (Review 2): Eine Meldung einer Person sichert Bio, Interessen und Banner im Schnappschuss; das
  gemeldete Banner ist bis zur Moderation vor dem Löschen geschützt (wie gemeldete Profilbilder).
- Pace-Bot und Willkommensmitteilung ohne Netzwerk; die Support-Mail sendet nichts automatisch.

## 21. Neue Migrationen

`supabase/migrations/20261030100000_profile_details.sql` – additiv, rückwärtskompatibel, **nicht ausgeführt**. Inhalt:
neue Profilspalten mit Prüfregeln und Triggern, `social_profile_details`, Banner in `can_read_avatar`, `social_report`
mit Bio/Interessen/Banner im Schnappschuss, Banner in `is_report_evidence` (gleiche Signaturen, `create or replace`),
Teilindex `reports_banner_evidence_idx`. Tests: `supabase/tests/17_profile_details.test.sql` (35 Prüfungen),
`06_social_friends.test.sql` angepasst (37 RPCs). Details
und Rollout: [SUPABASE_ROLLOUT.md](SUPABASE_ROLLOUT.md), Abschnitt „Auftrag 6“.

## 22. Bereits vorhandene Migrationen, die unverändert bleiben

Alle bisherigen Migrationen bis einschließlich `20261023100200_group_calendar.sql` (u. a. `20261016100000`–
`20261016100500`, `20261018100000_social.sql`, `20261019100000`–`20261019100400`, `20261023100000`,
`20261023100100`) sind unverändert und werden nicht erneut ausgeführt. Kein `db reset`, kein `db push`, kein
`supabase link` durch mich.

## 23. Zahl der erfolgreichen Tests

| Ebene | Ergebnis (letzter Code-Commit `bd0ae18`) |
|---|---|
| Swift-Unit-Tests unter Linux (PaceCore, ViewModels, Backend-Mapping; SwiftUI/UIKit ausgenommen) | **922 Tests in 123 Suiten grün** (vorher 913; neu u. a. `MediaSlotTests`, `SystemMessageCenterTests`, `PaceHelpBotTests`, `ProfileDetailsTests`, `WelcomeNotificationTests`, `HelpBotAndProfileDetailsTests`) |
| iOS-Simulator in der CI (alle Testziele, inkl. Snapshot- und Fenstertests) | **1144 Tests grün** (größte Ziele: 273 in 38 Suiten, 209 in 28, 157 in 29, 114 in 16, 102 in 11, 90 in 9, 83 in 14 Snapshot-Suiten) |
| Datenbank (pgTAP in Docker-Supabase, CI) | 17 Dateien, **1000 Prüfungen grün** (davon `17_profile_details` 35), `db lint` ohne Fehler, Advisors ohne Warnungen |
| Backend-Integration (Swift unter Linux gegen lokale Supabase) | 21 Tests in 5 Suiten grün |

Neue Tests in Auftrag 6 (Auswahl): Drift im Anpassen-Modus auf iPhone SE und Pro Max mit Pixelmessung, Überlaufprüfung,
deterministische Prüfung der Sperre mit Gegenprobe, Bildlader und Avatar-Wechsel (spät ankommender Download,
Fehlschlag, geteilte Downloads, Gruppenbild), Willkommensmitteilung (einmal, gelesen, gelöscht, je Konto), Pace-Bot
(alle Fragen in DE/EN/RU, Stichwörter, Datenschutzantwort, Verlauf), Profil 2.0 (Regeln, Entwürfe, Schreibreihenfolge,
Auszeichnungen), pgTAP für Spalten, Regeln, Sichtbarkeit, Blockierung und Meldeschutz.

## 24. Fehlgeschlagene Tests und deren Ursachen

Alle Fehlschläge in der CI dieses Auftrags, mit Ursache und Behebung:

| Commit | Was | Ursache | Behebung |
|---|---|---|---|
| `5863320` | iOS-Build | Compiler-Warnung (`nonisolated(unsafe)` unnötig) – die CI bricht bei jeder Warnung ab | `2995592` |
| `2995592` | `HorizontalDriftTests` (iPhone SE), `ImageLoadingTests` | Messartefakte (Zeilenränder mit X-Knöpfen), Messpunkt im Bild | Medianmessung, Messpunkt oben (`ef63352`) |
| `ef63352` | `HorizontalDriftTests` (SE), `ImageLoadingTests.failedDownload…`, 4 Test-Warnungen | Weiße Karten (#FFFFFF) lagen auf #F8F9F7 unter der Erkennungsschwelle – gemessen wurde Karteninhalt; der Bildtest brauchte bei parallel laufenden Suiten 31 s statt 6 s | Spaltenprofil über Kartenflächen, Frist 30 s, Warnungen behoben (`a456590`) |
| `a456590` | `HorizontalDriftTests` (SE) „nach dem Verschieben“ | Rechter Rand hängt nach dem Umsortieren von den sichtbaren Widgets ab; der linke Rand blieb stehen (keine Verschiebung) | nur linker Rand + Kopfzeile, Überlaufprüfung (`8d47dd0`) |
| `8d47dd0` | pgTAP `14_friend_nicknames`, Test 40 | Test erwartete den Meldeschnappschuss ohne die neuen Felder Bio/Interessen/Banner | Test vergleicht ohne diese Felder (die prüft Test 17), letzter Commit |

Keine Fehlschläge in den Läufen zu `8d47dd0` (iOS) und `bd0ae18` (iOS und Backend). Der Lauf zu `de73a8e` wurde
durch den Push von `bd0ae18` abgebrochen (gleiche Concurrency-Gruppe).

## 25. Ergebnisse unabhängiger Reviews

Drei unabhängige Reviews (eigene Agenten, nur lesend, je mit eigenem Schwerpunkt) über `bc02cf3..a456590`. Alle
Befunde der Stufen **hoch** und **mittel** sind in `8d47dd0` behoben oder begründet nicht übernommen; die niedrigen
sind behoben oder unter Punkt 26 dokumentiert.

**Review 1 – Navigation und UI** (0 hoch, 5 mittel, 8 niedrig; Einbau der Sperre an allen 15 Stellen korrekt)

| Befund | Ergebnis |
|---|---|
| M1 Sperre heilt sich nicht selbst, wenn sie die Tab-Leiste erwischt | behoben: `pin` hält die Leiste nie fest, `attach` löst eine solche Beobachtung |
| M2 Einrasten bricht ein laufendes Gleiten zum Ziel-Tab ab | behoben: während eines Gleitens zum gewählten Tab erst danach einrasten |
| M3 „Profil bearbeiten“ überschreibt Entwürfe | behoben: `prepareEditing` (siehe Punkt 15) |
| M4 Drift-Test prüft die Sperre nicht deterministisch | behoben: `lockResetsHorizontalOffsetButNeverThePager` mit Gegenprobe; Schritte 3–6 als Rauchtest gekennzeichnet |
| M5 Toleranzen verdecken den 0,5-pt-Überlauf, Kommentar „Rundung im Pager“ falsch | behoben: Home-Inhalt `containerRelativeFrame`, Überlaufprüfung, Toleranz 0,01 pt, genaue Maße im Protokoll, Kommentar korrigiert |
| Nachtrag: CI rot bei a456590 (Drift nach dem Umsortieren, rechter Rand) | behoben: nach Umsortieren und senkrechtem Scrollen nur linker Rand (eine Verschiebung bewegt ihn immer), dafür Kopfzeile wieder verglichen |
| N3 Banner ragt unter den Rand | behoben (`.clipped()` an der Bannerhöhe) |
| N4 Knopf abgeschnitten | behoben (siehe Review 3 M8) |
| N5 Tastatur bleibt beim Wechsel zu „Problem melden“ offen | behoben (Fokus vorher abgeben) |
| N7 Fenster nicht per `defer` geschlossen | behoben |
| N8 `systemMessage(kind)` ignoriert `kind` | behoben (Verzweigung nach Art) |
| N1, N2, N6 | Punkt 26 |

**Review 2 – Bilder und Backend** (0 hoch, 4 mittel, 11 niedrig; keine Datenschutzlücke; Bildansichten, Migration,
Grants, RLS und pgTAP ohne Befund)

| Befund | Ergebnis |
|---|---|
| M1 Speichern und Banner-Upload parallel → verlorene Bio bzw. Banner auf gelöschter Datei | behoben: Schreibvorgänge nacheinander (`isBusy`), altes Banner erst nach Bestätigung löschen, Test `writesRunOneAfterAnother` |
| M2 Meldungen sichern Bio und Banner nicht | behoben in der (nicht ausgeführten) Migration: Schnappschuss mit Bio/Interessen/Banner, Banner als Beweis geschützt, 3 neue pgTAP-Prüfungen |
| M3 Bildtest rot | Ursache: Zeitlimit bei parallel laufenden Snapshot-Suiten (der Test brauchte 31 s); Frist 30 s, seit a456590 grün |
| M4 Entwurf erst nach dem Laden gesetzt, „Speichern“ vorher aktiv | behoben: `prepareEditing`, Test `editingStartsFromKnownStateAndKeepsTypingDuringReload` |
| N1 Auszeichnungen veralten oder verlieren eine Stufe | behoben (nur aufwerten, automatisch nachtragen), Test `publishedAchievementsAreOnlyUpgraded` |
| N2 Abbruch als Netzfehler gemeldet | behoben (`isCancellation` im Repository) |
| N3 Aufräumen bei verlorener Antwort | behoben (Serverstand prüfen, bevor die neue Datei gelöscht wird) |
| N5 Hinweistext nennt die Zielgruppe nicht | behoben („Sichtbar für alle, die dein Profil sehen können“) |
| N4, N6–N11 | Punkt 26 |

**Review 3 – Produkt und neue Funktionen** (2 hoch, 10 mittel, 20 niedrig)

| Befund | Ergebnis |
|---|---|
| H1 Pace-Bot: falsche Datenschutzauskunft | behoben, Test `privacyAnswerNamesEveryoneWhoSeesSteps` |
| H2 Antwort nach dem Antippen nicht im Bild | behoben: Scrollen zur neuen Frage, Auslöser letzte Nachricht statt Anzahl; zusätzliches Fensterbild `a6-bot-answer-screen` |
| M1 „Automatisch“ ohne Sonne/Mond | behoben (zusammengesetztes Symbol) |
| M2 Bot ohne geladenes Social nicht erreichbar | behoben (Karte bei Laden, Fehler, ohne Backend) |
| M3 Stichworterkennung ordnet falsch zu | behoben: Wortanfänge, Vorränge, Ausschlüsse; Test `ownQuestionsMatchTheirTopicAndUnrelatedInputGetsNoAnswer` |
| M4 Pfade und Bezeichnungen weichen von der App ab | behoben (alle sieben Stellen, DE/EN/RU) |
| M5 Support-Hinweise wecken falsche Erwartungen | behoben (ehrliche Datenschutzangabe, kein Konfigurationshinweis); die Rückfallantwort bleibt wörtlich wie im Auftrag |
| M6 Lade- und Fehlerzustand in „Profil bearbeiten“ | behoben |
| M7 Ungespeicherte Änderungen gehen verloren | behoben (Entwurf bleibt, „Gespeichert“); eine Rückfrage beim Verlassen fehlt (Punkt 26) |
| M8 Knopf „Profil bearbeiten“ abgeschnitten | im Simulatorbild bestätigt („Profil bear…“, „Редактир…“), behoben: „Bearbeiten“/„Edit“/«Изменить», VoiceOver mit vollem Text, Profilbild-Größe begrenzt |
| M9 Auszeichnungen nie nachgetragen | behoben (siehe Review 2 N1) |
| M10 Kurztext verspricht „gemeinsame Challenges“ | nicht geändert: Wortlaut aus dem Auftrag – Entscheidung beim Auftraggeber (Punkt 26) |
| Niedrig behoben | N3 (Datum der Willkommensmitteilung in App-Sprache, `bd0ae18`), N7 (RU „Главная“ statt „главный экран“, Frage „Wie passe ich Home an?“), N8 (Bot-Name lokalisiert), N9 (RU-Kennzeichen „Бот“, EN „Frequently asked questions“), N10 („10.000+“, Hinweistext), N12 (kein Server-Jargon), N15 (lesbare Exportnamen), N17 (RU-Feinschliff), N18 (VoiceOver-Hinweis bei deaktivierten Interessen), RU „в своём регионе“ |
| Niedrig offen | Punkt 26 |

## 26. Noch offene Probleme

- **Gerätetest der seitlichen Verschiebung steht aus.** Im Simulator trat sie nicht auf; behoben sind der gemessene
  Überlauf (375,5 pt) und alle Wege, über die eine senkrechte Seite seitlich wandern kann. Bestätigt ist das erst mit
  IPHONE_TEST A 1–13.
- **Migration nicht eingespielt:** Bis zur Freigabe zeigt die App Profil 2.0 nur als „steht bald zur Verfügung“.
- **Keine offizielle Support-Adresse** im Repository: Der Bot bietet nur „Problem melden“ an, bis `PACE_SUPPORT_EMAIL`
  gesetzt ist.
- **Wortlaut aus dem Auftrag** (Review 3 M10, N6): Der Kurztext der Willkommensmitteilung nennt „gemeinsame
  Challenges“, die es in der App noch nicht gibt; die Abschnitte wechseln zwischen „du“ und „ihr“. Bewusst
  unverändert übernommen – bitte entscheiden, ob der Text angepasst werden soll.
- **Interesse „Spazieren“** (Review 3 N11) heißt wie im Auftrag; „Spazierengehen“ wäre geläufiger.
- **Leicht, nicht behoben:**
  - Keine Rückfrage beim Verlassen von „Profil bearbeiten“ mit ungespeicherten Änderungen (R3 M7, Teil).
  - Die Sperre verdeckt einen künftigen Überlauf auf anderen Seiten nur; dort hilft die neue Überlaufprüfung bisher nur für Home (R1 N1).
  - Kein erneuter Anhängeversuch, wenn die Breite beim Anhängen 0 bleibt (R1 N2, Vermutung).
  - Links aus der Willkommensmitteilung ersetzen den Social-Stapel und lassen Home auf der Detailseite stehen (R1 N6, R3 N4).
  - Banner-Foto wird in voller Auflösung auf dem Main Thread dekodiert (R2 N4).
  - Auszeichnungen sind Selbstauskunft des Clients, der Server prüft nur den Katalog (R2 N5, R3 N20) – Produktentscheidung.
  - Eigenes Rate-Limit für `social_profile_details` (R2 N6); U+2028/U+2029 in der Bio und Flaggen-Emojis (R2 N7).
  - Kleines Doppel-Download-Fenster im Bildlader, schon vor Auftrag 6 (R2 N8); Retry-Symbol während des automatischen Nachladens, verschachtelter Retry-Knopf im Chat (R2 N9, N10).
  - Fehlende negative pgTAP-Fälle für Banner (blockiert, altes Banner, Bucket-Liste) (R2 N11).
  - Mitteilungsliste: Absender nur als Initialen, ungelesen nur über Deckkraft; Hinweis „nicht verfügbar“ verschwindet neben der Willkommensmitteilung (R3 N1, N2, N5).
  - Echter Name bei Spitznamen unter der Profilkarte; Banner-Verlauf im Dunkelmodus kräftig; Bot-Verlauf nicht kontogebunden; Auszeichnungen werden bei jeder Eingabe neu berechnet; gemischte Speicherlogik Banner/Bio (R3 N13–N16, N19).

## 27. Screenshots mit Links

Index mit allen Bildern (Hell/Dunkel, wichtige Ansichten zusätzlich EN/RU):
**[docs/previews/auftrag6/README.md](previews/auftrag6/README.md)** – 71 PNG-Dateien, alle 24 Pflichtansichten.
**Simulator-Bilder aus der CI (Commit `bd0ae18`), keine iPhone-Aufnahmen**, mit Beispieldaten und gezeichneten
Beispielbildern.

| Nr. | Ansicht | Hell |
|---|---|---|
| 1 | Home normal | [01-home-light.png](previews/auftrag6/01-home-light.png) |
| 2 | Home im Anpassen-Modus | [02-home-anpassen-light.png](previews/auftrag6/02-home-anpassen-light.png) |
| 3 | Nach seitlichem Versatz mit Sperre / Vergleich ohne Sperre | [03-home-anpassen-nach-wischen-light.png](previews/auftrag6/03-home-anpassen-nach-wischen-light.png) · [03-vergleich-ohne-sperre-light.png](previews/auftrag6/03-vergleich-ohne-sperre-light.png) |
| 4 | Widget verschieben | [04-widget-verschieben-light.png](previews/auftrag6/04-widget-verschieben-light.png) |
| 5–8 | Profilbild Home, Freunde-Ranking, Gruppenbild Widget und Gruppeninfo | [05](previews/auftrag6/05-profilbild-home-light.png) · [06](previews/auftrag6/06-profilbild-freunde-ranking-light.png) · [07](previews/auftrag6/07-gruppenbild-widget-light.png) · [08](previews/auftrag6/08-gruppenbild-gruppeninfo-light.png) |
| 9–10 | Eigenes Profil mit / ohne Banner | [09](previews/auftrag6/09-eigenes-profil-mit-banner-light.png) · [09 RU](previews/auftrag6/09-eigenes-profil-mit-banner-ru-light.png) · [10](previews/auftrag6/10-eigenes-profil-ohne-banner-light.png) |
| 11–13 | Profil bearbeiten, Bio, Interessen | [11](previews/auftrag6/11-profil-bearbeiten-light.png) · [12](previews/auftrag6/12-bio-bearbeiten-light.png) · [13](previews/auftrag6/13-interessen-light.png) |
| 14–15 | Fremdes Profil, Profil mit Auszeichnungen | [14](previews/auftrag6/14-fremdes-profil-light.png) · [15](previews/auftrag6/15-profil-mit-auszeichnungen-light.png) |
| 16 | Darstellungsauswahl | [16](previews/auftrag6/16-darstellung-light.png) |
| 17–18 | Mitteilungscenter, geöffnete Willkommensmitteilung | [17](previews/auftrag6/17-mitteilungen-willkommen-light.png) · [18](previews/auftrag6/18-willkommen-geoeffnet-light.png) |
| 19–24 | Chatliste mit Bot, Begrüßung, Frage, Antwort (Seite und Bildschirm), unbekannte Frage, Support | [19](previews/auftrag6/19-chatliste-pace-bot-light.png) · [20](previews/auftrag6/20-bot-begruessung-light.png) · [21](previews/auftrag6/21-bot-frage-light.png) · [22](previews/auftrag6/22-bot-antwort-light.png) · [22 Bildschirm](previews/auftrag6/22-bot-antwort-bildschirm-light.png) · [23](previews/auftrag6/23-bot-unbekannt-light.png) · [24](previews/auftrag6/24-bot-support-light.png) |

Visuelle Prüfung (am Bild): Der Knopf „Profil bearbeiten“ war in DE und RU abgeschnitten, das Freunde-Ranking zeigte
keine Profilbilder, das Datum der Willkommensmitteilung stand auf Englisch, im Bot-Kopf stand ein Platzhalter für
das Menü – alles behoben, in den Bildern zu `bd0ae18` korrekt. Keine überlappenden Texte, keine Statusleisten-Kollision,
kein waagerechter Überlauf. Bekannt: Im Bild 3 mit Sperre fehlt unten ein Teil der Seite – ein Darstellungsfehler der
Nachstellung im Snapshot-Renderer (die Seite steht an derselben Stelle wie in Bild 2).

## 28. Tatsächlich auf Gerät getestete Funktionen

**Keine.** In diesem Auftrag stand kein iPhone zur Verfügung. Alle Ergebnisse stammen aus Unit-Tests, Simulator-Tests
und Simulator-Screenshots in der CI.

## 29. Noch ausstehende echte iPhone-Tests

Alles aus [IPHONE_TEST.md](IPHONE_TEST.md), vor allem:

- A 1–13: keine seitliche Verschiebung im Anpassen-Modus und auf allen senkrechten Seiten (im Simulator nicht
  reproduzierbar – erst der Gerätetest bestätigt die Behebung), Tab-Wischen danach normal.
- B 14–21: Profil- und Gruppenbilder in schnell gescrollten Listen, nach Änderungen, im Flugmodus; Chatmedien nach
  Chatwechsel und Neustart.
- C 22–23: Darstellungsauswahl mit VoiceOver.
- D 24–32: Profil 2.0 mit zwei Konten (erst nach eingespielter Migration).
- E 33–37 und F 38–46: Willkommensmitteilung und Pace-Bot (inkl. offline, DE/EN/RU).
- G 47–50: Regressionen (Live-Schritte mit 20-Minuten-Regel, keine Gruppe→Flamme→Chat-Schleife, Tab-Wischen, Widgets).

## 30. Letzter Code-Commit

`bd0ae18` – „Freunde-Ranking zeigt Profilbilder, Datum der Willkommensmitteilung in App-Sprache“. Davor in diesem
Auftrag: `5863320`, `2995592`, `ef63352`, `a456590`, `8d47dd0`, `de73a8e`.

## 31. Letzter Dokumentations-Commit

Der Commit mit diesem Bericht und den Vorschaubildern („Auftrag 6: Abschlussbericht und Vorschaubilder“), direkt
nach `bd0ae18`. Doku davor: `a456590` (Rollout, Social, Home-Widgets), `de73a8e` (iPhone-Anleitung, Rollout, Social,
Backend).

## 32. Push-Status

Alle Commits sind auf `origin/claude/gallant-brahmagupta-hvvp13` gepusht – kein Pull Request, kein Force-Push,
keine anderen Branches.

## 33. Abschließender CI-Status

**Grün** für den letzten Code-Commit `bd0ae18`:

- iOS (Lauf 41195030910): Build ohne Compiler-Warnungen (App und Tests), Info.plist- und Icon-Prüfungen, Prüfung gegen
  geheime Schlüssel, **1144 Tests grün**, Snapshot-Artefakt, Backend-Integration baut auf macOS.
- Backend (Lauf 41195030850): pgTAP **1000 Prüfungen in 17 Dateien grün**, `db lint` ohne Fehler, Advisors ohne
  Warnungen, Realtime-Ende-zu-Ende, Backend-Integration (21 Tests), Secret-Scan.

Der Commit mit diesem Bericht ändert nur Dokumentation und Bilder; sein CI-Lauf wird im Chat gemeldet.

## 34. Kurze Anleitung zur Installation auf dem vorhandenen iPhone

1. Terminal: `cd ~/Developer/pace` (eigenen Pfad verwenden), dann
   `git fetch origin && git checkout claude/gallant-brahmagupta-hvvp13 && git pull origin claude/gallant-brahmagupta-hvvp13`.
2. `Pace.xcodeproj` öffnen, warten bis die Pakete aufgelöst sind, **Product → Clean Build Folder**.
3. iPhone verbinden und entsperren, oben das iPhone wählen (nicht den Simulator), Personal Team unverändert lassen.
4. ▶ drücken. Daten, Identität und Einstellungen bleiben erhalten; keine neuen Berechtigungen.
5. Optional: `PACE_SUPPORT_EMAIL` in `Config/Pace.xcconfig`, nur mit offizieller Adresse.

Ausführlich mit allen Testfällen: [IPHONE_TEST.md](IPHONE_TEST.md).

## 35. Anleitung für neue Supabase-Migrationen

Erforderlich nur für Social-Profil 2.0 (Bio, Interessen, Banner, Auszeichnungen); ohne Migration läuft die App wie
bisher. Ablauf (nur nach eigener Prüfung und Freigabe, ausschließlich Projekt `bnkrenfvfiaapsbkeejq`):

1. Sicherung anlegen bzw. Backup-Zeitpunkt notieren.
2. Probelauf: `supabase migration list --linked` (nur `20261030100000` „local“) und `supabase db push --dry-run` (muss
   genau diese eine Migration nennen).
3. Einspielen: `supabase db push` (nie mit `--include-seed`, nie `db reset`).
4. Prüfabfragen und App-Test mit zwei Konten aus [SUPABASE_ROLLOUT.md](SUPABASE_ROLLOUT.md), Abschnitt „Auftrag 6“.
