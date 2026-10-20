import Foundation
import HealthKit
import PaceCore

/// Einziger Zugangspunkt der App zu HealthKit.
///
/// Liest Bewegungsdaten (Schritte, Distanz, aktive Energie, Stockwerke, Trainingsminuten) und schreibt nichts in Health.
/// Ruhepuls und Ø Puls beim Gehen liest Pace nur nach einer eigenen, ausdrücklich angestoßenen Freigabe in den
/// Tagesdetails; sie bleiben auf dem Gerät. Siehe docs/HEALTH_DATA.md.
///
/// `@unchecked Sendable`: Der einzige Zustand ist die unveränderliche Referenz auf `HKHealthStore`, der laut Apple
/// threadsicher ist und app-weit als einzelne Instanz verwendet werden soll.
public final class HealthKitService: @unchecked Sendable {
    private let healthStore: HKHealthStore

    public init() {
        healthStore = HKHealthStore()
    }

    /// Alle Typen, für die Pace beim ersten Start Lesezugriff anfragt (nur Bewegungsdaten).
    static var readTypes: Set<HKObjectType> {
        Set(HealthMetricMapping.quantityTypes)
    }

    /// Optionale Herzwerte – eigene Abfrage, nur auf Wunsch (nie beim App-Start, kein Hintergrund-Observer).
    static var heartRateReadTypes: Set<HKObjectType> {
        [HKQuantityType(.restingHeartRate), HKQuantityType(.walkingHeartRateAverage)]
    }
}

// MARK: - Berechtigungen

extension HealthKitService: HealthAuthorizationProviding {
    public var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    public func authorizationRequestStatus() async throws -> HealthAuthorizationRequestStatus {
        guard isHealthDataAvailable else { throw HealthDataError.healthDataUnavailable }

        let status: HKAuthorizationRequestStatus
        do {
            status = try await withCheckedThrowingContinuation { continuation in
                healthStore.getRequestStatusForAuthorization(toShare: [], read: Self.readTypes) { status, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: status)
                    }
                }
            }
        } catch {
            throw HealthKitErrorMapping.map(error, fallback: HealthDataError.queryFailed)
        }

        // Kommen neue Lesetypen hinzu, meldet HealthKit wieder `.shouldRequest` – die Abfrage erscheint dann erneut.
        switch status {
        case .shouldRequest:
            return .shouldRequest
        case .unnecessary:
            return .alreadyRequested
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    public func requestAuthorization() async throws {
        guard isHealthDataAvailable else { throw HealthDataError.healthDataUnavailable }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
        } catch {
            throw HealthKitErrorMapping.map(error, fallback: HealthDataError.authorizationRequestFailed)
        }
    }
}

// MARK: - Bewegungsdaten

extension HealthKitService: ActivityDataProviding {
    public func dailyTotals(
        of metric: ActivityMetric,
        for days: ClosedRange<LocalDate>,
        calendar: ActivityCalendar
    ) async throws -> [LocalDate: Double] {
        let interval = calendar.interval(from: days.lowerBound, through: days.upperBound)
        var totals: [LocalDate: Double] = [:]
        for (start, value) in try await statistics(of: metric, in: interval, bucket: DateComponents(day: 1)) {
            let day = calendar.day(containing: start)
            guard days.contains(day) else { continue }
            totals[day, default: 0] += value
        }
        return totals
    }

    public func hourlyTotals(
        of metric: ActivityMetric,
        on day: LocalDate,
        calendar: ActivityCalendar
    ) async throws -> [Int: Double] {
        let interval = calendar.interval(for: day)
        var totals: [Int: Double] = [:]
        for (start, value) in try await statistics(of: metric, in: interval, bucket: DateComponents(hour: 1)) {
            guard interval.contains(start) else { continue }
            totals[calendar.calendar.component(.hour, from: start), default: 0] += value
        }
        return totals
    }

