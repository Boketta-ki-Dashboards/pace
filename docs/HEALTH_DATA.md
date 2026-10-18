# Gesundheitsdaten in Pace

Pace ist eine Wettbewerbs-App für Bewegung, keine Fitness- oder Gesundheits-App. Gesundheitsdaten sind nur Mittel
zum Zweck: Sie liefern die Schritte für den Wettbewerb und ein paar persönliche Zusatzwerte.

## Grundsatz

1. **Nur lesen, nichts schreiben.** Pace fordert ausschließlich Lesezugriff an. Es gibt keinen
   `NSHealthUpdateUsageDescription`-Text, weil Pace nichts in Health schreibt (die CI prüft das).
2. **Nur Bewegungsdaten.** Keine Herzfrequenz, kein Ruhepuls, kein Gewicht, kein Körperfett, kein Schlaf, kein
   Blutdruck, kein Blutzucker, keine Zyklusdaten, keine medizinischen Daten.
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
- Stundenwerte liest nur die Tagesansicht der Statistik (`hourlyTotals`, Stunden-Buckets) – für vergangene Tage
  einmal, für heute erneut, sobald sich der Tageswert ändert, plus der Vortag für den Vergleich „zur gleichen Zeit“.
- Alle Werte bleiben auf dem Gerät. Für Streak und Zieltage zählt wie überall die Wettbewerbsschrittzahl.
- CoreMotion wird nicht verwendet: Die Schritte des iPhones stehen über Health bereits zur Verfügung, und nur Health
  führt iPhone und Apple Watch ohne Doppelzählung zusammen.

## Was ins Backend geht

Tabelle `daily_activity` (siehe `docs/BACKEND.md`):

| Feld | Inhalt |
|---|---|
| `user_id` | Pace-Nutzer |
| `activity_date` | lokaler Kalendertag (`YYYY-MM-DD`) |
| `competition_steps` | Competition Steps dieses Tags (0 bis 200.000) |
| `synced_at`, `steps_changed_at` | vom Server gesetzt |

Bewusst **nicht** im Backend: Health Steps, Distanz, aktive Energie, Stockwerke, Trainingsminuten. Keine dieser
Zahlen wird für eine Social- oder Wettbewerbsfunktion gebraucht.

Synchronisiert werden die Competition Steps der letzten 7 Tage, aber nur Tage, deren Wert sich geändert hat:

- beim App-Start, bei Rückkehr in die App, bei Pull-to-Refresh und vor dem Laden eines Rankings;
- bei HealthKit-Updates höchstens einmal pro Minute.

Es gibt kein Polling.

## Was andere sehen

In öffentlichen Regionalrankings (nur nach ausdrücklicher Zustimmung) sehen andere Nutzer ausschließlich
Anzeigename, Benutzername, die Competition Steps des Tags und den Rang. Keine weiteren Gesundheitswerte, keine
Gemeinde anderer Nutzer, keine Standortdaten.
