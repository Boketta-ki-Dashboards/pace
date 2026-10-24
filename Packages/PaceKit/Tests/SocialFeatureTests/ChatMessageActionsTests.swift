import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

/// Antworten, Bearbeiten, Favoriten, Anpinnen, Springen und Sprachnachrichten im einzelnen Chat.
@MainActor
struct ChatMessageActionsTests {
    private let base = Fixtures.date(2026, 10, 16, 18)

    private func makeChat(
        _ repository: ChatRepositoryStub,
        conversation: ConversationSummary,
        media: MediaRepositoryStub? = nil
    ) async -> (ChatViewModel, ChatListViewModel) {
        let ticker = ManualTicker()
        let list = ChatListViewModel(
            repository: repository,
            media: media,
            calendar: Fixtures.activityCalendar,
            now: { [base] in base },
            sleep: { try await ticker.sleep($0) }
        )
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()
        return (chat, list)
    }

    private func message(_ text: String, in conversation: ConversationSummary, own: Bool = false, minutesAgo: Double = 1) -> ChatMessage {
        ChatFixtures.message(
            in: conversation.id,
            from: own ? nil : ChatFixtures.mia,
            isOwn: own,
            text: text,
            at: base.addingTimeInterval(-minutesAgo * 60)
        )
    }

    // MARK: Menü

    @Test func menuOffersOnlyWhatIsPossible() async {
        let conversation = ChatFixtures.direct(canPin: true)
        let own = message("Bin da", in: conversation, own: true)
        let theirs = message("Gehen wir heute spazieren?", in: conversation)
        let photo = ChatFixtures.message(in: conversation.id, from: ChatFixtures.mia, kind: .image, mediaPath: "c/p.jpg", at: base)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [theirs, own, photo]
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)

        #expect(chat.actions(for: own) == [.reply, .copy, .edit, .favorite, .pin])
        #expect(chat.actions(for: theirs) == [.reply, .copy, .favorite, .pin])
        // Bild ohne Text: nichts zu kopieren, nichts zu bearbeiten.
        #expect(chat.actions(for: photo) == [.reply, .favorite, .pin])

