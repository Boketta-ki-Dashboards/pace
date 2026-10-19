import Foundation
import Observation
import PaceCore

/// Was gemeldet wird – Person oder Gruppe (Nachrichten meldet der Chat selbst).
public enum SocialReportSubject: Hashable, Sendable {
    case user(SocialProfile)
    case group(id: UUID, name: String)

    public var target: ReportTarget {
        switch self {
        case .user(let profile): .user(publicID: profile.publicID)
        case .group(let id, _): .group(id: id)
        }
    }

    /// Titel der Seite, z. B. „Nutzer melden“.
    public var title: String {
        switch self {
        case .user: SocialText.reportUser
        case .group: SocialText.reportGroup
        }
    }

    /// Name bzw. @Benutzername unter dem Titel.
    public var subtitle: String {
        switch self {
        case .user(let profile): "\(profile.displayName) · @\(profile.username)"
        case .group(_, let name): name
        }
    }
}

/// Meldung an das Pace-Team: Grund aus ``ReportReason`` und optionale Details. Gespeichert wird auf dem Server, die
/// Bearbeitung erfolgt außerhalb der App.
@MainActor
@Observable
public final class ReportViewModel {
    public static let maximumDetailsLength = 500

    public let subject: SocialReportSubject
    public var reason: ReportReason?
    public var details = ""
    public private(set) var isSending = false
    public private(set) var didSend = false

    @ObservationIgnored private weak var social: SocialViewModel?

    public init(subject: SocialReportSubject, social: SocialViewModel?) {
        self.subject = subject
        self.social = social
    }

    public var canSend: Bool {
        reason != nil && !isSending && details.count <= Self.maximumDetailsLength
    }

    public var remainingCharacters: Int {
        Self.maximumDetailsLength - details.count
    }

    /// Sendet die Meldung. Erfolg und Fehler stehen im gemeinsamen Hinweis (`social.notice`).
    @discardableResult
    public func send() async -> Bool {
        guard let social, let reason, canSend else { return false }
        isSending = true
        defer { isSending = false }
        let sent = await social.report(subject.target, reason: reason, details: details)
        didSend = sent
        return sent
    }
}
