# Pace – Abschlussbericht Auftrag 7

Home-Anpassen-Kopf, Pace-Bot als gewöhnlicher Chat, ruhige Statistik beim Wischen, Profilbild und Banner direkt
bearbeiten, Interessen 2.0 (Katalog, eigene Interessen, Sprachen, Land) und Rückkehr des Profil-Tabs zur Startseite.

**Ehrlicher Rahmen:** Geprüft wurde mit Unit-Tests unter Linux, einer lokalen Docker-Supabase im
Entwicklungscontainer (pgTAP, Lint, Advisors, Swift-Integrationstests), Simulator-Tests und Simulator-Screenshots in
der CI (GitHub Actions, macOS) sowie zwei unabhängigen Code-Reviews. **Auf einem echten iPhone wurde in diesem Auftrag
nichts getestet** – siehe Punkt 17. Die neue Migration ist **nicht** auf dem Produktivprojekt ausgeführt.

Ausgangs-Commit `b6e5011`, Branch `claude/gallant-brahmagupta-hvvp13` (kein Pull Request, kein Force-Push).

## 1. Alle Änderungen

| Teil | Änderung | Wichtigste Dateien |
|---|---|---|
| A 1 | Home-Anpassen-Kopf: „Fertig“ und „+ Widget hinzufügen“ als 36-pt-Pillen mit 44-pt-Tippfläche, weniger Innenabstand, Symbol dicht am Text; eine Zeile, wenn Begrüßung und Knopf nebeneinander passen, sonst fest zweizeilig (Knopf rechts unter der Begrüßung); bei Bedienungshilfen-Schrift zweizeilige Beschriftung statt Abschneiden | `HomeHeaderView.swift`, `HomeEditChrome.swift` |
| B 2 | Pace-Bot als gewöhnlicher Eintrag der Chatliste, sortiert nach der letzten eigenen Frage; unbenutzt ganz unten; nur unter „Alle“; Suche; offline genau eine Karte; Zeitstempel wie bei Chats | `ChatListViewModel.swift`, `ChatListViews.swift`, `PaceBotView.swift`, `SocialView.swift`, `PaceHelpBot.swift` |
| C 3 | Statistik: Nur der Container bewegt sich; Karte und Diagramm wechseln ohne eigene Animation | `StatisticsView.swift`, `PacePeriodSwipe.swift` |
| D 4 | „Profil bearbeiten“ mit Vorschau (Banner, überlappendes Profilbild, Stift-Symbole); Antippen öffnet direkt Auswahl → Zuschnitt → Speichern; Entfernen; Lade- und Fehlerzustände direkt an den Bildern | `ProfileEditPage.swift`, `AvatarImageProcessing.swift` |
| D 5 | Interessen 2.0: 50 Interessen in 5 Kategorien, eigene Interessen, bis zu 20, gesprochene Sprachen, Land & Kultur; eigenes Profil zeigt alle, fremde sechs + „Alle Interessen ansehen“; neue Migration | `ProfileInterests.swift`, `ProfileDetails.swift`, `ProfileInterestsEditor.swift`, `PaceProfileShowcase.swift`, `SupabaseProfileDetailsRepository.swift`, `20261102100000_profile_interests.sql` |
| E 6 | Profil-Tab: Beim Verlassen zurück zur Startseite und nach oben; Unterseiten mit ungespeicherten Eingaben bleiben offen | `ProfileViewModel.swift`, `MainViewModel.swift`, `MainTabView.swift`, `ProfileView.swift`, `HelpPages.swift` |
| F | Tests (Kopf-Layouttest, Pace-Bot-, Statistik-, Tab-, Interessen-, Repository-, Integrations- und pgTAP-Tests), Vorschaubilder, Doku | siehe Punkte 11, 12, 18 |

## 2. Ursachen

- **Kopf (A 1):** Beide Pillen füllten ihre 44-pt-Zeilen vollständig aus (`frame(minHeight: 44)` direkt am Hintergrund),
  und Kopf- und Titelzeile von `PaceRootHeader` liegen ohne Abstand übereinander. Stand „+ Widget hinzufügen“ in der
  Titelzeile rechts, berührte es „Fertig“ genau an der Kante; mit 16 pt Innenabstand und Standard-Symbolabstand war die
  Pille zudem breit, so dass je nach Breite und Sprache das Layout wechselte. Die Ausweichanordnung stellte den Knopf
  links unter die Begrüßung – also nicht klar definiert.
