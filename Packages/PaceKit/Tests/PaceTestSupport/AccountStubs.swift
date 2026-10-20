import Foundation
import PaceCore

/// Test-Double für `AccountRepository`.
public final class AccountRepositoryStub: AccountRepository, Sendable {
    public struct State: Sendable {
        public var exportJSON = Data(#"{"profile":{"username":"niklas"}}"#.utf8)
        public var media: [MediaReference] = []
        /// Fehler für alle Aufrufe.
        public var error: AccountError?
        /// Fehler nur für einzelne Aufrufe.
        public var exportError: AccountError?
        public var ownMediaError: AccountError?
        public var deleteError: AccountError?
        public var feedbackError: AccountError?
        public var exportCalls = 0
        public var deleteCalls = 0
        public var feedback: [(FeedbackKind, String, String)] = []
    }

    public let state: Locked<State>

    public init(configure: (inout State) -> Void = { _ in }) {
        var state = State()
        configure(&state)
        self.state = Locked(state)
    }

    public func exportData() async throws -> Data {
        try state.withLock { state in
            state.exportCalls += 1
            if let error = state.error ?? state.exportError { throw error }
            return state.exportJSON
        }
    }

    public func ownMedia() async throws -> [MediaReference] {
        try state.withLock { state in
            if let error = state.error ?? state.ownMediaError { throw error }
            return state.media
        }
    }

    public func deleteAccount() async throws {
        try state.withLock { state in
            if let error = state.error ?? state.deleteError { throw error }
            state.deleteCalls += 1
        }
    }

    public func submitFeedback(kind: FeedbackKind, message: String, appVersion: String) async throws {
        try state.withLock { state in
            if let error = state.error ?? state.feedbackError { throw error }
            state.feedback.append((kind, message, appVersion))
        }
    }
}

// MARK: - Mitteilungen

/// Test-Double für lokale Mitteilungen.
public final class NotificationSchedulerStub: LocalNotificationScheduling, Sendable {
    public struct State: Sendable {
        public var authorization: NotificationAuthorization = .notDetermined
        public var grantsOnRequest = true
        public var scheduled: [(hour: Int, minute: Int, skipToday: Bool)] = []
        public var cancelCalls = 0
    }

    public let state: Locked<State>

    public init(configure: (inout State) -> Void = { _ in }) {
        var state = State()
        configure(&state)
        self.state = Locked(state)
    }

    public func authorization() async -> NotificationAuthorization {
        state.withLock { $0.authorization }
    }

    public func requestAuthorization() async -> Bool {
        state.withLock { state in
            state.authorization = state.grantsOnRequest ? .authorized : .denied
            return state.grantsOnRequest
        }
    }

    public func scheduleStreakReminders(hour: Int, minute: Int, skipToday: Bool, title: String, body: String) async {
        state.withLock { $0.scheduled.append((hour, minute, skipToday)) }
    }

    public func cancelStreakReminders() async {
        state.withLock { $0.cancelCalls += 1 }
    }
}
