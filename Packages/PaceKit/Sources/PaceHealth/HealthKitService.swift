import Foundation
import HealthKit
import PaceCore

/// Einziger Zugangspunkt der App zu HealthKit.
///
/// Liest ausschließlich den Typ `stepCount` und schreibt nichts in Health.
/// `@unchecked Sendable`: Der einzige Zustand sind unveränderliche Referenzen; `HKHealthStore` ist laut Apple
/// threadsicher und soll app-weit als einzelne Instanz verwendet werden.
public final class HealthKitService: @unchecked Sendable {
    private let healthStore: HKHealthStore
    private let stepCountType = HKQuantityType(.stepCount)

    public init() {
        healthStore = HKHealthStore()
    }

    private var readTypes: Set<HKObjectType> {
        [stepCountType]
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
                healthStore.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: status)
                    }
                }
            }
        } catch {
            throw Self.mapError(error, fallback: HealthDataError.queryFailed)
        }

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
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            throw Self.mapError(error, fallback: HealthDataError.authorizationRequestFailed)
        }
    }
}

// MARK: - Schritte

extension HealthKitService: StepCountProviding {
    public func stepCount(in interval: DateInterval) async throws -> Int? {
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )
        // `.cumulativeSum` dedupliziert überlappende Quellen (iPhone + Apple Watch) wie die Health-App.
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: stepCountType, predicate: predicate),
            options: .cumulativeSum
        )

        do {
            guard let sum = try await descriptor.result(for: healthStore)?.sumQuantity() else {
                return nil
            }
            return Int(sum.doubleValue(for: .count()).rounded())
        } catch let error as HKError where error.code == .errorNoData {
            return nil
        } catch {
            throw Self.mapError(error, fallback: HealthDataError.queryFailed)
        }
    }

    public func hasAnyStepSamples() async throws -> Bool {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: stepCountType)],
            sortDescriptors: [],
            limit: 1
        )

        do {
            let samples = try await descriptor.result(for: healthStore)
            return !samples.isEmpty
        } catch let error as HKError where error.code == .errorNoData {
            return false
        } catch {
            throw Self.mapError(error, fallback: HealthDataError.queryFailed)
        }
    }

    public func stepCountChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

        let query = HKObserverQuery(sampleType: stepCountType, predicate: nil) { _, completionHandler, error in
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

// MARK: - Fehler

private extension HealthKitService {
    static func mapError(_ error: Error, fallback: (String) -> HealthDataError) -> HealthDataError {
        if let error = error as? HealthDataError {
            return error
        }
        if let error = error as? HKError {
            switch error.code {
            case .errorHealthDataUnavailable, .errorHealthDataRestricted:
                return .healthDataUnavailable
            case .errorDatabaseInaccessible:
                return .protectedDataUnavailable
            default:
                break
            }
        }
        return fallback(error.localizedDescription)
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
