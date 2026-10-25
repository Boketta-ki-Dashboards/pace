import DesignSystem
import PaceCore
import SwiftUI

/// Bild oder GIF, das im Vollbild geöffnet wird.
struct ChatViewerItem: Identifiable {
    let reference: MediaReference
    let isGIF: Bool
    /// VoiceOver-Beschreibung („Foto von Marie“).
    let label: String

    var id: String { "\(reference.bucket.rawValue)/\(reference.path)" }
}

/// Was gemeldet wird: eine einzelne Nachricht oder die ganze Unterhaltung (Person bzw. Gruppe).
enum ChatReportSubject {
    case message(ChatMessage)
    case conversation
}

/// Rückfrage vor einer Aktion.
enum ChatDialog {
    case delete(ChatMessage)
    case block(SocialProfile)
    case report(ChatReportSubject)
}

/// Aktionen aus dem Chat-Inhalt heraus; der Rahmen (``ChatView``) verbindet sie mit ViewModel, Navigation und Dialogen.
struct ChatActions {
    /// Öffnet eine Social-Seite (über den Navigator des Social-Tabs).
    var openRoute: (SocialRoute) -> Void = { _ in }
    var openProfile: (SocialProfile) -> Void = { _ in }
    var openMedia: (ChatViewerItem) -> Void = { _ in }
    var loadOlder: () -> Void = {}
    var retryLoad: () -> Void = {}
    var refresh: () -> Void = {}
    var retry: (UUID) -> Void = { _ in }
    var discard: (UUID) -> Void = { _ in }
    var reveal: (UUID) -> Void = { _ in }
    var dismissNotice: () -> Void = {}
    var confirm: (ChatDialog) -> Void = { _ in }
    /// Antworten, Kopieren, Bearbeiten, Favorit, Anpinnen aus dem Kontextmenü.
    var messageAction: (ChatMessageAction, ChatMessage) -> Void = { _, _ in }
    /// Zur ursprünglichen Nachricht springen (Antwort-Verweis).
    var jumpTo: (UUID) -> Void = { _ in }
    /// Eigene Favoriten dieses Chats zeigen.
    var openFavorites: () -> Void = {}
}

/// Inhalt eines Chats (Referenzbild 5) ohne Scrollen und Eingabeleiste: Kopf, Gruppen- bzw. Profilkopf, Hinweise und
/// Verlauf – für Snapshot-Tests. In der App steht der Kopf fest über dem scrollbaren ``ChatBody``.
struct ChatContent: View {
    let viewModel: ChatViewModel
    /// Ziel des Zurück-Links; ohne Angabe „Social“.
    var backTitle: String?
    var actions = ChatActions()
    /// Nachrichten in einem `LazyVStack` (in der App); für Snapshots alle sofort.
    var isLazy = true

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            ChatTitleBar(viewModel: viewModel, backTitle: backTitle ?? SocialText.social, actions: actions)
            ChatGroupBar(viewModel: viewModel, actions: actions)
            ChatBody(viewModel: viewModel, actions: actions, isLazy: isLazy)
        }
    }
}

/// Scrollbarer Teil eines Chats: Gruppen- bzw. Profilkopf, Hinweise, Zustände und Verlauf.
struct ChatBody: View {
    let viewModel: ChatViewModel
    var actions = ChatActions()
    var isLazy = true

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            ChatInfoHeader(viewModel: viewModel, actions: actions)
            if let notice = viewModel.notice {
                NoticeBanner(notice: SocialViewModel.Notice(text: notice.text, isError: notice.isError), onDismiss: actions.dismissNotice)
            }
            switch viewModel.state {
            case .unavailable(let message):
                ChatUnavailableCard(message: message)
            case .failed(let message):
                SocialFailedCard(message: message, onRetry: actions.retryLoad)
            case .idle, .loading:
                SocialLoadingCard(message: ChatUIText.loadingMessages)
            case .loaded:
                if let refreshError = viewModel.refreshError {
                    ChatInlineError(message: refreshError, onRetry: actions.refresh)
                }
                ChatTimelineView(viewModel: viewModel, actions: actions, isLazy: isLazy)
            }
        }
    }
}

