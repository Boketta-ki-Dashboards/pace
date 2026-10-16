import Foundation
import PaceCore

/// Konfigurierbarer Test-Double für die Health-Protokolle. Threadsicher über einen Lock.
public final class HealthServiceStub: HealthAuthorizationProviding, StepCountProviding, @unchecked Sendable {
    public struct Configuration: Sendable {
        public var isHealthDataAvailable = true
        public var authorizationStatus: Result<HealthAuthorizationRequestStatus, HealthDataError> = .success(.alreadyRequested)
        public var requestAuthorizationResult: Result<Void, HealthDataError> = .success(())
        public var stepCount: Result<Int?, HealthDataError> = .success(nil)
        public var hasAnyStepSamples: Result<Bool, HealthDataError> = .success(false)

        public init() {}
    }

    public struct Calls: Sendable {
        public var authorizationRequests = 0
        public var stepCountIntervals: [DateInterval] = []
        public var hasAnyStepSamplesQueries = 0
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

    /// Simuliert eine Benachrichtigung von HealthKit über neue Schrittdaten.
    public func simulateStepCountChange() {
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

    // MARK: StepCountProviding

    public func stepCount(in interval: DateInterval) async throws -> Int? {
        try withLock {
            calls.stepCountIntervals.append(interval)
            return configuration.stepCount
        }.get()
    }

    public func hasAnyStepSamples() async throws -> Bool {
        try withLock {
            calls.hasAnyStepSamplesQueries += 1
            return configuration.hasAnyStepSamples
        }.get()
    }

    public func stepCountChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.withLock { _ = self.changeContinuations.removeValue(forKey: id) }
        }
        withLock { changeContinuations[id] = continuation }
        return stream
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
