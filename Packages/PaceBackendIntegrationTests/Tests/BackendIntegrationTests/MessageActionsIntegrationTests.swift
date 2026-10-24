import Foundation
import PaceBackend
import PaceCore
import Testing

/// Spitznamen, Nachrichtenaktionen, Sprachnachrichten und Gruppenkalender mit zwei (bzw. drei) echten Nutzern gegen
/// den lokalen Stack (Migrationen 20261023100000–100200), über dieselbe Schicht wie die App.
@Suite(.enabled(if: IntegrationEnvironment.configuration != nil, "PACE_SUPABASE_URL/PACE_SUPABASE_PUBLISHABLE_KEY fehlen"))
struct MessageActionsIntegrationTests {
    @Test func nicknamesArePrivateToTheirOwner() async throws {
        let anna = try await IntegrationUser.make("Anna", steps: 0)
        let ben = try await IntegrationUser.make("Ben", steps: 0)
        let outsider = try await IntegrationUser.make("Fremd", steps: 0)
        try await anna.befriend(ben)

        let named = try await anna.social.setFriendNickname(publicID: ben.publicID, nickname: "  Benni  ")
        #expect(named.nickname == "Benni")
        #expect(named.displayName == "Ben")
        #expect(try await anna.social.friends().first?.profile.shownName == "Benni")
        #expect(try await anna.social.publicProfile(ben.publicID, date: IntegrationUser.today).profile.nickname == "Benni")
        let ranking = try await anna.social.friendRanking(period: .daily, date: IntegrationUser.today)
        #expect(ranking.first { $0.publicUserID == ben.publicID }?.shownName == "Benni")

        // Ben sieht Annas Spitznamen nie, vergibt aber seinen eigenen.
        #expect(try await ben.social.friends().first?.profile.nickname == nil)
        _ = try await ben.social.setFriendNickname(publicID: anna.publicID, nickname: "Anni")
        let direct = try await anna.chat.openDirectConversation(with: ben.publicID)
        _ = try await ben.chat.send(.text("Hallo Anna"), to: direct.id)
        let annasView = try #require(try await anna.chat.conversations().first { $0.id == direct.id })
        #expect(annasView.shownTitle == "Benni")
        #expect(annasView.peer?.nickname == "Benni")
        let message = try #require(try await anna.chat.messages(in: direct.id, before: nil, limit: 40).first)
        #expect(message.sender?.shownName == "Benni")
        #expect(try await ben.chat.conversations().first { $0.id == direct.id }?.peer?.nickname == "Anni")

        // Nur für Freunde; leere Eingabe entfernt.
        await #expect(throws: SocialError.notFound) {
            try await anna.social.setFriendNickname(publicID: outsider.publicID, nickname: "Niemand")
        }
        let cleared = try await anna.social.setFriendNickname(publicID: ben.publicID, nickname: "")
        #expect(cleared.nickname == nil)
        #expect(try await anna.social.friends().first?.profile.shownName == "Ben")

