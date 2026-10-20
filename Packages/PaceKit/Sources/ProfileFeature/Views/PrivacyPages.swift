import DesignSystem
import PaceCore
import SwiftUI

// MARK: - Privatsphäre

/// Privatsphäre: regionale Rankings, Auffindbarkeit, Sichtbarkeit der Wettbewerbsdaten, blockierte Personen.
struct PrivacyPage: View {
    let viewModel: ProfileViewModel
    let backTitle: String

    var body: some View {
        ProfileSubpage {
            PrivacyPageContent(viewModel: viewModel, backTitle: backTitle)
        }
        .task { [privacy = viewModel.privacy] in await privacy.blockedUsers.load() }
    }
}

struct PrivacyPageContent: View {
    let viewModel: ProfileViewModel
    let backTitle: String

    private var privacy: PrivacySettingsViewModel { viewModel.privacy }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.privacy.title)
                .padding(.bottom, PaceSpacing.xs)

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(PaceLocalization.text(de: "Regionale Rankings", en: "Regional rankings", ru: "Региональные рейтинги"))
                    RankingVisibilityControl(viewModel: viewModel)
                }
            }

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(PaceLocalization.text(de: "Auffindbarkeit", en: "Discoverability", ru: "Поиск профиля"))
                    ProfileToggleTile(
                        title: PaceLocalization.text(
                            de: "In der Suche vorschlagen",
                            en: "Suggest me in search",
                            ru: "Показывать в поиске"
                        ),
                        isOn: privacy.discoverableToggleValue,
                        isHighlighted: privacy.isDiscoverable,
                        isDisabled: privacy.isUpdatingDiscoverable
                    ) { discoverable in
                        Task { await privacy.setDiscoverable(discoverable) }
                    }
                    if let error = privacy.discoverableError {
                        ProfileFootnote(text: error, isError: true)
                    }
                    ProfileFootnote(text: privacy.discoverableExplanation)
                }
            }

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(PaceLocalization.text(de: "Wer was sieht", en: "Who sees what", ru: "Кто что видит"))
                    ProfileNoteRow(systemImage: "person.2", text: PaceLocalization.text(
                        de: "Freunde und Mitglieder deiner Gruppen sehen deinen Namen, dein Profilbild und deine täglichen Wettbewerbsschritte – unabhängig von regionalen Rankings.",
                        en: "Friends and members of your groups see your name, profile picture and daily competition steps – regardless of regional rankings.",
                        ru: "Друзья и участники твоих групп видят твоё имя, фото профиля и ежедневные шаги для соревнований – независимо от региональных рейтингов."
                    ))
                    ProfileNoteRow(systemImage: "map", text: PaceLocalization.text(
                        de: "In regionalen Rankings erscheinst du nur, wenn du oben zustimmst.",
                        en: "You only appear in regional rankings if you agree above.",
                        ru: "В региональных рейтингах ты появляешься, только если дал согласие выше."
                    ))
                    ProfileNoteRow(systemImage: "heart.text.square", text: PaceLocalization.text(
                        de: "Andere Gesundheitsdaten verlassen dein iPhone nicht.",
                        en: "Other health data never leaves your iPhone.",
                        ru: "Другие данные о здоровье не покидают твой iPhone."
                    ))
                }
            }

            BlockedUsersCard(viewModel: privacy.blockedUsers)

            RequestsInfoCard(onOpenSocial: viewModel.openSocial)
        }
    }
}

// MARK: - Social-Einstellungen

/// Social-Einstellungen im Profil: Anfragen und Einladungen, blockierte Personen, Chats. Dieselben Bausteine und
/// Daten wie „Privatsphäre“ – keine zweite Logik.
struct SocialSettingsPage: View {
    let viewModel: ProfileViewModel
    let backTitle: String

    var body: some View {
        ProfileSubpage {
            SocialSettingsPageContent(viewModel: viewModel, backTitle: backTitle) { viewModel.open($0) }
        }
        .task { [privacy = viewModel.privacy] in await privacy.blockedUsers.load() }
    }
}

struct SocialSettingsPageContent: View {
    let viewModel: ProfileViewModel
    let backTitle: String
    var onOpen: (ProfileRoute) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.social.title)
                .padding(.bottom, PaceSpacing.xs)

            RequestsInfoCard(onOpenSocial: viewModel.openSocial)

            BlockedUsersCard(viewModel: viewModel.privacy.blockedUsers)

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(PaceLocalization.text(de: "Chats", en: "Chats", ru: "Чаты"))
                    ProfileNoteRow(systemImage: "bubble.left.and.bubble.right", text: PaceLocalization.text(
                        de: "Deine Chats findest du im Social-Tab. Ungelesene Nachrichten zeigt Pace dort und am Social-Tab an.",
                        en: "You'll find your chats in the Social tab. Pace shows unread messages there and on the Social tab.",
                        ru: "Твои чаты находятся во вкладке «Друзья». Непрочитанные сообщения Pace показывает там и на значке вкладки."
                    ))
                    ProfileNoteRow(systemImage: "bell.badge", text: viewModel.notifications.pushNotice)
                }
            }

            ProfileSettingsRow(
                systemImage: "magnifyingglass",
                title: PaceLocalization.text(de: "Auffindbarkeit", en: "Discoverability", ru: "Поиск профиля"),
                subtitle: PaceLocalization.text(
                    de: "Wer dich in der Suche findet",
                    en: "Who can find you in search",
                    ru: "Кто может найти тебя в поиске"
                )
            ) { onOpen(.privacy) }
        }
    }
}

