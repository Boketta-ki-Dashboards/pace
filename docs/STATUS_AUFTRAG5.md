# Pace – Abschlussbericht Auftrag 5

Branch `claude/gallant-brahmagupta-hvvp13`, Basis `a9d478e` (Ende Auftrag 4). Kein Pull Request, keine Force-Pushes.
Kein Redesign: Farben, Schriften, Tab-Paging, Messenger, Widget-Drag und Einstellungen blieben unverändert. Signing,
Bundle Identifier, Entitlements, `Pace.xcodeproj/project.pbxproj`, Info.plist und die lokale Konfiguration
(`Config/Pace.xcconfig`, von Git ausgeschlossen) sind unverändert. Kein Schlüssel im Repository, keine neue Berechtigung
(insbesondere kein Standort).

**Vorweg zu den Tests:** Alles hier ist automatisch geprüft:
- Unit-Tests unter Linux und auf dem Mac.
- Simulator-Tests im echten Fenster (Pixelprüfung der Statusleiste, Kopfhöhen, Pager, Tastatur).
- Snapshots in der CI.

**Nichts davon ist auf einem echten iPhone getestet.** Die Live-Schritte sind nur mit **simulierten** Sensorwerten
geprüft. Die 5-Minuten-Gehprobe in [IPHONE_TEST.md](IPHONE_TEST.md) steht noch aus.

## 1. Zusammenfassung

| Teil | Stand |
|---|---|
| A1 Statusleiste | Home und alle Seiten ohne Systemleiste haben einen Hintergrund hinter der Statusleiste. Im Fenster-Test liegt beim Scrollen nie Inhalt unter Uhrzeit und Symbolen (klein/groß, hell/dunkel, Anpassen-Modus). |
| A2 Live-Schritte | Ursache des „nur +24“ gefunden und behoben. Neuer Abgleich mit Sensor-Tagessumme. Simulation mit 100 Schritten/min, 15 Szenarien. Diagnose nur in Entwicklungs-Builds. Neue Gehprobe in der iPhone-Anleitung. |
| A3 Regionale Karten | Im Code entstehen immer vier Karten (zehn Fälle geprüft). Der Ebenen-Editor ist jetzt eindeutig: „x von 4 Ebenen sichtbar“, „Alle vier zeigen“. Home erklärt im Anpassen-Modus fehlende Karten. |
| A4 Schritte-Widget | Klein/Mittel/Groß/Max neu gestaffelt. Max mit 7-Tage-Mini-Diagramm (historisches Ziel je Tag) und Vergleich gestern/Ø; Inhalte wählbar. |
| B5 Gruppenchat | Feste Leiste unter dem Kopf: links bis 4 echte Bilder, Anzahl und „+“; rechts nur 🔥 und Zahl. |
| B6 Pins | Vorschau mit Inhalt: Text, Foto-/GIF-Miniatur, Sprachnachricht mit Dauer, Profil, Absender. 2–4 Pins mit Strichen; verborgene Pins zeigen nichts. |
| B7 Gruppeninfo | Eine Karte mit „x von n …“, 🔥 + Zahl, Balken mit ⌈n/3⌉-Schwelle und Hinweis. Die ganze Karte öffnet den Gruppenkalender. Die drei alten Karten sind entfernt. |
| C8–C10 | Diagramme ersetzen statt verwandeln, feste Achse und Höhen. Gleich hohe Köpfe in allen vier Tabs. Das Zeitraum-Wischen lässt den linken Rand (28 pt) für die Zurück-Geste frei. |
| D | Fünf neue Widgets in allen Größen mit Galerie-Abschnitten Aktivität/Motivation/Social: Tagesvergleich, Serie diese Woche, Persönliche Rekorde, Aktivitätszeiten, Gruppenfortschritt. |
| E | 889 Linux-Tests grün, iOS-CI grün (Zahlen in 17 und 23). Zwei unabhängige Reviews: kein hoher Befund; alle mittleren und die meisten niedrigen sind behoben. Screenshots in `docs/previews/auftrag5/`. **Keine Datenbankänderung.** |

## 2. Ursachen der gemeldeten Fehler

