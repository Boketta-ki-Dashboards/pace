import DesignSystem
import PaceCore
import SwiftUI

// MARK: - Hilfe & Feedback

/// Hilfe & Feedback: häufige Fragen, Problem melden, Feedback senden, Rechtliches, App-Version.
struct HelpPage: View {
    let viewModel: ProfileViewModel
    let backTitle: String

    var body: some View {
        ProfileSubpage {
            HelpPageContent(appVersion: viewModel.appVersion, backTitle: backTitle) { viewModel.open($0) }
        }
    }
}

struct HelpPageContent: View {
    let appVersion: String
    let backTitle: String
    let onOpen: (ProfileRoute) -> Void

    @State private var expanded: Set<String>

    init(appVersion: String, backTitle: String, expanded: Set<String> = [], onOpen: @escaping (ProfileRoute) -> Void = { _ in }) {
        self.appVersion = appVersion
        self.backTitle = backTitle
        self.onOpen = onOpen
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.help.title)
                .padding(.bottom, PaceSpacing.xs)

            ProfileSectionTitle(PaceLocalization.text(de: "Häufige Fragen", en: "Frequently asked questions", ru: "Частые вопросы"))
            PaceCard(padding: PaceSpacing.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(HelpContent.faq.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                                .overlay(PaceColor.border)
                                .padding(.horizontal, PaceSpacing.s)
                        }
                        FAQRow(item: item, isExpanded: expanded.contains(item.id)) {
                            if expanded.contains(item.id) {
                                expanded.remove(item.id)
                            } else {
                                expanded.insert(item.id)
                            }
                        }
                    }
                }
            }

            ProfileSectionTitle(PaceLocalization.text(de: "Kontakt", en: "Contact", ru: "Связь"))
            ProfileSettingsRow(
                systemImage: "exclamationmark.bubble",
                title: FeedbackKind.problem.title,
                subtitle: PaceLocalization.text(
                    de: "Etwas funktioniert nicht wie erwartet",
                    en: "Something doesn't work as expected",
                    ru: "Что-то работает не так, как ожидалось"
                )
            ) { onOpen(.feedback(.problem)) }
            ProfileSettingsRow(
                systemImage: "lightbulb",
                title: FeedbackKind.idea.title,
                subtitle: PaceLocalization.text(
                    de: "Ideen und Wünsche für Pace",
                    en: "Ideas and wishes for Pace",
                    ru: "Идеи и пожелания для Pace"
                )
            ) { onOpen(.feedback(.idea)) }

            ProfileSectionTitle(ProfileRoute.legal.title)
            ProfileSettingsRow(
                systemImage: "doc.text",
                title: ProfileRoute.legal.title,
                subtitle: PaceLocalization.text(
                    de: "Datenschutzerklärung, Impressum, Nutzungsbedingungen",
                    en: "Privacy policy, legal notice, terms of use",
                    ru: "Политика конфиденциальности, выходные данные, условия"
                )
            ) { onOpen(.legal) }

            ProfileInfoRow(
                systemImage: "info.circle",
                title: PaceLocalization.text(de: "App-Version", en: "App version", ru: "Версия приложения"),
                value: appVersion.isEmpty ? ProfileTexts.placeholder : appVersion
            )
            .padding(.top, PaceSpacing.xs)
        }
    }
}

/// Aufklappbare Frage.
private struct FAQRow: View {
    let item: InfoSection
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            Button(action: onToggle) {
                HStack(spacing: PaceSpacing.s) {
                    ProfileRowIcon(systemImage: item.systemImage)
                    Text(item.title)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: PaceSpacing.xs)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .accessibilityValue(isExpanded
                ? PaceLocalization.text(de: "aufgeklappt", en: "expanded", ru: "развёрнуто")
                : PaceLocalization.text(de: "zugeklappt", en: "collapsed", ru: "свёрнуто"))

            if isExpanded {
                Text(item.body)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 48)
                    .padding(.bottom, PaceSpacing.xs)
            }
        }
        .padding(.horizontal, PaceSpacing.s)
        .padding(.vertical, PaceSpacing.xxs)
    }
}

// MARK: - Rückmeldung

/// „Problem melden“ bzw. „Feedback senden“.
struct FeedbackPage: View {
    @State private var viewModel: FeedbackViewModel
    let backTitle: String

    init(viewModel: FeedbackViewModel, backTitle: String) {
        _viewModel = State(initialValue: viewModel)
        self.backTitle = backTitle
    }

    var body: some View {
        ProfileSubpage {
            FeedbackPageContent(viewModel: viewModel, backTitle: backTitle) {
                FeedbackEditor(viewModel: viewModel)
            }
        }
    }
}