// MARK: - Bausteine

/// Freundschaftsanfragen und Gruppeneinladungen werden im Social-Tab beantwortet – hier nur Erklärung und Weg dorthin.
struct RequestsInfoCard: View {
    let onOpenSocial: (@MainActor () -> Void)?

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(PaceLocalization.text(
                    de: "Anfragen & Einladungen",
                    en: "Requests & invitations",
                    ru: "Запросы и приглашения"
                ))
                ProfileNoteRow(systemImage: "person.badge.plus", text: PaceLocalization.text(
                    de: "Freundschaftsanfragen kann dir jeder senden, der deinen Benutzernamen kennt – blockierte Personen nicht. Du entscheidest im Social-Tab, ob du sie annimmst.",
                    en: "Anyone who knows your username can send you a friend request – except people you blocked. You decide in the Social tab whether to accept.",
                    ru: "Запрос в друзья может отправить любой, кто знает твоё имя пользователя, кроме заблокированных. Принять его или нет, решаешь ты во вкладке «Друзья»."
                ))
                ProfileNoteRow(systemImage: "person.3", text: PaceLocalization.text(
                    de: "Gruppeneinladungen erscheinen ebenfalls im Social-Tab. Du trittst einer Gruppe erst bei, wenn du annimmst.",
                    en: "Group invitations also appear in the Social tab. You only join a group once you accept.",
                    ru: "Приглашения в группы тоже появляются во вкладке «Друзья». Ты вступаешь в группу, только если примешь приглашение."
                ))
                if let onOpenSocial {
                    Button {
                        onOpenSocial()
                    } label: {
                        Label(ProfileTexts.openSocialTab, systemImage: "person.2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.paceSecondary)
                }
            }
        }
    }
}

/// Blockierte Personen mit „Aufheben“ – gemeinsam für Privatsphäre und Social-Einstellungen.
struct BlockedUsersCard: View {
    let viewModel: BlockedUsersViewModel

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(PaceLocalization.text(de: "Blockierte Personen", en: "Blocked people", ru: "Заблокированные"))
                content
                if let error = viewModel.actionError {
                    ProfileFootnote(text: error, isError: true)
                }
                ProfileFootnote(text: viewModel.explanation)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .unavailable:
            ProfileNoteRow(systemImage: "icloud.slash", text: viewModel.unavailableText)
        case .idle, .loading:
            if viewModel.users.isEmpty {
                HStack(spacing: PaceSpacing.xs) {
                    ProgressView()
                    Text(PaceLocalization.text(de: "Wird geladen …", en: "Loading …", ru: "Загрузка …"))
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                list
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                ProfileFootnote(text: message, isError: true)
                Button(ProfileTexts.retry) {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.paceOutline)
            }
        case .loaded:
            if viewModel.users.isEmpty {
                ProfileNoteRow(systemImage: "checkmark.circle", text: viewModel.emptyText)
            } else {
                list
            }
        }
    }

    private var list: some View {
        VStack(spacing: PaceSpacing.xs) {
            ForEach(viewModel.users) { user in
                PaceTile {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: PaceSpacing.s) {
                            identity(user)
                            Spacer(minLength: PaceSpacing.xs)
                            unblockButton(user)
                        }
                        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                            identity(user)
                            unblockButton(user)
                        }
                    }
                    .padding(.vertical, PaceSpacing.xxs)
                }
            }
        }
    }

    private func identity(_ user: SocialProfile) -> some View {
        HStack(spacing: PaceSpacing.s) {
            PaceAvatar(name: user.displayName, seed: user.publicID.uuidString, size: 40, image: MediaReference.avatar(user.avatarPath))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: user.displayName)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                Text(verbatim: "@\(user.username)")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func unblockButton(_ user: SocialProfile) -> some View {
        Button {
            Task { await viewModel.unblock(user) }
        } label: {
            if viewModel.busyIDs.contains(user.publicID) {
                ProgressView()
                    .frame(minWidth: 80)
            } else {
                Text(PaceLocalization.text(de: "Aufheben", en: "Unblock", ru: "Разблокировать"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.paceOutline)
        .fixedSize()
        .disabled(viewModel.busyIDs.contains(user.publicID))
        .accessibilityLabel(PaceLocalization.text(
            de: "Blockierung von \(user.displayName) aufheben",
            en: "Unblock \(user.displayName)",
            ru: "Разблокировать \(user.displayName)"
        ))
    }
}