    /// Summen je Intervall (`bucket`) im Zeitraum, nur Intervalle mit Samples.
    private func statistics(
        of metric: ActivityMetric,
        in interval: DateInterval,
        bucket: DateComponents
    ) async throws -> [(start: Date, value: Double)] {
        var predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        if let filter = HealthMetricMapping.additionalPredicate(for: metric) {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, filter])
        }

        // Statistik-Abfragen mit `.cumulativeSum` führen überlappende Quellen (iPhone + Apple Watch) nach der
        // Prioritätenliste der Health-App zusammen – auch, wenn ein zusätzliches Predicate Samples ausschließt.
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HealthMetricMapping.quantityType(for: metric), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: interval.start,
            intervalComponents: bucket
        )

        let collection: HKStatisticsCollection
        do {
            collection = try await descriptor.result(for: healthStore)
        } catch let error as HKError where error.code == .errorNoData {
            return []
        } catch {
            throw HealthKitErrorMapping.map(error, fallback: HealthDataError.queryFailed)
        }

        let unit = HealthMetricMapping.unit(for: metric)
        // `statistics()` enthält nur Intervalle mit Samples.
        return collection.statistics().compactMap { statistics in
            statistics.sumQuantity().map { (start: statistics.startDate, value: $0.doubleValue(for: unit)) }
        }
    }

    public func hasAnySamples(of metric: ActivityMetric) async throws -> Bool {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: HealthMetricMapping.quantityType(for: metric),
                predicate: HealthMetricMapping.additionalPredicate(for: metric)
            )],
            sortDescriptors: [],
            limit: 1
        )

        do {
            let samples = try await descriptor.result(for: healthStore)
            return !samples.isEmpty
        } catch let error as HKError where error.code == .errorNoData {
            return false
        } catch {
            throw HealthKitErrorMapping.map(error, fallback: HealthDataError.queryFailed)
        }
    }

    public func activityChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

        let descriptors = HealthMetricMapping.quantityTypes.map { HKQueryDescriptor(sampleType: $0, predicate: nil) }
        let query = HKObserverQuery(queryDescriptors: descriptors) { _, _, completionHandler, error in
            if error == nil {
                continuation.yield()
            }
            completionHandler()
        }
        let registration = ObserverQueryRegistration(healthStore: healthStore, query: query)
        continuation.onTermination = { _ in
            registration.stop()
        }
        healthStore.execute(query)

        return stream
    }
}

// MARK: - Optionale Herzwerte

extension HealthKitService {
    public func heartRateAccess() async -> HeartRateAccess {
        guard isHealthDataAvailable else { return .unavailable }
        do {
            let status: HKAuthorizationRequestStatus = try await withCheckedThrowingContinuation { continuation in
                healthStore.getRequestStatusForAuthorization(toShare: [], read: Self.heartRateReadTypes) { status, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: status)
                    }
                }
            }
            // Ob zugestimmt wurde, verrät HealthKit bei Lesezugriffen nicht – nur, ob schon gefragt wurde.
            switch status {
            case .unnecessary:
                return .requested
            case .shouldRequest, .unknown:
                return .notRequested
            @unknown default:
                return .notRequested
            }
        } catch {
            return .unavailable
        }
    }

    public func requestHeartRateAccess() async throws {
        guard isHealthDataAvailable else { throw HealthDataError.healthDataUnavailable }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.heartRateReadTypes)
        } catch {
            throw HealthKitErrorMapping.map(error, fallback: HealthDataError.authorizationRequestFailed)
        }
    }

    public func dailyHeartRate(on day: LocalDate, calendar: ActivityCalendar) async throws -> DailyHeartRate {
        let interval = calendar.interval(for: day)
        let resting = try await averageBeatsPerMinute(of: .restingHeartRate, in: interval)
        let walking = try await averageBeatsPerMinute(of: .walkingHeartRateAverage, in: interval)
        return DailyHeartRate(restingBeatsPerMinute: resting, walkingAverageBeatsPerMinute: walking)
    }

    /// Durchschnitt der Samples im Intervall in Schlägen pro Minute; `nil` ohne Samples (oder ohne Zustimmung).
    private func averageBeatsPerMinute(of identifier: HKQuantityTypeIdentifier, in interval: DateInterval) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
            options: .discreteAverage
        )
        do {
            let statistics = try await descriptor.result(for: healthStore)
            return statistics?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        } catch let error as HKError where error.code == .errorNoData {
            return nil
        } catch {
            throw HealthKitErrorMapping.map(error, fallback: HealthDataError.queryFailed)
        }
    }
}

/// Hält eine laufende Observer-Query, damit sie beim Beenden des Streams gestoppt werden kann.
/// `@unchecked Sendable`: Beide Referenzen sind unveränderlich, `HKHealthStore.stop(_:)` ist threadsicher.
private final class ObserverQueryRegistration: @unchecked Sendable {
    private let healthStore: HKHealthStore
    private let query: HKObserverQuery

    init(healthStore: HKHealthStore, query: HKObserverQuery) {
        self.healthStore = healthStore
        self.query = query
    }

    func stop() {
        healthStore.stop(query)
    }
}