// MARK: - Kopf

/// Fester Kopf eines Chats: „‹ Social“ oben links, Wortmarke mit Info und Einstellungen, Name des Chats.
struct ChatTitleBar: View {
    let viewModel: ChatViewModel
    let backTitle: String
    let actions: ChatActions

    var body: some View {
        PaceSubpageHeader(backTitle: backTitle, title: viewModel.title) {
            HStack(spacing: PaceSpacing.xs) {
                if viewModel.state == .loaded {
                    Button(action: actions.openFavorites) {
                        Image(systemName: "star")
                    }
                    .buttonStyle(.paceIcon)
                    .accessibilityLabel(ChatUIText.favorites)
                }
                infoButton
                settingsButton
            }
        }
    }

    @ViewBuilder
    private var infoButton: some View {
        if viewModel.kind == .group, let groupID = viewModel.groupID {
            ChatRouteLink(route: .group(groupID), openRoute: actions.openRoute) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.paceIcon)
            .accessibilityLabel(ChatUIText.groupDetails)
        } else if let peer = viewModel.peer {
            Button {
                actions.openProfile(peer)
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.paceIcon)
            .accessibilityLabel(ChatUIText.viewProfile)
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if viewModel.kind == .group, let groupID = viewModel.groupID {
            ChatRouteLink(route: .groupSettings(groupID), openRoute: actions.openRoute) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.paceIcon)
            .accessibilityLabel(ChatUIText.groupSettings)
        } else if let peer = viewModel.peer {
            Menu {
                Button {
                    actions.openProfile(peer)
                } label: {
                    Label(ChatUIText.viewProfile, systemImage: "person.crop.circle")
                }
                Button {
                    actions.confirm(.report(.conversation))
                } label: {
                    Label(ChatUIText.reportPerson, systemImage: "exclamationmark.bubble")
                }
                if !viewModel.blockedUserIDs.contains(peer.publicID) {
                    Button(role: .destructive) {
                        actions.confirm(.block(peer))
                    } label: {
                        Label(ChatUIText.blockPerson, systemImage: "hand.raised")
                    }
                }
            } label: {
                ChatIconLabel(systemImage: "gearshape")
            }
            .accessibilityLabel(ChatUIText.chatOptions)
        }
    }
}

/// Profilkopf im Privatchat (scrollt mit dem Verlauf). Gruppen haben stattdessen die feste ``ChatGroupBar``.
struct ChatInfoHeader: View {
    let viewModel: ChatViewModel
    let actions: ChatActions

    var body: some View {
        if viewModel.kind != .group, let peer = viewModel.peer {
            ChatPeerCard(profile: peer) { actions.openProfile(peer) }
        }
    }
}

/// Feste Leiste unter dem Kopf eines Gruppenchats (scrollt nicht mit): links echte Mitgliederbilder, Anzahl und „+“,
/// rechts nur Flamme und Zahl.
///
/// Antippen: Bilder bzw. Anzahl → Mitglieder (mit Profilen), „+“ → Mitglieder einladen, Flamme → Gruppenkalender –
/// jeweils über den Navigator des Social-Tabs, damit keine Seite doppelt aufgelegt wird.
struct ChatGroupBar: View {
    let viewModel: ChatViewModel
    let actions: ChatActions

    /// Höchstens so viele Bilder überlappend; der Rest steckt in der Anzahl.
    static let shownAvatars = 4

