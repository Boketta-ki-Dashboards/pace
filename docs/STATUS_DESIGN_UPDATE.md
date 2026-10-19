# Design- und Funktions-Update (Referenzbilder 1–9) – Ausgangsstand und Plan

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

## Lücken gegenüber dem Master-Prompt (Auszug)

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
