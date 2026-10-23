import DesignSystem
import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import SwiftUI
import Testing
import UIKit

/// Chatliste (Referenzbild 9), Gruppenchat (Referenzbild 5), Privatchat und Zustände – jeweils mit Kopfzeile.
@MainActor
@Suite(.snapshotsEnabled)
struct ChatSnapshotTests {
    private let languages: [AppLanguage] = [.german, .english, .russian]

    private func page(_ content: some View, loader: PaceImageLoader? = nil) -> some View {
        content
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.m)
            .environment(\.paceImageLoader, loader)
    }

    /// Chat-Inhalt mit Eingabeleiste darunter, wie auf dem iPhone (ohne Scrollen).
    private func chatPage(_ chat: ChatViewModel, loader: PaceImageLoader? = nil) -> some View {
        VStack(spacing: 0) {
            ChatContent(viewModel: chat, isLazy: false)
                .padding(.horizontal, PaceSpacing.m)
                .padding(.vertical, PaceSpacing.m)
            ChatInputBar(viewModel: chat, onPickMedia: {}, onSend: {})
        }
        .environment(\.paceImageLoader, loader)
    }

    @Test func chatList() async throws {
        let list = await ChatSnapshotData.list()
        let content = VStack(alignment: .leading, spacing: PaceSpacing.s) {
            Text(SocialText.chats)
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(PaceColor.textPrimary)
            ChatListContent(viewModel: list)
        }
        try Snapshot.render(page(content), name: "chat-list", languages: languages)
    }

    @Test func groupChat() async throws {
        let (list, loader) = await ChatSnapshotData.groupSetup()
        let chat = list.chat(for: .group(id: ChatSnapshotData.groupID, name: "Smoking red"))
        await chat.load()
        try Snapshot.render(chatPage(chat, loader: loader), name: "group-chat", languages: languages)
    }

    @Test func directChat() async throws {
        let (list, repository) = await ChatSnapshotData.directSetup()
        let chat = list.chat(for: .direct(ChatSnapshotData.mia))
        await chat.load()
        // Eine Nachricht, die ohne Verbindung nicht gesendet werden konnte.
        repository.state.withLock { $0.sendError = .network }
        chat.draftText = "Bin gleich da!"
        await chat.sendText()
        chat.draftText = "Bis gleich"
        try Snapshot.render(chatPage(chat), name: "direct-chat", languages: languages)
    }

    @Test func chatStates() async throws {
        let unavailable = ChatListViewModel(repository: nil, media: nil)
        let empty = ChatListViewModel(repository: ChatRepositoryStub(), media: nil, calendar: Fixtures.activityCalendar)
        await empty.load()
        let failed = ChatListViewModel(repository: ChatRepositoryStub { $0.error = .network }, media: nil, calendar: Fixtures.activityCalendar)
        await failed.load()
        let lists = VStack(alignment: .leading, spacing: PaceSpacing.l) {
            ChatListContent(viewModel: empty)
            ChatListContent(viewModel: failed)
            ChatListContent(viewModel: unavailable)
        }
        try Snapshot.render(page(lists), name: "chat-states", languages: languages)

        let readOnly = await ChatSnapshotData.readOnlySetup()
        let chat = readOnly.chat(for: .direct(ChatSnapshotData.mia))
        await chat.load()
        try Snapshot.render(chatPage(chat), name: "chat-read-only")

        let offline = ChatListViewModel(repository: nil, media: nil).chat(for: .direct(ChatSnapshotData.mia))
        try Snapshot.render(chatPage(offline), name: "chat-unavailable")
    }
}

/// Beispieldaten im Stil der Referenzbilder 5 und 9 (nur für Bilder).
enum ChatSnapshotData {
    static let groupID = UUID(uuidString: "61000000-0000-4000-8000-000000000001")!
    static let groupConversationID = UUID(uuidString: "61000000-0000-4000-8000-000000000002")!
    static let directConversationID = UUID(uuidString: "61000000-0000-4000-8000-000000000003")!
    /// Freitag, 16. Oktober 2026, 18:20 in Berlin.
    static let now = Fixtures.date(2026, 10, 16, 18, 20)

