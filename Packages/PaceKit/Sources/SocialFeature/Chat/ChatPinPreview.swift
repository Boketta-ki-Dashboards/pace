import Foundation
import PaceCore

/// Inhalt des Pin-Hinweises oben im Chat: was angepinnt ist (Text-Ausschnitt, Bild- bzw. GIF-Miniatur, Sprachnachricht
/// mit Dauer, geteiltes Profil), von wem und welcher von mehreren Pins gerade gezeigt wird.
///
/// Verborgene Pins (gelöschte Nachricht, blockierte Person) zeigen nie Inhalt, Absender oder Miniatur – nur
/// „Nachricht nicht verfügbar“.
public struct ChatPinPreview: Equatable, Sendable {
    public enum Visual: Equatable, Sendable {
        /// Textnachricht: Pin-Symbol.
        case text
        /// Foto: kleine Miniatur aus dem geschützten Chat-Speicher.
        case image(MediaReference)
        /// GIF: Miniatur (erstes Bild) mit „GIF“.
        case gif(MediaReference)
        /// Sprachnachricht: Wellen-Symbol, Dauer im Text.
        case voice
        /// Geteiltes Profil: Profilbild der Person.
        case profile(SocialProfile)
        /// Verborgen oder ohne Inhalt.
        case unavailable
    }

    /// Höchstlänge des Text-Ausschnitts (der Hinweis zeigt eine Zeile; VoiceOver liest den Ausschnitt vor).
    public static let excerptLength = 120

    public let messageID: UUID
    public let visual: Visual
    /// z. B. „Angepinnt 2 von 3“ bzw. „Angepinnte Nachricht“.
    public let title: String
    /// Absender in Gruppen („Marie“, eigene: „Du“); `nil` im Privatchat und bei verborgenen Pins.
    public let sender: String?
    /// z. B. „Wer ist heute Abend …“, „Foto · Hier treffen wir uns“, „Sprachnachricht · 0:12“, „Profil: @mia“.
    public let excerpt: String
    public let isHidden: Bool
    /// Position unter mehreren Pins (0-basiert) und Anzahl.
    public let index: Int
    public let count: Int

    public init(pin: ChatPin, index: Int, count: Int, showsSender: Bool) {
        let message = pin.message
        messageID = message.id
        self.index = index
        self.count = count
        isHidden = pin.isHidden
        title = ChatUIText.pinnedBanner(index + 1, of: count)
        guard !pin.isHidden else {
            visual = .unavailable
            sender = nil
            excerpt = ChatUIText.originalUnavailable
            return
        }
        sender = showsSender
            ? (message.isOwn ? ChatUIText.you : (message.sender?.shownName ?? ChatFormatting.deletedAccount))
            : nil
        let caption = Self.excerpt(message.text)
        switch message.kind {
        case .text:
            visual = .text
            excerpt = caption ?? ""
        case .image:
            visual = message.media.map(Visual.image) ?? .unavailable
            excerpt = [ChatFormatting.photo, caption].compactMap { $0 }.joined(separator: " · ")
        case .gif:
            visual = message.media.map(Visual.gif) ?? .unavailable
            excerpt = "GIF"
        case .voice:
            visual = .voice
            excerpt = ChatFormatting.content(kind: .voice, text: nil, duration: message.mediaDuration)
        case .profile:
            if let profile = message.sharedProfile {
                visual = .profile(profile)
                excerpt = PaceLocalization.text(de: "Profil", en: "Profile", ru: "Профиль") + ": @\(profile.username)"
            } else {
                visual = .unavailable
                excerpt = ChatFormatting.content(kind: .profile, text: nil)
            }
        }
    }

    /// Zeile unter dem Titel, z. B. „Marie: Wer ist heute Abend …“.
    public var line: String {
        guard let sender else { return excerpt }
        return "\(sender): \(excerpt)"
    }

    /// Mehrere Pins: Markierungen für den Wechsel (höchstens vier, sonst eine kompakte Zählung).
    public var showsSegments: Bool {
        count > 1 && count <= 4
    }

    public var accessibilityLabel: String {
        "\(title). \(line)"
    }

    /// Ausschnitt eines Textes in einer Zeile; `nil` ohne Text.
    static func excerpt(_ text: String?) -> String? {
        let words = (text ?? "").split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !words.isEmpty else { return nil }
        guard words.count > excerptLength else { return words }
        return String(words.prefix(excerptLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
