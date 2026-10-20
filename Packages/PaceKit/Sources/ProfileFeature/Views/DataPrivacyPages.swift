import DesignSystem
import PaceCore
import SwiftUI

// MARK: - Datenschutz & Daten

/// Datenschutz & Daten: Erklärungen (als Entwurf gekennzeichnet), Datenexport und Konto löschen.
struct DataPrivacyPage: View {
    let viewModel: ProfileViewModel
    let backTitle: String

    var body: some View {
        ProfileSubpage {
            DataPrivacyPageContent(viewModel: viewModel.dataPrivacy, backTitle: backTitle) { viewModel.open($0) }
        }
        // Die Exportdatei nicht länger als nötig im Zwischenspeicher lassen.
        .onDisappear { [data = viewModel.dataPrivacy] in data.discardExport() }
    }
}

struct DataPrivacyPageContent: View {
    let viewModel: DataPrivacyViewModel
    let backTitle: String
    var onOpen: (ProfileRoute) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.dataPrivacy.title)
                .padding(.bottom, PaceSpacing.xs)

            DraftNoticeCard()

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.m) {
                    ForEach(PrivacyContent.dataSections) { section in
                        InfoSectionView(section: section)
                    }
                }
            }

            ProfileSettingsRow(
                systemImage: "doc.text",
                title: LegalDocument.privacyPolicy.title
            ) { onOpen(.legalDocument(.privacyPolicy)) }

            ProfileSectionTitle(PaceLocalization.text(de: "Deine Daten", en: "Your data", ru: "Твои данные"))
            exportCard
            deleteCard
        }
    }

    private var exportCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(PaceLocalization.text(de: "Datenexport", en: "Data export", ru: "Экспорт данных"))
                ProfileFootnote(text: PaceLocalization.text(
                    de: "Erstellt eine JSON-Datei mit allen Daten, die Pace auf dem Server zu deinem Konto speichert, und den Daten auf diesem iPhone (Einstellungen, Tagesziel-Verlauf, Rekord, Home-Aufbau).",
                    en: "Creates a JSON file with all data Pace stores on the server for your account plus the data on this iPhone (settings, daily goal history, record, home layout).",
                    ru: "Создаёт JSON-файл со всеми данными, которые Pace хранит на сервере для твоего аккаунта, и данными на этом iPhone (настройки, история дневной цели, рекорд, раскладка главного экрана)."
                ))
                if viewModel.isAvailable {
                    switch viewModel.exportState {
                    case .idle, .failed:
                        exportButton
                    case .exporting:
                        HStack(spacing: PaceSpacing.xs) {
                            ProgressView()
                            Text(PaceLocalization.text(de: "Export wird erstellt …", en: "Creating export …", ru: "Создаём экспорт …"))
                                .font(PaceFont.callout)
                                .foregroundStyle(PaceColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    case .ready(let file):
                        ShareLink(item: file) {
                            Label(
                                PaceLocalization.text(de: "Datei teilen oder sichern", en: "Share or save file", ru: "Поделиться или сохранить файл"),
                                systemImage: "square.and.arrow.up"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pacePrimary)
                        ProfileFootnote(text: file.lastPathComponent)
                    }
                    if case .failed(let message) = viewModel.exportState {
                        ProfileFootnote(text: message, isError: true)
                    }
                } else {
                    ProfileNoteRow(systemImage: "icloud.slash", text: viewModel.unavailableText)
                }
            }
        }
    }

    private var exportButton: some View {
        Button {
            Task { await viewModel.export() }
        } label: {
            Label(PaceLocalization.text(de: "Export erstellen", en: "Create export", ru: "Создать экспорт"), systemImage: "arrow.down.doc")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.paceSecondary)
    }

    private var deleteCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(ProfileRoute.deleteAccount.title)
                ProfileFootnote(text: PaceLocalization.text(
                    de: "Löscht dein Konto und alle personenbezogenen Daten auf dem Server und auf diesem iPhone endgültig.",
                    en: "Permanently deletes your account and all personal data on the server and on this iPhone.",
                    ru: "Безвозвратно удаляет аккаунт и все персональные данные на сервере и на этом iPhone."
                ))
                Button(PaceLocalization.text(de: "Konto löschen …", en: "Delete account …", ru: "Удалить аккаунт …")) {
                    onOpen(.deleteAccount)
                }
                .buttonStyle(ProfileDangerOutlineButtonStyle())
                .disabled(!viewModel.isAvailable)
            }
        }
    }
}

// MARK: - Konto löschen

/// Zweite Stufe: Folgen erklären, Benutzernamen eintippen, endgültig bestätigen.
struct DeleteAccountPage: View {
    @Bindable var viewModel: DataPrivacyViewModel
    let backTitle: String

    @State private var showsConfirmation = false

    var body: some View {
        ProfileSubpage {
            DeleteAccountPageContent(viewModel: viewModel, backTitle: backTitle) {
                TextField(viewModel.requiredConfirmation, text: $viewModel.confirmationText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            } onDelete: {
                showsConfirmation = true
            }
        }
        .confirmationDialog(
            PaceLocalization.text(
                de: "Konto endgültig löschen?",
                en: "Delete account permanently?",
                ru: "Удалить аккаунт навсегда?"
            ),
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button(PaceLocalization.text(de: "Endgültig löschen", en: "Delete permanently", ru: "Удалить навсегда"), role: .destructive) {
                Task { await viewModel.deleteAccount() }
            }
            Button(ProfileTexts.cancel, role: .cancel) {}
        } message: {
            Text(viewModel.deletionWarning)
        }
    }
}

struct DeleteAccountPageContent<Field: View>: View {
    let viewModel: DataPrivacyViewModel
    let backTitle: String
    private let field: Field
    private let onDelete: () -> Void

    init(
        viewModel: DataPrivacyViewModel,
        backTitle: String,
        @ViewBuilder field: () -> Field,
        onDelete: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.backTitle = backTitle
        self.field = field()
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.deleteAccount.title)
                .padding(.bottom, PaceSpacing.xs)

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    HStack(spacing: PaceSpacing.s) {
                        ProfileRowIcon(systemImage: "exclamationmark.triangle", tint: PaceColor.danger)
                        Text(PaceLocalization.text(de: "Das wird gelöscht", en: "What will be deleted", ru: "Что будет удалено"))
                            .font(PaceFont.cardTitle)
                            .foregroundStyle(PaceColor.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                        ForEach(viewModel.deletionConsequences, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(PaceColor.danger)
                                    .accessibilityHidden(true)
                                Text(item)
                                    .font(PaceFont.callout)
                                    .foregroundStyle(PaceColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    ProfileFootnote(text: viewModel.deletionWarning)
                }
            }

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    Text(viewModel.confirmationPrompt)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    field
                        .font(.body)
                        .padding(.horizontal, PaceSpacing.s)
                        .frame(minHeight: 48)
                        .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                        .disabled(viewModel.isDeleting)
                    if let status = viewModel.deletionStatusText {
                        HStack(spacing: PaceSpacing.xs) {
                            ProgressView()
                            Text(status)
                                .font(PaceFont.callout)
                                .foregroundStyle(PaceColor.textSecondary)
                        }
                    }
                    if let error = viewModel.deletionError {
                        ProfileFootnote(text: error, isError: true)
                    }
                    Button(PaceLocalization.text(de: "Konto endgültig löschen", en: "Delete account permanently", ru: "Удалить аккаунт навсегда"), action: onDelete)
                        .buttonStyle(ProfileDangerButtonStyle())
                        .disabled(!viewModel.canDelete)
                }
            }
        }
    }
}
