import Foundation
import Observation
import PaceCore

/// Steuert die Anfrage nach Health-Zugriff beim ersten Start.
@MainActor
@Observable
public final class HealthPermissionViewModel {
    public enum State: Equatable {
        case idle
        case requesting
        case failed(message: String)
    }

    public private(set) var state: State = .idle

    public var isRequesting: Bool {
        state == .requesting
    }

    private let authorization: any HealthAuthorizationProviding
    private let onFinished: @MainActor () -> Void

    /// - Parameter onFinished: Wird aufgerufen, sobald der System-Dialog abgeschlossen ist.
    ///   Ob der Nutzer zugestimmt hat, ist für Lesezugriffe nicht ermittelbar; das prüft der Home-Screen.
    public init(
        authorization: any HealthAuthorizationProviding,
        onFinished: @escaping @MainActor () -> Void
    ) {
        self.authorization = authorization
        self.onFinished = onFinished
    }

    public func requestAccess() async {
        guard !isRequesting else { return }
        state = .requesting

        do {
            try await authorization.requestAuthorization()
            state = .idle
            onFinished()
        } catch {
            state = .failed(message: Self.message(for: error))
        }
    }

    static func message(for error: Error) -> String {
        switch error as? HealthDataError {
        case .healthDataUnavailable:
            "Apple Health ist auf diesem Gerät nicht verfügbar."
        case .protectedDataUnavailable:
            "Entsperre dein iPhone und versuche es erneut."
        default:
            "Die Verbindung zu Apple Health konnte nicht hergestellt werden. Bitte versuche es erneut."
        }
    }
}