        // Ohne Schreibrecht: keine Antwort, kein Bearbeiten, kein Anpinnen – Favorit bleibt (privat).
        let readOnly = ChatFixtures.direct(id: conversation.id, canSend: false, canPin: true)
        repository.state.withLock { $0.conversations = [readOnly] }
        chat.updateSummary(from: [readOnly])
        #expect(chat.actions(for: own) == [.copy, .favorite])
    }

    @Test func groupMembersWithoutPinRightSeeNoPinAction() async {
        let conversation = ChatFixtures.group(canPin: false)
        let theirs = message("Treffen Samstag 14 Uhr am Bahnhof.", in: conversation)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [theirs]
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)

        #expect(!chat.canPin)
        #expect(!chat.actions(for: theirs).contains(.pin))
    }

    // MARK: Antworten

    @Test func replyIsLinkedAndShownBeforeTheServerAnswers() async throws {
        let conversation = ChatFixtures.direct()
        let original = message("Gehen wir heute spazieren?", in: conversation)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [original]
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)

        chat.startReply(to: original)
        #expect(chat.replyingTo == original)
        #expect(chat.replyAuthor(of: original) == "Mia")

        repository.gate.close("send")
        chat.draftText = "Klar, um 18 Uhr!"
        let sending = Task { await chat.sendText() }
        try await waitUntil { repository.gate.waitingCount("send") == 1 }
        // Vorschau über der Eingabe ist weg, die ausstehende Nachricht trägt den Verweis schon.
        #expect(chat.replyingTo == nil)
        #expect(chat.pending.first?.replyTo?.id == original.id)
        repository.gate.open("send")
        await sending.value

        let draft = try #require(repository.state.withLock { $0.sentDrafts.last?.0 })
        #expect(draft.replyToID == original.id)
        let saved = try #require(chat.messages.first { $0.clientID == draft.clientID })
        #expect(saved.replyPreview?.id == original.id)
        #expect(saved.replyPreview?.text == "Gehen wir heute spazieren?")
        #expect(chat.pending.isEmpty)
    }

    /// Antwort auf eine eigene, ältere (nicht geladene) Nachricht: Der Verweis zeigt „Du“, nicht den eigenen Namen.
    @Test func replyToOwnUnloadedMessageShowsYou() async {
        let me = SocialProfile(publicID: UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000099")!, username: "niklas", displayName: "Niklas")
        let conversation = ChatFixtures.direct()
        let reply = ChatFixtures.message(
            in: conversation.id, from: ChatFixtures.mia, text: "Ja, gern!", at: base,
            replyPreview: ChatReplyPreview(id: UUID(), sender: me, kind: .text, text: "Laufen wir morgen?", mediaDuration: nil, isDeleted: false)
        )
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [reply]
        }
        let list = ChatListViewModel(
            repository: repository, media: nil, calendar: Fixtures.activityCalendar, now: { [base] in base },
            sleep: { try await ManualTicker().sleep($0) }, ownPublicID: { me.publicID }
        )
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()
        let preview = try? #require(chat.messages.first?.replyPreview)

        let author = PaceLocalization.$languageOverride.withValue(.german) { preview.map { chat.replyAuthor(of: $0) } }
        #expect(author == "Du")
        // Antwort auf Mia bleibt „Mia“.
        let other = ChatReplyPreview(id: UUID(), sender: ChatFixtures.mia, kind: .text, text: "Hi", mediaDuration: nil, isDeleted: false)
        #expect(chat.replyAuthor(of: other) == "Mia")
    }

    @Test func replyCanBeCancelled() async {
        let conversation = ChatFixtures.direct()
        let original = message("Hi", in: conversation)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [original]
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)

        chat.startReply(to: original)
        chat.cancelReply()
        chat.draftText = "Ohne Antwort"
        await chat.sendText()

        #expect(repository.state.withLock { $0.sentDrafts.last?.0.replyToID } == nil)
    }

    @Test func jumpingLoadsOlderPagesAndReportsMissingMessages() async {
        let conversation = ChatFixtures.direct()
        // 45 Nachrichten: Die erste liegt außerhalb der ersten Seite (40).
        let history = (0..<45).map { index in
            message("Nachricht \(index)", in: conversation, minutesAgo: Double(45 - index))
        }
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = history
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)
        #expect(!chat.messages.contains { $0.id == history[0].id })

        await chat.jump(to: history[0].id)
        #expect(chat.jumpRequest?.messageID == history[0].id)
        #expect(chat.messages.contains { $0.id == history[0].id })

        let previous = chat.jumpRequest
        await chat.jump(to: UUID())
        #expect(chat.jumpRequest == previous)
        #expect(chat.notice == ChatNotice(text: ChatTexts.messageUnavailable, isError: false))
    }

    // MARK: Bearbeiten

    @Test func editingReplacesTheTextAndMarksTheMessage() async throws {
        let conversation = ChatFixtures.direct()
        let own = message("Treffen um 14 Uhr", in: conversation, own: true)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [own]
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)
        chat.draftText = "Halber Entwurf"

        chat.startEditing(own)
        #expect(chat.editingMessage == own)
        #expect(chat.draftText == "Treffen um 14 Uhr")

        chat.draftText = "Treffen um 15 Uhr"
        await chat.sendText()

        let edited = try #require(chat.messages.first { $0.id == own.id })
        #expect(edited.text == "Treffen um 15 Uhr")
        #expect(edited.isEdited)
        #expect(chat.messages.count == 1) // nichts doppelt angelegt
        #expect(repository.state.withLock { $0.sentDrafts }.isEmpty)
        #expect(chat.editingMessage == nil)
        // Der vorherige Entwurf ist wieder da.
        #expect(chat.draftText == "Halber Entwurf")
    }

    @Test func editingCanBeCancelledAndOnlyOwnTextsAreEditable() async {
        let conversation = ChatFixtures.direct()
        let own = message("Mein Text", in: conversation, own: true)
        let theirs = message("Fremder Text", in: conversation)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [theirs, own]
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)

        chat.startEditing(theirs)
        #expect(chat.editingMessage == nil)

        chat.draftText = "Entwurf"
        chat.startEditing(own)
        chat.draftText = "Geändert, aber verworfen"
        chat.cancelEditing()
        #expect(chat.editingMessage == nil)
        #expect(chat.draftText == "Entwurf")
        #expect(chat.messages.first { $0.id == own.id }?.text == "Mein Text")
    }

    @Test func failedEditKeepsTheTextInTheField() async {
        let conversation = ChatFixtures.direct()
        let own = message("Alt", in: conversation, own: true)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [own]
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)
        chat.startEditing(own)
        chat.draftText = "Neu"
        repository.state.withLock { $0.actionError = .network }

        await chat.sendText()

        #expect(chat.editingMessage == own)
        #expect(chat.draftText == "Neu")
        #expect(chat.notice?.isError == true)
        #expect(chat.messages.first?.text == "Alt")
    }

    // MARK: Favoriten

    @Test func favoritesArePrivateTogglesWithAList() async {
        let conversation = ChatFixtures.direct()
        let address = message("Treffpunkt: Hauptstraße 5", in: conversation, minutesAgo: 2)
        let other = message("Bis gleich", in: conversation)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [address, other]
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)
        await chat.loadFavorites()
        #expect(chat.favorites == .loaded([]))

        await chat.toggleFavorite(address)
        #expect(chat.messages.first { $0.id == address.id }?.isFavorite == true)
        #expect(repository.state.withLock { $0.favoriteIDs } == [address.id])
        guard case .loaded(let list) = chat.favorites else {
            Issue.record("Favoriten nicht geladen")
            return
        }
        #expect(list.map(\.id) == [address.id])
        #expect(chat.actions(for: chat.messages.first { $0.id == address.id }!).contains(.unfavorite))

        await chat.toggleFavorite(chat.messages.first { $0.id == address.id }!)
        #expect(chat.messages.first { $0.id == address.id }?.isFavorite == false)
        #expect(chat.favorites == .loaded([]))
    }

    @Test func failedFavoriteIsRolledBack() async {
        let conversation = ChatFixtures.direct()
        let text = message("Wichtig", in: conversation)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [text]
            state.actionError = .network
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)

        await chat.toggleFavorite(text)

        #expect(chat.messages.first?.isFavorite == false)
        #expect(chat.notice?.isError == true)
    }

    // MARK: Anpinnen

    @Test func pinningShowsTheBannerAndJumps() async {
        let conversation = ChatFixtures.group(canPin: true)
        let meeting = message("Treffen Samstag 14 Uhr am Bahnhof.", in: conversation, minutesAgo: 3)
        let route = message("Route: 8 km am Fluss", in: conversation, minutesAgo: 2)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [meeting, route]
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)
        #expect(chat.shownPin == nil)

        await chat.togglePin(meeting)
        await chat.togglePin(route)
        #expect(chat.pins.map(\.id) == [route.id, meeting.id])
        #expect(chat.messages.filter(\.isPinned).count == 2)
        #expect(chat.shownPin?.id == route.id)

        // Antippen springt zum gezeigten Pin und zeigt danach den nächsten.
        await chat.openShownPin()
        #expect(chat.jumpRequest?.messageID == route.id)
        #expect(chat.shownPin?.id == meeting.id)

        await chat.togglePin(chat.messages.first { $0.id == route.id }!)
        #expect(chat.pins.map(\.id) == [meeting.id])
        #expect(chat.messages.first { $0.id == route.id }?.isPinned == false)
    }

    @Test func pinLimitIsExplained() async {
        let conversation = ChatFixtures.direct(canPin: true)
        let texts = (0..<6).map { message("Nachricht \($0)", in: conversation, minutesAgo: Double(6 - $0)) }
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = texts
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)

        for text in texts {
            await chat.togglePin(text)
        }

        #expect(chat.pins.count == ChatRules.maximumPinnedMessages)
        #expect(chat.notice == ChatNotice(text: ChatTexts.pinLimitReached, isError: true))
    }

    @Test func pinsOfOthersArriveByRealtime() async throws {
        let conversation = ChatFixtures.group(canPin: false)
        let meeting = message("Treffen Samstag", in: conversation)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [meeting]
        }
        let (chat, _) = await makeChat(repository, conversation: conversation)
        let observing = Task { await chat.observe() }
        try await waitUntil { repository.subscriberCount(conversationID: conversation.id) >= 1 }

        // Der Owner pinnt auf einem anderen Gerät.
        repository.state.withLock { state in
            state.pins[conversation.id] = [ChatPin(message: meeting.withPinned(true), pinnedBy: ChatFixtures.leon, pinnedAt: base)]
        }
        repository.sendActivity(.pinsChanged, in: conversation.id)
        try await waitUntil { chat.shownPin?.id == meeting.id }
        #expect(chat.messages.first?.isPinned == true)

        observing.cancel()
        await observing.value
    }

    // MARK: Sprachnachrichten

    @Test func voiceMessageIsUploadedOnlyWhenSentAndKeepsItsDuration() async throws {
        let conversation = ChatFixtures.direct()
        let original = message("Wie war der Lauf?", in: conversation)
        let media = MediaRepositoryStub()
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [original]
        }
        let (chat, _) = await makeChat(repository, conversation: conversation, media: media)
        chat.startReply(to: original)

        await chat.sendVoice(Data(repeating: 1, count: 2_048), duration: .seconds(18))

        #expect(media.state.withLock { $0.uploads } == [.chat(conversationID: conversation.id)])
        let draft = try #require(repository.state.withLock { $0.sentDrafts.last?.0 })
        #expect(draft.kind == .voice)
        #expect(draft.mediaDuration == .seconds(18))
        #expect(draft.replyToID == original.id)
        #expect(draft.mediaPath?.hasSuffix(".m4a") == true)
        let saved = try #require(chat.messages.first { $0.clientID == draft.clientID })
        #expect(saved.kind == .voice)
        #expect(saved.mediaDuration == .seconds(18))
        // Die gerade aufgenommenen Daten stehen ohne zweiten Download für die Wiedergabe bereit.
        #expect(saved.media.flatMap { chat.uploadedData(for: $0) } == Data(repeating: 1, count: 2_048))
    }

    @Test func invalidVoiceMessagesAreNotSent() async {
        let conversation = ChatFixtures.direct()
        let media = MediaRepositoryStub()
        let repository = ChatRepositoryStub { $0.conversations = [conversation] }
        let (chat, _) = await makeChat(repository, conversation: conversation, media: media)

        await chat.sendVoice(Data(repeating: 1, count: 100), duration: .seconds(301))
        #expect(chat.notice == ChatNotice(text: ChatTexts.voiceInvalidDuration, isError: true))
        await chat.sendVoice(Data(), duration: .seconds(3))
        #expect(chat.notice == ChatNotice(text: ChatTexts.voiceRecordingFailed, isError: true))

        #expect(media.state.withLock { $0.uploads }.isEmpty)
        #expect(chat.pending.isEmpty)
    }

    @Test func discardingAFailedVoiceMessageRemovesTheUploadedFile() async throws {
        let conversation = ChatFixtures.direct()
        let media = MediaRepositoryStub()
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.sendError = .network
        }
        let (chat, _) = await makeChat(repository, conversation: conversation, media: media)

        await chat.sendVoice(Data(repeating: 2, count: 512), duration: .seconds(4))
        let failed = try #require(chat.pending.first)
        #expect(failed.isFailed)
        let path = try #require(failed.mediaPath)

        chat.discard(failed.clientID)

        #expect(chat.pending.isEmpty)
        try await waitUntil { !media.state.withLock { $0.deleted }.isEmpty }
        #expect(media.state.withLock { $0.deleted } == [MediaReference(bucket: .chatMedia, path: path)])
    }
}

