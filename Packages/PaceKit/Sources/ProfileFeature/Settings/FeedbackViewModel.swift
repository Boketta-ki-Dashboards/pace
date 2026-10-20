import Foundation
import Observation
import PaceCore

/// „Problem melden“ und „Feedback senden“: Die Nachricht wird über `AccountRepository.submitFeedback` beim Pace-Team
/// gespeichert – ohne E-Mail-Adresse und ohne erfundene Empfänger.
@MainActor
@Observable
public final class FeedbackViewModel {
    public enum State: Equatable, Sendable {
        case editing
        case sending
        case sent
        case failed(String)
    }

    public let kind: FeedbackKind
    public var message = ""
    public private(set) var state: State = .editing

    /// Mindestlänge, damit eine Rückmeldung verständlich ist.
    public static let minimumLength = 10

    @ObservationIgnored private let account: (any AccountRepository)?
    @ObservationIgnored private let appVersion: String

    public init(kind: FeedbackKind, account: (any AccountRepository)?, appVersion: String) {
        self.kind = kind
        self.account = account
        self.appVersion = appVersion
    }

    public var isAvailable: Bool { account != nil }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var characterCount: Int { trimmedMessage.count }

    public var isTooLong: Bool { characterCount > FeedbackRules.maximumLength }

    public var canSend: Bool {
        isAvailable && state != .sending && characterCount >= Self.minimumLength && !isTooLong
    }

    /// z. B. „120/2.000“.
    public var counterText: String {
        "\(characterCount.paceFormatted)/\(FeedbackRules.maximumLength.paceFormatted)"
    }

    /// Hinweis unter dem Textfeld.
    public var validationMessage: String? {
        if isTooLong {
            return PaceLocalization.text(
                de: "Höchstens \(ProfileTexts.characters(FeedbackRules.maximumLength)).",
                en: "At most \(ProfileTexts.characters(FeedbackRules.maximumLength)).",
                ru: "Максимум \(ProfileTexts.characters(FeedbackRules.maximumLength))."
            )
        }
        if characterCount > 0, characterCount < Self.minimumLength {
            return PaceLocalization.text(
                de: "Bitte beschreibe es etwas genauer (mindestens \(ProfileTexts.characters(Self.minimumLength))).",
                en: "Please describe it in a bit more detail (at least \(ProfileTexts.characters(Self.minimumLength))).",
                ru: "Пожалуйста, опиши подробнее (минимум \(ProfileTexts.characters(Self.minimumLength)))."
            )
        }
        return nil
    }

    public func send() async {
        guard let account, canSend else { return }
        state = .sending
        do {
            try await account.submitFeedback(kind: kind, message: trimmedMessage, appVersion: appVersion)
            message = ""
            state = .sent
        } catch let error as AccountError {
            state = .failed(error.message)
        } catch {
            state = .failed(AccountError.unexpected(String(describing: error)).message)
        }
    }

    /// Nach einem Fehler oder einer gesendeten Nachricht wieder schreiben.
    public func resume() {
        if state != .sending { state = .editing }
    }

    public var placeholder: String {
        switch kind {
        case .problem:
            PaceLocalization.text(
                de: "Was ist passiert? Was hast du erwartet?",
                en: "What happened? What did you expect?",
                ru: "Что произошло? Чего ты ожидал?"
            )
        case .idea:
            PaceLocalization.text(
                de: "Was gefällt dir, was können wir besser machen?",
                en: "What do you like, what could we do better?",
                ru: "Что тебе нравится и что можно улучшить?"
            )
        }
    }

    public var explanation: String {
        PaceLocalization.text(
            de: "Deine Nachricht wird mit deinem Konto und der App-Version (\(appVersion.isEmpty ? ProfileTexts.placeholder : appVersion)) gespeichert, damit wir nachvollziehen können, worum es geht. Schreibe bitte keine Gesundheitsdaten oder Passwörter hinein. Eine Antwort ist derzeit nicht möglich.",
            en: "Your message is stored with your account and the app version (\(appVersion.isEmpty ? ProfileTexts.placeholder : appVersion)) so we can understand the context. Please don't include health data or passwords. We can't reply at the moment.",
            ru: "Сообщение сохраняется вместе с твоим аккаунтом и версией приложения (\(appVersion.isEmpty ? ProfileTexts.placeholder : appVersion)), чтобы мы поняли контекст. Не указывай данные о здоровье или пароли. Ответить мы пока не можем."
        )
    }

    public var sentTitle: String {
        PaceLocalization.text(de: "Danke für deine Nachricht!", en: "Thanks for your message!", ru: "Спасибо за сообщение!")
    }

    public var sentMessage: String {
        PaceLocalization.text(
            de: "Wir haben sie gespeichert und schauen sie uns an.",
            en: "We've saved it and will take a look.",
            ru: "Мы сохранили его и обязательно посмотрим."
        )
    }

    public var unavailableText: String {
        PaceLocalization.text(
            de: "Rückmeldungen lassen sich ohne Verbindung zum Pace-Server nicht senden.",
            en: "Feedback can't be sent without a connection to the Pace server.",
            ru: "Без подключения к серверу Pace отправить отзыв нельзя."
        )
    }

    public var sendTitle: String {
        PaceLocalization.text(de: "Senden", en: "Send", ru: "Отправить")
    }
}