- **Pace-Bot (B 2):** Fester Eintrag vor allen Chats, unabhängig von Aktivität.
- **Statistik (C 3):** Zwei Zeitachsen liefen gegeneinander: Die Karte glitt nach dem Loslassen mit `snappy(0.28 s)`
  zurück, während das neue Diagramm mit `transition(.opacity)` und `animation(.easeOut(0.18 s), value: chartIdentity)`
  eingeblendet wurde. Diese implizite Animation erfasste auch Balkenhöhen, Achsen und Linien – sie wanderten innerhalb
  der bewegten Karte von alten zu neuen Positionen und rasteten nachträglich ein.
- **Profilbild (D 4):** Profilbild nur über „Konto & Profil“ erreichbar, Banner nur über eine eigene Karte weiter unten.
- **Interessen (D 5):** Fester Katalog mit zehn IDs und höchstens fünf Einträgen – im App-Enum und als festes Array im
  Constraint `profiles_interests_valid` der produktiven Migration 20261030100000.
- **Profil-Tab (E 6):** Jeder Haupttab behält seinen `NavigationStack`-Pfad; beim Tabwechsel wurde nichts zurückgesetzt.

## 3. Chat-Sortierung

`ChatListViewModel.entries(showsHelpBot:helpBotActivity:)` fügt den Bot genau einmal in die nach `updatedAt` sortierte
Liste ein – vor dem ersten Chat, der älter ist als die letzte eigene Frage (`PaceHelpBotSession.lastUserActivity` =
Datum der letzten Nachricht mit Rolle „Nutzer“). Ohne eigene Frage steht er am Ende. Begrüßung, Neustart (Verlauf aus
UserDefaults), Laden der Liste, erneutes Öffnen, Sprachwechsel und FAQ-Inhalte ändern dieses Datum nicht. „Verlauf
zurücksetzen“ macht den Bot wieder „unbenutzt“ (unten) – bewusst so. Nur unter „Alle“, nie unter „Freunde“/„Gruppen“,
kein Ungelesen-Zähler. Suche: Namensanfang ab drei Zeichen („Pace-Bot“, „Bot“, „Hilfe“, „Help“, „Бот“, „FAQ“ …), nicht
„Talbot“ oder „Botswana“. Kann die Liste nicht geladen werden, erscheint unter dem Hinweis genau eine Bot-Karte.
Vorschau und Zeitstempel wie bei Chats. Keine KI, keine neue Tabelle.

## 4. Statistik-Animationen

Variante A (ruhig): Während der Geste wird nur der Container (Wertkarte + Diagramm) verschoben. Beim Einrasten wird
der neue Zeitraum ohne Animation eingesetzt (`Transaction` mit `disablesAnimations`), das Diagramm per `.id` ohne
Übergang ersetzt (`.transition(.identity)`); danach gleitet der Container von der Seite in die Mitte
(`snappy(0.28 s)`, mit Generationszähler gegen veraltete Animationen bei schnellem Wischen). Gesten unverändert:
Finger nach rechts = vorheriger, nach links = nächster Zeitraum; Zurück-Geste und Tab-Wischen unverändert. Das
Diagramm bleibt im Plotbereich beschnitten, Beschriftungen nicht. Test `rapidPeriodChangesAlwaysShowACompleteConsistentReport`:
alle Metriken × Tag/Woche/Monat, 10 × zurück, Richtungswechsel, 10 × vor – jeder Zwischenstand vollständig, y-Maximum
≥ alle Balken, eindeutige Diagramm-Identität.

## 5. Profilbild und Banner

„Profil bearbeiten“ beginnt mit einer Vorschau wie das Profil: Banner (112 pt) und überlappendes Profilbild (84 pt) mit
Stift-Symbolen und Hinweis. Ohne Bild öffnet ein Tippen direkt die Fotoauswahl, mit Bild erst „Ändern“/„Entfernen“ –
höchstens zwei Schritte. Profilbild: quadratischer Zuschnitt mit runder Vorschau (verschieben per Ziehen oder Regler),
Upload über das bestehende System von „Konto & Profil“. Banner: Zuschnitt 3:1, bestehender Banner-Upload. Alte Dateien
werden erst nach bestätigtem Speichern gelöscht; während ein Bild hochlädt oder das Foto gelesen wird, sind beide
Bilder gesperrt (Ladeanzeige); das neue Bild liegt sofort im Bildspeicher. Fehler erscheinen direkt bei den Bildern.
„Namen & Konto“ bleibt als Zeile erhalten.

