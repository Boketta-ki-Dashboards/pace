# Gesundheitsdaten in Pace

Pace ist eine Wettbewerbs-App für Bewegung, keine Fitness- oder Gesundheits-App. Gesundheitsdaten sind nur Mittel
zum Zweck: Sie liefern die Schritte für den Wettbewerb und ein paar persönliche Zusatzwerte.

## Grundsatz

1. **Nur lesen, nichts schreiben.** Pace fordert ausschließlich Lesezugriff an. Es gibt keinen
   `NSHealthUpdateUsageDescription`-Text, weil Pace nichts in Health schreibt (die CI prüft das).
2. **Bewegungsdaten – Puls nur auf ausdrücklichen Wunsch.** Beim ersten Start fragt Pace nur nach Bewegungsdaten.
   Ruhepuls und Ø Puls beim Gehen liest Pace erst, wenn der Nutzer in den Tagesdetails „Puls aus Apple Health
   anzeigen“ antippt (eigene Abfrage, siehe unten). Kein Gewicht, kein Körperfett, kein Schlaf, kein Blutdruck, kein
   Blutzucker, keine Zyklusdaten, keine medizinischen Daten.
3. **Ins Backend geht nur, was der Wettbewerb braucht:** die tägliche Zahl der Competition Steps. Alles andere bleibt
   auf dem iPhone.
4. **Keine Rohdaten.** Weder lokal gespeichert noch übertragen werden einzelne HealthKit-Samples – nur Tagessummen.

## Gelesene HealthKit-Typen

| HealthKit-Typ | Wofür | Bleibt lokal? |
|---|---|---|
| `stepCount` | Schrittzahl (Health Steps) und Competition Steps | Health Steps: ja. Competition Steps: als Tageswert ans Backend |
| `distanceWalkingRunning` | Distanz auf Home und in den Statistiken | ja |
| `activeEnergyBurned` | aktive Kalorien auf Home und in den Statistiken | ja |
| `flightsClimbed` | Stockwerke in den Statistiken | ja |
| `appleExerciseTime` | Trainingsminuten in den Statistiken (in der Praxis nur mit Apple Watch) | ja |
| `restingHeartRate` | optional: Ruhepuls in den Tagesdetails (Tagesdurchschnitt) | ja, nie ans Backend |
| `walkingHeartRateAverage` | optional: Ø Puls beim Gehen in den Tagesdetails | ja, nie ans Backend |

Die beiden Herztypen gehören **nicht** zur Abfrage beim ersten Start (`HealthKitService.readTypes`) und nicht zu den
Hintergrund-Observern. Sie werden über `ActivityDataProviding.requestHeartRateAccess()` separat angefragt – nur nach
einem Tipp auf „Puls aus Apple Health anzeigen“. `heartRateAccess()` meldet nur, ob schon gefragt wurde: Ob der Nutzer
zugestimmt hat, verrät HealthKit bei Lesezugriffen nicht. Ohne Zustimmung oder ohne Messung gibt es schlicht keine
Werte; die Kacheln erscheinen dann nicht (nie als 0, nie geschätzt). Der vorhandene Text
`NSHealthShareUsageDescription` deckt beide Abfragen ab.

Implementiert in `Packages/PaceKit/Sources/PaceHealth` – dem einzigen Modul mit `import HealthKit`.

## Health Steps und Competition Steps

| | Health Steps | Competition Steps |
|---|---|---|
| Bedeutung | persönliche Schrittzahl wie in der Health-App | Schritte, die für Rankings und spätere Challenges gelten |
| Manuell eingetragene Schritte | enthalten | **nicht** enthalten |
| Anzeige | in den Statistiken, wenn sie abweichen („In Apple Health: …“) | große Zahl auf Home, Rankings |
| Hinweis | „Manuell eingetragene Schritte zählen nicht für Rankings.“ – auf Home unter der Schrittzahl, wenn die Werte heute abweichen; in den Statistiken, wenn sie an einem der letzten 7 Tage abweichen | |
| Backend | nein | ja, ein Wert pro Tag |

### Wie gezählt wird

Beide Werte stammen aus einer Statistik-Abfrage (`HKStatisticsCollectionQueryDescriptor`) mit `.cumulativeSum` und
Tages-Buckets. HealthKit führt dabei überlappende Quellen (iPhone und Apple Watch) nach der Prioritätenliste der
Health-App zusammen. So wird nichts doppelt gezählt, und der Wert entspricht dem der Health-App.

Competition Steps verwenden dieselbe Abfrage mit einem zusätzlichen Filter:

```swift
HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyWasUserEntered,
                            operatorType: .notEqualTo, value: NSNumber(value: true))
```