| Fehler | Ursache |
|---|---|
| Home-Inhalte unter Uhrzeit und Symbolen der Statusleiste (A1) | Home und alle Seiten ohne Systemleiste (`paceRootPage`, `paceSubpage`) blenden die Navigationsleiste aus. Ohne sie gab es hinter der Statusleiste keinen Hintergrund: Die Scrollansicht lief bis an den oberen Rand, und Inhalte lagen unter Uhrzeit und Symbolen. |
| Live-Schritte steigen kaum („nur +24 in Minuten“, A2) | Siehe Kasten unter der Tabelle. |
| Zeitweise nur drei regionale Karten (A3) | Siehe Kasten unter der Tabelle. |
| Diagramme bei schnellem Wischen (C8) | Wochen- und Monatsbalken haben kategoriale X-Werte (Tage). Beim Wechsel des Zeitraums blieb es dasselbe `Chart`, und Swift Charts verwandelte alte in neue Balken. Zwischenzeitlich gab es beide Kategorienmengen: schmale, verschobene, überlagerte Balken. Die Y-Achse skalierte je Zeitraum neu, sodass die Höhen sprangen. Platzhalter (Laden, keine Daten) waren niedriger als das Diagramm, sodass die Kartenhöhe sprang. |
| Kopf springt beim Tabwechsel (C9) | Die vier Startseiten hatten unterschiedliche Zeilenhöhen: eine Wortmark-Zeile mit 44-pt-Knöpfen (Social, Home) bzw. ohne (Rankings, Profil), dazu verschiedene Abstände. |
| Zurückgeste auf Unterseiten (C10) | Das Zeitraum-Wischen (Statistik, Kalender, Flammenkalender) reagierte auch auf Bewegungen vom linken Rand. Beim Zurückwischen verschob es zugleich das Diagramm und konnte den Zeitraum wechseln. |
| Gruppenchat, Pins, Gruppeninfo (B5–B7) | Kein Fehler im engeren Sinn, sondern Gestaltung: Mitglieder und Flamme scrollten mit dem Verlauf. Der Pin zeigte nur Text („Foto“). Die Gruppeninfo hatte drei Karten mit doppelter Information. Nebenbei zeigte die Gruppenliste „Heute 9 von 8 nötig“. |

**Live-Schritte (A2).** Die Abfrage im Vordergrund lief alle 15 s und rief jedes Mal `LiveStepEstimator.healthKit(_:)`
auf, auch bei **unverändertem** HealthKit-Wert. Jeder Aufruf setzte die Sensor-Basis neu.
- iOS schreibt die iPhone-Schritte erst Minuten später nach Health. HealthKit lag deshalb hinter der Anzeige, und der
  Sensor-Fortschritt wurde verworfen.
- Sichtbar blieben höchstens die Schritte eines Intervalls: 15 s × 100/min ≈ 25, also genau die gemeldeten „+24“.
- Dazu kam: Die Tagessumme des Sensors wurde nicht genutzt, und die Messung lief nach Mitternacht vom Vortag weiter.

**Regionale Karten (A3).** Im Code entstehen ohne eigene Auswahl immer vier Karten. Weniger Karten gibt es nur über
die gespeicherte Ebenen-Auswahl, und der Editor machte das leicht:
- Die Ebenen-Chips sahen aus wie eine Auswahl, Antippen **blendete die Ebene aber aus**.
- Ein zweites Regional-Widget wurde mit „zeigt das schon“ abgelehnt, ohne Hinweis auf die Größe. So war das Abwählen
  einer Ebene der einzige Weg zum Hinzufügen.
- Auf Home war danach nicht erkennbar, warum eine Karte fehlte.

Den Fall auf einem echten Gerät nachzustellen, war hier nicht möglich.

## 3. Was behoben wurde

- **A1:** `paceStatusBarBackdrop()` legt den Seitenhintergrund genau in die obere Safe Area. Er wird über
  `paceRootPage`/`paceSubpage` gesetzt, ohne feste Werte. Inhalt beginnt oben direkt unter der Statusleiste, kein
  Leerraum, bis zum Ende scrollbar.
- **A2:** neuer Abgleich (Abschnitt 4) und testbare Sensor-Abstraktion (`LiveStepCounting`, `PedometerLiveSteps`,
  `SimulatedLiveSteps`).
  - Tageswechsel: Die Messung beginnt neu und verwirft Werte vom Vortag.
  - Unbestätigte Schritte verfallen nach 20 Minuten. Das kam aus dem Stabilitäts-Review dazu.
  - Diagnose-Seite nur in Debug-Builds.
- **A3:** Editor „x von 4 Ebenen sichtbar“ mit „Alle vier zeigen“; dieselben Kartentitel wie auf Home.
  Duplikat-Hinweis verweist auf die Größe. Anpassen-Modus zeigt „3 von 4 Ebenen sichtbar“. Tests decken Standard,
  Speichern, Neustart, Migration, Größenwechsel, fehlende Daten, kreisfreie Stadt, Stadtstaat und unvollständige
  Gebietsdaten ab.
- **A4:** Schritte-Widget in vier Stufen (Abschnitt 9).
- **B5–B7:** Chat-Leiste, Pin-Vorschau und Gruppenkarte (Abschnitte 10–12). Die Gruppenliste zeigt jetzt
  „Flamme heute gesichert (9 erreicht)“ statt „9 von 8 nötig“.
- **C8–C10:** Abschnitt 13.
- **D:** fünf Widgets (Abschnitte 14–15).

## 4. Live-Schritte: neuer Abgleich

`LiveStepEstimator` (PaceCore) verbindet die HealthKit-Wettbewerbsschritte mit den schnelleren Sensorwerten.

- **Messung ab Tagesbeginn.** Der erste Sensorwert ist die Tagessumme des iPhones (sofort da), danach laufende
  Meldungen. Gemeldet wird nur, was größer ist als der letzte Wert.
- **Anzeige** = größter Wert aus HealthKit-Stand, Sensor-Tagessumme und `Basis + Sensor-Fortschritt seit der Basis`.
  Sensor und HealthKit werden nie addiert.
