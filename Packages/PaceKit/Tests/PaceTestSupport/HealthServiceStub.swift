import Foundation
import PaceCore

/// Konfigurierbarer Test-Double für die Health-Protokolle.
///
/// `@unchecked Sendable`: Der gesamte veränderliche Zustand wird ausschließlich unter `lock` gelesen und geschrieben.
public final class HealthServiceStub: HealthAuthorizationProviding, ActivityDataProviding, @unchecked Sendable {
    public struct Configuration: Sendable {
        public var isHealthDataAvailable = true
        public var authorizationStatus: Result<HealthAuthorizationRequestStatus, HealthDataError> = .success(.alreadyRequested)
        public var requestAuthorizationResult: Result<Void, HealthDataError> = .success(())
        /// Tageswerte je Kennzahl. Eine fehlende Kennzahl bzw. ein fehlender Tag bedeutet „keine Samples“.
        public var dailyTotals: [ActivityMetric: [LocalDate: Double]] = [:]
        /// Fehler, den `dailyTotals(of:for:calendar:)` für alle Kennzahlen wirft.
        public var dailyTotalsError: HealthDataError?
        /// Stundenwerte je Kennzahl und Tag (Stunde 0–23).
        public var hourlyTotals: [ActivityMetric: [LocalDate: [Int: Double]]] = [:]
        /// Kennzahlen, für die irgendwann Samples existieren (unabhängig vom Zeitraum).
        public var metricsWithAnySamples: Set<ActivityMetric> = []
        /// Zugriff auf die optionalen Herzwerte. Standard wie eine Quelle ohne Herzwerte.
        public var heartRateAccess: HeartRateAccess = .unavailable
        /// Ergebnis der Freigabe-Abfrage; bei Erfolg wechselt `heartRateAccess` zu `.requested`.
        public var requestHeartRateAccessResult: Result<Void, HealthDataError> = .success(())
        /// Herzwerte je Tag. Fehlende Tage haben keine Werte.
        public var heartRates: [LocalDate: DailyHeartRate] = [:]
        /// Fehler beim Lesen der Herzwerte.
        public var heartRateError: HealthDataError?

        public init() {}

        /// Setzt einen Tageswert und markiert die Kennzahl als grundsätzlich lesbar.
        public mutating func set(_ metric: ActivityMetric, _ value: Double, on day: LocalDate) {
            dailyTotals[metric, default: [:]][day] = value
            metricsWithAnySamples.insert(metric)
        }

        /// Setzt Health- und Wettbewerbsschritte eines Tags.
        public mutating func setSteps(_ steps: Int, competition: Int? = nil, on day: LocalDate) {
            set(.steps, Double(steps), on: day)
            set(.competitionSteps, Double(competition ?? steps), on: day)
        }
    }

    public struct Calls: Sendable {
        public var authorizationRequests = 0
        public var dailyTotalsRequests: [(metric: ActivityMetric, days: ClosedRange<LocalDate>)] = []
        public var hourlyTotalsRequests: [(metric: ActivityMetric, day: LocalDate)] = []
        public var hasAnySamplesQueries: [ActivityMetric] = []
        public var heartRateAccessRequests = 0
        public var dailyHeartRateRequests: [LocalDate] = []
    }

    private let lock = NSLock()
    private var configuration: Configuration
    private var calls = Calls()
    private var changeContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(configure: (inout Configuration) -> Void = { _ in }) {
        var configuration = Configuration()
        configure(&configuration)
        self.configuration = configuration
    }

    public func update(_ change: (inout Configuration) -> Void) {
        withLock { change(&configuration) }
    }

    public var recordedCalls: Calls {
        withLock { calls }
    }

    public var activeChangeObservers: Int {
        withLock { changeContinuations.count }
    }

    /// Simuliert eine Benachrichtigung von HealthKit über neue Daten.
    public func simulateActivityChange() {
        let continuations = withLock { Array(changeContinuations.values) }
        continuations.forEach { $0.yield() }
    }

    // MARK: HealthAuthorizationProviding

    public var isHealthDataAvailable: Bool {
        withLock { configuration.isHealthDataAvailable }
    }

    public func authorizationRequestStatus() async throws -> HealthAuthorizationRequestStatus {
        try withLock { configuration.authorizationStatus }.get()
    }

    public func requestAuthorization() async throws {
        try withLock {
            calls.authorizationRequests += 1
            return configuration.requestAuthorizationResult
        }.get()
    }

    // MARK: ActivityDataProviding

    public func dailyTotals(
        of metric: ActivityMetric,
        for days: ClosedRange<LocalDate>,
        calendar: ActivityCalendar
    ) async throws -> [LocalDate: Double] {
        try withLock {
            calls.dailyTotalsRequests.append((metric, days))
            if let error = configuration.dailyTotalsError {
                throw error
            }
            return (configuration.dailyTotals[metric] ?? [:]).filter { days.contains($0.key) }
        }
    }

    public func hourlyTotals(
        of metric: ActivityMetric,
        on day: LocalDate,
        calendar: ActivityCalendar
    ) async throws -> [Int: Double] {
        try withLock {
            calls.hourlyTotalsRequests.append((metric, day))
            if let error = configuration.dailyTotalsError {
                throw error
            }
            return configuration.hourlyTotals[metric]?[day] ?? [:]
        }
    }

    public func hasAnySamples(of metric: ActivityMetric) async throws -> Bool {
        withLock {
            calls.hasAnySamplesQueries.append(metric)
            return configuration.metricsWithAnySamples.contains(metric)
        }
    }

    public func activityChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.withLock { _ = self.changeContinuations.removeValue(forKey: id) }
        }
        withLock { changeContinuations[id] = continuation }
        return stream
    }

    public func heartRateAccess() async -> HeartRateAccess {
        withLock { configuration.heartRateAccess }
    }

    public func requestHeartRateAccess() async throws {
        try withLock {
            calls.heartRateAccessRequests += 1
            let result = configuration.requestHeartRateAccessResult
            if case .success = result, configuration.heartRateAccess == .notRequested {
                configuration.heartRateAccess = .requested
            }
            return result
        }.get()
    }

    public func dailyHeartRate(on day: LocalDate, calendar: ActivityCalendar) async throws -> DailyHeartRate {
        try withLock {
            calls.dailyHeartRateRequests.append(day)
            if let error = configuration.heartRateError {
                throw error
            }
            return configuration.heartRates[day] ?? .empty
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
