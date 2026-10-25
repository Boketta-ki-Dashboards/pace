import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

/// Kombinierte Gruppenkarte (Auftrag 5, B7): nur Werte der vorhandenen Gruppe, ⌈n/3⌉-Regel vom Server, Mehrzahl in
/// allen drei Sprachen.
struct GroupDayProgressTests {
    @Test func cardTextsFollowTheThirdRule() {
        // 12 Mitglieder → 4 nötig (⌈12/3⌉), 3 erreicht → noch 1.
        let open = GroupDayProgress(group: SocialRepositoryStub.group(memberCount: 12, currentStreak: 12, reached: 3))
        #expect(open.required == 4)
        #expect(open.missing == 1)
        #expect(open.progress == 0.25)
        #expect(open.thresholdFraction.map { abs($0 - 4.0 / 12.0) < 0.0001 } == true)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(open.reachedText == "3 von 12 Mitgliedern haben das Tagesziel erreicht")
            #expect(open.hint == "Noch 1 Mitglied bis zur heutigen Gruppenflamme")
            #expect(open.streakText == "12")
        }
        let secured = GroupDayProgress(group: SocialRepositoryStub.group(memberCount: 12, currentStreak: 12, reached: 5))
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(secured.hint == "Gruppenflamme für heute gesichert")
        }
        #expect(secured.isSecured)

        let two = GroupDayProgress(reached: 0, members: 6, required: 2, streak: 0, isSecured: false)
        #expect(!two.isFlameLit)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(two.hint == "Noch 2 Mitglieder bis zur heutigen Gruppenflamme")
        }
        let one = GroupDayProgress(reached: 1, members: 3, required: 1, streak: 2, isSecured: true)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(one.reachedText == "1 von 3 Mitgliedern hat das Tagesziel erreicht")
        }
    }

    @Test func englishAndRussianPlurals() {
        let progress = GroupDayProgress(reached: 1, members: 21, required: 7, streak: 5, isSecured: false)
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(progress.reachedText == "1 of 21 members reached the daily goal")
            #expect(progress.hint == "6 more members for today's group flame")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(progress.reachedText == "1 из 21 участника выполнил дневную цель")
            #expect(progress.hint == "Ещё 6 участников до сегодняшнего огня группы")
            let three = GroupDayProgress(reached: 3, members: 12, required: 4, streak: 1, isSecured: false)
            #expect(three.reachedText == "3 из 12 участников выполнили дневную цель")
            #expect(three.hint == "Ещё 1 участник до сегодняшнего огня группы")
            let few = GroupDayProgress(reached: 0, members: 9, required: 3, streak: 0, isSecured: false)
            #expect(few.hint == "Ещё 3 участника до сегодняшнего огня группы")
        }
    }

    @Test func edgeCasesStayHonest() {
        // Mehr gemeldet als Mitglieder: auf Mitglieder begrenzt; ohne Mitglieder kein Hinweis und kein Balken.
        let capped = GroupDayProgress(reached: 9, members: 8, required: 3, streak: 4, isSecured: true)
        #expect(capped.reached == 8)
        #expect(capped.progress == 1)
        let empty = GroupDayProgress(reached: 0, members: 0, required: 0, streak: 0, isSecured: false)
        #expect(empty.hint == nil)
        #expect(empty.progress == 0)
        #expect(empty.thresholdFraction == nil)
        // Einzelperson: Schwelle = alle, keine eigene Markierung.
        #expect(GroupDayProgress(reached: 0, members: 1, required: 1, streak: 0, isSecured: false).thresholdFraction == nil)
    }
}

/// Pin-Vorschau mit Inhalt (Auftrag 5, B6).
struct ChatPinPreviewTests {
    private let conversation = UUID()
    private let mia = SocialProfile(publicID: UUID(), username: "mia", displayName: "Mia")
    private let leon = SocialProfile(publicID: UUID(), username: "leon", displayName: "Leon")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func pin(_ message: ChatMessage, hidden: Bool = false) -> ChatPin {
        ChatPin(message: message, pinnedBy: mia, pinnedAt: now, isHidden: hidden)
    }

    @Test func eachKindShowsItsContent() {
        PaceLocalization.$languageOverride.withValue(.german) {
            let text = ChatFixtures.message(in: conversation, from: mia, text: "Treffpunkt:\nSamstag   9 Uhr", at: now)
            let textPreview = ChatPinPreview(pin: pin(text), index: 0, count: 1, showsSender: true)
            #expect(textPreview.visual == .text)
            #expect(textPreview.line == "Mia: Treffpunkt: Samstag 9 Uhr")
            #expect(textPreview.title == "Angepinnte Nachricht")

            let photo = ChatFixtures.message(in: conversation, from: nil, isOwn: true, kind: .image, text: "Hier", mediaPath: "c/park.jpg", at: now)
            let photoPreview = ChatPinPreview(pin: pin(photo), index: 1, count: 3, showsSender: true)
            #expect(photoPreview.visual == .image(MediaReference(bucket: .chatMedia, path: "c/park.jpg")))
            #expect(photoPreview.line == "Du: Foto · Hier")
            #expect(photoPreview.title == "Angepinnt 2 von 3")
            #expect(photoPreview.showsSegments)

            let gif = ChatFixtures.message(in: conversation, from: leon, kind: .gif, mediaPath: "c/wave.gif", at: now)
            #expect(ChatPinPreview(pin: pin(gif), index: 0, count: 1, showsSender: false).line == "GIF")

            let voice = ChatFixtures.message(in: conversation, from: leon, kind: .voice, mediaPath: "c/v.m4a", at: now, mediaDuration: .seconds(18))
            let voicePreview = ChatPinPreview(pin: pin(voice), index: 0, count: 1, showsSender: false)
            #expect(voicePreview.visual == .voice)
            #expect(voicePreview.line == "Sprachnachricht · 0:18")

            let profile = ChatFixtures.message(in: conversation, from: mia, kind: .profile, sharedProfile: leon, at: now)
            let profilePreview = ChatPinPreview(pin: pin(profile), index: 0, count: 1, showsSender: false)
            #expect(profilePreview.visual == .profile(leon))
            #expect(profilePreview.line == "Profil: @leon")
        }
    }

    @Test func hiddenPinsShowNothingOfTheMessage() {
        PaceLocalization.$languageOverride.withValue(.german) {
            let secret = ChatFixtures.message(in: conversation, from: leon, kind: .image, text: "geheim", mediaPath: "c/secret.jpg", at: now)
            let preview = ChatPinPreview(pin: pin(secret, hidden: true), index: 0, count: 1, showsSender: true)
            #expect(preview.visual == .unavailable)
            #expect(preview.sender == nil)
            #expect(preview.line == "Nachricht nicht verfügbar")
            #expect(!preview.accessibilityLabel.contains("geheim"))
            #expect(!preview.accessibilityLabel.contains("Leon"))
        }
    }

    @Test func longTextsAreShortenedAndManyPinsAreCompact() {
        let long = String(repeating: "Schritt ", count: 40)
        let message = ChatFixtures.message(in: conversation, from: mia, text: long, at: now)
        let preview = ChatPinPreview(pin: pin(message), index: 5, count: 7, showsSender: false)
        #expect(preview.excerpt.count == ChatPinPreview.excerptLength)
        #expect(preview.excerpt.hasSuffix("…"))
        #expect(!preview.showsSegments)
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(ChatPinPreview(pin: pin(message), index: 5, count: 7, showsSender: false).title == "Pinned 6 of 7")
        }
    }
}
