import DesignSystem
import PaceCore
import SwiftUI

/// Inhalt der Chatliste (Referenzbild 9): Filter Alle/Freunde/Gruppen und Zeilen – ohne Überschrift, Scrollen und
/// Aktualisierung; auch für Snapshot-Tests.
struct ChatListContent: View {
    @Bindable var viewModel: ChatListViewModel
    var onOpen: (ChatTarget) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            switch viewModel.state {
            case .unavailable(let message):
                ChatUnavailableCard(message: message)
            case .failed(let message):
                SocialFailedCard(message: message) { [viewModel] in
                    Task { await viewModel.load() }
                }
            case .idle, .loading:
                SocialLoadingCard(message: ChatUIText.loadingChats)
            case .loaded:
                loaded
            }
        }
    }

    @ViewBuilder
    private var loaded: some View {
        PaceSegmentedControl(
            options: ChatListViewModel.Filter.allCases.map { (value: $0, title: $0.title) },
            selection: $viewModel.filter
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ChatUIText.filterLabel)
        if let refreshError = viewModel.refreshError {
            ChatInlineError(message: refreshError) { [viewModel] in
                Task { await viewModel.load() }
            }
        }
        let rows = viewModel.filteredConversations
        if rows.isEmpty {
            SocialEmptyCard(
                systemImage: "bubble.left.and.bubble.right",
                title: ChatUIText.emptyTitle(viewModel.filter),
                message: ChatUIText.emptyMessage(viewModel.filter)
            )
        } else {
            VStack(spacing: 0) {
                ForEach(rows) { conversation in
                    ChatListRow(
                        conversation: conversation,
                        preview: ChatFormatting.preview(for: conversation),
                        timestamp: viewModel.timestamp(for: conversation),
                        accessibilityText: viewModel.accessibilityLabel(for: conversation)
                    ) {
                        onOpen(ChatTarget(conversation))
                    }
                    if conversation.id != rows.last?.id {
                        Rectangle()
                            .fill(PaceColor.border)
                            .frame(height: 1)
                            .padding(.leading, ChatListRow.avatarSize + PaceSpacing.s)
                    }
                }
            }
        }
    }
}

/// Zeile der Chatliste: Profil- bzw. Gruppenbild, Name, letzte Nachricht, Zeit, Ungelesen-Zähler, Pfeil.
struct ChatListRow: View {
    static let avatarSize: CGFloat = 52

    let conversation: ConversationSummary
    let preview: String
    let timestamp: String
    let accessibilityText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                ChatConversationAvatar(conversation: conversation, size: Self.avatarSize)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
                        Text(conversation.shownTitle)
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: PaceSpacing.xs)
                        Text(timestamp)
                            .font(PaceFont.caption)
                            .monospacedDigit()
                            .foregroundStyle(PaceColor.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    HStack(alignment: .center, spacing: PaceSpacing.xs) {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(PaceColor.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: PaceSpacing.xs)
                        if conversation.unreadCount > 0 {
                            PaceCountBadge(conversation.unreadCount)
                        }
                    }
                }
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
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }
}

/// Profilbild des Freundes bzw. Gruppenbild; ohne Gruppenbild ein Gruppen-Symbol auf Mint (Referenzbild 9).
struct ChatConversationAvatar: View {
    let conversation: ConversationSummary
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch conversation.kind {
        case .direct:
            if let peer = conversation.peer {
                PaceAvatar(name: peer.shownName, seed: peer.publicID.uuidString, size: size, image: peer.avatar)
            } else {
                PaceAvatar(name: conversation.shownTitle, seed: conversation.id.uuidString, size: size)
            }
        case .group:
            if let image = conversation.image {
                PaceAvatar(name: conversation.shownTitle, seed: conversation.id.uuidString, size: size, image: image)
            } else {
                Image(systemName: "person.3.fill")
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? PaceColor.accent : PaceColor.onSelection)
                    .frame(width: size, height: size)
                    .background(colorScheme == .dark ? PaceColor.accentSoft : PaceColor.selectionFill, in: Circle())
                    .overlay(Circle().strokeBorder(PaceColor.accent.opacity(colorScheme == .dark ? 0.35 : 0), lineWidth: 1))
                    .accessibilityHidden(true)
            }
        }
    }
}
