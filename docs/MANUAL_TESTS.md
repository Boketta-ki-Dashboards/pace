# Manuelle Tests auf dem iPhone

Die automatisierten Tests laufen in der CI (Simulator, Linux, lokaler Supabase-Stack). Ein Test auf einem echten
iPhone war aus der Entwicklungsumgebung **nicht möglich** – HealthKit-Daten, App-Icon-Wechsel und echte
Schrittaktualisierung lassen sich nur auf einem Gerät prüfen. Diese Liste deckt genau diese Punkte ab.

## Vorbereitung

1. Änderungen holen (siehe README, „Aktualisieren“) und in Xcode **Product → Clean Build Folder** ausführen,
   damit die neuen App-Icons sicher im Build landen.
2. Unter *Signing & Capabilities* dein Personal Team wählen (falls Xcode es nach dem Pull zurückgesetzt hat).
3. Backend: Für Freunde und Gruppen muss die Migration `supabase/migrations/20261018100000_social.sql` im
   Pace-Projekt eingespielt sein (`supabase db push`, siehe `docs/BACKEND.md`). Ohne sie zeigt die App im Social-Tab
   „Freunde und Gruppen sind auf dem Server noch nicht eingerichtet“ – alles andere funktioniert.
4. App auf dem iPhone starten (nicht im Simulator – dort gibt es keine echten Schritte).

## App-Icon

- [ ] Home-Bildschirm zeigt die Pace-Wortmarke (dunkelgrün auf hell).
- [ ] Profil → Darstellung → **Dunkel**: iOS zeigt seinen Hinweis „Du hast das Symbol … geändert“, das Icon ist
      danach mint auf dunklem Grund. Pace zeigt keine zusätzliche Meldung.
- [ ] **Hell** und **Automatisch** ebenso; nach einem Neustart der App ist die Auswahl noch markiert.
- [ ] iOS 18+: Mit „Automatisch“ und Home-Bildschirm „Dunkel“ (Bearbeiten → Anpassen) erscheint die dunkle Variante,
      mit „Getönt“ die getönte.

## Statistik und Tagesdetails

- [ ] Home → große Schrittzahl antippen → Statistik „Heute“: Werte stimmen mit der Health-App überein
      (Wettbewerbsschritte, d. h. ohne manuell eingetragene Schritte).
- [ ] Distanz bzw. Kalorien antippen → Wochenstatistik der jeweiligen Kennzahl.
- [ ] „Deine Woche“ → einen vergangenen Wochentag antippen → Tagesdetails dieses Tages.
- [ ] In Woche und Monat einen Balken antippen → Tagesansicht. Pfeile blättern zurück (bis 12 Monate), nicht in
      die Zukunft.
- [ ] Ohne Apple Watch bzw. ohne Stockwerk-Daten steht dort „nicht verfügbar“, nicht „0“.
- [ ] Ein Schritt-Eintrag von Hand in der Health-App erscheint als Hinweis („In Apple Health: …“), zählt aber nicht.

## Tagesziel und Serie

- [ ] Tagesziel ändern (Home oder Profil): gilt ab heute; die Serie der Vortage bleibt unverändert.
- [ ] Serie: Ist das Ziel heute noch offen, bleibt die bisherige Serie stehen (Flamme pulsiert dezent). Nach
      Erreichen des Ziels steigt sie um 1.
- [ ] Profil zeigt Serie und Rekord.

## Home-Module

- [ ] Home → „Anpassen“: Module verschieben, entfernen (Minus), hinzufügen; Größe und – bei „Dein Umfeld“ – Ebene
      über das Regler-Symbol ändern. Nach einem App-Neustart ist alles gespeichert.
- [ ] „Deine Schritte heute“ lässt sich weder entfernen noch verkleinern.
- [ ] Nach dem Update aus einer älteren Version sind deine bisherigen Bereiche in derselben Reihenfolge vorhanden.

## Freunde und Gruppen (zweites Gerät oder zweiter Testnutzer nötig)

- [ ] Social → Benutzernamen des anderen Nutzers exakt eingeben → Anfrage senden; auf dem anderen Gerät annehmen.
- [ ] „Freunde heute“ zeigt beide mit Schritten; Freund antippen → Profil mit Schritten heute/Woche; entfernen.
- [ ] Gruppe erstellen → Einladungscode teilen → auf dem zweiten Gerät mit Code beitreten.
- [ ] Gruppenziel ändern: gilt ab morgen („Ab morgen: …“).
- [ ] Gruppen-Serie: Mit 2 Mitgliedern genügt 1 Person mit erreichtem Ziel.
- [ ] Gruppe verlassen (Verwaltung geht über), Gruppe löschen.

## Aktualisierung und Akku

- [ ] App offen lassen und gehen: Die Schrittzahl steigt ohne Pull-to-Refresh (iOS liefert iPhone-Schritte
      gebündelt, meist alle paar Minuten; Apple-Watch-Schritte teils später).
- [ ] App in den Hintergrund und zurück: Schritte und Platzierungen werden aktualisiert.

## Bekannte Grenzen

- Schritte kommen vom Gerät; das System ist nicht vollständig manipulationssicher (siehe `docs/SOCIAL.md`).
- Das Pace-Konto ist an das iPhone gebunden (anonyme Anmeldung). Serie, Rekord und Tagesziel liegen nur auf dem
  Gerät.