    var body: some View {
        if viewModel.kind == .group, let groupID = viewModel.groupID {
            HStack(spacing: PaceSpacing.xs) {
                ChatRouteLink(route: .groupMembers(groupID), openRoute: actions.openRoute) {
                    HStack(spacing: PaceSpacing.xs) {
                        if !avatars.isEmpty {
                            HStack(spacing: -10) {
                                ForEach(avatars) { member in
                                    PaceAvatar(name: member.shownName, seed: member.publicID.uuidString, size: 30, image: member.avatar)
                                        .padding(2)
                                        .background(Circle().fill(PaceColor.background))
                                }
                            }
                        }
                        Text(ChatFormatting.members(viewModel.memberCount))
                            .font(PaceFont.callout.weight(.semibold))
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ChatFormatting.members(viewModel.memberCount))
                .accessibilityHint(ChatUIText.showMembers)

                if viewModel.canInvite {
                    ChatRouteLink(route: .groupMembers(groupID), openRoute: actions.openRoute) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PaceColor.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(PaceColor.fieldBackground, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pacePressable)
                    .accessibilityLabel(ChatUIText.inviteMembers)
                }

                Spacer(minLength: PaceSpacing.xs)

                if let group = viewModel.group {
                    let progress = GroupDayProgress(group: group)
                    ChatRouteLink(route: .groupCalendar(groupID), openRoute: actions.openRoute) {
                        GroupFlameCount(progress: progress)
                            .padding(.horizontal, PaceSpacing.xs)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pacePressable)
                    .accessibilityLabel(ChatUIText.groupFlameAccessibility(days: group.currentStreak))
                    .accessibilityHint(PaceLocalization.text(
                        de: "Öffnet den Gruppenkalender", en: "Opens the group calendar", ru: "Открывает календарь группы"
                    ))
                }
            }
        }
    }

    private var avatars: [SocialProfile] {
        Array(viewModel.memberPreview.prefix(Self.shownAvatars))
    }
}

/// Öffnet eine Social-Seite über den Navigator des Social-Tabs (nie per `NavigationLink(value:)`, damit eine schon offene
/// Seite – z. B. die Gruppe hinter der Flamme – nicht erneut aufgelegt wird).
struct ChatRouteLink<Content: View>: View {
    let route: SocialRoute
    let openRoute: (SocialRoute) -> Void
    @ViewBuilder let label: () -> Content

    var body: some View {
        Button {
            openRoute(route)
        } label: {
            label()
        }
    }
}

/// Symbol im Stil von `.paceIcon` – für `Menu`, das keinen Button-Stil übernimmt.
struct ChatIconLabel: View {
    let systemImage: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? PaceColor.accent : PaceColor.onSelection)
            .frame(width: 44, height: 44)
            .background(colorScheme == .dark ? PaceColor.accentSoft : PaceColor.selectionFill, in: shape)
            .overlay(shape.strokeBorder(PaceColor.accent.opacity(colorScheme == .dark ? 0.3 : 0), lineWidth: 1))
            .contentShape(shape)
    }
}

/// Profil-Kopf im Privatchat: Profilbild, @Benutzername, „Profil ansehen“.
struct ChatPeerCard: View {
    let profile: SocialProfile
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                PaceAvatar(name: profile.shownName, seed: profile.publicID.uuidString, size: 44, image: profile.avatar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "@\(profile.username)")
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                    Text(ChatUIText.viewProfile)
                        .font(.subheadline)
                        .foregroundStyle(PaceColor.accent)
                }
                Spacer(minLength: PaceSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PaceColor.textPrimary)
            }
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paceCardBackground(cornerRadius: PaceRadius.tile)
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.shownName + ", @" + profile.username)
        .accessibilityHint(ChatUIText.viewProfile)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Zustände

/// Gestalteter Hinweis, wenn Chats ohne Backend nicht verfügbar sind.
struct ChatUnavailableCard: View {
    let message: String

    var body: some View {
        PaceCard {
            HStack(alignment: .top, spacing: PaceSpacing.m) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title2)
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 52, height: 52)
                    .background(PaceColor.accentSoft, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                    Text(ChatUIText.unavailableTitle)
                        .font(PaceFont.cardTitle)
                        .foregroundStyle(PaceColor.textPrimary)
                    Text(message)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fehler beim Aktualisieren – der bisherige Stand bleibt sichtbar.
struct ChatInlineError: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: PaceSpacing.s) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(PaceColor.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: PaceSpacing.xs)
            Button(SocialText.retry, action: onRetry)
                .buttonStyle(.paceCompact)
                .fixedSize()
        }
        .padding(PaceSpacing.s)
        .background(PaceColor.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
    }
}