## 6. Interessen und Kategorien

50 Katalog-Interessen mit stabilen IDs und DE/EN/RU-Titeln: Sport & Bewegung (18, inkl. der zehn bisherigen),
Musik & Kreativität (10), Technik & Gaming (8), Alltag & Freizeit (9), Sprachen & Kultur (5; „Reisen“ erscheint auch
hier). Aufklappbare Kategorien mit Zähler, oben „Deine Auswahl“ mit Entfernen-Knopf. Bis zu 20 Interessen insgesamt.
Eigenes Profil: alle; fremde Profile: sechs und „Alle Interessen ansehen (n)“. Server ohne neue Migration: wie bisher
fünf aus dem ursprünglichen Katalog, mit Hinweis.

## 7. Speicherung eigener Interessen

`profiles.custom_interests text[]`: normalisierter Text (Leerraum zusammengefasst, NFC), so angezeigt wie eingegeben
(`Text(verbatim:)`, nie übersetzt). Regeln in App und Server gleich: 2–30 Zeichen, keine Steuer-, unsichtbaren oder
leer dargestellten Zeichen, keine Links/`www.`/`domain.tld/…`/`@`, keine Doppelten ohne Rücksicht auf
Groß-/Kleinschreibung (auch kyrillisch). Begriffe aus dem Katalog (in jeder App-Sprache) werden vorgeschlagen bzw. als
Katalogeintrag gewählt; ein Katalogeintrag ersetzt einen gleichnamigen eigenen Begriff. Eigene Begriffe gehören nur
zum eigenen Profil, werden nie Teil des Katalogs und landen beim Melden im Schnappschuss. Ein eingetippter, noch nicht
hinzugefügter Begriff zählt als ungespeicherte Änderung und wird mit „Speichern“ übernommen.

## 8. Gesprochene Sprachen

Eigener kompakter Bereich, freiwillig, bis zu 10 ISO-639-Codes aus einer Liste von 81 Sprachen mit Suche (Name in der
App-Sprache, auf Englisch oder in der Sprache selbst, z. B. „Српски“). Nie aus der App-Sprache abgeleitet. Anzeige auf
dem Profil als Zeile „Sprachen: Deutsch · Russisch · Serbisch“.

## 9. Land & Kultur

Umgesetzt: freiwillig, ein ISO-3166-Land mit Flagge aus einer durchsuchbaren Liste (245 Länder und Gebiete), Hinweis „wird nicht überprüft und
hat keinen Einfluss auf Ranglisten“. Sichtbar nur, wenn gewählt (Entfernen jederzeit), mit denselben
Sichtbarkeits-/Blockierregeln wie die Bio. Keine Ableitung aus Standort, Sprache oder Namen; Regionen und Ranglisten
beruhen weiter allein auf `region_id`.

## 10. Verhalten des Profil-Tabs

Wechsel von Profil in einen anderen Haupttab: Beim nächsten Besuch erscheint die Profil-Startseite, ganz oben – ohne
sichtbare Animation, ohne neues ViewModel, ohne Neuladen. Unterseiten mit ungespeicherten Eingaben bleiben offen:
„Profil bearbeiten“ mit Änderungen (auch eingetippter Begriff) und eine angefangene Rückmeldung; öffnet ein anderer
Tab eine Profilseite, bleibt die Rückmeldung darunter liegen. Neu erreichte Auszeichnungsstufen zählen nicht als
Änderung. Erneutes Tippen auf den aktiven Tab scrollt wie bisher nach oben; die Zurück-Geste geht wie bisher eine Seite
zurück. Chats, SocialNavigator und Widgets unverändert.

## 11. Ergebnisse der UI-Tests

- **Linux (plattformunabhängige Teile, Swift 6.2):** 947 Tests in 127 Suites grün – u. a. `HelpBotChatListTests`
  (nie benutzt, nach echter Frage, neue Gruppen-/Privatnachricht, Filter, genau ein Eintrag, kein Ungelesen-Zähler,
  Neustart/Sprachwechsel ohne künstliche Aktivität, Suche „Pace-Bot“), `rapidPeriodChangesAlwaysShowACompleteConsistentReport`,
  `ProfileTabResetTests` (alle Unterseiten, ungespeicherter Entwurf, angefangene Rückmeldung, Öffnen aus anderem Tab,
  neu erreichte Auszeichnung), `ProfileInterestRulesTests` und `ProfileInterestsViewModelTests` (alte Profile mit 3 und
  5 Interessen, 20 Interessen, eigene hinzufügen/entfernen, Doppelte, lange Eingaben, Kyrillisch, Emoji, Sprachwechsel,
  leeres Profil, älterer Server, Einträge einer neueren App-Version), `AppRouterSettingsTests`.