    static func profile(_ index: Int, _ name: String, _ username: String) -> SocialProfile {
        SocialProfile(
            publicID: UUID(uuidString: String(format: "71000000-0000-4000-8000-%012d", index))!,
            username: username,
            displayName: name
        )
    }

    static let leon = profile(1, "Leon", "leon")
    static let marie = profile(2, "Marie", "marie")
    static let gotscha = profile(3, "Gotscha", "gotscha")
    static let flavio = profile(4, "Flavio", "flavio")
    static let lina = profile(5, "Lina", "lina")
    static let jonas = profile(6, "Jonas", "jonas")
    static let mia = profile(7, "Mia Schneider", "mia_s")

    static let parkPath = "\(groupConversationID.uuidString.lowercased())/park.jpg"
    static let gifPath = "\(groupConversationID.uuidString.lowercased())/winken.gif"

    static func at(_ hour: Int, _ minute: Int) -> Date {
        Fixtures.date(2026, 10, 16, hour, minute)
    }

    static func preview(_ text: String?, kind: ChatMessageKind = .text, from sender: String?, own: Bool = false, at date: Date) -> ChatMessagePreview {
        ChatMessagePreview(kind: kind, text: text, senderName: sender, isOwn: own, sentAt: date)
    }

    @MainActor
    static func makeList(_ repository: ChatRepositoryStub, social: SocialRepositoryStub? = nil, media: MediaRepositoryStub? = nil) -> ChatListViewModel {
        ChatListViewModel(
            repository: repository,
            media: media,
            social: social,
            calendar: Fixtures.activityCalendar,
            now: { now }
        )
    }

    // MARK: Chatliste

    @MainActor
    static func list() async -> ChatListViewModel {
        let repository = ChatRepositoryStub { state in
            state.conversations = [
                ChatFixtures.direct(peer: leon, last: preview("Noch eine Runde spazieren?", from: "Leon", at: at(18, 12)), unread: 2, updatedAt: at(18, 12)),
                ChatFixtures.direct(peer: marie, last: preview("Die 10.000 sind geschafft!", from: "Marie", at: at(17, 55)), updatedAt: at(17, 55)),
                ChatFixtures.group(title: "Klassengruppe", memberCount: 24, last: preview("Wer läuft morgen mit?", from: "Flavio", at: Fixtures.date(2026, 10, 15, 17, 50)), unread: 5, updatedAt: Fixtures.date(2026, 10, 15, 17, 50)),
                ChatFixtures.group(title: "Smoking red", memberCount: 12, last: preview(nil, kind: .gif, from: "Gotscha", at: Fixtures.date(2026, 10, 13, 17, 22)), updatedAt: Fixtures.date(2026, 10, 13, 17, 22)),
                ChatFixtures.direct(peer: mia, last: preview(nil, kind: .profile, from: nil, own: true, at: Fixtures.date(2026, 9, 28, 9, 5)), updatedAt: Fixtures.date(2026, 9, 28, 9, 5)),
            ]
        }
        let list = makeList(repository)
        await list.load()
        return list
    }

    // MARK: Gruppenchat (Referenzbild 5)

