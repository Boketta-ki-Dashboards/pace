import ActivityFeature
import Foundation
import PaceCore

/// Inhalte der Karte „Deine Schritte heute“. Ohne SwiftUI, dadurch testbar.
///
/// Die Texte entstehen beim Erzeugen in der aktuellen Sprache; das Dashboard erzeugt die Zusammenfassung bei jedem
/// Zeichnen neu.
public struct StepsTodaySummary: Equatable, Sendable {
    /// Wettbewerbsschritte heute, z. B. `8.432`.
    public let stepsText: String
    public let steps: Int
    public let goal: Int
    /// z. B. `von 10.000 Schritten`
    public let goalText: String
    /// 0…1 (kann über 1 liegen, wenn das Ziel übertroffen ist).
    public let progress: Double
    /// z. B. `84%`
    public let percentText: String
    /// z. B. `Noch 1.568 bis zu deinem Ziel` oder `Tagesziel erreicht!`
    public let remainingText: String
    public let isGoalReached: Bool
    /// `nil`, wenn die Kennzahl nicht lesbar ist – dann wird sie nicht angezeigt (keine falsche 0).
    public let distanceText: String?
    /// Aktive Kalorien (`324 kcal`, geschätzt `≈ 245 kcal`) oder „Nicht verfügbar“, wenn Apple Health für heute keine
    /// hat und nicht geschätzt wird (nie eine falsche 0).
    public let energyText: String
    public let isEnergyAvailable: Bool
    /// Herkunft unter dem Wert: „Aktive Kalorien“ (gemessen) bzw. „Geschätzte aktive Kalorien“.
    public let energyCaption: String
    public let isEnergyEstimated: Bool
    /// Für die großen Schrittkarten; `nil`, wenn nicht lesbar.
    public let flightsText: String?
    public let exerciseText: String?
    /// Für die Max-Schrittkarte: gestern und der Durchschnitt der letzten 7 Tage.
    public let yesterdayText: String?
    public let sevenDayAverageText: String?
    /// Hinweis, wenn heute Schritte in Apple Health nicht für Rankings zählen.
    public let manualStepsNote: String?

    public init(today: DailyActivitySummary, goal: Int, formatter: ActivityFormatter, bodyMetrics: BodyMetrics = BodyMetrics()) {
        self.init(
            today: today.estimatingActiveEnergy(with: bodyMetrics),
            yesterday: nil,
            lastSevenDays: nil,
            goal: goal,
            formatter: formatter
        )
    }

    /// - Parameter liveCompetitionSteps: Schritte von heute inklusive Live-Sensorwerten (nur Anzeige); ohne Angabe der
    ///   HealthKit-Wert.
    /// - Parameter bodyMetrics: Körperdaten für geschätzte Kalorien (nur ohne gemessene Werte).
    public init(
        overview: ActivityOverview,
        goal: Int,
        formatter: ActivityFormatter,
        liveCompetitionSteps: Int? = nil,
        bodyMetrics: BodyMetrics = BodyMetrics()
    ) {
        self.init(
            // Erst die Live-Schritte, dann die Schätzung – sie passt so zur angezeigten Schrittzahl.
            today: Self.today(overview.today, liveCompetitionSteps: liveCompetitionSteps).estimatingActiveEnergy(with: bodyMetrics),
            yesterday: overview.yesterday,
            lastSevenDays: overview.lastSevenDays,
            goal: goal,
            formatter: formatter
        )
    }

    /// Heutige Werte mit Live-Schritten: Wettbewerbs- und Health-Schritte steigen um dieselbe Differenz (der Hinweis
    /// auf manuelle Schritte bleibt dadurch korrekt).
    private static func today(_ today: DailyActivitySummary, liveCompetitionSteps: Int?) -> DailyActivitySummary {
        guard let liveCompetitionSteps, liveCompetitionSteps > today.competitionSteps else { return today }
        let delta = liveCompetitionSteps - today.competitionSteps
        return DailyActivitySummary(
            date: today.date,
            healthSteps: today.healthSteps + delta,
            competitionSteps: liveCompetitionSteps,
            walkingRunningDistanceMeters: today.walkingRunningDistanceMeters,
            activeEnergyKilocalories: today.activeEnergyKilocalories,
            flightsClimbed: today.flightsClimbed,
            exerciseMinutes: today.exerciseMinutes
        )
    }

    private init(
        today: DailyActivitySummary,
        yesterday: DailyActivitySummary?,
        lastSevenDays: ActivityPeriodSummary?,
        goal rawGoal: Int,
        formatter: ActivityFormatter
    ) {
        let goal = max(rawGoal, 1)
        self.goal = goal
        steps = today.competitionSteps
        stepsText = formatter.steps(today.competitionSteps)
        let goalSteps = formatter.steps(goal)
        goalText = PaceLocalization.text(
            de: "von \(goalSteps) Schritten",
            en: "of \(goalSteps) steps",
            ru: "из \(goalSteps) " + PaceLocalization.plural(goal, de: ("", ""), en: ("", ""), ru: ("шага", "шагов", "шагов"))
        )
        progress = Double(today.competitionSteps) / Double(goal)
        percentText = formatter.compactPercent(progress)
        isGoalReached = today.competitionSteps >= goal
        let remaining = formatter.steps(max(goal - today.competitionSteps, 0))
        remainingText = isGoalReached
            ? PaceLocalization.text(de: "Tagesziel erreicht!", en: "Daily goal reached!", ru: "Дневная цель выполнена!")
            : PaceLocalization.text(
                de: "Noch \(remaining) bis zu deinem Ziel",
                en: "\(remaining) to go to your goal",
                ru: "Ещё \(remaining) до твоей цели"
            )
        distanceText = today.walkingRunningDistanceMeters.map { formatter.distance(meters: $0) }
        let energy = today.activeEnergy
        energyText = formatter.energy(energy) ?? ActivityTexts.notAvailable
        isEnergyAvailable = energy != .unavailable
        isEnergyEstimated = energy.isEstimated
        energyCaption = energy.isEstimated
            ? ActivityTexts.estimatedActiveCalories
            : PaceLocalization.text(de: "Aktive Kalorien", en: "Active calories", ru: "Активные калории")
        flightsText = today.flightsClimbed.map { formatter.flights($0) }
        exerciseText = today.exerciseMinutes.map { formatter.exerciseMinutes($0) }
        yesterdayText = yesterday.map { formatter.steps($0.competitionSteps) }
        sevenDayAverageText = lastSevenDays.flatMap { $0.days.isEmpty ? nil : formatter.steps($0.averageCompetitionStepsPerDay) }
        manualStepsNote = today.hasNonCompetitionSteps ? HomeTexts.manualStepsNote : nil
    }
}

