import DesignSystem
import PaceCore
import SwiftUI

/// Fester Eintrag „Pace-Bot“ oben in der Chatliste – ein systemeigener Hilfe-Chat, kein Kontakt: keine ungelesenen
/// Nachrichten, kein Echtzeit-Abo, keine Freundschaft, verdrängt keine anderen Chats.
struct PaceBotChatRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                PaceBotAvatar(size: ChatListRow.avatarSize)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: PaceSpacing.xs) {
                        Text(PaceHelpBot.name)
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                        PaceBotTag()
                    }
                    Text(PaceHelpBot.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: PaceSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, PaceSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(PaceHelpBot.name), \(PaceBotTexts.automated). \(PaceHelpBot.subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Bild des Pace-Bots: Hilfe-Symbol auf Mint (kein Foto, keine Person).
struct PaceBotAvatar: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "questionmark.bubble.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(PaceColor.onSelection)
            .frame(width: size, height: size)
            .background(PaceColor.selectionFill, in: Circle())
            .overlay(Circle().strokeBorder(PaceColor.accent.opacity(0.5), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Kennzeichnung „Automatisch“ – der Bot ist erkennbar keine Person.
struct PaceBotTag: View {
    var body: some View {
        Text(PaceBotTexts.automated)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(PaceColor.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(PaceColor.accentSoft, in: Capsule())
            .accessibilityHidden(true)
    }
}

/// Hilfe-Chat mit dem Pace-Bot: im Stil des Pace-Messengers (Bot links, eigene Fragen rechts), darunter die
/// vorbereiteten Fragen, eine einfache Texteingabe und der Weg zum Support.
struct PaceBotView: View {
    let session: PaceHelpBotSession
    let support: PaceSupportContact
    let onOpenFeedback: (() -> Void)?

    @State private var input = ""
    @State private var showsSupport = false
    @State private var showsResetConfirmation = false
    @FocusState private var isInputFocused: Bool

    private static let questionsAnchor = "pace.bot.questions"
    private static let bottomAnchor = "pace.bot.bottom"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    PaceBotContent(
                        session: session,
                        support: support,
                        showsSupport: showsSupport || session.lastAnswerWasUnknown,
                        onAsk: { topic in
                            session.ask(topic)
                            showsSupport = false
                            scrollToBottom(proxy)
                        },
                        onShowQuestions: {
                            withAnimation { proxy.scrollTo(Self.questionsAnchor, anchor: .top) }
                        },
                        onContactSupport: {
                            showsSupport = true
                            scrollToBottom(proxy)
                        },
                        onOpenFeedback: onOpenFeedback,
                        onReset: { showsResetConfirmation = true },
                        questionsAnchor: Self.questionsAnchor
                    )
                    .padding(.horizontal, PaceSpacing.m)
                    .padding(.bottom, PaceSpacing.m)
                    .paceVerticalScrollLock()
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.messages.count) {
                    scrollToBottom(proxy)
                }
            }
            inputBar
        }
        .paceScreenBackground()
        .paceSubpage()
        .onAppear { session.start() }
        .confirmationDialog(PaceBotTexts.resetTitle, isPresented: $showsResetConfirmation, titleVisibility: .visible) {
            Button(PaceBotTexts.reset, role: .destructive) { session.reset() }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        }
    }

    /// Einfache Texteingabe: Stichwörter führen zu einem Thema, sonst eine ehrliche Antwort.
    private var inputBar: some View {
        HStack(spacing: PaceSpacing.xs) {
            TextField(PaceBotTexts.inputPlaceholder, text: $input)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, PaceSpacing.s)
                .frame(minHeight: 44)
                .background(PaceColor.fieldBackground, in: Capsule())
                .onChange(of: input) { _, value in
                    if value.count > PaceHelpBot.maximumInputLength {
                        input = String(value.prefix(PaceHelpBot.maximumInputLength))
                    }
                }
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PaceColor.onAccent)
                    .frame(width: 44, height: 44)
                    .background(PaceColor.actionFill, in: Circle())
            }
            .buttonStyle(.pacePressable)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(PaceBotTexts.send)
        }
        .padding(.horizontal, PaceSpacing.m)
        .padding(.vertical, PaceSpacing.xs)
        .background(PaceColor.background)
    }

    private func send() {
        let text = input
        input = ""
        session.send(text)
        showsSupport = false
    }
}

