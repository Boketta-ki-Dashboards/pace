import DesignSystem
import PaceCore
import SwiftUI

/// Eigene Favoriten eines Chats (nur für dich sichtbar). Antippen springt zur Nachricht im Verlauf.
struct ChatFavoritesSheet: View {
    let viewModel: ChatViewModel
    let onOpen: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    content
                }
                .padding(PaceSpacing.m)
                .paceVerticalScrollLock()
            }
            .scrollIndicators(.hidden)
            .paceScreenBackground()
            .navigationTitle(ChatUIText.favorites)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ChatUIText.done) { dismiss() }
                }
            }
            .refreshable { [viewModel] in await viewModel.loadFavorites() }
        }
        .presentationDetents([.medium, .large])
        .task { [viewModel] in await viewModel.loadFavorites() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.favorites {
        case .idle, .loading:
            SocialLoadingCard(message: ChatUIText.favorites)
        case .failed(let message):
            SocialFailedCard(message: message) { [viewModel] in
                Task { await viewModel.loadFavorites() }
            }
        case .loaded(let messages) where messages.isEmpty:
            SocialEmptyCard(systemImage: "star", title: ChatUIText.favorites, message: ChatUIText.favoritesEmpty)
        case .loaded(let messages):
            Text(ChatUIText.favoritesPrivacy)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
            ForEach(messages) { message in
                row(message)
            }
        }
    }

    private func row(_ message: ChatMessage) -> some View {
        Button {
            onOpen(message.id)
        } label: {
            HStack(alignment: .top, spacing: PaceSpacing.s) {
                Image(systemName: "star.fill")
                    .font(.footnote)
                    .foregroundStyle(PaceColor.accent)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: PaceSpacing.xs) {
                        Text(viewModel.replyAuthor(of: message))
                            .font(PaceFont.caption.weight(.semibold))
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(viewModel.listTimestamp(of: message.sentAt))
                            .font(PaceFont.caption)
                            .monospacedDigit()
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    Text(ChatReplySnippet.text(for: message))
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(PaceSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paceCardBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .accessibilityHint(ChatUIText.pinnedBannerHint)
        .contextMenu {
            Button {
                Task { [viewModel] in await viewModel.toggleFavorite(message) }
            } label: {
                Label(ChatUIText.unfavorite, systemImage: "star.slash")
            }
        }
    }
}