- **iOS-Simulator (CI):** siehe Punkt 21 – alle Pakete einschließlich Snapshot- und Fenster-Tests. Neu und bei jedem
  Lauf aktiv: `HomeEditHeaderLayoutTests` mit 36 Fällen (SE mit Display-Zoom 320 pt, SE 375, iPhone 16 393, Pro Max
  430 × DE/EN/RU × Standard, xxxLarge, Bedienungshilfen-Schrift AX3): Abstand der Pillen ≥ 4 pt, „Fertig“ oben,
  rechtsbündig, nichts über den Rand, sichtbare Höhe ≥ 36 pt. `RootHeaderLayoutTests` (gleiche Kopfhöhe aller Tabs)
  grün.

## 12. Ergebnisse der Backend-Tests

- **pgTAP (lokale Docker-Supabase und CI):** 1053 Prüfungen in 18 Dateien grün, davon `18_profile_interests` mit 52
  (Struktur, Rechte, Katalog, Bestandsdaten mit 3 und 5 Interessen, neue IDs, Doppelte, Länge in Zeichen,
  Leerzeichen, unsichtbare und leer dargestellte Zeichen, Links, NFC, 20/21 Interessen, Schutz vor älteren
  App-Versionen, Sprachen, Land, fremdes Profil, RLS, Blockierung, Meldeschnappschuss, Datenexport); 14 und 17 an die
  neuen Schlüssel angepasst.
- **`supabase db lint`:** keine Fehler. **Advisors:** keine Warnungen.
- **Swift-Backend (Linux, gegen die lokale Datenbank):** 141 Tests grün, darunter `ProfileInterestsRepositoryTests`
  (älterer Server, Erkennung der Erweiterung, Bereinigung, Spalten nur bei Erweiterung, `null` für Land, Einträge
  einer neueren Version) und `ProfileInterestsIntegrationTests` (Hin und zurück, fremdes Profil, 20 Interessen,
  Blockierung).

## 13. Ergebnisse der Reviews

Zwei unabhängige Reviews (nur lesend) über `b6e5011..HEAD`:

**Review A – UI/Navigation:** 3 mittel, 10 gering.
- A1 (mittel) „+ Widget hinzufügen“ bei Bedienungshilfen-Schrift abgeschnitten
- A2 (mittel) Profilkopf 8 pt tiefer als in den anderen Tabs (zusätzliches ScrollView-Kind)
- A3 (mittel) angefangene Rückmeldung ging verloren, wenn ein anderer Tab eine Profilseite öffnete
- A4 sichtbares Zurückblättern beim Tippen auf die Tab-Leiste; A5 neu erreichte Auszeichnung hielt den Tab offen,
  eingetippter Begriff nicht; A6 Bot-Suche zu weit („Talbot“); A7 Bot-Zeitstempel fehlten in Suche/Ladekarte;
  A8 „Verlauf zurücksetzen“ setzt den Bot nach unten; A9 Bannerfehler weit weg vom Banner; A10 keine Ladeanzeige beim
  Lesen des Fotos; A11 Chips 36 pt, Tippfläche „Land entfernen“; A12 Fokus im neuen Eingabefeld; A13 (unsicher)
  kleiner Sprung beim Wischen während des Einrastens

**Review B – Social-Profil/Backend:** 2 mittel, 6 gering, Kleinigkeiten.
- B1 (mittel) ältere App-Versionen hätten neue Interessen beim Speichern gelöscht
- B2 (mittel) die neue App hätte Katalog-IDs einer späteren Version gelöscht
- B3 Sprachcode-Prüfung umgehbar (`{"de,en"}`, `{""}`); B4 geschützte/leer dargestellte Leerzeichen; B5 Groß-/
  Kleinschreibung „İ“ in App und Server verschieden; B6 Links wie `t.me/x` nicht erkannt; B7 eingetippter Begriff
  ging verloren; B8 gleicher Begriff als Katalog- und eigener Eintrag; Kleinigkeiten (Testkommentar, Land „ZZ“,
  Sortierleistung)