/// Verborgene Pins (Nachricht gelöscht oder Absender blockiert) lassen sich lösen, obwohl man sie nicht im Verlauf sieht.
@MainActor
struct ChatHiddenPinTests {
    @Test func hiddenPinCanBeUnpinned() async throws {
        let base = Fixtures.date(2026, 10, 16, 18)
        let conversation = ChatFixtures.group(canPin: true)
        let placeholder = ChatFixtures.message(in: conversation.id, from: nil, at: base.addingTimeInterval(-600))
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [placeholder]
            state.pins[conversation.id] = [ChatPin(message: placeholder, pinnedBy: nil, pinnedAt: base, isHidden: true)]
        }
        let list = ChatListViewModel(repository: repository, media: nil, calendar: Fixtures.activityCalendar, now: { base })
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()
        let pin = try #require(chat.shownPin)
        #expect(pin.isHidden)

        await chat.unpin(pin)

        #expect(chat.pins.isEmpty)
        #expect(repository.state.withLock { $0.pins[conversation.id] }?.isEmpty == true)
    }
}

/// Befunde der unabhängigen Prüfung: Verlauf ohne Lücken, Bearbeitungen älterer Nachrichten, sicheres Verwerfen,
/// gesperrtes Abbrechen beim Speichern, verborgene Pins, ehrliche Fehler beim Sprung.
@MainActor
struct ChatReviewFixTests {
    private let base = Fixtures.date(2026, 10, 16, 18)

