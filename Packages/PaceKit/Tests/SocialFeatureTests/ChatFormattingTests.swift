import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

struct ChatFormattingTests {
    private let calendar = Fixtures.activityCalendar
    /// Freitag, 16. Oktober 2026, 18:00 in Berlin.
    private let now = Fixtures.date(2026, 10, 16, 18)

    // MARK: Zeitangaben

    @Test func listTimestampIsRelativeInTheAppLanguage() {
        PaceLocalization.$languageOverride.withValue(.german) {
            // Führende Null je nach Plattform-ICU („08:05“ bzw. „8:05“).
            #expect(ChatFormatting.listTimestamp(Fixtures.date(2026, 10, 16, 8, 5), now: now, calendar: calendar).hasSuffix("8:05"))
            #expect(ChatFormatting.listTimestamp(Fixtures.date(2026, 10, 15, 23), now: now, calendar: calendar) == "Gestern")
            #expect(ChatFormatting.listTimestamp(Fixtures.date(2026, 10, 12, 9), now: now, calendar: calendar) == "Montag")
            // Kurzes numerisches Datum („02.10.26“ bzw. „2.10.2026“ je nach Plattform-ICU).
            #expect(ChatFormatting.listTimestamp(Fixtures.date(2026, 10, 2, 9), now: now, calendar: calendar).contains("2.10."))
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(ChatFormatting.listTimestamp(Fixtures.date(2026, 10, 15, 23), now: now, calendar: calendar) == "Yesterday")
            #expect(ChatFormatting.listTimestamp(Fixtures.date(2026, 10, 12, 9), now: now, calendar: calendar) == "Monday")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ChatFormatting.listTimestamp(Fixtures.date(2026, 10, 15, 23), now: now, calendar: calendar) == "Вчера")
            #expect(ChatFormatting.listTimestamp(Fixtures.date(2026, 10, 12, 9), now: now, calendar: calendar) == "Понедельник")
        }
    }