- Schritte, die in der Health-App über „Daten hinzufügen“ eingetragen werden, tragen `HKWasUserEntered = true`
  und werden ausgeschlossen.
- Automatisch erfasste Samples von iPhone und Apple Watch tragen den Schlüssel gar nicht. `!= true` lässt sie durch.
  `== false` würde dagegen fast alle Sensordaten ausschließen.
- Das Zusammenführen der Quellen funktioniert auch mit dem zusätzlichen Filter, weil HealthKit erst filtert und
  dann zusammenführt.

### Bekannte Grenzen

- Apple dokumentiert nicht ausdrücklich, dass Samples ohne den Schlüssel einen `!= true`-Filter erfüllen. Belegt ist
  das durch Feldberichte (u. a. weit verbreitete Plugins seit 2024). **Auf einem echten iPhone prüfen:** An einem
  Tag ohne manuelle Einträge müssen Health Steps und Competition Steps gleich sein.
- In seltenen Fällen können Competition Steps größer sein als Health Steps: Manuell eingetragene Daten haben in
  Health standardmäßig Vorrang. Überlappt ein manueller Eintrag mit Sensordaten, zählt Health den manuellen Wert,
  Pace für den Wettbewerb dagegen die Sensordaten. Die UI setzt deshalb kein `≤` voraus.
- `HKMetadataKeyWasUserEntered` setzt die schreibende App selbst. Eine Dritt-App kann Schritte ohne diesen Schlüssel
  schreiben. Ein strengerer Schutz (z. B. nur Apple-Geräte als Quelle) wäre eine Produktentscheidung für spätere
  Milestones.

## Verfügbarkeit statt Fake-Nullen

HealthKit verrät nicht, ob der Lesezugriff verweigert wurde. Ohne Zugriff sind schlicht keine Daten sichtbar.
Deshalb gilt pro Kennzahl (`ActivitySummaryLoader`):

| Situation | Ergebnis |
|---|---|
| Samples im Zeitraum | Werte; Tage ohne Samples = 0 |
| Keine Samples im Zeitraum, aber irgendwann welche | 0 |
| Überhaupt keine Samples lesbar | nicht verfügbar (`nil`), wird nicht angezeigt |
| Keine Schritte lesbar | Zustand „Keine Schrittdaten lesbar“ mit Anleitung |

Unter iOS 27 können Nutzer den Zugriff auf einen Zeitraum begrenzen. Tage vor dieser Grenze erscheinen dann als 0.
Das betrifft nur die Statistik der letzten 7 Tage.

## Zeiträume und Kalender

- Ein Tag ist der lokale Kalendertag in der aktuellen Zeitzone des Geräts (gregorianisch, halboffen
  `[00:00, 00:00 des Folgetags)`). An Tagen mit Zeitumstellung hat er 23 bzw. 25 Stunden.
- Woche = ISO-Woche Montag bis Sonntag. Das passt zu den späteren Weekly-Rankings im Backend.
- Geladen werden immer die letzten 7 Tage. Daraus ergeben sich „heute“, „gestern“, „aktuelle Woche“ und
  „letzte 7 Tage“.
- Der **Monatskalender** beginnt in allen Sprachen am Montag (wie Woche und Streak).
  Er liest nichts zusätzlich, sondern nutzt den Verlauf (siehe unten): zurück bis zum Anfang des Verlaufs (12 volle
  Monate), vorwärts bis zum aktuellen Monat. Zustände je Tag: Ziel erreicht (volle Fläche), gemessen aber nicht
  erreicht (Ring, auch bei gemessenen 0 Schritten), keine Daten (gestrichelter Ring, „–“), Zukunft (neutral, „–“).
  Die Auswahl ist ein eigener Zustand: ein Akzentrahmen mit Abstand außen um das Feld (auch im Dark Mode und um
  gefüllte Tage klar sichtbar) – sie verändert das Feld selbst nicht und sieht nie wie „Ziel erreicht“ aus.
- Bewertet wird jeder Tag mit dem **damals gültigen Tagesziel** (`StepGoalHistory`) – dieselbe Grundlage wie die
  Streak. Eine spätere Zieländerung verändert vergangene Tage nicht.

### Aktive Energie (kcal): drei Zustände

- **gemessen** – Summe der aktiven Energie des Tages aus Apple Health,
- **gemessene 0** – Health hat Samples, aber 0 kcal für den Tag,
- **nicht verfügbar** – für den Tag liegt kein Wert vor (kein Zugriff, kein Gerät, das misst). Angezeigt als
  „Nicht verfügbar“ mit Erklärung – nie als erfundene 0.

Gleich auf Home, in den Tagesdetails, der Woche, dem Monat und im Kalender.