    private func makeChat(
        _ repository: ChatRepositoryStub,
        conversation: ConversationSummary,
        media: MediaRepositoryStub? = nil
    ) async -> ChatViewModel {
        let ticker = ManualTicker()
        let list = ChatListViewModel(
            repository: repository,
            media: media,
            calendar: Fixtures.activityCalendar,
            now: { [base] in base },
            sleep: { try await ticker.sleep($0) }
        )
        await list.load()
        let chat = list.chat(for: ChatTarget(conversation))
        await chat.load()
        return chat
    }

    private func history(_ count: Int, in conversation: ConversationSummary, endingMinutesAgo offset: Double = 0) -> [ChatMessage] {
        (0..<count).map { index in
            ChatFixtures.message(
                in: conversation.id,
                from: ChatFixtures.mia,
                text: "Nachricht \(index)",
                at: base.addingTimeInterval(Double(index - count) * 60 - offset * 60)
            )
        }
    }

    @Test func manyNewMessagesLeaveNoGap() async {
        let conversation = ChatFixtures.direct()
        let old = history(10, in: conversation, endingMinutesAgo: 100)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = old
        }
        let chat = await makeChat(repository, conversation: conversation)
        #expect(chat.messages.count == 10)

        // Während der Chat zu war: 50 neue Nachrichten.
        let new = (0..<50).map { index in
            ChatFixtures.message(in: conversation.id, from: ChatFixtures.mia, text: "Neu \(index)", at: base.addingTimeInterval(Double(index - 50) * 10))
        }
        for message in new { repository.store(message) }
        await chat.refresh()

