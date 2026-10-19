import Foundation
import Observation
import PaceCore

/// Ziel beim Öffnen eines Chats: eine vorhandene Unterhaltung, der direkte Chat mit einem Freund oder der Chat einer
/// Gruppe.
public enum ChatTarget: Hashable, Sendable {
    case conversation(id: UUID, kind: ConversationKind, title: String)
    case direct(SocialProfile)
    case group(id: UUID, name: String)
}

/// Chatliste im Social-Tab (Filter Alle/Freunde/Gruppen) und Erzeugung der einzelnen Chats.
///
/// Vertrag zwischen Social-Hauptseite, Gruppendetails und Chats; Inhalt und Logik entstehen im Chat-Arbeitspaket.
@MainActor
@Observable
public final class ChatListViewModel {
    public enum Filter: String, CaseIterable, Sendable, Identifiable {
        case all
        case friends
        case groups

        public var id: String { rawValue }
    }

    public var filter: Filter = .all
    public private(set) var conversations: [ConversationSummary] = []

    @ObservationIgnored let repository: (any ChatRepository)?
    @ObservationIgnored let media: (any MediaRepository)?

    /// - Parameters:
    ///   - repository: `nil`, wenn kein Backend konfiguriert ist.
    ///   - media: Hochladen und Laden von Bildern und GIFs.
    public init(repository: (any ChatRepository)?, media: (any MediaRepository)?) {
        self.repository = repository
        self.media = media
    }

    public var isAvailable: Bool {
        repository != nil
    }

    /// Ungelesene Nachrichten über alle Unterhaltungen.
    public var unreadCount: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }

    public func loadIfNeeded() async {}

    public func load() async {}

    /// Teilt ein Profil als Profilnachricht in die gewählten Chats (Freunde und eigene Gruppen).
    public func shareProfile(_ profile: SocialProfile, with targets: [ChatTarget]) async throws {
        throw SocialError.unavailable
    }

    /// ViewModel für einen einzelnen Chat.
    public func chat(for target: ChatTarget) -> ChatViewModel {
        ChatViewModel(target: target, repository: repository, media: media)
    }
}

/// Ein einzelner Chat (privat oder Gruppe).
@MainActor
@Observable
public final class ChatViewModel {
    public let target: ChatTarget

    @ObservationIgnored let repository: (any ChatRepository)?
    @ObservationIgnored let media: (any MediaRepository)?

    init(target: ChatTarget, repository: (any ChatRepository)?, media: (any MediaRepository)?) {
        self.target = target
        self.repository = repository
        self.media = media
    }
}