### Kalorienschätzung ohne Apple Watch (Auftrag 4, freiwillig)

Profil → Einstellungen → Aktivität & Gesundheit → **Kalorienschätzung**: Größe (100–250 cm), Gewicht (30–300 kg),
Schalter (Standard: aus). Nur wenn eingeschaltet, beide Werte gültig sind **und Apple Health für den Tag keine
gemessenen aktiven Kalorien hat**, zeigt Pace einen Schätzwert (`CalorieEstimator`, `PaceCore/Activity`):

- Modell: ACSM-Gleichung für Gehen auf ebener Strecke – Netto-Sauerstoffbedarf 0,1 ml je kg und Meter, 1 l O₂ ≈ 5 kcal
  → **0,0005 kcal je kg Körpergewicht und Meter** (≈ 0,5 kcal je kg und km, ohne Grundumsatz).
- Strecke: Distanz aus Apple Health; fehlt sie (oder sind manuell eingetragene Schritte im Spiel), automatisch
  erfasste Schritte × Schrittlänge (0,414 × Körpergröße). Kein fester Wert pro Schritt.
- Ohne erfasste Bewegung gibt es keinen Schätzwert (nicht „0 kcal“).
- Gemessen hat immer Vorrang; Messung und Schätzung werden nie addiert. Ein Zeitraum mit mindestens einem geschätzten
  Tag gilt als geschätzt.
- Kennzeichnung überall: „≈ 245 kcal“ mit „Geschätzte aktive Kalorien“ (Home, Aktivitäts-Widget, Tagesdetails),
  Statistik mit Herkunft „Gemessen“/„Geschätzt“; auch Kacheln (Ø, bester Tag, Vorzeitraum) und Bestwerte tragen „≈“,
  sobald ein beteiligter Tag geschätzt ist. Für geschätzte Tage gibt es keine Stundenbalken (Apple Health hat keine
  Stundenwerte) – stattdessen ein Hinweis, nie eine Linie aus Nullen.
- Grenzen: Steigungen, Treppen und Laufen werden nicht eigens berücksichtigt (Laufen kostet etwa doppelt so viel).
- Datenschutz: Größe und Gewicht werden nur auf dem Gerät gespeichert (`UserDefaults`, Schlüssel
  `pace.bodyMetrics.v1`; wie alle App-Daten Teil der Gerätebackups; im Datenexport enthalten, beim Löschen entfernt)
  und gehen nie an Server, Freunde, Gruppen, Rankings oder Chats.
  Schritte, Wettbewerbsschritte und Rankings bleiben von der Schätzung unberührt.

## Live-Schritte (Core Motion)

Solange Pace im Vordergrund ist, zählt die Anzeige „Deine Schritte heute“ über `CMPedometer` live mit
(`PedometerLiveSteps`, nur mit Erlaubnis „Bewegung & Fitness“, `NSMotionUsageDescription`). `LiveStepEstimator`
verhindert doppeltes Zählen:

- Grundlage bleibt der letzte HealthKit-Wert (Wettbewerbsschritte). Der Sensor liefert nur den Zuwachs seit diesem
  Wert; jeder neue HealthKit-Wert setzt die Basis neu (die Schritte sind dann in Health enthalten).
- Die Anzeige sinkt nie innerhalb eines Tages (hinkt Health hinterher, bleibt sie stehen, bis Health aufholt); ein
  neuer Tag beginnt mit dem HealthKit-Wert; ein neu gestarteter Sensor (kleinerer Zählerstand) zählt nicht doppelt.
- Die Live-Werte sind **nur Anzeige**: Rankings, Synchronisierung, Streak und Erinnerungen nutzen ausschließlich die
  HealthKit-Wettbewerbsschritte (manuell eingetragene Schritte zählen weiterhin nicht – die Live-Vorschau umgeht das
  nicht, weil der Sensor nur echte Bewegung misst und Health die Basis bleibt).
- Ohne Erlaubnis oder ohne Sensor zeigt Pace wie bisher die HealthKit-Werte.

## Wann gelesen wird

- Beim Start, bei Rückkehr in die App, per Pull-to-Refresh und bei Tages-/Zeitzonenwechsel.
- Sofort, wenn HealthKit neue Samples meldet (`HKObserverQuery`).
- Zusätzlich alle 15 Sekunden, solange die App im Vordergrund ist. Gelesen wird lokal aus Apple Health; nur wenn
  sich die Wettbewerbsschritte geändert haben, gehen sie gedrosselt (höchstens einmal pro Minute) an das Backend.
- Schneller als Apple Health selbst geht es nicht: iOS schreibt die Schritte des iPhones gebündelt nach Health.
  Pace bietet bewusst keine Möglichkeit, Schritte manuell einzutragen.

