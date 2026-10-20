import DesignSystem
import PaceCore
import PhotosUI
import SwiftUI

/// „Konto & Profil“: Profilbild, Namen, Profil teilen, Kontoinformationen, Anmeldung & Sicherheit.
struct AccountPage: View {
    let viewModel: AccountSettingsViewModel
    let backTitle: String

    @State private var nameEditor: NameEditViewModel?
    @State private var showsPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ProfileSubpage {
            AccountPageContent(
                viewModel: viewModel,
                backTitle: backTitle,
                onPickPhoto: { showsPhotoPicker = true },
                onEditNames: { nameEditor = viewModel.makeNameEditor() }
            )
        }
        .task { [viewModel] in await viewModel.loadSession() }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickerItem = nil
                if let data, let jpeg = AvatarImageProcessing.squareJPEG(from: data) {
                    await viewModel.uploadAvatar(jpegData: jpeg)
                } else {
                    viewModel.reportUnreadablePhoto()
                }
            }
        }
        .sheet(item: $nameEditor) { editor in
            NameEditSheet(editor: editor)
        }
    }
}

extension NameEditViewModel: Identifiable {}

/// Inhalt von „Konto & Profil“ (ohne Scrollen) – auch für Snapshots.
struct AccountPageContent: View {
    let viewModel: AccountSettingsViewModel
    let backTitle: String
    var onPickPhoto: () -> Void = {}
    var onEditNames: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.account.title)
                .padding(.bottom, PaceSpacing.xs)
            avatarCard
            namesCard
            shareCard
            accountCard
            securityCard
        }
    }

    // MARK: Profilbild

    private var avatarCard: some View {
        PaceCard {
            VStack(spacing: PaceSpacing.s) {
                ZStack {
                    PaceAvatar(name: viewModel.displayName, seed: viewModel.avatarSeed, size: 96, image: viewModel.avatar)
                    if viewModel.isAvatarBusy {
                        Circle()
                            .fill(.black.opacity(0.35))
                            .frame(width: 96, height: 96)
                        ProgressView()
                            .tint(.white)
                    }
                }
                .accessibilityLabel(PaceLocalization.text(de: "Profilbild", en: "Profile picture", ru: "Фото профиля"))

                HStack(spacing: PaceSpacing.s) {
                    Button(action: onPickPhoto) {
                        Label(
                            viewModel.avatar == nil
                                ? PaceLocalization.text(de: "Foto wählen", en: "Choose photo", ru: "Выбрать фото")
                                : PaceLocalization.text(de: "Foto ändern", en: "Change photo", ru: "Изменить фото"),
                            systemImage: "photo"
                        )
                        .font(.system(.subheadline, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.paceSoft)
                    if viewModel.avatar != nil {
                        Button {
                            Task { await viewModel.removeAvatar() }
                        } label: {
                            Label(PaceLocalization.text(de: "Entfernen", en: "Remove", ru: "Удалить"), systemImage: "trash")
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.paceOutline)
                    }
                }
                .disabled(!viewModel.supportsAvatar || viewModel.isAvatarBusy)

                if let error = viewModel.avatarError {
                    ProfileFootnote(text: error, isError: true)
                }
                ProfileFootnote(text: viewModel.avatarHint)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Namen

    private var namesCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(PaceLocalization.text(de: "Name", en: "Name", ru: "Имя"))
                VStack(spacing: PaceSpacing.xs) {
                    ProfileInfoRow(systemImage: "person", title: NameEditTexts.displayName, value: viewModel.displayName)
                    ProfileInfoRow(systemImage: "at", title: NameEditTexts.username, value: viewModel.username)
                }
                Button(PaceLocalization.text(de: "Namen ändern", en: "Change names", ru: "Изменить имена"), action: onEditNames)
                    .buttonStyle(.paceSecondary)
            }
        }
    }

    // MARK: Teilen

    private var shareCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(ProfileTexts.shareProfile)
                ProfileFootnote(text: PaceLocalization.text(
                    de: "Mit diesem Link öffnet Pace dein Profil, damit andere dich als Freund hinzufügen können.",
                    en: "This link opens your profile in Pace so others can add you as a friend.",
                    ru: "По этой ссылке Pace откроет твой профиль, чтобы другие могли добавить тебя в друзья."
                ))
                Text(verbatim: viewModel.share.url.absoluteString)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(PaceColor.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, PaceSpacing.s)
                    .padding(.vertical, PaceSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                ShareLink(
                    item: viewModel.share.url,
                    subject: Text(viewModel.share.subject),
                    message: Text(viewModel.share.message)
                ) {
                    Label(PaceLocalization.text(de: "Link teilen", en: "Share link", ru: "Поделиться ссылкой"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pacePrimary)
            }
        }
    }

    // MARK: Konto

    private var accountCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(PaceLocalization.text(de: "Kontoinformationen", en: "Account information", ru: "Данные аккаунта"))
                VStack(spacing: PaceSpacing.xs) {
                    ProfileInfoRow(
                        systemImage: "iphone",
                        title: PaceLocalization.text(de: "Konto-Art", en: "Account type", ru: "Тип аккаунта"),
                        value: viewModel.accountKind
                    )
                    ProfileInfoRow(
                        systemImage: "calendar",
                        title: PaceLocalization.text(de: "Dabei seit", en: "Member since", ru: "В Pace с"),
                        value: viewModel.memberSince
                    )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(PaceLocalization.text(de: "Öffentliche ID", en: "Public ID", ru: "Публичный ID"))
                        .font(PaceFont.micro)
                        .foregroundStyle(PaceColor.textSecondary)
                    Text(verbatim: viewModel.publicID)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(PaceColor.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var securityCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(PaceLocalization.text(de: "Anmeldung & Sicherheit", en: "Sign-in & security", ru: "Вход и безопасность"))
                ProfileNoteRow(systemImage: "lock.iphone", text: viewModel.securityExplanation)
                PaceTile {
                    VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                        Text(PaceLocalization.text(de: "In Vorbereitung", en: "Being prepared", ru: "В разработке"))
                            .font(PaceFont.micro)
                            .foregroundStyle(PaceColor.accentStrong)
                            .padding(.horizontal, PaceSpacing.xs)
                            .padding(.vertical, 3)
                            .background(PaceColor.accentSoft, in: Capsule())
                        Text(PaceLocalization.text(
                            de: "Dauerhafte Anmeldung und Kontoübertragung",
                            en: "Permanent sign-in and account transfer",
                            ru: "Постоянный вход и перенос аккаунта"
                        ))
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(viewModel.permanentSignInNotice)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, PaceSpacing.xxs)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Texte des Namen-Dialogs.
enum NameEditTexts {
    static var displayName: String {
        PaceLocalization.text(de: "Anzeigename", en: "Display name", ru: "Отображаемое имя")
    }

    static var username: String {
        PaceLocalization.text(de: "Benutzername", en: "Username", ru: "Имя пользователя")
    }
}

/// Anzeigename und Benutzername ändern – mit Prüfung beim Tippen.
private struct NameEditSheet: View {
    @Bindable var editor: NameEditViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpacing.l) {
                    field(title: NameEditTexts.displayName) {
                        TextField(NameEditTexts.displayName, text: $editor.displayName)
                            .textContentType(.nickname)
                            .submitLabel(.next)
                    } footer: {
                        if let message = editor.displayNameMessage {
                            ProfileFootnote(text: message, isError: true)
                        }
                    }

                    field(title: NameEditTexts.username) {
                        HStack(spacing: 2) {
                            Text(verbatim: "@")
                                .foregroundStyle(PaceColor.textSecondary)
                            TextField(NameEditTexts.username, text: $editor.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .submitLabel(.done)
                        }
                    } footer: {
                        if let message = editor.usernameMessage {
                            ProfileFootnote(text: message, isError: isUsernameProblem)
                        }
                        ProfileFootnote(text: editor.usernameRulesHint)
                    }

                    if let error = editor.errorMessage {
                        ProfileFootnote(text: error, isError: true)
                    }
                }
                .padding(PaceSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .paceScreenBackground()
            .navigationTitle(PaceLocalization.text(de: "Namen ändern", en: "Change names", ru: "Изменить имена"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ProfileTexts.cancel) { dismiss() }
                        .disabled(editor.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if editor.isSaving {
                        ProgressView()
                    } else {
                        Button(ProfileTexts.save) {
                            Task { await editor.save() }
                        }
                        .disabled(!editor.canSave)
                    }
                }
            }
        }
        .interactiveDismissDisabled(editor.isSaving)
        .task(id: editor.username) { [editor] in
            await editor.checkUsernameAvailability()
        }
        .onChange(of: editor.didSave) { _, saved in
            if saved { dismiss() }
        }
    }

    private var isUsernameProblem: Bool {
        switch editor.usernameStatus {
        case .invalid, .taken: true
        case .empty, .unchanged, .checking, .available, .unchecked: false
        }
    }

    private func field<Field: View, Footer: View>(
        title: String,
        @ViewBuilder field: () -> Field,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            Text(title)
                .font(PaceFont.headline)
                .foregroundStyle(PaceColor.textPrimary)
            field()
                .font(.body)
                .padding(.horizontal, PaceSpacing.s)
                .frame(minHeight: 48)
                .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
            footer()
        }
    }
}