        // Keine Lücke: Der alte Stand wurde verworfen, ältere lassen sich nachladen.
        #expect(chat.messages.map(\.id) == new.suffix(40).map(\.id))
        #expect(chat.hasOlderMessages)
        await chat.loadOlder()
        #expect(chat.messages.count == 60)
        #expect(Set(chat.messages.map(\.id)) == Set((old + new).map(\.id)))
    }

    @Test func editsOfOlderLoadedMessagesAreRefreshed() async throws {
        let conversation = ChatFixtures.direct()
        let messages = history(45, in: conversation)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = messages
        }
        let chat = await makeChat(repository, conversation: conversation)
        await chat.loadOlder()
        #expect(chat.messages.count == 45)

        // Jemand bearbeitet die älteste Nachricht (außerhalb der neuesten Seite).
        let oldest = messages[0]
        repository.state.withLock { state in
            state.messages[conversation.id]?[0] = ChatFixtures.message(
                id: oldest.id, in: conversation.id, from: ChatFixtures.mia, text: "Geändert", at: oldest.sentAt, editedAt: base
            )
        }
        await chat.refresh()
        await chat.refreshOlderLoadedMessages()

        let refreshed = try #require(chat.messages.first { $0.id == oldest.id })
        #expect(refreshed.text == "Geändert")
        #expect(refreshed.isEdited)
        #expect(chat.messages.count == 45)
    }

    @Test func discardKeepsTheFileWhenTheMessageArrivedAfterAll() async throws {
        let conversation = ChatFixtures.direct()
        let media = MediaRepositoryStub()
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.sendError = .network
        }
        let chat = await makeChat(repository, conversation: conversation, media: media)
        await chat.sendVoice(Data(repeating: 3, count: 256), duration: .seconds(5))
        let failed = try #require(chat.pending.first)
        let path = try #require(failed.mediaPath)

        // Die Antwort ging verloren – gespeichert hat der Server die Nachricht trotzdem.
        repository.store(ChatFixtures.message(
            in: conversation.id, from: nil, isOwn: true, kind: .voice, mediaPath: path, clientID: failed.clientID,
            at: base, mediaDuration: .seconds(5)
        ))
        repository.state.withLock { $0.sendError = nil }

        chat.discard(failed.clientID)

        try await waitUntil { chat.messages.contains { $0.clientID == failed.clientID } }
        #expect(media.state.withLock { $0.deleted }.isEmpty)
    }

    @Test func cancellingIsLockedWhileAnEditIsSaved() async throws {
        let conversation = ChatFixtures.direct()
        let own = ChatFixtures.message(in: conversation.id, from: nil, isOwn: true, text: "Alt", at: base)
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = [own]
        }
        let chat = await makeChat(repository, conversation: conversation)
        chat.draftText = "Mein Entwurf"
        chat.startEditing(own)
        chat.draftText = "Neu"
        repository.gate.close("editMessage")
        let saving = Task { await chat.sendText() }
        try await waitUntil { repository.gate.waitingCount("editMessage") == 1 }

        #expect(chat.isSavingEdit)
        chat.cancelEditing()
        #expect(chat.editingMessage == own) // gesperrt
        repository.gate.open("editMessage")
        await saving.value

        #expect(chat.editingMessage == nil)
        #expect(chat.draftText == "Mein Entwurf")
        #expect(chat.messages.first?.text == "Neu")
    }

    @Test func tappingAHiddenPinDoesNotLoadTheWholeHistory() async throws {
        let conversation = ChatFixtures.group(canPin: true)
        let messages = history(45, in: conversation)
        let placeholder = ChatFixtures.message(in: conversation.id, from: nil, at: base.addingTimeInterval(-90_000))
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = messages
            state.pins[conversation.id] = [ChatPin(message: placeholder, pinnedBy: nil, pinnedAt: base, isHidden: true)]
        }
        let chat = await makeChat(repository, conversation: conversation)
        let calls = repository.callCount("messages")

        await chat.openShownPin()

        #expect(repository.callCount("messages") == calls)
        #expect(chat.notice == ChatNotice(text: ChatTexts.messageUnavailable, isError: false))
    }

    @Test func jumpNamesNetworkErrorsHonestly() async {
        let conversation = ChatFixtures.direct()
        let repository = ChatRepositoryStub { state in
            state.conversations = [conversation]
            state.messages[conversation.id] = history(45, in: conversation)
        }
        let chat = await makeChat(repository, conversation: conversation)
        repository.state.withLock { $0.error = .network }

        await chat.jump(to: UUID())

        #expect(chat.notice == ChatNotice(text: ChatTexts.olderFailed, isError: true))
    }
}