### Verlauf für Statistik, Bestwerte und Streak

- Die letzten 7 Tage kommen immer aus dem laufend aktualisierten Stand von Home (siehe oben) – „heute“ ist in
  Statistik und Streak deshalb genauso aktuell wie auf Home, ohne zusätzliche Abfragen.
- Ältere Tage liest `ActivityHistoryStore` als Tageswerte vom Monatsanfang vor 12 Monaten bis heute: eine
  Statistik-Abfrage (`HKStatisticsCollectionQuery`, Tages-Buckets) je Kennzahl. Neu gelesen wird erst nach einem
  Tageswechsel oder wenn der Stand älter als eine Stunde ist – dadurch fließen spät synchronisierte Werte (z. B. von
  der Apple Watch, die teils erst Stunden später in Health landen) ein, ohne den Akku zu belasten.
- Stundenwerte lesen nur die Tagesansicht der Statistik und die Tagesdetails (`hourlyTotals`, Stunden-Buckets,
  Wettbewerbsschritte) – für vergangene Tage einmal, für heute erneut, sobald sich der Tageswert ändert; die
  Statistik zusätzlich den Vortag für den Vergleich „zur gleichen Zeit“.
- Die **Tagesdetails** (Kalender → Tag, Statistik → „Alle Tagesdetails“) zeigen Schritte, das Ziel dieses Tages, den
  Rest bis zum Ziel, Distanz, aktive Kalorien, Stockwerke, Trainingsminuten, den Tagesverlauf, die Streak und die
  letzten 7 Tage. Nicht lesbare Kennzahlen erscheinen als „–“.
- **Streak:** Ein laufender Tag unterbricht die Serie nicht. Die Tagesdetails zeigen deshalb „aktuelle Serie bis
  gestern“ und „Erreiche heute dein Ziel für Tag n“; sobald heute erreicht ist, zählt der Tag sofort. Für vergangene
  Tage beschreibt die Karte die Serie an diesem Tag. Tagesgrenzen folgen dem Kalender oben (auch beim
  Sommerzeitwechsel wird jeder Tag genau einmal gezählt); spät synchronisierte Werte fließen über die live
  aktualisierten letzten 7 Tage bzw. das stündliche Neuladen des Verlaufs ein.
- Alle Werte bleiben auf dem Gerät. Für Streak und Zieltage zählt wie überall die Wettbewerbsschrittzahl.
- Gezählt wird aus Apple Health: Nur Health führt iPhone und Apple Watch ohne Doppelzählung zusammen. Core Motion
  dient ausschließlich der Live-Anzeige auf Home (siehe „Live-Schritte“).

## Was ins Backend geht

Tabelle `daily_activity` (siehe `docs/BACKEND.md`):

| Feld | Inhalt |
|---|---|
| `user_id` | Pace-Nutzer |
| `activity_date` | lokaler Kalendertag (`YYYY-MM-DD`) |
| `competition_steps` | Competition Steps dieses Tags (0 bis 200.000) |
| `synced_at`, `steps_changed_at` | vom Server gesetzt |

Bewusst **nicht** im Backend: Health Steps, Distanz, aktive Energie, Stockwerke, Trainingsminuten, Ruhepuls und
Puls beim Gehen. Keine dieser Zahlen wird für eine Social- oder Wettbewerbsfunktion gebraucht.

Synchronisiert werden die Competition Steps der letzten 7 Tage, aber nur Tage, deren Wert sich geändert hat:

- beim App-Start, bei Rückkehr in die App, bei Pull-to-Refresh und vor dem Laden eines Rankings;
- bei HealthKit-Updates höchstens einmal pro Minute.

Es gibt kein Polling.

## Was andere sehen

In öffentlichen Regionalrankings (nur nach ausdrücklicher Zustimmung) sehen andere Nutzer ausschließlich
Anzeigename, Benutzername, die Competition Steps des Tags und den Rang. Keine weiteren Gesundheitswerte, keine
Gemeinde anderer Nutzer, keine Standortdaten.

Ist die Ranking-Sichtbarkeit ausgeschaltet, lädt der Rankings-Tab **keine** regionalen Rankingdaten und lädt auch
keine Schritte „für das Ranking“ hoch. Die Karte zeigt nur eine unscharfe Struktur mit neutralen Platzhaltern,
„Ranking ausgeschaltet“ und die Aktion „Ranking-Sichtbarkeit aktivieren“ (mit Bestätigung, gespeichert über
`ProfileStore.setRegionalLeaderboardEnabled`). Das Freunde-Ranking ist davon unabhängig: Freunde teilen ihre
Wettbewerbsschritte mit der Freundschaft.
