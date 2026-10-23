import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import Testing

/// Chatliste mit Sprachnachrichten („Sprachnachricht · 0:18“) und eigenem Spitznamen des Absenders.
struct ChatVoiceFormattingTests {
    @Test func voiceDurationIsShownAsMinutesAndSeconds() {
        #expect(ChatFormatting.voiceDuration(.milliseconds(18_400)) == "0:18")
        #expect(ChatFormatting.voiceDuration(.milliseconds(18_600)) == "0:19")
        #expect(ChatFormatting.voiceDuration(.seconds(300)) == "5:00")
        #expect(ChatFormatting.voiceDuration(.milliseconds(200)) == "0:01")
    }

    @Test func previewOfAVoiceMessageInAllLanguages() {
        let voice = ChatMessagePreview(kind: .voice, text: nil, senderName: "Mia", isOwn: false, sentAt: Date(), mediaDuration: .seconds(18))
        let direct = ChatFixtures.direct(last: voice)
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(ChatFormatting.preview(for: direct) == "Sprachnachricht · 0:18")
            #expect(ChatFormatting.content(kind: .voice, text: nil) == "Sprachnachricht")
        }
        PaceLocalization.$languageOverride.withValue(.english) {
            #expect(ChatFormatting.preview(for: direct) == "Voice message · 0:18")
        }
        PaceLocalization.$languageOverride.withValue(.russian) {
            #expect(ChatFormatting.preview(for: direct) == "Голосовое сообщение · 0:18")
        }
    }

    @Test func groupPreviewUsesTheOwnNicknameForTheSender() {
        let last = ChatMessagePreview(kind: .text, text: "Hallo", senderName: "Mia", isOwn: false, sentAt: Date(), senderNickname: "Mimi")
        PaceLocalization.$languageOverride.withValue(.german) {
            #expect(ChatFormatting.preview(for: ChatFixtures.group(last: last)) == "Mimi: Hallo")
        }
    }
}