/// Inhalt des Hilfe-Chats ohne Scrollen und Eingabe (auch für Snapshot-Tests).
struct PaceBotContent: View {
    let session: PaceHelpBotSession
    let support: PaceSupportContact
    var showsSupport = false
    var onAsk: (PaceHelpTopic) -> Void = { _ in }
    var onShowQuestions: () -> Void = {}
    var onContactSupport: () -> Void = {}
    var onOpenFeedback: (() -> Void)?
    var onReset: () -> Void = {}
    var questionsAnchor = "questions"

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: SocialText.social, title: PaceHelpBot.name) {
                Menu {
                    Button(PaceBotTexts.reset, systemImage: "arrow.counterclockwise", action: onReset)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(PaceBotTexts.more)
            }
            HStack(spacing: PaceSpacing.xs) {
                PaceBotTag()
                Text(PaceHelpBot.automatedNote)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(session.messages) { message in
                PaceBotBubble(message: message)
            }

            if session.messages.last?.role == .bot, session.messages.count > 1 {
                HStack(spacing: PaceSpacing.xs) {
                    Button(PaceBotTexts.otherQuestion, action: onShowQuestions)
                        .buttonStyle(.paceCompact)
                    Button(PaceBotTexts.contactSupport, action: onContactSupport)
                        .buttonStyle(.paceCompact)
                }
            }

            if showsSupport {
                supportCard
            }

            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                Text(PaceBotTexts.questions)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .padding(.top, PaceSpacing.s)
                ForEach(PaceHelpTopic.allCases) { topic in
                    Button {
                        onAsk(topic)
                    } label: {
                        HStack(spacing: PaceSpacing.s) {
                            Text(topic.question)
                                .font(PaceFont.callout.weight(.medium))
                                .foregroundStyle(PaceColor.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: PaceSpacing.xs)
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(PaceColor.accent)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, PaceSpacing.s)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pacePressable)
                }
            }
            .id(questionsAnchor)
        }
    }

    /// Weg zum Support: „Problem melden“ in der App (immer) und – nur wenn eingerichtet – eine E-Mail mit Vorlage.
    /// Es wird nichts automatisch mitgeschickt.
    private var supportCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(PaceBotTexts.supportTitle)
                Text(PaceBotTexts.supportPrivacy)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let onOpenFeedback {
                    Button(FeedbackKind.problem.title, systemImage: "exclamationmark.bubble", action: onOpenFeedback)
                        .buttonStyle(.paceSecondary)
                }
                if let mailURL = support.mailURL {
                    Link(destination: mailURL) {
                        Label(PaceBotTexts.emailSupport, systemImage: "envelope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.paceSecondary)
                } else {
                    Text(PaceBotTexts.emailNotConfigured)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Nachrichtenblase im Stil des Pace-Chats: Bot links auf Fläche, eigene Fragen rechts in Mint.
struct PaceBotBubble: View {
    let message: PaceHelpMessage

    var body: some View {
        let isBot = message.role == .bot
        HStack(alignment: .bottom, spacing: PaceSpacing.xs) {
            if isBot {
                PaceBotAvatar(size: 28)
            } else {
                Spacer(minLength: 48)
            }
            Text(verbatim: message.text)
                .font(PaceFont.body)
                .foregroundStyle(isBot ? PaceColor.textPrimary : PaceColor.onAccent)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PaceSpacing.s)
                .padding(.vertical, PaceSpacing.xs + 2)
                .background(
                    isBot ? PaceColor.surface : PaceColor.actionFill,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isBot ? PaceColor.border : .clear, lineWidth: 1)
                )
            if isBot {
                Spacer(minLength: 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: isBot ? .leading : .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel((isBot ? PaceHelpBot.name : PaceBotTexts.you) + ": " + message.text)
    }
}

enum PaceBotTexts {
    static var automated: String { PaceLocalization.text(de: "Automatisch", en: "Automated", ru: "Автоматически") }
    static var questions: String { PaceLocalization.text(de: "Häufige Fragen", en: "Frequently asked", ru: "Частые вопросы") }
    static var otherQuestion: String { PaceLocalization.text(de: "Weitere Frage", en: "Another question", ru: "Другой вопрос") }
    static var contactSupport: String { PaceLocalization.text(de: "Hilfe kontaktieren", en: "Contact support", ru: "Связаться с поддержкой") }
    static var supportTitle: String { PaceLocalization.text(de: "Support kontaktieren", en: "Contact support", ru: "Связаться с поддержкой") }
    static var supportPrivacy: String {
        PaceLocalization.text(
            de: "Es wird nur gesendet, was du selbst schreibst – keine Chats, Gesundheitsdaten oder Körperdaten.",
            en: "Only what you write yourself is sent – no chats, health data or body measurements.",
            ru: "Отправляется только то, что ты напишешь сам – без чатов, данных о здоровье и параметров тела."
        )
    }
    static var emailSupport: String { PaceLocalization.text(de: "E-Mail an den Support", en: "Email support", ru: "Написать в поддержку") }
    static var emailNotConfigured: String {
        PaceLocalization.text(
            de: "Eine Support-E-Mail-Adresse ist noch nicht eingerichtet. Nutze bitte „Problem melden“.",
            en: "A support email address isn't set up yet. Please use “Report a problem”.",
            ru: "Адрес поддержки по электронной почте пока не настроен. Используй «Сообщить о проблеме»."
        )
    }
    static var inputPlaceholder: String { PaceLocalization.text(de: "Frage eingeben …", en: "Type a question …", ru: "Введи вопрос …") }
    static var send: String { PaceLocalization.text(de: "Senden", en: "Send", ru: "Отправить") }
    static var reset: String { PaceLocalization.text(de: "Verlauf zurücksetzen", en: "Reset history", ru: "Очистить историю") }
    static var resetTitle: String { PaceLocalization.text(de: "Hilfeverlauf zurücksetzen?", en: "Reset help history?", ru: "Очистить историю помощи?") }
    static var more: String { PaceLocalization.text(de: "Mehr", en: "More", ru: "Ещё") }
    static var you: String { PaceLocalization.text(de: "Du", en: "You", ru: "Ты") }
}
