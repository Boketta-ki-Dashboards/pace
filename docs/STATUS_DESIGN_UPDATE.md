# Design- und Funktions-Update (Referenzbilder 1–9) – Ausgangsstand, Plan und Endstand

## Ausgangsstand (Sicherungspunkt)

- Branch `claude/gallant-brahmagupta-hvvp13`, Ausgangs-Commit **b9fb7e3** (lokal = Remote, keine offenen Änderungen).
- CI auf b9fb7e3 grün (iOS: Build ohne Warnungen, Tests, Snapshots; Backend: pgTAP, Lint, Advisors, Integrationstests).
- Nachgeprüfte Testzahlen dieses Stands: 318 Swift-Tests (Linux), 370 Datenbanktests (pgTAP, 8 Dateien),
  50 Backend- und Integrationstests gegen lokales Supabase.
- Die Social-Migration `supabase/migrations/20261018100000_social.sql` ist **nicht** im produktiven Projekt
  `bnkrenfvfiaapsbkeejq` eingespielt. Produktive Änderungen erfolgen erst nach ausdrücklicher Freigabe.

## Bestand (bereits vorhanden, wird wiederverwendet)

| Bereich | Vorhanden |
|---|---|
| Home | Module (klein/mittel/groß), Speicherung v2 mit Migration aus v1, Regionskarten, Schritte heute, Woche, Serie, Umfeld, Freunde/Gruppen-Vorschau |
| Statistik | Tag/Woche/Monat für Schritte, Distanz, Kalorien; 12 Monate Verlauf; historische Tagesziele; Bestwerte |
| Serie | Persönliche Serie, Rekord, laufender Tag bricht die Serie nicht |
| Social-Backend | Freundschaften, Anfragen, Gruppen, Einladungen, Gruppen-Streak (⌈n/3⌉) serverseitig, RLS ohne Policies, Rate-Limits |
| Social-App | Social-Tab (alter Aufbau), Gruppendetails, Freundesprofil |
| Profil | Name, Region, Ranking-Sichtbarkeit, Tagesziel, Serie/Rekord, App-Icon (Automatisch/Hell/Dunkel) |
| HealthKit | Schritte, Distanz, aktive Energie, Stockwerke, Training; Wettbewerbsschritte ohne manuelle Einträge |

## Lücken zu Beginn gegenüber dem Master-Prompt (Auszug)

- Eigene Tab-Leiste (aktiver Tab: Symbol **und** Text in einer Fläche), einheitlicher Unterseiten-Kopf
  (Zurück → pace → Titel).
- Lokalisierung Deutsch/Englisch/Russisch (bisher feste deutsche Texte), Formate je Sprache.
- Regionskarten: Größe „Groß“ zeigt bisher ein 2×2-Raster – muss immer eine Reihe sein.
- „Ranking ausgeschaltet“-Zustand mit Unschärfe statt Teilnahme-Hinweis.
- Social-Hauptseite nach Bild 9, „Freund hinzufügen“ (Bild 1), „Freundschaftsanfragen“ (Bild 2).
- Blockieren, Melden, Präfix-Suche, öffentliches Kurzprofil; Rate-Limit für `is_username_available`.
- Gruppe erstellen mit Bild, Privatsphäre, Einladungen (Bild 3); Gruppendetails (Bild 4); Gruppenchat (Bild 5);
  Privatchats; Bilder/GIFs; geteilte Profile; Ungelesen-Zähler.
- Home-Bearbeitungsmodus (Bild 6) mit Wackeln, X, Verschieben, Größe inkl. „Max“; Widget-Galerie (Bild 7) mit
  Konfiguration (z. B. mehrere Freunde-Widgets).
- Monatskalender (Bild 9) und ausführliche Tagesdetails (Bild 8), optional Ruhepuls und Geh-Puls.
- Einstellungen im Profil: Darstellung, Sprache, Privatsphäre, Benachrichtigungen, Datenschutz (Export, Konto
  löschen), Hilfe.

## Vorgehen

Phasen D2–D8 (siehe Commits): gemeinsame UI-Regeln → Social → Gruppen und Chats → Dashboard-Anpassung →
Kalender und Tagesdetails → Profil und Einstellungen → Verifikation. Jede Phase wird lokal (Linux-Tests, lokales
Supabase) und in der CI geprüft und einzeln committet.

## Endstand (20.10.2026)

Alle Phasen D2–D8 sind umgesetzt und auf dem Branch `claude/gallant-brahmagupta-hvvp13` gepusht (79 Commits seit
b9fb7e3, Sicherungspunkte 0b05480/83b17a1). **Im produktiven Supabase-Projekt `bnkrenfvfiaapsbkeejq` wurde nichts
verändert**; die sechs neuen Migrationen liegen nur im Repository (Rollout: [SUPABASE_ROLLOUT.md](SUPABASE_ROLLOUT.md),
erst nach ausdrücklicher Freigabe). Ein Test auf einem echten iPhone steht aus ([IPHONE_TEST.md](IPHONE_TEST.md),
[MANUAL_TESTS.md](MANUAL_TESTS.md)).

### Stand je Bereich

„Design fertig“ heißt: in Snapshots (Simulator, Hell/Dunkel, DE/EN/RU) mit den Referenzbildern verglichen – nicht auf
einem Gerät gesehen. „Backend getestet“ heißt: gegen einen lokalen Supabase-Stack (Docker) und in der CI geprüft.

