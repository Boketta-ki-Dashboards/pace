# Home & Widgets

Dieses Dokument beschreibt das Home-Dashboard (Referenzbild 9), den Anpassen-Modus (Bild 6), die Widget-Galerie
(Bild 7) und das Speicherformat der Widgets. Code: `Packages/PaceKit/Sources/HomeFeature`.

## Aufbau von Home

Reihenfolge im Standardlayout (freigegebenes Home-Design):

1. Kopf: Pace-Wortmarke und „Anpassen“ (gefüllter Knopf mit Regler-Symbol), darunter die Begrüßung („Hi Niklas“ /
   „Hi Niklas“ / „Привет, Niklas“) mit Kalender- und Glocken-Symbol.
2. Vier regionale Karten in einer Reihe: Stadt/Gemeinde · Landkreis · Bundesland · Land.
3. „Deine Schritte heute“ (visueller Mittelpunkt, „Tagesziel ändern“ ändert nur das Ziel).
4. „Deine Woche“.
5. Ranking-Umfeld („Pfungstadt · Dein Umfeld“) mit „Noch x Schritte bis Platz #n“ aus echten Wettbewerbsschritten.
6. Freunde- und Gruppen-Widgets.
7. Weitere Widgets (persönliche Streak, Aktivität, Kalender …).

Kalender-Symbol → `CalendarRoute` (`CalendarView`, Inhalt aus dem Kalender-Paket). Schrittkarte, Distanz,
Kalorien, Woche, Streak und Aktivität öffnen `StatisticsRoute` (`StatisticsView` mit Zurück-Link „Home“). Glocke → Unterseite
„Mitteilungen“ mit echten Einträgen; ein Badge zeigt deren Anzahl.

### Mitteilungen

Ausschließlich aus echten Daten des `SocialViewModel` (geteilt mit dem Social-Tab):

- eingehende Freundschaftsanfragen (`incomingRequests`),
- Gruppeneinladungen (`invitations`),
- Unterhaltungen mit ungelesenen Nachrichten (`social.chats.conversations`, `unreadCount > 0`).

Neueste zuerst; Tippen führt in den Social-Tab (`openSocial()`). Ohne Social-Backend erscheint ein gestalteter
Hinweis, ohne Einträge „Alles gelesen“. Keine erfundenen Mitteilungen.

### Regionale Karten

`HomeRegionCards.cards(hierarchy:standings:levels:)` liefert **immer** alle gewählten Ebenen (Standard: vier), in jeder
Widget-Größe in einer Reihe (kein 2 × 2):

| Region | Stadt | Landkreis | Bundesland | Land |
|---|---|---|---|---|
| Pfungstadt | Stadt #12 | Landkreis #148 | Bundesland #2.410 | Land #18.520 |
| Frankfurt (kreisfreie Stadt) | Stadt #40 | Kreisfreie Stadt #40 | Bundesland | Land |
| Berlin (Stadtstaat) | Stadt #7 | Kreisfreie Stadt #7 | Stadtstaat #7 | Land |

Hat eine Ebene dieselben Gemeinden wie die kleinere, gilt deren Ranking (gleicher Platz, passende Bezeichnung);
Tippen öffnet dieses Ranking. Lange Namen („Darmstadt-Dieburg“) brechen um.

### Ranking ausgeschaltet

Ist die Ranking-Sichtbarkeit aus (`regionalLeaderboardEnabled == false`), bleiben die Ranking-Widgets (vier Karten,
Umfeld, weitere regionale Widgets) an ihrer Stelle – als `PaceLockedCard` mit unscharfen **neutralen Platzhaltern**
(`RegionRanksPlaceholder`, `NeighborhoodPlaceholder`), `eye.slash`, „Ranking ausgeschaltet“ und kurzer Erklärung.
Es werden dafür keine Rankingdaten geladen (`RegionalStandingsViewModel` fragt ohne Teilnahme keine RPCs ab), VoiceOver
liest nur Überschrift, Erklärung und Aktion. „Ranking-Sichtbarkeit aktivieren“ → Bestätigung → `enableParticipation()`
speichert im Profil und auf dem Server und lädt danach die Platzierungen. Freunde- und Gruppen-Widgets sind davon
nicht betroffen (eigene Regeln).

## Anpassen-Modus (Bild 6)

„Anpassen“ schaltet Home direkt in den Bearbeitungszustand (kein Sheet):

- Kopf: „Fertig“ (mint Pille) statt „Anpassen“, „+ Widget hinzufügen“ (mint Pille) statt Kalender/Glocke, darunter
  „Halten und verschieben, um deine Übersicht anzupassen.“ mit Griff-Symbol.