/// Textfeld mit Platzhalter (TextEditor hat keinen eigenen).
private struct FeedbackEditor: View {
    @Bindable var viewModel: FeedbackViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.message.isEmpty {
                Text(viewModel.placeholder)
                    .font(.body)
                    .foregroundStyle(PaceColor.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $viewModel.message)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160)
                .accessibilityLabel(viewModel.kind.title)
        }
    }
}

struct FeedbackPageContent<Editor: View>: View {
    let viewModel: FeedbackViewModel
    let backTitle: String
    private let editor: Editor

    init(viewModel: FeedbackViewModel, backTitle: String, @ViewBuilder editor: () -> Editor) {
        self.viewModel = viewModel
        self.backTitle = backTitle
        self.editor = editor()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: viewModel.kind.title)
                .padding(.bottom, PaceSpacing.xs)

            if !viewModel.isAvailable {
                PaceCard {
                    ProfileNoteRow(systemImage: "icloud.slash", text: viewModel.unavailableText)
                }
            } else if viewModel.state == .sent {
                PaceCard {
                    VStack(spacing: PaceSpacing.s) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(PaceColor.accent)
                            .accessibilityHidden(true)
                        Text(viewModel.sentTitle)
                            .font(PaceFont.cardTitle)
                            .foregroundStyle(PaceColor.textPrimary)
                        Text(viewModel.sentMessage)
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                            .multilineTextAlignment(.center)
                        Button(PaceLocalization.text(de: "Weitere Nachricht schreiben", en: "Write another message", ru: "Написать ещё")) {
                            viewModel.resume()
                        }
                        .buttonStyle(.paceSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                PaceCard {
                    VStack(alignment: .leading, spacing: PaceSpacing.s) {
                        editor
                            .padding(PaceSpacing.xs)
                            .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                            .disabled(viewModel.state == .sending)
                        HStack {
                            if let message = viewModel.validationMessage {
                                ProfileFootnote(text: message, isError: viewModel.isTooLong)
                            }
                            Spacer(minLength: PaceSpacing.xs)
                            Text(verbatim: viewModel.counterText)
                                .font(PaceFont.caption)
                                .monospacedDigit()
                                .foregroundStyle(viewModel.isTooLong ? PaceColor.danger : PaceColor.textSecondary)
                        }
                        if case .failed(let message) = viewModel.state {
                            ProfileFootnote(text: message, isError: true)
                        }
                        Button {
                            Task { await viewModel.send() }
                        } label: {
                            if viewModel.state == .sending {
                                ProgressView()
                                    .tint(PaceColor.onAccent)
                            } else {
                                Text(viewModel.sendTitle)
                            }
                        }
                        .buttonStyle(.pacePrimary)
                        .disabled(!viewModel.canSend)
                        ProfileFootnote(text: viewModel.explanation)
                    }
                }
            }
        }
    }
}

// MARK: - Rechtliches

/// Übersicht der rechtlichen Texte.
struct LegalPage: View {
    let backTitle: String
    let onOpen: (ProfileRoute) -> Void

    var body: some View {
        ProfileSubpage {
            LegalPageContent(backTitle: backTitle, onOpen: onOpen)
        }
    }
}

struct LegalPageContent: View {
    let backTitle: String
    var onOpen: (ProfileRoute) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.legal.title)
                .padding(.bottom, PaceSpacing.xs)
            DraftNoticeCard()
            ForEach(LegalDocument.allCases) { document in
                ProfileSettingsRow(systemImage: systemImage(for: document), title: document.title) {
                    onOpen(.legalDocument(document))
                }
            }
        }
    }

    private func systemImage(for document: LegalDocument) -> String {
        switch document {
        case .privacyPolicy: "lock.shield"
        case .imprint: "building.2"
        case .terms: "doc.plaintext"
        }
    }
}

/// Ein rechtlicher Text als Entwurf bzw. mit Platzhaltern für den Betreiber.
struct LegalDocumentPage: View {
    let document: LegalDocument
    let backTitle: String

    var body: some View {
        ProfileSubpage {
            LegalDocumentPageContent(document: document, backTitle: backTitle)
        }
    }
}

struct LegalDocumentPageContent: View {
    let document: LegalDocument
    let backTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: document.title)
                .padding(.bottom, PaceSpacing.xs)
            DraftNoticeCard()
            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.m) {
                    ForEach(PrivacyContent.sections(for: document)) { section in
                        InfoSectionView(section: section)
                    }
                }
            }
        }
    }
}