        // Endet die Freundschaft, ist auch Bens Spitzname für Anna weg.
        try await anna.social.removeFriend(ben.publicID)
        try await anna.befriend(ben)
        #expect(try await ben.social.friends().first?.profile.nickname == nil)
    }

    @Test func repliesEditsFavoritesAndPins() async throws {
        let anna = try await IntegrationUser.make("Anna", steps: 0)
        let ben = try await IntegrationUser.make("Ben", steps: 0)
        try await anna.befriend(ben)
        let direct = try await anna.chat.openDirectConversation(with: ben.publicID)
        #expect(direct.canPin)

        // Antworten mit echter Verknüpfung.
        let question = try await anna.chat.send(.text("Treffen um sieben?"), to: direct.id)
        let answer = try await ben.chat.send(.text("Ja, gern!", replyTo: question.id), to: direct.id)
        #expect(answer.replyPreview?.id == question.id)
        #expect(answer.replyPreview?.text == "Treffen um sieben?")
        #expect(answer.replyPreview?.sender?.publicID == anna.publicID)
        let annasHistory = try await anna.chat.messages(in: direct.id, before: nil, limit: 40)
        #expect(annasHistory.last?.replyPreview?.id == question.id)

        // Bearbeiten: nur die eigene Textnachricht; die andere Person sieht den neuen Text mit „Bearbeitet“.
        let edited = try await anna.chat.editMessage(question.id, text: "Treffen um halb acht?")
        #expect(edited.isEdited)
        let bensHistory = try await ben.chat.messages(in: direct.id, before: nil, limit: 40)
        let bensCopy = try #require(bensHistory.first { $0.id == question.id })
        #expect(bensCopy.text == "Treffen um halb acht?")
        #expect(bensCopy.isEdited)
        #expect(bensHistory.first { $0.id == answer.id }?.replyPreview?.text == "Treffen um halb acht?")
        await #expect(throws: SocialError.notFound) {
            try await ben.chat.editMessage(question.id, text: "Gehackt")
        }

        // Favoriten sind privat.
        try await ben.chat.setFavorite(question.id, isFavorite: true)
        #expect(try await ben.chat.favorites(conversationID: direct.id).map(\.id) == [question.id])
        #expect(try await anna.chat.favorites(conversationID: direct.id).isEmpty)
        #expect(try await ben.chat.messages(in: direct.id, before: nil, limit: 40).first { $0.id == question.id }?.isFavorite == true)
        #expect(try await anna.chat.messages(in: direct.id, before: nil, limit: 40).first { $0.id == question.id }?.isFavorite == false)
        try await ben.chat.setFavorite(question.id, isFavorite: false)
        #expect(try await ben.chat.favorites(conversationID: direct.id).isEmpty)

        // Pins im Privatchat: beide dürfen, alle sehen sie.
        #expect(try await anna.chat.setPinned(answer.id, isPinned: true).map(\.id) == [answer.id])
        let bensPins = try await ben.chat.pins(conversationID: direct.id)
        #expect(bensPins.map(\.id) == [answer.id])
        #expect(bensPins.first?.pinnedBy?.publicID == anna.publicID)
        #expect(try await ben.chat.setPinned(answer.id, isPinned: false).isEmpty)

        // Gruppenchat: nur der Owner pinnt.
        let group = try await anna.social.createGroup(
            GroupDraft(name: "Pinrunde", kind: .friends, privacy: .inviteOnly, inviteePublicIDs: [ben.publicID]),
            timeZone: "Europe/Berlin"
        )
        let invitation = try #require(try await ben.social.groupInvitations().first { $0.groupID == group.id })
        _ = try await ben.social.respondToInvitation(invitation.id, accept: true)
        let groupChat = try await ben.chat.groupConversation(for: group.id)
        #expect(!groupChat.canPin)
        #expect(try await anna.chat.groupConversation(for: group.id).canPin)
        let notice = try await ben.chat.send(.text("Treffpunkt: Brunnen"), to: groupChat.id)
        await #expect(throws: SocialError.notAllowed) {
            try await ben.chat.setPinned(notice.id, isPinned: true)
        }
        #expect(try await anna.chat.setPinned(notice.id, isPinned: true).count == 1)
        #expect(try await ben.chat.messages(in: groupChat.id, before: nil, limit: 40).first { $0.id == notice.id }?.isPinned == true)
    }

    @Test func voiceMessagesAreStoredPrivately() async throws {
        let anna = try await IntegrationUser.make("Anna", steps: 0)
        let ben = try await IntegrationUser.make("Ben", steps: 0)
        let outsider = try await IntegrationUser.make("Fremd", steps: 0)
        try await anna.befriend(ben)
        let direct = try await anna.chat.openDirectConversation(with: ben.publicID)

        let audio = Data((0..<2_048).map { UInt8($0 % 251) })
        let reference = try await anna.media.upload(audio, contentType: MediaRules.voiceContentType, to: .chat(conversationID: direct.id))
        #expect(reference.bucket == .chatMedia)
        #expect(reference.path.hasSuffix(".m4a"))

        let voice = try await anna.chat.send(.voice(mediaPath: reference.path, duration: .milliseconds(3_200)), to: direct.id)
        #expect(voice.kind == .voice)
        #expect(voice.mediaDuration == .milliseconds(3_200))
        #expect(voice.media == reference)

        // Nur Teilnehmer laden die Datei.
        #expect(try await ben.media.data(for: reference) == audio)
        await #expect(throws: (any Error).self) {
            try await outsider.media.data(for: reference)
        }
        let bensView = try #require(try await ben.chat.conversations().first { $0.id == direct.id })
        #expect(bensView.lastMessage?.kind == .voice)
        #expect(bensView.lastMessage?.mediaDuration == .milliseconds(3_200))

        // Ohne Dauer bzw. mit fremder Datei lehnt der Server ab.
        await #expect(throws: SocialError.invalidInput) {
            try await ben.chat.send(.voice(mediaPath: reference.path, duration: .seconds(2)), to: direct.id)
        }
        // Löschen entfernt Nachricht und Datei.
        try await anna.chat.deleteMessage(voice.id)
        await #expect(throws: (any Error).self) {
            try await ben.media.data(for: reference)
        }
    }

    @Test func groupCalendarMatchesTheGroupDays() async throws {
        let anna = try await IntegrationUser.make("Anna", steps: 9_000)
        let ben = try await IntegrationUser.make("Ben", steps: 4_000)
        let outsider = try await IntegrationUser.make("Fremd", steps: 0)
        try await anna.befriend(ben)
        _ = try await anna.social.setFriendNickname(publicID: ben.publicID, nickname: "Benni")
        let group = try await anna.social.createGroup(
            GroupDraft(name: "Kalenderrunde", kind: .friends, dailyGoal: 8_000, privacy: .inviteOnly, inviteePublicIDs: [ben.publicID]),
            timeZone: "Europe/Berlin"
        )
        let invitation = try #require(try await ben.social.groupInvitations().first { $0.groupID == group.id })
        _ = try await ben.social.respondToInvitation(invitation.id, accept: true)

        let berlin = ActivityCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let grid = GroupCalendarRules.monthGrid(containing: IntegrationUser.today, calendar: berlin)
        let calendar = try await anna.social.groupCalendar(groupID: group.id, from: grid.lowerBound, to: grid.upperBound)

        // Gegründet heute: genau ein Tag, frühere Tage „vor der Gruppe“, spätere „Zukunft“.
        #expect(calendar.groupToday == IntegrationUser.today)
        #expect(calendar.firstGroupDay == IntegrationUser.today)
        let today = try #require(calendar.days.first)
        #expect(calendar.days.count == 1)
        #expect(today.isToday)
        #expect(today.memberCount == 2)
        #expect(today.requiredCount == GroupStreakRules.requiredMembers(forMemberCount: 2))
        #expect(today.reachedCount == 1)
        #expect(today.secured)
        #expect(today.dailyGoal == 8_000)
        #expect(today.ranking.map(\.profile?.publicID) == [anna.publicID, ben.publicID])
        #expect(today.ranking.map(\.competitionSteps) == [9_000, 4_000])
        #expect(today.ranking.map(\.reached) == [true, false])
        #expect(today.ranking.last?.profile?.shownName == "Benni")
        #expect(today.currentUserEntry?.profile?.publicID == anna.publicID)
        #expect(calendar.state(of: berlin.adding(-1, to: IntegrationUser.today)) == .beforeGroup)
        #expect(calendar.state(of: berlin.adding(1, to: IntegrationUser.today)) == .future)

        let groupDay = try #require(try await anna.social.groupDays(group.id, count: 7).first)
        #expect(groupDay.memberCount == today.memberCount)
        #expect(groupDay.requiredCount == today.requiredCount)
        #expect(groupDay.reachedCount == today.reachedCount)
        #expect(groupDay.reached == today.secured)

        // Ben sieht Annas Spitznamen nicht; Fremde bekommen keinen Kalender.
        let bensCalendar = try await ben.social.groupCalendar(groupID: group.id, from: grid.lowerBound, to: grid.upperBound)
        #expect(bensCalendar.days.first?.ranking.allSatisfy { $0.profile?.nickname == nil } == true)
        await #expect(throws: SocialError.notFound) {
            try await outsider.social.groupCalendar(groupID: group.id, from: grid.lowerBound, to: grid.upperBound)
        }
    }
}