| Bereich | Design fertig | Funktion fertig | Backend getestet | Produktiv bereit |
|---|---|---|---|---|
| Home | ja (Bild 9) | ja | ja (Rankings-RPCs bestehen produktiv) | ja – Glocke, Freunde-/Gruppen-Widgets erst nach Migration; iPhone-Test offen |
| Rankings | ja | ja | ja | regional ja; Freunde/Gruppen erst nach Migration |
| Social | ja (Bild 9) | ja | ja | nein – Migrationen nicht eingespielt |
| Freund hinzufügen | ja (Bild 1) | ja | ja | nein – Migrationen |
| Freundschaftsanfragen | ja (Bild 2) | ja | ja | nein – Migrationen |
| Gruppen (erstellen) | ja (Bild 3) | ja | ja | nein – Migrationen |
| Gruppendetails | ja (Bild 4) | ja | ja | nein – Migrationen |
| Gruppenchat | ja (Bild 5) | ja | ja (Echtzeit per Node-Test) | nein – Migrationen, Realtime-Einstellung |
| Privatchat | ja (wie Bild 5) | ja | ja (Echtzeit per Node-Test) | nein – Migrationen, Realtime-Einstellung |
| Widgets | ja (Bilder 6, 7) | ja | lokal gespeichert (kein Backend) | ja – Freunde-/Gruppen-Widgets nach Migration |
| Kalender | ja (Bild 9) | ja | entfällt (HealthKit auf dem Gerät) | ja – iPhone-Test offen |
| Tagesdetails | ja (Bild 8) | ja | entfällt (HealthKit auf dem Gerät) | ja – iPhone-Test offen |
| Profil | ja | ja | ja | Name/Region ja; Profilbild erst nach Migration |
| Einstellungen | ja | ja | ja | lokal ja; Auffindbarkeit, Blockierliste, „Problem melden“/„Feedback senden“, Export, Konto löschen nach Migration |

### Tests (Endstand)

| Prüfung | Beginn (b9fb7e3) | Endstand |
|---|---|---|
| Swift-Tests unter Linux (PaceCore, ViewModels) | 318 | 611 in 75 Suiten, alle grün |
| Datenbanktests (pgTAP) | 370 in 8 Dateien | 705 in 13 Dateien, alle grün |
| Backend- und Integrationstests gegen lokales Supabase | 50 | 102 in 18 Suiten grün, 1 übersprungen (Echtzeit über WebSocket nur auf Apple-Plattformen) |
| Realtime-Rauchtest (Node, private Kanäle, Abweisung Fremder) | – | 9/9 bestanden |
| `supabase db lint` / Advisors | sauber | sauber |
| CI (iOS: Build ohne Warnungen, Tests, Snapshots; Backend) | grün | grün |

Grüne Tests und CI belegen keine vollständige Produktreife: HealthKit-Werte, App-Icon, Mitteilungen, Fotoauswahl,
Drag & Drop und Echtzeit zwischen zwei Geräten sind nur auf echten iPhones prüfbar.

### Bewusste Abweichungen und offene Punkte

- **Social-Hauptseite:** zusätzliche Zeile „Gruppen“ (Weg zu allen Gruppen), die Bild 9 nicht zeigt.
- **Chats:** keine Lesebestätigungen („gelesen“) – der Vertrag kennt nur den eigenen Lesestand und Ungelesen-Zähler.
  Keine Push-Mitteilungen für neue Nachrichten (bräuchte einen APNs-Schlüssel und einen Server-Dienst); neue
  Nachrichten kommen in Echtzeit, solange Pace geöffnet ist.
- **Widget-Galerie:** Freunde-Chips im 2 × 2-Raster statt einer Reihe, damit Namen nicht abgeschnitten werden.
- **„Deine Woche“:** Mittel = Tageskacheln, Max = Diagramm mit Achse und Ziellinie (Größen gab Bild 6 nur teilweise vor).
- **Kalender:** Kopf mit Wortmarke wie alle Unterseiten (Abschnitt 4), Legende kompakt neben der Monatsnavigation.
- **Snapshots:** gerendert mit 393 pt Breite, die Referenzen mit etwa 430 pt; Profilbilder und Fotos erscheinen dort
  als Initialen, weil Bilder asynchron laden.
- **Konto:** weiterhin anonym und an das iPhone gebunden; „Mit Apple anmelden“ bzw. Kontoübertragung nicht eingebaut
  (ehrlich als „In Vorbereitung“ gekennzeichnet).
- **Rechtstexte** (Datenschutzerklärung, Nutzungsbedingungen, Impressum) sind Entwürfe und vom Betreiber zu ergänzen.
- **Mitteilungen:** Die Tagesziel-Erinnerung entfällt nur, wenn Pace nach dem Erreichen des Ziels geöffnet wurde
  (keine HealthKit-Hintergrundzustellung – bräuchte eine zusätzliche Capability; die App-Texte sagen das so).
- **Produktiv:** Social, Gruppen, Chats, Freunde-/Gruppen-Rankings, Glocke, Profilbilder, Auffindbarkeit,
  Blockieren/Melden, „Problem melden“/„Feedback senden“, Export und Konto löschen funktionieren erst nach dem
  Einspielen der Migrationen; bis dahin zeigt die App einen Hinweis („… auf dem Server noch nicht eingerichtet.“).