- **Neue Basis nur bei geändertem HealthKit-Wert:** `Basis = max(angezeigt, HealthKit)`. Ein unveränderter Wert
  (Abfrage alle 15 s) ändert nichts mehr – das war der Fehler.
- **HealthKit höher** (z. B. Apple Watch): Der höhere Wert gilt. Bereits angezeigte Sensorschritte werden nicht
  doppelt gezählt.
- **App verlassen/zurück:** Der Sensor stoppt im Hintergrund. Beim Neustart kommen die Schritte aus der Pause dazu,
  wenn HealthKit sich inzwischen nicht geändert hat.
- **Unbestätigte Schritte verfallen nach 20 Minuten** (Stabilitäts-Review): Hat der Sensor 20 Minuten keine neuen
  Schritte gemeldet und HealthKit die vorläufigen bis dahin nicht bestätigt, gilt HealthKit – auch wenn die Anzeige
  dabei sinkt.
  - Grund: Health bevorzugt bei Überschneidung die Watch und verwirft iPhone-Schritte. Sonst stünde Home bis
    Mitternacht über HealthKit.
  - Die 20 Minuten sind eine Annahme; die Gehprobe prüft sie.
- **„Tagesziel erreicht!“ erst mit bestätigten Schritten** – wie die Serie. Davor steht „Ziel erreicht – Bestätigung
  aus Apple Health folgt“.
- **Nur Anzeige:** Rankings, Sync, Serie, Mitteilungen und Erinnerungen nutzen weiter ausschließlich die
  HealthKit-Wettbewerbsschritte (ohne manuell eingetragene). Es lassen sich keine Schritte manuell eintragen.
- **Akku:** Gemessen wird nur im Vordergrund mit `CMPedometer` – kein GPS, kein Standort, keine
  Hintergrundaktualisierung.

## 5. Simulation und Szenarien

**Simulierter Sensor.**
- `WalkingProfile` beschreibt Gehabschnitte mit Tempo. `SimulatedLiveSteps` liefert daraus Messwerte wie
  `CMPedometer`, auch im Zeitraffer.
- In Debug-Builds startet die Simulation über die Startoption `-PaceSimulatedStepsPerMinute 100` oder über den
  Schalter auf der Diagnose-Seite.

**Szenarien.** `LiveStepSimulationTests` spielt den Ablauf wie in der App durch:
- Sensor etwa alle 2,5 s.
- HealthKit verspätet und gebündelt.
- Abfrage alle 15 s, mit Verfallsprüfung.

| Nr. | Szenario | Erwartung (geprüft) |
|---|---|---|
| 1 | 100 Schritte/min, 5 min | 30 s ≈ 50, 60 s ≈ 100, 120 s ≈ 200, 300 s ≈ 500 (auch über einer höheren HealthKit-Basis) |
| 2 | schneller (150/min) | + 350 nach 3 min, + 500 nach 4 min |
| 3/4 | Pause, Fortsetzung | Wert bleibt in der Pause stehen, zählt danach weiter |
| 5 | HealthKit 10 min verspätet | Anzeige trotzdem + 500 |
| 6 | HealthKit holt ein | Anzeige = HealthKit, nichts doppelt |
| 7 | HealthKit höher (andere Quelle) | springt auf HealthKit, läuft weiter, später exakt |
| 8 | App verlassen/zurück | Pausen-Schritte sofort da |
| 9 | Sensor-Neustart | keine Doppelzählung |
| 10 | Mitternacht | neuer Tag beginnt bei HealthKit, alte Werte verworfen (`HomeViewModelTests`) |
| 11 | kein Sensor | nur HealthKit, nie mehr |
| 12 | keine Erlaubnis | nur HealthKit (`HomeViewModelTests`) |
| 13 | Apple Watch zählt denselben Gang | jeder Schritt einmal |
| 14 | neue Quelle | Zuwachs übernommen, später exakt |
| 15 | HealthKit bestätigt nur 90 % | während des Gehens jeder Sensorschritt; 20 min nach dem letzten Schritt genau HealthKit |

**Weitere Tests.**
- 40 zufällige Abfolgen in `LiveStepEstimatorTests`.
- Diagnose-Protokoll begrenzt auf 80 Einträge.
- Simulation nach Mitternacht zählt ab dem neuen Tag.
- Sensor-Abstraktion: Stream-Ende stoppt den Sensor.

**Alle Werte sind simuliert, nicht vom echten Sensor.**

## 6. Grenzen von Simulator und CI

- Der iOS-Simulator hat keinen Schrittzähler (`CMPedometer.isStepCountingAvailable() == false`) und keine echten
  Health-Daten vom Gerät. Ob iOS die Schritte des iPhones wirklich nach wenigen Minuten nach Health schreibt, ob das
  20-Minuten-Fenster passt und wie oft der Sensor meldet, zeigt nur die Gehprobe.
- Die CI-Simulatoren zeigen keine echte Statusleiste mit Uhrzeit. Der Fenster-Test prüft stattdessen die
  Pixel der oberen Safe Area. In den Screenshots ist die Statusleiste nachgezeichnet.