## 14. Behobene Befunde

| Befund | Behebung | Test |
|---|---|---|
| A1 | Pille darf in eigener Zeile zweizeilig umbrechen, Schrift der Pillen bis AX3 | Kopf-Layouttest bis AX3 |
| A2 | Scroll-Anker direkt am Inhalt | `RootHeaderLayoutTests` |
| A3 | `show(_:)` legt bei ungespeicherten Eingaben die Seite oben auf bzw. geht zur offenen Seite zurück | `openingAProfilePageFromAnotherTabKeepsAStartedFeedback` |
| A4 | Zurücksetzen in einer Transaktion ohne Animation | – (nur auf dem Gerät sichtbar) |
| A5, B7 | `hasUserEdits` ohne Auszeichnungs-Nachtrag, mit eingetipptem Begriff; „Speichern“ übernimmt ihn | `newlyEarnedAchievementsAreNoUserEditButTypedTermsAre`, `pendingTerm…` |
| A6 | Suche nur Namensanfang ab drei Zeichen | `searchFindsTheBot` |
| A7 | Zeitstempel überall | – |
| A9 | `bannerError` an den Bildern | `failedSaveDeletesTheUploadedBanner` |
| A10 | Ladeanzeige und Sperre beim Lesen des Fotos | – |
| A11 (teilweise) | Tippfläche „Land entfernen“ 44 pt | – |
| A12 | Fokus nach kurzer Verzögerung | – (nur auf dem Gerät prüfbar) |
| B1 | Trigger erkennt Änderungen ohne `custom_interests` und behält, was eine ältere App nicht sehen konnte | pgTAP 18 |
| B2 | `preservedInterestIDs`: angerechnet und unverändert zurückgeschickt | Repository- und ViewModel-Tests |
| B3 | Jeder Sprachcode einzeln geprüft | pgTAP 18 |
| B4 (eigene Interessen) | Leerzeichen am Rand inkl. U+00A0/U+3000, leer dargestellte Zeichen abgelehnt (App und Server) | pgTAP 18, Regeltests |
| B6 | `domain.tld/…` und bekannte Endungen abgelehnt (App und Server), „Node.js“ erlaubt | pgTAP 18, Regeltests |
| B8 | Katalogeintrag ersetzt gleichnamigen eigenen Begriff | `pendingTerm…CatalogChoice…` |
| Kleinigkeiten | Testkommentar, Länder nur aus der Liste, Namen beim Sortieren einmal bestimmt | – |

Zusätzlich aus CI und visueller Prüfung: Wettlauf im Bildlader (zweiter Download in der Lücke zwischen Download-Ende
und Speicher, CI-Test `oneDownloadForAllSizesAndViews` unter Last) behoben; Zuschnitt-Titel gekürzt (wurde
abgeschnitten); Sprach-/Ländersuche am Wortanfang.

## 15. Offene kleinere Punkte

- A8: „Verlauf zurücksetzen“ macht den Bot wieder „unbenutzt“ (unten) – bewusst, da es keine eigene Frage mehr gibt.
- A11: Interessen-Chips sind 36 pt hoch (wie in Auftrag 6, mit 8 pt Abstand); nicht auf 44 pt vergrößert, um die
  Auswahl kompakt zu halten.
- A13 (unsicher): möglicher kleiner Sprung, wenn während des Einrastens erneut gewischt und ohne Wechsel losgelassen
  wird – nur auf dem Gerät prüfbar (IPHONE_TEST 5 C 3).
- B4: Bio und Anzeigename lassen leer dargestellte Füllzeichen weiter zu – ihre Regeln stehen in bereits produktiven
  Migrationen; bei Bedarf in einer eigenen Migration.
- B5: Seltene Sonderfälle der Groß-/Kleinschreibung (z. B. türkisches „İ“) behandeln App und Datenbank verschieden; die
  Datenbank lehnt dann ab und die App zeigt die allgemeine Meldung „Bitte prüfe Bio und Auswahl“.