    @Test func dayTitlesForSeparators() {
        let today = calendar.day(containing: now)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(ChatFormatting.dayTitle(today, today: today, calendar: calendar) == "Heute")
            #expect(ChatFormatting.dayTitle(Fixtures.day(2026, 10, 15), today: today, calendar: calendar) == "Gestern")
            #expect(ChatFormatting.dayTitle(Fixtures.day(2026, 10, 13), today: today, calendar: calendar) == "Dienstag")
            #expect(ChatFormatting.dayTitle(Fixtures.day(2026, 9, 3), today: today, calendar: calendar) == "3. September")
            #expect(ChatFormatting.dayTitle(Fixtures.day(2025, 12, 24), today: today, calendar: calendar) == "24. Dezember 2025")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(ChatFormatting.dayTitle(today, today: today, calendar: calendar) == "Today")
            #expect(ChatFormatting.dayTitle(Fixtures.day(2026, 9, 3), today: today, calendar: calendar) == "September 3")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ChatFormatting.dayTitle(today, today: today, calendar: calendar) == "Сегодня")
            #expect(ChatFormatting.dayTitle(Fixtures.day(2026, 9, 3), today: today, calendar: calendar) == "3 сентября")
        }
    }

    @Test func messageTimeFollowsTheLanguage() {
        let date = Fixtures.date(2026, 10, 16, 18, 42)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(ChatFormatting.time(date, calendar: calendar) == "18:42")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ChatFormatting.time(date, calendar: calendar) == "18:42")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            let english = ChatFormatting.time(date, calendar: calendar)
            #expect(english.hasPrefix("6:42"))
            #expect(english.hasSuffix("PM"))
        }
    }

    // MARK: Chatliste

    @Test func previewDescribesTheLastMessage() {
        let id = UUID()
        func group(_ preview: ChatMessagePreview?) -> ConversationSummary {
            ChatFixtures.group(id: id, last: preview)
        }
        func direct(_ preview: ChatMessagePreview?) -> ConversationSummary {
            ChatFixtures.direct(id: id, last: preview)
        }
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(ChatFormatting.preview(for: direct(ChatMessagePreview(kind: .text, text: "Noch eine\nRunde?", senderName: "Leon", isOwn: false, sentAt: now))) == "Noch eine Runde?")
            #expect(ChatFormatting.preview(for: group(ChatMessagePreview(kind: .text, text: "Wer läuft mit?", senderName: "Flavio", isOwn: false, sentAt: now))) == "Flavio: Wer läuft mit?")
            #expect(ChatFormatting.preview(for: group(ChatMessagePreview(kind: .image, text: nil, senderName: nil, isOwn: true, sentAt: now))) == "Du: Foto")
            #expect(ChatFormatting.preview(for: direct(ChatMessagePreview(kind: .gif, text: nil, senderName: "Mia", isOwn: false, sentAt: now))) == "GIF")
            #expect(ChatFormatting.preview(for: direct(ChatMessagePreview(kind: .profile, text: nil, senderName: "Mia", isOwn: false, sentAt: now))) == "Profil geteilt")
            #expect(ChatFormatting.preview(for: group(ChatMessagePreview(kind: .text, text: "Hallo", senderName: nil, isOwn: false, sentAt: now))) == "Gelöschtes Konto: Hallo")
            #expect(ChatFormatting.preview(for: direct(nil)) == "Noch keine Nachrichten")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(ChatFormatting.preview(for: group(ChatMessagePreview(kind: .image, text: nil, senderName: nil, isOwn: true, sentAt: now))) == "You: Photo")
            #expect(ChatFormatting.preview(for: group(nil)) == "No messages in the group yet")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ChatFormatting.preview(for: group(ChatMessagePreview(kind: .image, text: nil, senderName: nil, isOwn: true, sentAt: now))) == "Вы: Фото")
        }
    }

    @Test func groupTextsUseCorrectPlurals() {
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(ChatFormatting.members(1) == "1 Mitglied")
            #expect(ChatFormatting.members(12) == "12 Mitglieder")
            #expect(ChatFormatting.streakTitle(12) == "12 Tage Streak")
            #expect(ChatFormatting.streakTitle(0) == "Noch keine Streak")
            #expect(ChatFormatting.streakStatus(reached: 4, required: 4, complete: true) == "Flamme gesichert")
            #expect(ChatFormatting.streakStatus(reached: 2, required: 4, complete: false) == "Noch 2 Ziele heute")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(ChatFormatting.members(1) == "1 member")
            #expect(ChatFormatting.streakTitle(12) == "12-day streak")
            #expect(ChatFormatting.streakStatus(reached: 3, required: 4, complete: false) == "1 more goal today")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ChatFormatting.members(2) == "2 участника")
            #expect(ChatFormatting.members(5) == "5 участников")
            #expect(ChatFormatting.members(21) == "21 участник")
            #expect(ChatFormatting.streakStatus(reached: 0, required: 5, complete: false) == "Сегодня ещё 5 целей")
        }
    }

    // MARK: Verlauf

    @Test func timelineAddsDaySeparatorsAndGroupsConsecutiveMessages() {
        let conversationID = UUID()
        let messages = [
            ChatFixtures.message(in: conversationID, from: ChatFixtures.leon, text: "Gestern", at: Fixtures.date(2026, 10, 15, 20)),
            ChatFixtures.message(in: conversationID, from: ChatFixtures.leon, text: "Wer ist dabei?", at: Fixtures.date(2026, 10, 16, 18, 10)),
            ChatFixtures.message(in: conversationID, from: ChatFixtures.marie, kind: .image, mediaPath: "a/b.jpg", at: Fixtures.date(2026, 10, 16, 18, 11)),
            ChatFixtures.message(in: conversationID, from: ChatFixtures.marie, text: "Hier treffen wir uns", at: Fixtures.date(2026, 10, 16, 18, 12)),
            ChatFixtures.message(in: conversationID, from: nil, isOwn: true, text: "Ich komme mit.", at: Fixtures.date(2026, 10, 16, 18, 14)),
        ]
        let items = PaceLocalization.$languageOverride.withValue(.german) {
            ChatTimeline.build(
                messages: messages.reversed(),
                pending: [],
                kind: .group,
                blockedUserIDs: [],
                revealedMessageIDs: [],
                calendar: calendar,
                now: now
            )
        }

        let days = items.compactMap { item -> String? in
            if case .day(_, let title) = item { return title }
            return nil
        }
        #expect(days == ["Gestern", "Heute"])
        let entries = items.compactMap { item -> ChatTimelineEntry? in
            if case .entry(let entry) = item { return entry }
            return nil
        }
        #expect(entries.count == 5)
        // Chronologisch, trotz umgekehrter Eingabe.
        #expect(entries.map(\.sentAt) == messages.map(\.sentAt))
        // Name nur über der ersten Nachricht eines Blocks, Uhrzeit nur unter der letzten.
        #expect(entries.map(\.showsSender) == [true, true, true, false, false])
        #expect(entries.map(\.showsTime) == [true, true, false, true, true])
    }

    @Test func directChatsShowNoSenderNames() {
        let conversationID = UUID()
        let items = ChatTimeline.build(
            messages: [ChatFixtures.message(in: conversationID, from: ChatFixtures.mia, text: "Hi", at: now)],
            pending: [],
            kind: .direct,
            blockedUserIDs: [],
            revealedMessageIDs: [],
            calendar: calendar,
            now: now
        )
        guard case .entry(let entry)? = items.last else {
            Issue.record("Nachricht fehlt")
            return
        }
        #expect(!entry.showsSender)
        #expect(entry.showsTime)
    }

    @Test func pendingMessagesStayAtTheEnd() {
        let conversationID = UUID()
        let pending = PendingChatMessage(
            clientID: UUID(),
            kind: .text,
            text: "Unterwegs",
            localMedia: nil,
            mediaPath: nil,
            createdAt: now.addingTimeInterval(-86_400 * 2),
            status: .sending
        )
        let items = ChatTimeline.build(
            messages: [ChatFixtures.message(in: conversationID, from: ChatFixtures.mia, text: "Hi", at: now)],
            pending: [pending],
            kind: .direct,
            blockedUserIDs: [],
            revealedMessageIDs: [],
            calendar: calendar,
            now: now
        )

        #expect(items.last?.id == "pending-\(pending.clientID.uuidString)")
        #expect(items.filter { if case .day = $0 { true } else { false } }.count == 1)
    }
}
