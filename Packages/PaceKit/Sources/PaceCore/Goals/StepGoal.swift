import Foundation
import Observation

/// Regeln für das tägliche Schrittziel.
public enum StepGoalRules {
    public static let defaultGoal = 10_000
    public static let range = 1_000...50_000
    public static let increment = 500

    /// Mögliche Ziele in 500er-Schritten.
    public static let options = Array(stride(from: range.lowerBound, through: range.upperBound, by: increment))

    /// Ziel im erlaubten Bereich, gerundet auf 500er-Schritte.
    public static func clamped(_ goal: Int) -> Int {
        let clamped = min(max(goal, range.lowerBound), range.upperBound)
        return (clamped + increment / 2) / increment * increment
    }
}

/// Verlauf des Tagesziels. Jede Änderung gilt ab dem Tag, an dem sie vorgenommen wurde – vergangene Tage behalten
/// ihr damaliges Ziel. So verändern Zieländerungen Streaks, Zieltage und Statistiken nicht rückwirkend.
public struct StepGoalHistory: Equatable, Sendable {
    public struct Change: Codable, Equatable, Sendable {
        public let effectiveFrom: LocalDate
        public let goal: Int

        public init(effectiveFrom: LocalDate, goal: Int) {
            self.effectiveFrom = effectiveFrom
            self.goal = goal
        }
    }

    /// Ab diesem Tag gilt das erste Ziel. Vor Einführung des Verlaufs galt das damals gespeicherte Ziel für alle Tage.
    public static let origin = LocalDate(year: 2000, month: 1, day: 1)

    /// Chronologisch, nie leer, höchstens eine Änderung pro Tag.
    public private(set) var changes: [Change]

    public init(initialGoal: Int = StepGoalRules.defaultGoal) {
        changes = [Change(effectiveFrom: Self.origin, goal: StepGoalRules.clamped(initialGoal))]
    }

    /// Repariert gespeicherte Werte: sortiert, pro Tag gilt die letzte Änderung, Ziele im erlaubten Bereich.
    public init(changes: [Change]) {
        var byDay: [LocalDate: Int] = [:]
        for change in changes {
            byDay[change.effectiveFrom] = StepGoalRules.clamped(change.goal)
        }
        let sorted = byDay.keys.sorted().map { Change(effectiveFrom: $0, goal: byDay[$0]!) }
        self.changes = sorted.isEmpty ? [Change(effectiveFrom: Self.origin, goal: StepGoalRules.defaultGoal)] : sorted
    }

    /// Das Ziel, das an `day` galt bzw. gilt. Tage vor der ersten Änderung haben das erste Ziel.
    public func goal(on day: LocalDate) -> Int {
        changes.last { $0.effectiveFrom <= day }?.goal ?? changes[0].goal
    }

    /// Setzt das Ziel ab `day`. Spätere Änderungen (z. B. nach einer Zeitzonenreise) werden verworfen.
    public mutating func setGoal(_ goal: Int, from day: LocalDate) {
        let goal = StepGoalRules.clamped(goal)
        guard day > Self.origin else {
            changes = [Change(effectiveFrom: Self.origin, goal: goal)]
            return
        }
        var remaining = changes.filter { $0.effectiveFrom < day }
        if remaining.isEmpty {
            remaining = [Change(effectiveFrom: Self.origin, goal: changes[0].goal)]
        }
        if remaining.last?.goal != goal {
            remaining.append(Change(effectiveFrom: day, goal: goal))
        }
        changes = remaining
    }
}

extension StepGoalHistory: Codable {
    private enum CodingKeys: String, CodingKey {
        case changes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(changes: try container.decode([Change].self, forKey: .changes))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(changes, forKey: .changes)
    }
}

/// Speichert den Zielverlauf (nur auf dem Gerät).
public protocol StepGoalStoring: Sendable {
    func load() -> StepGoalHistory?
    func save(_ history: StepGoalHistory)
}

/// Speichert den Zielverlauf als JSON in den `UserDefaults`.
public struct UserDefaultsStepGoalStore: StepGoalStoring {
    private let suiteName: String?
    private let key = "pace.goals.steps"

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    public func load() -> StepGoalHistory? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StepGoalHistory.self, from: data)
    }

    public func save(_ history: StepGoalHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}

/// Hält den Zielverlauf nur im Speicher – für Vorschauen und Tests.
public final class InMemoryStepGoalStore: StepGoalStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: StepGoalHistory?

    public init(_ history: StepGoalHistory? = nil) {
        stored = history
    }

    public func load() -> StepGoalHistory? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public func save(_ history: StepGoalHistory) {
        lock.lock()
        defer { lock.unlock() }
        stored = history
    }
}

/// Das Tagesziel, live für alle Ansichten (Home, Statistiken, Streak, Profil).
@MainActor
@Observable
public final class StepGoalSettings {
    public private(set) var history: StepGoalHistory

    @ObservationIgnored private let store: any StepGoalStoring
    @ObservationIgnored private let calendar: ActivityCalendar
    @ObservationIgnored private let now: @Sendable () -> Date

    /// - Parameter legacyGoal: Ziel aus einer älteren Version (vor dem Zielverlauf). Gilt dann für alle bisherigen Tage.
    public init(
        store: any StepGoalStoring,
        legacyGoal: Int? = nil,
        calendar: ActivityCalendar = ActivityCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.calendar = calendar
        self.now = now
        if let stored = store.load() {
            history = stored
        } else {
            history = StepGoalHistory(initialGoal: legacyGoal ?? StepGoalRules.defaultGoal)
            store.save(history)
        }
    }

    /// Das heute gültige Ziel.
    public var currentGoal: Int {
        history.goal(on: calendar.day(containing: now()))
    }

    public func goal(on day: LocalDate) -> Int {
        history.goal(on: day)
    }

    /// Ändert das Ziel ab heute. Vergangene Tage behalten ihr Ziel.
    public func setGoal(_ goal: Int) {
        var updated = history
        updated.setGoal(goal, from: calendar.day(containing: now()))
        guard updated != history else { return }
        history = updated
        store.save(updated)
    }
}