- Jedes Widget: X oben links (Entfernen mit „Rückgängig“-Leiste; „Deine Schritte heute“ ist Pflicht und hat kein X),
  oben rechts „Größe auswählen“ mit Menü Klein/Mittel/Groß/Max (Haken an der aktuellen, nur unterstützte Größen) und
  Ziehgriff (sechs Punkte). Keine Ziehecken.
- Umsortieren am Ziehgriff (sechs Punkte) mit einer eigenen Geste (`HomeReorderController`, kein System-Drag &
  Drop mehr): Das Widget hängt am Finger (leicht vergrößert, Schatten), die anderen weichen animiert aus, sobald seine
  Mitte über einem anderen Platz liegt (`HomeReorderMath.targetIndex`); Haptik bei jedem Platzwechsel. Nahe am oberen
  bzw. unteren Rand scrollt die Seite automatisch mit (`CADisplayLink`, Geschwindigkeit steigt quadratisch bis
  1.150 pt/s, `HomeReorderMath.autoScrollVelocity`) – so lassen sich Widgets über mehrere Bildschirmhöhen verschieben.
  Während des Ziehens ist das normale Scrollen gesperrt, das Wischen zwischen Tabs ebenfalls. Loslassen speichert die
  neue Reihenfolge sofort; „Fertig“ oder Verlassen beendet ein laufendes Ziehen sauber. VoiceOver-Alternative:
  Aktionen „Nach oben/unten verschieben“, Größen und Entfernen am Titel jedes Widgets.
- „Größe auswählen“ trägt das Symbol aus dem Anpassen-Design (`HomeSizeGlyph`: Quadrat mit offener Ecke und
  versetztem kleinen Quadrat), gezeichnet als Pfad und mit der Schriftgröße skaliert.
- Dezentes Wackeln (±0,45°), bei reduzierter Bewegung aus. Das aktive Widget (Größenmenü offen, gerade bewegt) hat
  einen mint Rahmen.
- Inhalte sind nicht antippbar (keine versehentliche Navigation); Antippen eines Widgets öffnet die Galerie zum
  Bearbeiten seiner Auswahl.
- Jede Änderung wird sofort gespeichert; „Fertig“ beendet nur den Modus.

## Widget-Galerie (Bild 7)

Unterseite von Home: „‹ Anpassen“ → pace → „Widget hinzufügen“ (bzw. „Widget bearbeiten“).

1. **Kategorie** (2 Spalten): Schritte und Aktivität · Wochenübersicht · Persönliche Streak · Freunde · Gruppen
   („Gruppe auswählen“) · Regionale Rankings („Stadt · Landkreis · Bundesland · Deutschland“) · Ranking-Umfeld ·
   Kalender. Einzel-Widgets, die schon auf Home sind, tragen „Schon auf Home“.
2. **Auswahl je Art**: Freunde (Chips mit Haken/Plus, „Weitere…“ → vollständige Liste, Widget-Name mit Löschen,
   Hinweis „Mehrere Freunde-Widgets mit eigener Auswahl möglich – ohne Gruppe.“), Gruppen (Alle Gruppen oder eine
   Gruppe), Regionale Rankings (Ebenen, mindestens eine), Ranking-Umfeld (Ebene mit Gebietsnamen), Aktivität
   (Schritte, Distanz, aktive Kalorien); Woche, Streak, Kalender ohne weitere Auswahl.
3. **Widget-Vorschau**: das echte Widget mit echten Daten in der gewählten Größe; ändert sich sofort mit Kategorie,
   Auswahl und Größe.
4. **Größe auswählen**: vier Kacheln mit verkleinerter Live-Vorschau; nicht unterstützte Größen sind deaktiviert.
5. „Widget hinzufügen“ bzw. „Änderungen sichern“. Doppelte Widgets (z. B. zweimal dieselbe Gruppe) werden mit Hinweis
   verhindert.

## Widgets und Größen

| Widget | Klein | Mittel | Groß | Max |
|---|---|---|---|---|
| Regionale Karten | Leiste mit Platz und Ebene | vier Karten (Bild 9) | Karten + Abstand zum nächsten Platz | dazu je Ebene „Noch … bis Platz …“ |
| Schritte heute | – | Bild 9 | + Stockwerke, Trainingsminuten | + gestern, Ø 7 Tage |
| Woche | Summe + Zieltage | 7 Tageskacheln | + Gesamt, Durchschnitt | Diagramm mit Achse und Ziellinie |
| Persönliche Streak | Flamme + Serie | Serie + Rekord + Status | + Wochenleiste | + 4 Wochen kompakt, letzte 30 Tage |
| Ranking-Umfeld | eigener Platz + Abstand | 3 Zeilen | 5 Zeilen | Diagramm (bis 7 Plätze) |
| Freunde | Platz 1 | Top 3 (du immer dabei) | Top 5 | Diagramm + Top 5 |
| Gruppe (eine) | Name + Serie | + heutiger Fortschritt | + Tagesziel, beste Serie | + Kennzahlen, Beschreibung |
| Gruppen (alle) | längste Serie | 3 Gruppen | 5 Gruppen | 8 Gruppen |
| Aktivität | Wert heute | + Mini-Diagramm | + Summe, Durchschnitt | großes Diagramm + bester Tag |
| Kalender | laufende Woche | zwei Wochen | Monat | Monat mit Schrittzahlen |