- Gesten (Zurück vom Rand, Zeitraum-Wischen, Widget-Drag) sind als Rechenregeln getestet. Das Gefühl der Geste lässt
  sich nur auf dem Gerät beurteilen.
- Keine echte Tastatur, kein Mikrofon, keine Push-Mitteilungen in der CI.

## 7. Safe Area

Der Statusleisten-Hintergrund ist eine Umgebungseinstellung (`paceStatusBarBackdropEnabled`). Er greift auf Home, den
Startseiten und allen Unterseiten ohne Systemleiste und folgt Hell/Dunkel.

`StatusBarSafeAreaTests` rendert Home im Aufbau von `MainTabView` im echten Fenster:
- Geräte: iPhone SE und Pro Max, jeweils hell und dunkel.
- Geprüft wird, dass die obere Safe Area nur den Seitenhintergrund zeigt: oben, leicht gescrollt, weit gescrollt, am
  Ende, nach Tabwechsel und im Anpassen-Modus.
- Der Inhalt beginnt oben direkt unter der Statusleiste.
- Gegenprobe: Ohne den Hintergrund liegt dort Inhalt, also der frühere Fehler.

Vorher/Nachher: [01](previews/auftrag5/README.md#01-home-mit-statusleiste).

## 8. Regionale Karten

- Ohne eigene Auswahl immer vier Karten: Stadt/Gemeinde, Landkreis, Bundesland, Land. Auch kreisfreie Städte,
  Stadtstaaten und unvollständige Gebietsdaten ergeben vier Karten.
- Ebenen-Editor:
  - „x von 4 Ebenen sichtbar“.
  - Chips mit Haken für „sichtbar“.
  - „Alle vier zeigen“.
  - Hinweis „Tippe auf eine Ebene, um ihre Karte ein- oder auszublenden. Mindestens eine bleibt.“
- Auf Home zeigt der Anpassen-Modus „3 von 4 Ebenen sichtbar“, wenn bewusst eine Ebene abgewählt ist.
- Ein zweites Regional-Widget mit denselben Ebenen wird abgelehnt, mit dem Hinweis, stattdessen die Größe des
  vorhandenen zu ändern.
- `RegionCardsReliabilityTests` decken die Fälle aus Abschnitt 3 ab. Dazu kommt ein Snapshot des Editors
  ([20](previews/auftrag5/README.md#20-regionale-ebenen)).

## 9. Schritte-Widget Groß und Max

| Größe | Inhalt |
|---|---|
| Klein | Überschrift, große Zahl, „von 10.000“, %, Fortschrittsbalken |
| Mittel | + Ring, Ziel-Fortschritt, „Noch … bis zu deinem Ziel“ |
| Groß | + Distanz, aktive Kalorien (geschätzte gekennzeichnet „≈“), Stockwerke, Training |
| Max | + **7-Tage-Mini-Diagramm**: ein Balken je Tag, gestrichelte Linie mit dem damals geltenden Ziel, „Ziel an 4 von 6 Tagen erreicht“; Tippen → Wochenstatistik. Dazu **Vergleich** gestern / Ø letzte 7 Tage. |

Groß und Max sind über „Inhalte“ konfigurierbar; das Mini-Diagramm erst ab Groß.
- Der Ø steht nicht doppelt: Im Diagrammkopf entfällt er, wenn die Vergleichskachel aktiv ist.
- Heute zählt in „Ziel an … Tagen“ erst bestätigt mit. Ohne gezählten Tag entfällt die Zeile, also nie „0 von 0“.

Snapshots in DE/EN/RU. Vorher/Nachher: [04](previews/auftrag5/README.md#04-schritte-groß),
[05](previews/auftrag5/README.md#05-schritte-max).

## 10. Gruppenchat-Leiste

Die Leiste sitzt unter dem Chat-Kopf außerhalb der Scrollansicht und scrollt deshalb nicht mit.
- **Links:** bis zu 4 echte Mitgliederbilder, die Anzahl und „+“. Alle öffnen die Mitgliederliste der Gruppe;
  dort liegen Profile und das Einladen.
- **Rechts:** nur 🔥 und die Zahl. Tippen öffnet den Gruppenkalender über `SocialNavigator.showGroupCalendar`.
- Der Pfad bleibt Gruppe → Kalender, ohne Schleife; Test `chatBarRoutesNeverStackPages`.
- Alle Tippflächen sind mindestens 44 pt groß, mit VoiceOver-Texten.
- Die frühere Streak-Karte im Chat-Info-Kopf ist entfernt.

Vorher/Nachher: [06](previews/auftrag5/README.md#06-gruppenchat-leiste).

## 11. Pin-Vorschau

`ChatPinPreview` zeigt den Inhalt je Art:
- **Text:** Ausschnitt, höchstens 120 Zeichen, Zeilenumbrüche zusammengefasst.
- **Foto/GIF:** Miniatur plus „Foto · Bildtext“.
- **Sprachnachricht:** Symbol plus Dauer.
- **Profil:** Avatar plus „Profil: @name“.
- **Absender:** in Gruppen, z. B. „Du:“, „Mia:“.

Mehrere Pins:
- 2–4 Pins zeigen Striche oben, ab 5 steht „Angepinnt 6 von 7“.
- Tippen springt zur Nachricht und hebt sie hervor (wie bisher); danach zeigt der Hinweis den nächsten Pin.

Verborgene Pins zeigen weder Inhalt noch Absender noch Miniatur, nur „Nachricht nicht verfügbar“.

Snapshots: [07](previews/auftrag5/README.md#07-pin-vorschau), [08](previews/auftrag5/README.md#08-gruppenchat-mit-foto-pin).

## 12. Kombinierte Gruppenkarte

Eine Karte (`GroupDayProgressCard`):
- Links oben „3 von 12 Mitgliedern haben das Tagesziel erreicht“ (RU „3 из 12 участников выполнили дневную цель“).
- Rechts nur 🔥 und die Zahl.
- Darunter ein Balken mit einem Strich an der ⌈n/3⌉-Schwelle. Der Wert `todayRequiredCount` kommt vom Server.
- Hinweis „Noch 1 Mitglied bis zur heutigen Gruppenflamme“ bzw. „Gruppenflamme für heute gesichert“. Ohne Serverwert
  gibt es keinen Hinweis.

Die ganze Karte öffnet den Gruppenkalender: kein Pfeil, kein „Gruppenkalender“-Text, kein zweiter Link. Die alten
Streak-, Fortschritts- und Kalender-Karten sind entfernt; das Tagesziel steht im Kopf. Alle Werte stammen aus der
vorhandenen `GroupSummary`, ohne neue Abfrage.

Vorher/Nachher: [09](previews/auftrag5/README.md#09-gruppeninfo).

## 13. Diagramme, Kopfzeilen, Gesten

**Diagramme (C8).**
- Jeder Zeitraum ist ein eigenes Diagramm (`.id(report.chartIdentity)`). Es wird ausgetauscht (kurzes Ein-/Ausblenden)
  statt verwandelt, also ohne schmale, verschobene oder überlagerte Balken.
- Die Y-Achse ist fest auf einen runden Höchstwert gerundet (`niceCeiling`). Datenänderungen werden nicht animiert.
- Diagramm und Platzhalter sind gleich hoch.
- Ein gemeinsamer Stil (`PaceChartStyle`) gilt für Achsen, Ecken, Abstände und Auswahl. „Bewegung reduzieren“ wird
  beachtet, die Farben bleiben.
- Snapshots: Tag/Woche/Monat ([10–12](previews/auftrag5/README.md#10-statistik-tag)).

**Köpfe (C9).**
- `PaceRootHeader` hat in allen vier Tabs eine feste Zeilenhöhe von 44 pt, mit und ohne Knöpfe.
- `RootHeaderLayoutTests` misst im Fenster gleiche Höhe und gleiche Position von Wortmarke und Titel.
- Das Paging ist unverändert.

**Zurück-Geste (C10).**
- Das Zeitraum-Wischen ignoriert Bewegungen, die in den ersten 28 pt vom linken Rand beginnen
  (`PaceSwipeNavigation.belongsToBackSwipe`, globale Koordinaten). Die System-Zurück-Geste bleibt frei.
- Das gilt für Statistik, Kalender, Flammen- und Gruppenkalender. Andere Unterseiten hatten kein konkurrierendes
  Wischen.
- Der Randfall ist getestet; das Gefühl der Geste ist auf dem Gerät zu prüfen.

## 14. Fünf neue Widgets

Alle in Klein, Mittel, Groß und Max, aus vorhandenen Daten, ohne neue Tabelle oder Server-Abfrage:

| Widget | Inhalt | Tippen |
|---|---|---|
| **Tagesvergleich** | heute (mit Live-Schritten) gegen gestern **bis zur gleichen Uhrzeit** aus Stundenwerten; Differenz („650 Schritte mehr als gestern um diese Zeit“), %, Balken, „Gestern insgesamt“. Ohne Werte von gestern „Noch kein Vergleich verfügbar“; gestern bis jetzt 0 → kein Prozentwert | Tagesstatistik |
| **Serie diese Woche** | Mo–So mit erreichten Tagen (jeweils damals geltendes Ziel), optional Serie, Rekord, nächster Meilenstein | Flammen-Seite |
| **Persönliche Rekorde** | wählbar: Bester Tag, Beste Woche, Bester Monat, Längste Serie, Aktuelle Serie, Weiteste Strecke; Groß + 2 weitere, Max alle. „Letzte 12 Monate“ nur bei Rekorden aus dem Verlauf | Statistik (Monat) |
| **Aktivitätszeiten** | Stundenwerte in Tageszeiten (Nachts 0–5, Morgens 5–11, Mittags 11–14, Nachmittags 14–18, Abends 18–24), „Am aktivsten nachmittags“; Max zusätzlich 24 Stunden. Ohne Stundenwerte ein Hinweis, nie eine erfundene Verteilung | Tagesstatistik |
| **Gruppenfortschritt** | gewählte Gruppe: Name, Mitglieder, „x von n …“, Balken mit Schwelle, 🔥 + Zahl, optional Hinweis und Tagesziel/beste Serie. Verlassene/gelöschte Gruppe, Laden und Ladefehler haben eigene Zustände | Gruppe; 🔥 → Gruppenkalender |

**Begriffe.** Die Rekord-Titel heißen wie in der Statistik, die dieselben Werte zeigt: „Längste Serie“,
„Aktuelle Serie“, „Weiteste Strecke“. Der Auftrag nannte sie „längste/aktuelle Flamme, größte Distanz“; die
Vereinheitlichung folgt dem Produkt-Review. Das Streak-Wochen-Widget heißt „Serie diese Woche“.

**Laden.** Tagesvergleich und Aktivitätszeiten teilen sich eine Abfrage der Stundenwerte.
- Neu geladen wird nur bei neuem Tag oder neuem HealthKit-Stand; die Werte von gestern einmal pro Tag. Pull-to-Refresh
  lädt beide neu.
- Bis die Stundenwerte da sind, zeigen beide einen Ladekreis. Bei einem Fehler steht „Stundenwerte gerade nicht
  verfügbar. Zum Aktualisieren nach unten ziehen.“
- Serie und Rekorde nutzen den ohnehin geladenen Verlauf, Gruppenfortschritt die geladenen Gruppen.

Screenshots: [14–19](previews/auftrag5/README.md#14-tagesvergleich).

## 15. Optionen und Speichern

**Galerie.** Drei Abschnitte (`HomeGallerySection`):
- **Aktivität:** Schritte und Aktivität, Wochenübersicht, Tagesvergleich, Aktivitätszeiten, Kalender.
- **Motivation:** Persönliche Serie, Serie diese Woche, Persönliche Rekorde.
- **Social** (RU „Друзья“): Freunde, Gruppen, Gruppenfortschritt, Regionale Rankings, Ranking-Umfeld.

**Optionen.**
- Rekordart: einspaltige Auswahl, damit lange russische Titel nicht abgeschnitten werden; RU-Snapshot
  [22](previews/auftrag5/README.md#22-rekordauswahl-russisch).
- Gruppe: Pflicht, die erste Gruppe wird vorgeschlagen. Eine verlassene Gruppe gilt als nicht gewählt.
- Zusatzinhalte je Größe.

**Speichern.**
- Gespeichert wird in den vorhandenen Home-Einstellungen; neues Feld `record`, Rohwerte.
- Unbekannte Werte aus neueren Versionen fallen auf den Standard zurück.
- Fremde Optionen werden nicht gespeichert.
- Duplikate richten sich nach dem Inhalt: zwei Rekord-Widgets mit verschiedenen Rekorden sind erlaubt.

**Keine bisher kostenlose Funktion wurde hinter Pace Pro verschoben.**

## 16. Datenbank

**Keine Datenbankänderung, keine Migration, kein Reset.** Alle neuen Anzeigen nutzen vorhandene Daten:
- Gruppenkarte, Chat-Leiste und Gruppenfortschritt: die schon geladene `GroupSummary` (`todayReachedCount`,
  `todayRequiredCount` = ⌈n/3⌉ vom Server, `currentStreak`, `memberCount`).
- Tagesvergleich und Aktivitätszeiten: Stundenwerte aus Apple Health auf dem Gerät.
- Rekorde und Serie diese Woche: der lokale Verlauf.

Keine neue Tabelle, keine neue RPC, keine geänderte Sicherheitsregel. Das produktive Supabase-Projekt und das
Projekt der Boketta-KI-Webseite wurden nicht angefasst. Die Backend-CI (pgTAP, Lint, Advisors, Realtime, Integration)
läuft unverändert grün.

## 17. Tests

**Linux:** `swift test` mit **889 Tests in 116 Suites, alle grün**. SwiftUI-Dateien werden dort übersprungen.

Neu in Auftrag 5:
- `LiveStepEstimatorTests` (Abgleich, Verfall, 40 Zufallsfolgen).
- `LiveStepSimulationTests` (15 Szenarien, Simulation).
- `LiveStepDiagnosticsTests`.
- `HomeViewModelTests` (Abfrage mit gleichem HealthKit-Wert, Mitternacht, verweigert, kein Sensor, Diagnose).
- `RegionCardsReliabilityTests`.
- `InsightWidgetTests`, `InsightWidgetLoadingTests` (eine Abfrage, Laden, Fehler, Pull-to-Refresh).
- `GroupProgressGalleryTests`.
- `GroupDayProgressTests` (⌈n/3⌉, Plural DE/EN/RU).
- `ChatPinPreviewTests`.
- `SocialNavigatorTests.chatBarRoutesNeverStackPages`.
- Diagramm-Identität in `StatisticsReportTests`, Rand-Ausschluss in `PaceSwipeNavigationTests`.
- „Ziel nur bestätigt“ in `HomeWidgetModelTests`.

**iOS-CI (Simulator, Xcode 26.3, Lauf 40226508417 auf `2ec903a`):** `xcodebuild test` mit **1.073 Tests in
144 Suites, alle grün**. Darin enthalten sind die Snapshot- und Fenster-Tests (66 Tests in 11 Suites). Dazu kommen
21 Backend-Integrationstests, die auf macOS gebaut werden. Prüfungen „keine Compiler-Warnungen“ (App und Tests),
Info.plist-Texte, App-Icons und Schlüsselprüfung sind grün.

Fenster-Tests:
- `StatusBarSafeAreaTests` (Pixel der Statusleiste).
- `RootHeaderLayoutTests`.
- Aus Auftrag 4: `KeyboardLayoutTests`, `TabPagerDirectionTests`.

Neue Snapshots:
- Schritte in allen Größen (DE/EN/RU).
- Neue Widgets in allen Größen.
- Statistik Monat, Pin-Varianten, Statusleiste vorher/nachher/Anpassen, Ebenen-Editor.
- Rekordauswahl (DE/EN/RU).

**Regressionen geschützt** (bestehende Tests weiter grün):
- Navigation mit 50 Wechseln Flamme ↔ Chat.
- Wischrichtung und Abbruch.
- Tastatur (300 pt).
- Messenger: Antworten, Bearbeiten, Pins, Sprachnachricht.
- Widget-Drag-Regeln.
- HealthKit-Regeln (manuelle Schritte zählen nicht).
- Cache-Grenzen.
- Tab-Leiste.

**Bekannter Wackler:** `ActivitySyncCoordinatorTests.flushWaitsForRunningUpload` schlug unter Linux einmal unter
Last fehl. Allein lief er 3 von 3 Mal grün. Der Test ist älter als Auftrag 5 und hier nicht verändert.

## 18. Reviews

Zwei unabhängige Prüfungen, jeweils über `git diff a9d478e..ff4f62a`.

**1. Stabilität, Navigation, Live-Schritte:** 0 hoch, 1 mittel, 5 niedrig, 1 Info.
- **Mittel, behoben:** Die Live-Anzeige konnte bis Mitternacht über HealthKit stehen, wenn das iPhone mehr zählt, als
  Health übernimmt (Watch bevorzugt). Home zeigte dann „Tagesziel erreicht!“, obwohl die Serie nicht gesichert war.
  Jetzt verfallen unbestätigte Schritte nach 20 Minuten, und „erreicht“ gilt nur bestätigt (Abschnitt 4). Szenario 15
  und neue Tests decken das ab.
- Niedrig, behoben:
  - Stundenwerte werden nach einem Fehler oder per Pull-to-Refresh erneut geladen, gestern ebenfalls.
  - Die Simulation erfindet nach Mitternacht keine Schritte mehr.
  - Der Simulator-Schalter ist dokumentiert (vor der Gehprobe ausschalten).
- Niedrig, offen: siehe Abschnitt 19.
- Ohne Befund geprüft:
  - Live-Abfolgen, Stream-Ende, Navigation ohne Schleifen.
  - Rand-Ausschluss, keine neuen Force-Unwraps.
  - Live-Schritte erreichen weder Sync noch Ranking, Serie oder Mitteilungen.

**2. Produkt, UI, Lokalisierung:** 0 hoch, 4 mittel, 12 niedrig – alle mittleren behoben.
- Begriffe vereinheitlicht: Serie statt Flamme/Streak für Werte in Tagen, Rekord-Titel wie in der Statistik.
- Russische Texte korrigiert:
  - „Активнее всего днём“ statt „Больше всего: День“.
  - „Серия за неделю“, „Сегодня и вчера“, „Всего за вчера“.
  - „Ещё 3 участника – и огонь группы на сегодня сохранён“.
  - Galerie „Друзья“, kein Komma vor „или“.
- Lade- und Fehlerzustand bei Tagesvergleich und Aktivitätszeiten statt „keine Werte“.
- Rekordauswahl einspaltig, mit RU-Snapshot.
- Niedrig, behoben:
  - Keine „0 von 0 Tagen“; Einzahl in DE/EN („von 1 Tag“).
  - Ø nicht doppelt.
  - VoiceOver im kleinen Gruppenfortschritt.
  - Dynamic Type für die großen Zahlen.
  - Zeitraum nur bei 12-Monats-Rekorden.
  - Verlassene Gruppe gilt beim Bearbeiten als nicht gewählt.
  - Kein erfundener Hinweis ohne Serverwert.
  - Einheit im Satz des Tagesvergleichs.
  - „Morgens“ statt „Morgen“, EN „5–11“.
  - Gruppenliste „Flamme heute gesichert“.
  - Doc-Kommentar korrigiert.
- Niedrig, offen: siehe Abschnitt 19.

## 19. Offen und Grenzen

- **Gerätetests stehen aus** – vor allem die Gehprobe, die Statusleiste mit echter Uhrzeit und das Gefühl der
  Zurück-Geste. Dafür gibt es [IPHONE_TEST.md](IPHONE_TEST.md).
- **20-Minuten-Fenster:** Die Annahme muss sich auf dem Gerät bestätigen. Schreibt iOS die iPhone-Schritte später
  nach Health, kann die Anzeige nach dem Gehen kurz auf den alten Health-Wert fallen und mit dem Nachtrag wieder
  steigen.
- Offene niedrige Befunde aus den Reviews:
  - Theoretische Doppelzählung, wenn HealthKit Schritte schon vor dem Sensor kennt. Auf dem iPhone unwahrscheinlich;
    der Verfall begrenzt sie auf 20 Minuten.
  - Zeitzonenwechsel nach Westen kurz nach Mitternacht.
  - Diagrammwechsel: Das alte Diagramm bleibt möglicherweise 0,18 s sichtbar. Lange Platzhaltertexte werden bei sehr
    großer Schrift abgeschnitten.
  - Die Diagnose zeichnet auch in Release-Builds auf, höchstens 80 Einträge, nicht erreichbar.
  - Der Diagramm-Stil gilt noch nicht für die Mini-Diagramme auf Home.
  - Max bringt bei Gruppenfortschritt und Tagesvergleich wenig Neues.
  - Nicht mehr genutzte Chat-Texte.
  - Die Flamme fehlt in der Chat-Leiste, bis die Gruppe geladen ist.

## 20. Screenshots

[`docs/previews/auftrag5/`](previews/auftrag5/README.md) enthält die PNG-Dateien mit Index.
- **Ansichten:** Home mit Statusleiste, Schritte Klein/Mittel/Groß/Max, Gruppenchat-Leiste, Pin-Varianten, Chat mit
  Foto-Pin, Gruppenkarte, Statistik Tag/Woche/Monat, Galerie, die fünf neuen Widgets einzeln und zusammen,
  Ebenen-Editor, Anpassen-Modus, Rekordauswahl auf Russisch.
- **Hell und dunkel** für jede Ansicht.
- **Vorher/Nachher** für Schritte Groß/Max, Chat-Kopf, Gruppeninfo und Statusleiste. „Vorher“ stammt aus dem
  Snapshot-Artefakt von `a9d478e`; bei der Statusleiste aus demselben Test mit abgeschaltetem Hintergrund.

Es sind Simulator-Renderings aus der CI, keine Fotos vom iPhone.

## 21. Commits und Branch

Branch `claude/gallant-brahmagupta-hvvp13`:

| Commit | Inhalt |
|---|---|
| `b6943ce` | Statusleisten-Hintergrund und zuverlässigere Live-Schritte (A1, A2) |
| `d928bcd` | Regionale Karten, Schritte-Größen, stabile Diagramme, einheitliche Köpfe (A3, A4, C8–C10) |
| `66deab7` | Gruppenchat-Leiste, Pin-Vorschau, Gruppenkarte und fünf neue Widgets (B, D) |
| `1ca8660` | Snapshot-Sammelbild verkleinert, Doku und Vorschau-Snapshots |
| `ff4f62a` | Gruppenfortschritt: Fehlerzustand und Gruppen-Vorschlag |
| `2ec903a` | Review-Befunde (Live-Schritte verfallen ohne Bestätigung, Begriffe, RU-Texte, Ladezustand) |
| (letzter Commit) | Screenshots, Index und dieser Bericht – nur Dokumentation |

## 22. Push

Alle Commits sind auf `origin/claude/gallant-brahmagupta-hvvp13` gepusht: normaler Push, kein Force-Push, kein Pull
Request.

## 23. CI

| Commit | iOS | Backend |
|---|---|---|
| `b6943ce` (A1, A2) | grün | grün |
| `d928bcd` (A3, A4, C) | grün | grün |
| `66deab7` (B, D) | rot: Sammelbild aller Widgets in Max zu hoch zum Speichern → `1ca8660` | grün |
| `1ca8660` | vom nächsten Push abgebrochen (`cancel-in-progress`) | grün |
| `ff4f62a` | grün | grün |
| `2ec903a` (Review-Befunde, letzter Code-Stand) | **grün** (1.073 Tests) | **grün** |

Der letzte Commit enthält nur Bericht, Index und PNG-Dateien. Er löst dieselben Workflows erneut aus; ihr
Ergebnis steht in der Abschlussmeldung.

## 24. iPhone-Anleitung

[IPHONE_TEST.md](IPHONE_TEST.md) ist für Auftrag 5 neu geschrieben. Herunterladen und Installieren laufen wie bisher;
es gibt keine neuen Berechtigungen und keinen Standort.

**Abschnitt 5: 5-Minuten-Gehprobe.**
1. Startwert notieren.
2. 5 Minuten gleichmäßig gehen und alle 30 Sekunden den Wert auf Home in eine Tabelle eintragen. Erwartet:
   ≈ 50, 100, 150 … 500.
3. Danach einen Screenshot der Diagnose-Seite machen.
4. Nach etwa 10 Minuten mit der Health-App vergleichen.

Dazu notieren: ob der Wert etwa 20 Minuten nach dem Gehen auf den Health-Wert zurückgeht und ob „Ziel erreicht –
Bestätigung folgt“ erscheint.

**Abschnitt 6:** 20 neue Testfälle und 5 Regressionsfälle:
- Neu: Statusleiste, regionale Karten, Schritte-Größen, Chat-Leiste, Pins, Gruppenkarte, Diagramme, Zurückgeste, Köpfe,
  Galerie, fünf neue Widgets, Neustart, Sprachen.
- Regression: Navigation, Wischrichtung, Tastatur, Sprachnachricht, Widget-Drag.