    @MainActor
    static func groupSetup() async -> (ChatListViewModel, PaceImageLoader) {
        let conversation = ChatFixtures.group(id: groupConversationID, groupID: groupID, title: "Smoking red", memberCount: 12, updatedAt: at(18, 17))
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[groupConversationID] = [
                ChatFixtures.message(in: groupConversationID, from: leon, text: "Wer ist heute Abend bei einer Runde dabei?", at: at(18, 10)),
                ChatFixtures.message(in: groupConversationID, from: marie, kind: .image, mediaPath: parkPath, at: at(18, 11)),
                ChatFixtures.message(in: groupConversationID, from: marie, text: "Hier treffen wir uns", at: at(18, 12)),
                ChatFixtures.message(in: groupConversationID, from: nil, isOwn: true, text: "Ich komme mit. Mir fehlen noch ein paar Schritte.", at: at(18, 14)),
                ChatFixtures.message(in: groupConversationID, from: gotscha, kind: .gif, mediaPath: gifPath, at: at(18, 16)),
                ChatFixtures.message(in: groupConversationID, from: nil, isOwn: true, text: "Passt, bis gleich!", at: at(18, 17)),
            ]
        }
        let members = [leon, marie, gotscha, flavio, lina, jonas]
        let social = SocialRepositoryStub { state in
            state.groups = [SocialRepositoryStub.group(id: groupID, name: "Smoking red", kind: .friends, role: .member, memberCount: 12, currentStreak: 12, reached: 12)]
            state.groupRankings[groupID] = GroupRanking(
                totalParticipants: 12,
                groupToday: Fixtures.day(2026, 10, 16),
                dailyGoal: 8_000,
                entries: members.enumerated().map { index, profile in
                    GroupRankingEntry(rank: index + 1, profile: profile, competitionSteps: 12_000 - index * 900, isCurrentUser: false, role: .member, reachedGoalToday: true)
                }
            )
        }
        let media = MediaRepositoryStub()
        let loader = PaceImageLoader(repository: media)
        loader.store(sampleImage(size: CGSize(width: 840, height: 400), colors: [UIColor(red: 0.42, green: 0.62, blue: 0.30, alpha: 1), UIColor(red: 0.80, green: 0.74, blue: 0.55, alpha: 1)]), for: MediaReference(bucket: .chatMedia, path: parkPath))
        loader.store(sampleImage(size: CGSize(width: 520, height: 340), colors: [UIColor(red: 0.20, green: 0.55, blue: 0.35, alpha: 1), UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1)]), for: MediaReference(bucket: .chatMedia, path: gifPath))
        let list = makeList(repository, social: social, media: media)
        await list.load()
        return (list, loader)
    }

    /// Einfarbiger Verlauf als Platzhalterfoto (nur für Snapshots).
    static func sampleImage(size: CGSize, colors: [UIColor]) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgColors = colors.map(\.cgColor) as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        return image.pngData() ?? Data()
    }

    // MARK: Privatchat

    @MainActor
    static func directSetup() async -> (ChatListViewModel, ChatRepositoryStub) {
        let conversation = ChatFixtures.direct(id: directConversationID, peer: mia, updatedAt: at(18, 5))
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.directConversations[mia.publicID] = conversation
            state.messages[directConversationID] = [
                ChatFixtures.message(in: directConversationID, from: mia, text: "Hast du Leon schon gesehen? Er ist jetzt auch bei Pace.", at: Fixtures.date(2026, 10, 15, 20, 31)),
                ChatFixtures.message(in: directConversationID, from: mia, kind: .profile, sharedProfile: leon, at: Fixtures.date(2026, 10, 15, 20, 31)),
                ChatFixtures.message(in: directConversationID, from: nil, isOwn: true, text: "Cool, ich schick ihm gleich eine Anfrage.", at: Fixtures.date(2026, 10, 15, 20, 40)),
                ChatFixtures.message(in: directConversationID, from: mia, text: "Laufen wir heute die große Runde?", at: at(18, 5)),
            ]
        }
        let list = makeList(repository)
        await list.load()
        return (list, repository)
    }

    @MainActor
    static func readOnlySetup() async -> ChatListViewModel {
        let conversation = ChatFixtures.direct(id: directConversationID, peer: mia, canSend: false, updatedAt: at(9, 0))
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[directConversationID] = [
                ChatFixtures.message(in: directConversationID, from: mia, text: "Bis morgen!", at: at(9, 0)),
            ]
        }
        let list = makeList(repository)
        await list.load()
        return list
    }
}