- Sprach- und Ländernamen kommen aus iOS (`Locale`) und können je nach iOS-Version leicht abweichen.
- Ältere App-Versionen (Stand Auftrag 6) zeigen weiterhin höchstens fünf Interessen; die übrigen bleiben erhalten.
- Wischen in der Statistik und Abstand im Home-Kopf sind im Simulator geprüft, nicht auf einem Gerät.
- Simulator-Bilder: In den hellen Fensterbildern der Sheets (Zuschnitt, Sprachen, Land) ist der Titel der
  System-Navigationsleiste weiß (unsichtbar), in den dunklen richtig. Die App setzt keine eigene Titelfarbe; das
  Harness wurde angeglichen (Fenster-Erscheinungsbild, `preferredColorScheme`, Akzentfarbe), der Titel blieb im
  Renderer hell. Wahrscheinlich ein Artefakt des Test-Renderers – auf dem iPhone mitprüfen (IPHONE_TEST 5 D 2, 5 E 5).

## 16. Migrationen

- **Neu:** `supabase/migrations/20261102100000_profile_interests.sql` (additiv): Katalogtabelle
  `private.profile_interest_catalog` (50 IDs), Spalten `custom_interests`, `spoken_languages`, `country_code`;
  `profiles_interests_valid` (feste Fünferliste) ersetzt durch `profiles_interests_total` (≤ 20) sowie Prüfregeln für
  Sprachen und Land; Trigger-Funktionen `private.validate_profile_details` (ersetzt) und
  `private.mark_profile_extended_write` (neu); Spaltenrechte; `social_profile_details` und `social_report` (gleiche
  Signaturen) erweitert. Nur lokal und in der CI getestet, **nicht** produktiv ausgeführt.
- **Unverändert:** alle bisherigen Migrationen, insbesondere die produktive `20261030100000_profile_details.sql`.
- **Nötig?** Nur für die Interessen-Erweiterung (Punkt 6–9). Alle anderen Teile laufen ohne Migration; ohne sie bleibt
  die App bei fünf Interessen aus dem ursprünglichen Katalog.
- **Probelauf (durch den Nutzer):** `supabase migration list --linked` (nur `20261102100000` „local“) und
  `supabase db push --dry-run` – erwartet genau `20261102100000_profile_interests.sql`. Danach nur nach Freigabe
  `supabase db push` (nie `--include-seed`, nie `db reset`). Vollständige Anleitung mit Prüfabfragen und Rücknahme:
  [SUPABASE_ROLLOUT.md](SUPABASE_ROLLOUT.md), Abschnitt „Auftrag 7“.

## 17. Tatsächliche iPhone-Tests

**Keine.** In diesem Auftrag wurde nichts auf einem echten iPhone getestet. Alle Aussagen beruhen auf Unit-Tests,
Datenbanktests, Simulator-Tests und Simulator-Bildern. Ausstehend (Anleitung: [IPHONE_TEST.md](IPHONE_TEST.md)):
Home-Kopf in allen Sprachen und Schriftgrößen (A), Pace-Bot-Sortierung mit zwei Konten und offline (B), Wischgefühl in
der Statistik (C), Profilbild/Banner mit echten Fotos inkl. iCloud (D), Interessen mit eingespielter Migration und zwei
Konten (E), Profil-Tab-Verhalten (F), Regressionen (G).

## 18. Screenshot-Index

Alle Bilder mit Hell/Dunkel und – wo längere Texte wichtig sind – Englisch/Russisch:
[docs/previews/auftrag7/README.md](previews/auftrag7/README.md). **Simulator-Bilder, keine iPhone-Aufnahmen.**

| Nr. | Ansicht | Datei (hell) |
|---|---|---|
| 1 | Home-Anpassen vorher (Stand Auftrag 6) | `01-home-anpassen-vorher-light.png` |
| 2 | Home-Anpassen nachher, dazu der Kopf in 320/375/393/430 pt und mit großer Schrift | `02-home-anpassen-nachher-light.png`, `02-kopf-*.png` |
| 3 | Chatliste mit unbenutztem Bot ganz unten | `03-chatliste-bot-unbenutzt-light.png` |
| 4 | Chatliste nach neuer Gruppennachricht | `04-chatliste-nach-gruppennachricht-light.png` |
| 5 | Chatliste nach eigener Bot-Frage | `05-chatliste-nach-bot-frage-light.png` |
| 6 | Tag/Woche/Monat während der Geste (Versatz nachgestellt) | `06-statistik-*-waehrend-wischen-light.png` |
| 7 | Tag/Woche/Monat nach dem Einrasten | `07-statistik-*-eingerastet-light.png` |
| 8 | Profil bearbeiten mit Banner und Profilbild | `08-profil-bearbeiten-bilder-light.png` |
| 9 | Profilbild-Editor | `09-profilbild-editor-light.png` |
| 10 | Banner-Editor | `10-banner-editor-light.png` |
| 11 | Erweiterter Interessenkatalog (zwei Ausschnitte, dazu älterer Server) | `11-interessen-*.png` |
| 12 | Eigenes Interesse, Katalogvorschlag, Doppelter Begriff | `12-*.png` |
| 13 | Eigenes Profil mit 16 Interessen; fremdes Profil kompakt | `13-*.png` |
| 14 | Gesprochene Sprachen (Bereich, Liste, Suche) | `14-*.png` |
| 15 | Land & Kultur (Auswahl mit Suche) | `15-landauswahl-light.png` |
| 16 | Profil-Hauptseite nach Wechsel zu Social und zurück | `16-profil-nach-rueckkehr-light.png` |

