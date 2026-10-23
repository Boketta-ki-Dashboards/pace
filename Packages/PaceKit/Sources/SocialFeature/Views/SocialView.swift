import DesignSystem
import PaceCore
import SwiftUI

/// Ziel einer Navigation im Social-Tab.
public enum SocialRoute: Hashable, Sendable {
    case group(UUID)
    /// Profil einer Person (gleich wie ``profile(_:)``; bleibt für bestehende Aufrufer erhalten).
    case friend(SocialProfile)
    case profile(SocialProfile)
    case addFriend
    case requests
    case createGroup
    case groups
    case groupMembers(UUID)
    case groupSettings(UUID)
    case friendsRanking
    case settings
    case shareProfile(SocialProfile)
    case report(SocialReportSubject)
}

/// Social-Tab (Referenzbild 9): Freunde, Anfragen, Gruppen und Chats mit allen Unterseiten.
public struct SocialView: View {
    @Bindable private var viewModel: SocialViewModel
    @State private var path = NavigationPath()

    public init(viewModel: SocialViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                SocialContent(
                    viewModel: viewModel,
                    onOpen: { path.append($0) },
                    onOpenChat: { path.append($0) }
                )
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.l)
                .paceTabRoot(isAtRoot: path.isEmpty) { path = NavigationPath() }
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { [viewModel] in
                await viewModel.load()
                await viewModel.chats.load()
            }
            .paceScreenBackground()
            .paceRootPage()
            .navigationDestination(for: SocialRoute.self) { route in
                SocialDestination(
                    route: route,
                    viewModel: viewModel,
                    onOpen: { path.append($0) },
                    onOpenChat: { path.append($0) },
                    onReplace: { route in
                        if !path.isEmpty { path.removeLast() }
                        path.append(route)
                    },
                    onPopToRoot: { path = NavigationPath() },
                    onReplaceWithChat: { target in
                        if !path.isEmpty { path.removeLast() }
                        path.append(target)
                    }
                )
            }
            .navigationDestination(for: ChatTarget.self) { target in
                ChatView(
                    viewModel: viewModel.chats.chat(for: target),
                    onOpenRoute: { path.append($0) },
                    onOpenProfile: { path.append(SocialRoute.profile($0)) }
                )
            }
        }
        .task { [viewModel] in
            await viewModel.loadIfNeeded()
            await viewModel.chats.loadIfNeeded()
        }
        .task(id: viewModel.requestedProfile) {
            await openRequestedProfile()
        }
        .task(id: viewModel.requestedGroup) {
            openRequestedGroup()
        }
    }

    /// Ein geteilter Link (`pace://u/<name>`): Profil öffnen oder auf der Hauptseite erklären, dass es fehlt.
    private func openRequestedProfile() async {
        guard viewModel.requestedProfile != nil else { return }
        let profile = await viewModel.resolveRequestedProfile()
        path = NavigationPath()
        if let profile {
            path.append(SocialRoute.profile(profile))
        }
    }

    /// Eine Gruppe von außen (z. B. aus einem Home-Widget).
    private func openRequestedGroup() {
        guard let groupID = viewModel.requestedGroup else { return }
        viewModel.clearRequestedGroup()
        path = NavigationPath()
        path.append(SocialRoute.group(groupID))
    }
}

