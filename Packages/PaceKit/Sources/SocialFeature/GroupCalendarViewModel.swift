import Foundation
import Observation
import PaceCore

/// Gruppenkalender (aus den Gruppendetails): Monatsraster ab Montag, je Tag Flamme und Tagesbeste(r), darunter die
/// vollständige Tagesrangliste des ausgewählten Tags mit Gruppenziel, „erreicht x von n“, benötigten Mitgliedern und
/// Flamme.
///
/// Alle Werte kommen vom Server (`SocialRepository.groupCalendar`) und sind historisch: Mitglieder und Ziel so, wie sie
/// an dem Tag galten. Tage ohne Daten, vor der Gründung und in der Zukunft zeigen keine Zahlen.
@MainActor
@Observable
public final class GroupCalendarViewModel {
    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(String)
        /// Auf dem Server (noch) nicht eingerichtet.
        case unavailable(String)
    }

    /// Eine Zelle im Monatsraster.
    public struct Cell: Equatable, Sendable, Identifiable {
        public let day: LocalDate
        public let state: GroupCalendarDayState
        /// Tagesbeste(r) mit mehr als 0 Schritten.
        public let best: GroupCalendarEntry?
        public let isToday: Bool
        public let isSelected: Bool
        /// Antippbar: Tage der Gruppe bis heute.
        public let isSelectable: Bool

        public var id: LocalDate { day }
    }

    public let groupID: UUID
    public let groupName: String
    public private(set) var state: State = .loading
    /// Erster Tag des angezeigten Monats.
    public private(set) var displayedMonth: LocalDate
    public private(set) var selectedDay: LocalDate?
    /// Geladene Monate (erster Tag → Kalender), damit Vor/Zurück nicht jedes Mal neu lädt.
    public private(set) var months: [LocalDate: GroupCalendar] = [:]

    @ObservationIgnored private let repository: any SocialRepository
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var loadingMonth: LocalDate?
    /// Wann jeder Monat geladen wurde und an welchem Tag (Gerät) zuletzt – für das Auffrischen beim Erscheinen.
    @ObservationIgnored private var loadedAt: [LocalDate: Date] = [:]
    @ObservationIgnored private var lastLoadDay: LocalDate?

    /// Älter darf ein gespeicherter Monat beim erneuten Öffnen nicht sein (heutige Rangliste ändert sich laufend).
    static let maximumAge: TimeInterval = 5 * 60

    public init(
        groupID: UUID,
        groupName: String,
        repository: any SocialRepository,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.groupID = groupID
        self.groupName = groupName
        self.repository = repository
        self.calendar = calendar
        self.now = now
        displayedMonth = calendar.startOfMonth(containing: calendar.day(containing: now()))
    }

    // MARK: Anzeige

    /// Kalender des angezeigten Monats, sobald geladen.
    public var current: GroupCalendar? { months[displayedMonth] }

    /// Heutiger Gruppentag (Zeitzone der Gruppe), sonst der des Geräts.
    public var today: LocalDate {
        current?.groupToday ?? months.values.first?.groupToday ?? calendar.day(containing: now())
    }

    private var firstGroupDay: LocalDate? {
        current?.firstGroupDay ?? months.values.first?.firstGroupDay
    }

    public var canShowPrevious: Bool {
        guard let firstGroupDay else { return false }
        return displayedMonth > calendar.startOfMonth(containing: firstGroupDay)
    }

    public var canShowNext: Bool {
        displayedMonth < calendar.startOfMonth(containing: today)
    }

    /// Nicht der Monat von heute → „Heute“ führt zurück.
    public var canShowToday: Bool {
        displayedMonth != calendar.startOfMonth(containing: today)
    }

    public var monthTitle: String {
        GroupCalendarFormatting.monthYear(displayedMonth, calendar: calendar)
    }

    /// Wochentage Mo–So (kurz) und ausgeschrieben für VoiceOver.
    public var weekdays: [(short: String, long: String)] {
        let monday = calendar.startOfWeek(containing: displayedMonth)
        return (0..<7).map { offset in
            let day = calendar.adding(offset, to: monday)
            return (GroupCalendarFormatting.weekdayShort(day, calendar: calendar), GroupCalendarFormatting.weekdayLong(day, calendar: calendar))
        }
    }

    /// Wochen des Monats; `nil` für Tage außerhalb des Monats (Platzhalter).
    public var weeks: [[Cell?]] {
        let grid = GroupCalendarRules.monthGrid(containing: displayedMonth, calendar: calendar)
        let month = displayedMonth.month
        var cells: [Cell?] = []
        var day = grid.lowerBound
        while day <= grid.upperBound {
            cells.append(day.month == month ? cell(for: day) : nil)
            day = calendar.adding(1, to: day)
        }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    private func cell(for day: LocalDate) -> Cell {
        let state = current?.state(of: day) ?? (day > today ? .future : .notLoaded)
        let entry = current?.day(day)
        return Cell(
            day: day,
            state: state,
            best: entry?.best,
            isToday: day == today,
            isSelected: day == selectedDay,
            isSelectable: state != .future && state != .beforeGroup
        )
    }

    /// Daten des ausgewählten Tags.
    public var selected: GroupCalendarDay? {
        selectedDay.flatMap { day in current?.day(day) }
    }

    public var selectedState: GroupCalendarDayState? {
        guard let selectedDay else { return nil }
        return current?.state(of: selectedDay)
    }

    public var selectedTitle: String? {
        selectedDay.map { GroupCalendarFormatting.dayLong($0, calendar: calendar) }
    }

    // MARK: Laden und Navigation

    /// Beim Erscheinen: gespeicherten Monat nutzen, aber neu laden, wenn er älter als ``maximumAge`` ist; hat inzwischen
    /// ein neuer Tag begonnen, beginnt der Kalender neu im laufenden Monat (heute ausgewählt).
    public func appear() async {
        let currentDay = calendar.day(containing: now())
        if let lastLoadDay, lastLoadDay != currentDay {
            months = [:]
            loadedAt = [:]
            selectedDay = nil
            displayedMonth = calendar.startOfMonth(containing: currentDay)
            await load(force: true)
            return
        }
        if let stamp = loadedAt[displayedMonth], now().timeIntervalSince(stamp) > Self.maximumAge {
            await load(force: true)
        } else {
            await load()
        }
    }

    /// Lädt den angezeigten Monat (einmal je Monat; `force` lädt neu, z. B. „Erneut versuchen“ oder Ziehen).
    public func load(force: Bool = false) async {
        let month = displayedMonth
        if !force, months[month] != nil {
            state = .loaded
            return
        }
        if loadingMonth == month { return }
        loadingMonth = month
        defer { if loadingMonth == month { loadingMonth = nil } }
        if months[month] == nil { state = .loading }
        let grid = GroupCalendarRules.monthGrid(containing: month, calendar: calendar)
        do {
            let loaded = try await repository.groupCalendar(groupID: groupID, from: grid.lowerBound, to: grid.upperBound)
            months[month] = loaded
            loadedAt[month] = now()
            lastLoadDay = calendar.day(containing: now())
            guard displayedMonth == month else { return }
            state = .loaded
            selectDefaultDayIfNeeded()
        } catch is CancellationError {
            return
        } catch let error as SocialError where error == .unavailable {
            if displayedMonth == month { state = .unavailable(SocialText.featureUnavailable) }
        } catch {
            if displayedMonth == month, months[month] == nil {
                state = .failed(SocialText.message(for: error))
            }
        }
    }

    public func showPrevious() async {
        guard canShowPrevious else { return }
        await show(calendar.addingMonths(-1, to: displayedMonth))
    }

    public func showNext() async {
        guard canShowNext else { return }
        await show(calendar.addingMonths(1, to: displayedMonth))
    }

    /// Zurück zum Monat von heute (heute ausgewählt).
    public func showToday() async {
        selectedDay = nil
        await show(calendar.startOfMonth(containing: today))
    }

    public func select(_ day: LocalDate) {
        guard let cell = weeks.joined().compactMap({ $0 }).first(where: { $0.day == day }), cell.isSelectable else { return }
        selectedDay = day
    }

    private func show(_ month: LocalDate) async {
        displayedMonth = month
        if let selectedDay, calendar.startOfMonth(containing: selectedDay) != month {
            self.selectedDay = nil
        }
        state = months[month] == nil ? .loading : .loaded
        selectDefaultDayIfNeeded()
        await load()
    }

    /// Ohne Auswahl: heute im aktuellen Monat, sonst der letzte Tag der Gruppe im Monat.
    private func selectDefaultDayIfNeeded() {
        guard selectedDay == nil, let current else { return }
        let inMonth = current.days.filter { calendar.startOfMonth(containing: $0.day) == displayedMonth }
        selectedDay = inMonth.first { $0.day == current.groupToday }?.day ?? inMonth.last?.day
    }

    // MARK: Texte

    /// „Gruppenziel: 8.000 Schritte pro Mitglied“
    public func goalText(_ day: GroupCalendarDay) -> String? {
        day.dailyGoal.map { goal in
            PaceLocalization.text(
                de: "Gruppenziel: \(PaceLocalization.steps(goal)) pro Mitglied",
                en: "Group goal: \(PaceLocalization.steps(goal)) per member",
                ru: "Цель группы: \(PaceLocalization.steps(goal)) на участника"
            )
        }
    }

    /// „5 von 12 Mitgliedern haben das Tagesziel erreicht.“
    public func reachedText(_ day: GroupCalendarDay) -> String {
        PaceLocalization.text(
            de: "\(day.reachedCount) von \(day.memberCount) Mitgliedern haben das Tagesziel erreicht.",
            en: "\(day.reachedCount) of \(day.memberCount) members reached the daily goal.",
            ru: "\(day.reachedCount) из \(day.memberCount) участников выполнили дневную цель."
        )
    }

    /// „4 benötigt (ein Drittel der Mitglieder)“
    public func requiredText(_ day: GroupCalendarDay) -> String {
        PaceLocalization.text(
            de: "Benötigt: \(day.requiredCount) (ein Drittel der Mitglieder, aufgerundet)",
            en: "Needed: \(day.requiredCount) (a third of the members, rounded up)",
            ru: "Нужно: \(day.requiredCount) (треть участников, с округлением вверх)"
        )
    }

    /// „Flamme gesichert.“ bzw. „Flamme nicht gesichert.“ / „Noch offen“ (heute).
    public func flameText(_ day: GroupCalendarDay) -> String {
        if day.secured {
            return PaceLocalization.text(de: "Flamme gesichert.", en: "Flame secured.", ru: "Огонь сохранён.")
        }
        if day.isToday {
            return PaceLocalization.text(
                de: "Heute noch offen – \(max(day.requiredCount - day.reachedCount, 0)) fehlen noch.",
                en: "Still open today – \(max(day.requiredCount - day.reachedCount, 0)) still needed.",
                ru: "Сегодня ещё открыто – не хватает \(max(day.requiredCount - day.reachedCount, 0))."
            )
        }
        return PaceLocalization.text(de: "Flamme nicht gesichert.", en: "Flame not secured.", ru: "Огонь не сохранён.")
    }

    /// Text für Tage ohne Rangliste.
    public func emptyText(for state: GroupCalendarDayState) -> String {
        switch state {
        case .future:
            PaceLocalization.text(
                de: "Dieser Tag liegt in der Zukunft.", en: "This day is in the future.", ru: "Этот день ещё не наступил."
            )
        case .beforeGroup:
            PaceLocalization.text(
                de: "Die Gruppe gab es an diesem Tag noch nicht.",
                en: "The group didn't exist on this day yet.",
                ru: "В этот день группы ещё не было."
            )
        case .notLoaded:
            PaceLocalization.text(de: "Wird geladen …", en: "Loading …", ru: "Загрузка …")
        case .noData, .secured, .open, .missed:
            PaceLocalization.text(de: "Keine Daten verfügbar.", en: "No data available.", ru: "Нет данных.")
        }
    }

    /// VoiceOver-Text einer Zelle.
    public func accessibilityLabel(for cell: Cell) -> String {
        var parts = [GroupCalendarFormatting.dayLong(cell.day, calendar: calendar)]
        switch cell.state {
        case .secured: parts.append(PaceLocalization.text(de: "Flamme gesichert", en: "Flame secured", ru: "Огонь сохранён"))
        case .missed: parts.append(PaceLocalization.text(de: "Flamme nicht gesichert", en: "Flame not secured", ru: "Огонь не сохранён"))
        case .open: parts.append(PaceLocalization.text(de: "Heute, noch offen", en: "Today, still open", ru: "Сегодня, ещё открыто"))
        case .noData: parts.append(emptyText(for: .noData))
        case .future, .beforeGroup, .notLoaded: break
        }
        if let best = cell.best {
            parts.append(PaceLocalization.text(
                de: "Tagesbeste: \(best.shownName), \(PaceLocalization.steps(best.competitionSteps))",
                en: "Best of the day: \(best.shownName), \(PaceLocalization.steps(best.competitionSteps))",
                ru: "Лучший дня: \(best.shownName), \(PaceLocalization.steps(best.competitionSteps))"
            ))
        }
        return parts.joined(separator: ", ")
    }
}