/// Wochenübersicht Montag bis Sonntag der aktuellen Woche.
public struct WeekOverview: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public let date: LocalDate
        /// Erster Buchstabe des Wochentags in der App-Sprache, z. B. `M`, `D`, `M`, `D`, `F`, `S`, `S`.
        public let letter: String
        /// Kurzer Wochentag, z. B. `Mo`.
        public let shortName: String
        /// `nil` für Tage in der Zukunft.
        public let steps: Int?
        /// Ziel des Tages laut Zielverlauf.
        public let goal: Int
        /// Höhe relativ zum besten Tag bzw. Tagesziel, 0…1.
        public let level: Double
        public let isToday: Bool
        /// Ziel des Tages erreicht (Ziel laut Zielverlauf).
        public let reachedGoal: Bool
        /// Für VoiceOver, z. B. `Montag, 12. Oktober: 8.432 Schritte`.
        public let accessibilityLabel: String

        public var id: LocalDate { date }
        public var isFuture: Bool { steps == nil }
    }

    public let days: [Day]
    public let total: Int
    public let average: Int
    /// Tage mit erreichtem Ziel; heute zählt mit, sobald das Ziel erreicht ist.
    public let reachedDays: Int
    public let countedDays: Int
    /// Höchster Wert der Woche bzw. das Tagesziel – Skala für Diagramme.
    public let scale: Int
    /// z. B. `41.230`
    public let totalText: String
    /// z. B. `Ø 6.872 pro Tag`
    public let averageText: String
    /// z. B. `3 von 4 Tagen Ziel erreicht`.
    public let goalDaysText: String
    /// Für VoiceOver, z. B. `Diese Woche 41.230 Schritte`.
    public let accessibilitySummary: String

    public init(overview: ActivityOverview, goals: StepGoalHistory, calendar: ActivityCalendar, formatter: ActivityFormatter) {
        let today = overview.today.date
        let monday = calendar.startOfWeek(containing: today)
        let stepsByDay = Dictionary(overview.currentWeek.days.map { ($0.date, $0.competitionSteps) }, uniquingKeysWith: { _, last in last })
        let scale = max(goals.goal(on: today), stepsByDay.values.max() ?? 0, 1)
        self.scale = scale

        days = (0..<7).map { offset in
            let date = calendar.adding(offset, to: monday)
            let isFuture = date > today
            let steps = isFuture ? nil : (stepsByDay[date] ?? 0)
            let goal = goals.goal(on: date)
            return Day(
                date: date,
                letter: HomeFormat.weekdayLetter(date, formatter: formatter),
                shortName: formatter.weekdayShort(date),
                steps: steps,
                goal: goal,
                level: steps.map { min(Double($0) / Double(scale), 1) } ?? 0,
                isToday: date == today,
                reachedGoal: steps.map { $0 >= goal } ?? false,
                accessibilityLabel: "\(formatter.dayLong(date)): " + (steps.map { PaceLocalization.steps($0) }
                    ?? PaceLocalization.text(de: "noch offen", en: "upcoming", ru: "ещё впереди"))
            )
        }
        let elapsed = days.filter { !$0.isFuture }
        total = elapsed.compactMap(\.steps).reduce(0, +)
        average = elapsed.isEmpty ? 0 : Int((Double(total) / Double(elapsed.count)).rounded())
        let counted = elapsed.filter { !$0.isToday || $0.reachedGoal }
        reachedDays = counted.filter(\.reachedGoal).count
        countedDays = counted.count
        totalText = formatter.steps(total)
        let averageSteps = formatter.steps(average)
        averageText = PaceLocalization.text(de: "Ø \(averageSteps) pro Tag", en: "Avg. \(averageSteps) per day", ru: "В среднем \(averageSteps) в день")
        goalDaysText = Self.goalDaysText(reached: reachedDays, counted: countedDays)
        accessibilitySummary = PaceLocalization.text(
            de: "Diese Woche \(PaceLocalization.steps(total))",
            en: "This week \(PaceLocalization.steps(total))",
            ru: "На этой неделе \(PaceLocalization.steps(total))"
        )
    }

    static func goalDaysText(reached: Int, counted: Int) -> String {
        let reachedText = reached.paceFormatted
        let countedText = counted.paceFormatted
        return PaceLocalization.text(
            de: "\(reachedText) von \(countedText) \(counted == 1 ? "Tag" : "Tagen") Ziel erreicht",
            en: "Goal reached on \(reachedText) of \(countedText) \(counted == 1 ? "day" : "days")",
            ru: "Цель выполнена в \(reachedText) из \(countedText) "
                + PaceLocalization.plural(counted, de: ("", ""), en: ("", ""), ru: ("дня", "дней", "дней"))
        )
    }
}