/// Inhalt der Social-Hauptseite (ohne Navigation und Scrollen) – auch für Snapshot-Tests.
struct SocialContent: View {
    @Bindable var viewModel: SocialViewModel
    var onOpen: (SocialRoute) -> Void = { _ in }
    var onOpenChat: (ChatTarget) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            header
            actionButtons
            PaceSearchField(SocialText.searchFriendsAndChats, text: $viewModel.filterText)
                .disabled(!viewModel.isAvailable)
            if let notice = viewModel.notice {
                NoticeBanner(notice: notice) { viewModel.dismissNotice() }
            }
            switch viewModel.state {
            case .unavailable(let message):
                SocialUnavailableCard(message: message)
            case .failed(let message):
                SocialFailedCard(message: message) {
                    Task { await viewModel.load() }
                }
            case .idle, .loading:
                SocialLoadingCard(message: SocialText.loading)
            case .loaded:
                if viewModel.isFiltering {
                    searchResults
                } else {
                    topFriends
                    chats
                }
            }
        }
    }

    // MARK: Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
            HStack(alignment: .center, spacing: PaceSpacing.xs) {
                PaceWordmark(height: 33)
                Spacer()
                requestsButton
                Button {
                    onOpen(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.paceIcon)
                .accessibilityLabel(SocialText.socialSettings)
            }
            Text(SocialText.social)
                .font(.system(.title, weight: .bold))
                .foregroundStyle(PaceColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, PaceSpacing.xs)
    }

    /// Freundschaftsanfragen: gleicher Stil wie das Zahnrad, Zähler offener Anfragen als Badge.
    private var requestsButton: some View {
        Button {
            onOpen(.requests)
        } label: {
            Image(systemName: "person.crop.circle.badge.plus")
        }
        .buttonStyle(.paceIcon)
        .overlay(alignment: .topTrailing) {
            if viewModel.incomingRequests.count > 0 {
                PaceCountBadge(viewModel.incomingRequests.count)
                    .offset(x: 6, y: -6)
                    .allowsHitTesting(false)
            }
        }
        .disabled(!viewModel.isAvailable)
        .accessibilityLabel(SocialText.friendRequests)
        .accessibilityValue(viewModel.incomingRequests.isEmpty ? "" : SocialText.openRequests(viewModel.incomingRequests.count))
    }

    private var actionButtons: some View {
        HStack(spacing: PaceSpacing.s) {
            actionButton(SocialText.addFriend, systemImage: "person.badge.plus") { onOpen(.addFriend) }
            actionButton(SocialText.createGroup, systemImage: "person.3.fill") { onOpen(.createGroup) }
        }
        .disabled(!viewModel.isAvailable)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.paceSoft)
    }

    // MARK: Top-Freunde

    @ViewBuilder
    private var topFriends: some View {
        SocialSectionTitle(title: SocialText.topFriends) {
            if viewModel.hasFriends {
                Button {
                    onOpen(.friendsRanking)
                } label: {
                    HStack(spacing: 4) {
                        Text(SocialText.seeAll)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(PaceColor.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        if viewModel.topFriends.isEmpty {
            PaceCard {
                Text(SocialText.noFriendsYet)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(alignment: .top, spacing: PaceSpacing.xs) {
                ForEach(viewModel.topFriends) { entry in
                    TopFriendCard(entry: entry) {
                        onOpen(.profile(entry.socialProfile))
                    }
                }
                // Gleiche Breite wie bei drei Freunden, auch wenn es weniger sind.
                ForEach(viewModel.topFriends.count..<3, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Chats und Gruppen

    /// Chats direkt unter den Top-Freunden; „Meine Gruppen“ (mit Einladungen) als kompakter Link daneben.
    @ViewBuilder
    private var chats: some View {
        SocialSectionTitle(title: SocialText.chats) {
            Button {
                onOpen(.groups)
            } label: {
                HStack(spacing: 4) {
                    Text(SocialText.myGroups)
                    if !viewModel.invitations.isEmpty {
                        PaceCountBadge(viewModel.invitations.count)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(PaceColor.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(groupsAccessibilityValue)
        }
        ChatListSection(viewModel: viewModel.chats, onOpen: onOpenChat)
    }

    private var groupsAccessibilityValue: String {
        let groups = SocialText.groupCount(viewModel.groups.count)
        guard !viewModel.invitations.isEmpty else { return groups }
        return "\(groups), \(SocialText.openInvitations(viewModel.invitations.count))"
    }

    // MARK: Suche

    @ViewBuilder
    private var searchResults: some View {
        let friends = viewModel.matchingFriends
        let conversations = viewModel.matchingConversations
        if friends.isEmpty && conversations.isEmpty {
            PaceCard {
                Text(SocialText.noMatches(viewModel.normalizedFilter))
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if !friends.isEmpty {
            SocialSectionTitle(SocialText.friends)
            ForEach(friends) { friend in
                SocialPersonCard(profile: friend.profile, onOpenProfile: { onOpen(.profile(friend.profile)) }) {
                    Button {
                        onOpenChat(.direct(friend.profile))
                    } label: {
                        Image(systemName: "message")
                    }
                    .buttonStyle(.paceIcon)
                    .accessibilityLabel(SocialText.writeMessage)
                }
            }
        }
        if !conversations.isEmpty {
            SocialSectionTitle(SocialText.chats)
            ForEach(conversations) { conversation in
                ConversationMatchRow(conversation: conversation) {
                    onOpenChat(.conversation(id: conversation.id, kind: conversation.kind, title: conversation.shownTitle))
                }
            }
        }
    }
}

/// Karte eines Top-Freundes: Platz, Profilbild, Name, Schritte (Referenzbild 9).
private struct TopFriendCard: View {
    let entry: LeaderboardEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: PaceSpacing.xxs) {
                ZStack(alignment: .topLeading) {
                    PaceAvatar(name: entry.shownName, seed: entry.publicUserID.uuidString, size: 48, image: entry.avatar)
                        .frame(maxWidth: .infinity)
                    Text(verbatim: "#\(entry.rank.paceFormatted)")
                        .font(.system(.subheadline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.textPrimary)
                }
                Text(entry.shownName)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Image(systemName: "shoeprints.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(PaceColor.textSecondary)
                        .accessibilityHidden(true)
                    Text(entry.competitionSteps.paceFormatted)
                        .font(.system(.headline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(PaceSpacing.xs)
            .frame(maxWidth: .infinity)
            .paceCardBackground(cornerRadius: PaceRadius.tile)
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PaceLocalization.text(
            de: "Platz \(entry.rank.paceFormatted), \(entry.shownName)",
            en: "Rank \(entry.rank.paceFormatted), \(entry.shownName)",
            ru: "Место \(entry.rank.paceFormatted), \(entry.shownName)"
        ) + ", " + PaceLocalization.steps(entry.competitionSteps))
        .accessibilityAddTraits(.isButton)
    }
}

/// Treffer der Hauptseitensuche in den Chats (Name und Art der Unterhaltung).
private struct ConversationMatchRow: View {
    let conversation: ConversationSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                if let peer = conversation.peer {
                    PaceAvatar(name: peer.shownName, seed: peer.publicID.uuidString, size: 48, image: peer.avatar)
                } else {
                    GroupAvatar(name: conversation.shownTitle, kind: .friends, image: MediaReference.groupImage(conversation.groupImagePath), size: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.shownTitle)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                    Text(conversation.kind == .group ? SocialText.members(conversation.memberCount) : (conversation.peer.map { "@\($0.username)" } ?? ""))
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: PaceSpacing.xs)
                if conversation.unreadCount > 0 {
                    PaceCountBadge(conversation.unreadCount)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PaceSpacing.s)
            .padding(.vertical, PaceSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .paceCardBackground(cornerRadius: PaceRadius.tile)
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