/// Datumsangaben des Gruppenkalenders in der App-Sprache (Woche ab Montag).
enum GroupCalendarFormatting {
    private static func style(_ calendar: ActivityCalendar) -> Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: PaceLocalization.shared.locale,
            calendar: calendar.calendar,
            timeZone: calendar.timeZone
        )
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased(with: PaceLocalization.shared.locale) + text.dropFirst()
    }

    /// `Oktober 2026` (Monatsname im Nominativ, auch auf Russisch).
    static func monthYear(_ day: LocalDate, calendar: ActivityCalendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = PaceLocalization.shared.locale
        formatter.calendar = calendar.calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "LLLL yyyy"
        return capitalized(formatter.string(from: calendar.startOfDay(day)))
    }

    /// `Mo`, `Mon`, `Пн`
    static func weekdayShort(_ day: LocalDate, calendar: ActivityCalendar) -> String {
        capitalized(
            calendar.startOfDay(day).formatted(style(calendar).weekday(.abbreviated))
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        )
    }

    /// `Montag`
    static func weekdayLong(_ day: LocalDate, calendar: ActivityCalendar) -> String {
        capitalized(calendar.startOfDay(day).formatted(style(calendar).weekday(.wide)))
    }

    /// `Samstag, 17. Oktober`
    static func dayLong(_ day: LocalDate, calendar: ActivityCalendar) -> String {
        capitalized(calendar.startOfDay(day).formatted(style(calendar).weekday(.wide).day().month(.wide)))
    }
}