- **Streak**: Ist die Serie 0, zeigt der Verlauf trotzdem erreichte Tage; der Status erklärt den Unterschied
  („Gerade keine laufende Serie – diese Woche hast du dein Ziel an 2 Tagen erreicht.“).
- **Kalender**: nicht erreicht = Ring mit Fortschritt auf neutraler Fläche, erreicht = volle grüne Fläche
  (`goalReachedFill`), heute umrandet, Zukunft neutral ohne Werte. Jeder Tag wird mit dem damals geltenden Ziel
  bewertet (Zielverlauf), wie die Streak. Tippen öffnet den Kalender.
- **Gruppen-Widget**: Tippen öffnet die echte Gruppe (`social.showGroup(id)` + Social-Tab). Gibt es die Gruppe nicht
  mehr, erscheint ein Hinweis statt einer leeren Karte.
- **Freunde-Widget**: nur die ausgewählten Freunde + „Du“ aus dem echten Freundesranking; Plätze innerhalb der
  Auswahl. Nicht mehr befreundete Personen werden als Hinweis gezählt.

## Speicherformat (Version 3)

`UserDefaults`-Schlüssel `pace.home.preferences`, JSON:

```json
{
  "version": 3,
  "stepGoal": 12500,
  "modules": [
    { "id": "…", "kind": "regionRanks", "size": "medium" },
    { "id": "…", "kind": "friends", "size": "large",
      "config": { "friendIDs": ["…", "…"], "name": "Meine Laufrunde" } },
    { "id": "…", "kind": "groups", "size": "small", "config": { "groupID": "…" } },
    { "id": "…", "kind": "neighborhood", "size": "max", "regionLevel": "district" },
    { "id": "…", "kind": "activity", "size": "medium", "config": { "metric": "distance" } }
  ]
}
```

- Position = Reihenfolge in `modules`. `config` fehlt bei Widgets ohne eigene Einstellungen.
- Version 2 (gleiche Felder ohne `config`/`max`) wird verlustfrei übernommen; Version 1 (`sections` mit
  `isVisible`) wird in Nutzer-Reihenfolge migriert, die Streak kommt nach der Woche. `stepGoal` bleibt, bis der
  Zielverlauf es übernommen hat.
- Tolerant: unbekannte Arten werden übersprungen, unbekannte Größen fallen auf „Mittel“ zurück, unbekannte Felder
  und kaputte IDs werden ignoriert. `normalized()` entfernt doppelte IDs und doppelte Widgets (`uniquenessKey`) und
  ergänzt die Schrittkarte.
- Mehrfach erlaubt: regionale Rankings (verschiedene Ebenen), Umfeld, Freunde (eigene Auswahl/Name), Gruppen
  (verschiedene Gruppen), Aktivität (verschiedene Kennzahlen). Einmalig: Schritte heute, Woche, Streak, Kalender.

## Sprache

Alle Texte des HomeFeature in Deutsch, Englisch und Russisch über `PaceLocalization` (`HomeTexts`, Modelle mit
berechneten Texten). Zahlen über `paceFormatted`, Datumsangaben über `ActivityFormatter`/`HomeFormat`.

## Tests

- Linux (`Tests/HomeFeatureTests`): Speicherformat v3, Migration v1/v2, unbekannte Felder, Hinzufügen/Entfernen/
  Rückgängig/Verschieben/Größe inkl. „Neustart“, mehrere Freunde-Widgets, Dubletten, gelöschte Freunde/Gruppen,
  vier Karten bei kreisfreier Stadt und Stadtstaat, Mitteilungen aus echten Social-/Chat-Daten, Ranking aus lädt
  keine Rankingdaten, Galerie, Sprache.
- Snapshots (`Tests/PaceSnapshotTests/HomeSnapshotTests.swift`): `home`, `home-edit` (mit offenem Größenmenü),
  `widget-gallery` (DE/EN/RU), `home-widgets-small|medium|large|max`, `home-ranking-off`, `home-notifications` –
  jeweils Hell und Dunkel.

## Nur auf dem iPhone prüfbar

Drag & Drop mit Haptik, Wackeln und Reduce Motion, Größenmenü über anderen Widgets, Textfeld und Tastatur in der
Galerie, Wisch-Geste zurück, VoiceOver-Aktionen, Dynamic Type in großen Stufen.