## 19. Letzter Commit

Code und Tests: `6931c1c` („Vorschau-Harness wie die App (preferredColorScheme), Rollout-Prüfung für
Kleinschreibung“). Davor in diesem Auftrag: `5ae20b8` (visuelle Prüfung), `0291670` (Bildlader), `561b756`
(Review-Befunde), `635baa4` (Interessen 2.0), `5020660` (Home-Kopf, Pace-Bot, Statistik, Profil-Tab,
Bildbearbeitung). Bericht und Vorschaubilder: der Commit „Auftrag 7: Abschlussbericht und Vorschaubilder“ direkt
danach.

## 20. Branch- und Push-Status

Alle Commits sind auf `origin/claude/gallant-brahmagupta-hvvp13` gepusht – kein Pull Request, kein Force-Push, keine
anderen Branches. `Config/Pace.xcconfig`, Bundle Identifier und Signing sind unverändert; keine Secrets im Repository
(CI-Prüfung „Secret scan“ grün).

## 21. Abschließender CI-Status

**Grün** für den letzten Code- und Test-Commit `6931c1c`:

- **iOS** (Lauf 41527438602): App-Build ohne Compiler-Warnungen (App- und Testcode), Info.plist-, Icon- und
  Schlüsselprüfungen, **1183 Tests in 14 Testläufen grün, 0 Fehler** (einschließlich `HomeEditHeaderLayoutTests`,
  `RootHeaderLayoutTests`, `ImageLoadingTests`, Drift-, Tastatur- und Statusleisten-Tests sowie aller
  Snapshot-Suiten), Snapshot-Artefakt hochgeladen, Backend-Integration baut auf macOS.
- **Backend** (Lauf 41527438579): pgTAP **1053 Prüfungen in 18 Dateien grün**, `db lint` ohne Fehler, Advisors ohne
  Warnungen, Realtime-Ende-zu-Ende, Backend-Integration (23 Tests), Secret-Scan.

Verlauf: Der Lauf zu `561b756` scheiterte an einem einzigen Test (`ImageLoadingTests.oneDownloadForAllSizesAndViews`,
Wettlauf im Bildlader unter Last, siehe Punkt 14) – mit `0291670` behoben; seitdem alle Läufe grün (`5ae20b8`,
`6931c1c`). Der Commit mit diesem Bericht ändert nur Dokumentation und Bilder; sein CI-Lauf wird im Chat gemeldet.

## 22. Installations- und Testanleitung

1. Terminal: `cd ~/Developer/pace` (eigenen Pfad verwenden), dann
   `git fetch origin && git checkout claude/gallant-brahmagupta-hvvp13 && git pull origin claude/gallant-brahmagupta-hvvp13`.
2. `Pace.xcodeproj` öffnen, warten bis die Pakete aufgelöst sind, **Product → Clean Build Folder**.
3. iPhone verbinden und entsperren, oben das iPhone wählen (nicht den Simulator), Personal Team unverändert lassen.
4. ▶ drücken. Daten, Identität und Einstellungen bleiben erhalten; keine neuen Berechtigungen.
5. Optional, nur nach eigener Prüfung: Migration `20261102100000_profile_interests.sql` nach
   [SUPABASE_ROLLOUT.md](SUPABASE_ROLLOUT.md), Abschnitt „Auftrag 7“ (Probelauf, dann `supabase db push`). Ohne sie
   funktioniert alles außer der Interessen-Erweiterung.

Alle Testfälle Schritt für Schritt: [IPHONE_TEST.md](IPHONE_TEST.md).
