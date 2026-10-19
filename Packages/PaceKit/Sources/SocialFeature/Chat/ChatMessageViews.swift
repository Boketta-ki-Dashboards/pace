import DesignSystem
import PaceCore
import SwiftUI
import UIKit

/// Verlauf: ältere Nachrichten nachladen, Tages-Trenner und Nachrichten (Referenzbild 5).
struct ChatTimelineView: View {
    let viewModel: ChatViewModel
    let actions: ChatActions
    var isLazy = true

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            olderMessages
            let items = viewModel.timeline
            if items.isEmpty {
                Text(ChatUIText.emptyConversation)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PaceSpacing.xl)
            } else if isLazy {
                LazyVStack(alignment: .leading, spacing: PaceSpacing.xs) {
                    rows(items)
                }
            } else {
                VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                    rows(items)
                }
            }
        }
    }

    @ViewBuilder
    private var olderMessages: some View {
        if viewModel.isLoadingOlder {
            HStack(spacing: PaceSpacing.xs) {
                ProgressView()
                Text(ChatUIText.loadingOlder)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PaceSpacing.xs)
        } else if viewModel.olderError != nil {
            Button(ChatUIText.loadOlder, action: actions.loadOlder)
                .buttonStyle(.paceCompact)
                .frame(maxWidth: .infinity)
        } else if viewModel.hasOlderMessages {
            // Erscheint beim Hochscrollen am Anfang des Verlaufs und lädt die nächste ältere Seite.
            Color.clear
                .frame(height: 1)
                .onAppear(perform: actions.loadOlder)
                .accessibilityHidden(true)
        }
    }

    private func rows(_ items: [ChatTimelineItem]) -> some View {
        ForEach(items) { item in
            switch item {
            case .day(_, let title):
                ChatDaySeparator(title: title)
                    .id(item.id)
            case .entry(let entry):
                ChatEntryRow(entry: entry, viewModel: viewModel, actions: actions)
                    .id(item.id)
            }
        }
    }
}

/// „——— Heute ———“
struct ChatDaySeparator: View {
    let title: String

    var body: some View {
        HStack(spacing: PaceSpacing.s) {
            line
            Text(title)
                .font(.subheadline)
                .foregroundStyle(PaceColor.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)
            line
        }
        .padding(.vertical, PaceSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var line: some View {
        Rectangle()
            .fill(PaceColor.border)
            .frame(height: 1)
    }
}

// MARK: - Zeile

/// Eine Nachricht: fremde links (in Gruppen mit Profilbild und Name), eigene rechts.
struct ChatEntryRow: View {
    let entry: ChatTimelineEntry
    let viewModel: ChatViewModel
    let actions: ChatActions

    private static let avatarSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: PaceSpacing.s) {
            if entry.isOwn {
                Spacer(minLength: 56)
                VStack(alignment: .trailing, spacing: 4) {
                    content
                    footer
                }
            } else {
                if viewModel.kind == .group {
                    leadingAvatar
                }
                VStack(alignment: .leading, spacing: 4) {
                    if entry.showsSender {
                        Text(senderName)
                            .font(.subheadline)
                            .foregroundStyle(PaceColor.textSecondary)
                            .lineLimit(1)
                            .padding(.leading, PaceSpacing.xxs)
                            .accessibilityHidden(true)
                    }
                    content
                    footer
                }
                Spacer(minLength: 40)
            }
        }
        .padding(.top, entry.showsSender ? PaceSpacing.xs : 0)
    }

    private var senderName: String {
        entry.sender?.displayName ?? ChatFormatting.deletedAccount
    }

    @ViewBuilder
    private var leadingAvatar: some View {
        if entry.showsSender, let sender = entry.sender {
            Button {
                actions.openProfile(sender)
            } label: {
                PaceAvatar(name: sender.displayName, seed: sender.publicID.uuidString, size: Self.avatarSize, image: sender.avatar)
            }
            .buttonStyle(.pacePressable)
            .accessibilityLabel(sender.displayName)
            .accessibilityHint(ChatUIText.viewProfile)
        } else if entry.showsSender {
            PaceAvatar(name: senderName, seed: senderName, size: Self.avatarSize)
        } else {
            Color.clear
                .frame(width: Self.avatarSize, height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .message(let message):
            ChatMessageContent(message: message, viewModel: viewModel, actions: actions)
        case .pending(let pending):
            ChatPendingContent(pending: pending)
        case .blocked(let message):
            ChatBlockedContent { actions.reveal(message.id) }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch entry.content {
        case .message:
            if entry.showsTime {
                Text(viewModel.time(of: entry.sentAt))
                    .font(PaceFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textSecondary)
                    .padding(.horizontal, PaceSpacing.xxs)
                    .accessibilityHidden(true)
            }
        case .pending(let pending):
            ChatPendingStatus(pending: pending, actions: actions)
        case .blocked:
            EmptyView()
        }
    }
}

// MARK: - Inhalte

/// Text, Bild, GIF oder geteiltes Profil – mit Kontextmenü (Kopieren, Melden, Blockieren, Löschen).
struct ChatMessageContent: View {
    let message: ChatMessage
    let viewModel: ChatViewModel
    let actions: ChatActions

    var body: some View {
        VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 4) {
            switch message.kind {
            case .text:
                ChatTextBubble(text: message.text ?? "", isOwn: message.isOwn)
            case .image, .gif:
                media
                if let caption = message.text, !caption.isEmpty {
                    ChatTextBubble(text: caption, isOwn: message.isOwn)
                }
            case .profile:
                if let profile = message.sharedProfile {
                    ChatProfileCard(profile: profile) { actions.openProfile(profile) }
                } else {
                    ChatTextBubble(text: ChatUIText.profileUnavailable, isOwn: message.isOwn, isPlaceholder: true)
                }
            }
        }
        .opacity(viewModel.busyMessageIDs.contains(message.id) ? 0.5 : 1)
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityActions { accessibilityMenu }
    }

    @ViewBuilder
    private var media: some View {
        let isGIF = message.kind == .gif
        let label = isGIF ? ChatUIText.gif(from: message.isOwn ? nil : message.sender?.displayName) : ChatUIText.photo(from: message.isOwn ? nil : message.sender?.displayName)
        ChatMediaBubble(
            reference: message.media,
            localData: message.media.flatMap { viewModel.uploadedData(for: $0) },
            isGIF: isGIF,
            accessibilityText: label,
            onOpen: { reference in
                actions.openMedia(ChatViewerItem(reference: reference, isGIF: isGIF, label: label))
            }
        )
    }

    private var accessibilityText: String {
        let sender = message.isOwn ? nil : (message.sender?.displayName ?? ChatFormatting.deletedAccount)
        let description: String
        switch message.kind {
        case .text:
            description = message.text ?? ""
        case .image, .gif:
            description = ChatFormatting.content(kind: message.kind, text: nil) + (message.text.map { ", " + $0 } ?? "")
        case .profile:
            description = message.sharedProfile.map { ChatUIText.sharedProfileAccessibility(name: $0.displayName, username: $0.username) }
                ?? ChatUIText.profileUnavailable
        }
        return ChatUIText.messageAccessibility(sender: sender, content: description, time: viewModel.time(of: message.sentAt))
    }

    @ViewBuilder
    private var menu: some View {
        if let text = message.text, !text.isEmpty {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label(ChatUIText.copy, systemImage: "doc.on.doc")
            }
        }
        if message.isOwn {
            Button(role: .destructive) {
                actions.confirm(.delete(message))
            } label: {
                Label(ChatUIText.delete, systemImage: "trash")
            }
        } else {
            if let sender = message.sender {
                Button {
                    actions.openProfile(sender)
                } label: {
                    Label(ChatUIText.viewProfile, systemImage: "person.crop.circle")
                }
            }
            Button {
                actions.confirm(.report(.message(message)))
            } label: {
                Label(ChatUIText.reportMessage, systemImage: "exclamationmark.bubble")
            }
            if viewModel.kind == .group, let sender = message.sender, !viewModel.blockedUserIDs.contains(sender.publicID) {
                Button(role: .destructive) {
                    actions.confirm(.block(sender))
                } label: {
                    Label(ChatUIText.blockPerson, systemImage: "hand.raised")
                }
            }
        }
    }

    @ViewBuilder
    private var accessibilityMenu: some View {
        if message.isOwn {
            Button(ChatUIText.delete) {
                actions.confirm(.delete(message))
            }
        } else {
            Button(ChatUIText.reportMessage) {
                actions.confirm(.report(.message(message)))
            }
            if let sender = message.sender {
                Button(ChatUIText.viewProfile) {
                    actions.openProfile(sender)
                }
            }
        }
    }
}

/// Sprechblase: fremde hellgrau, eigene mint (Referenzbild 5).
struct ChatTextBubble: View {
    let text: String
    let isOwn: Bool
    var isPlaceholder = false

    var body: some View {
        Text(text)
            .font(.body)
            .italic(isPlaceholder)
            .foregroundStyle(isOwn ? PaceColor.onSelection : (isPlaceholder ? PaceColor.textSecondary : PaceColor.textPrimary))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isOwn ? PaceColor.selectionFill : PaceColor.fieldBackground,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}

/// Geteiltes Profil als antippbare Karte (Profilbild, Anzeigename, @Benutzername).
struct ChatProfileCard: View {
    let profile: SocialProfile
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                PaceAvatar(name: profile.displayName, seed: profile.publicID.uuidString, size: 44, image: profile.avatar)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ChatUIText.sharedProfile)
                        .font(PaceFont.micro)
                        .foregroundStyle(PaceColor.textSecondary)
                    Text(profile.displayName)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                    Text(verbatim: "@\(profile.username)")
                        .font(.subheadline)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: PaceSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
            }
            .padding(PaceSpacing.s)
            .frame(maxWidth: 260, alignment: .leading)
            .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
        }
        .buttonStyle(.pacePressable)
    }
}

/// Eingeklappte Nachricht einer blockierten Person.
struct ChatBlockedContent: View {
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: PaceSpacing.xs) {
            Image(systemName: "eye.slash")
                .foregroundStyle(PaceColor.textSecondary)
                .accessibilityHidden(true)
            Text(ChatUIText.blockedMessage)
                .font(.subheadline)
                .italic()
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(ChatUIText.show, action: onReveal)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PaceColor.accent)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 14)
        .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ausstehende Nachrichten

/// Eigene Nachricht, die noch gesendet wird (oder fehlgeschlagen ist).
struct ChatPendingContent: View {
    let pending: PendingChatMessage

    var body: some View {
        Group {
            switch pending.kind {
            case .image, .gif:
                ChatMediaBubble(
                    reference: nil,
                    localData: pending.localMedia?.data,
                    isGIF: pending.kind == .gif,
                    accessibilityText: pending.kind == .gif ? ChatUIText.gif(from: nil) : ChatUIText.photo(from: nil),
                    isUploading: pending.status == .uploading
                )
            case .text, .profile:
                ChatTextBubble(text: pending.text ?? "", isOwn: true)
            }
        }
        .opacity(pending.isFailed ? 0.6 : 0.85)
    }
}

/// Status unter einer ausstehenden Nachricht: „Wird gesendet …“ bzw. „Nicht gesendet“ mit „Erneut senden“.
struct ChatPendingStatus: View {
    let pending: PendingChatMessage
    let actions: ChatActions

    var body: some View {
        switch pending.status {
        case .uploading, .sending:
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text(pending.status == .uploading ? ChatUIText.uploading : ChatUIText.sending)
            }
            .font(PaceFont.caption)
            .foregroundStyle(PaceColor.textSecondary)
            .padding(.horizontal, PaceSpacing.xxs)
        case .failed(let reason):
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(PaceColor.danger)
                        .accessibilityHidden(true)
                    Text(ChatUIText.notSent)
                        .foregroundStyle(PaceColor.danger)
                }
                .font(PaceFont.caption.weight(.semibold))
                Text(reason)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: PaceSpacing.xs) {
                    Button(ChatUIText.discard) {
                        actions.discard(pending.clientID)
                    }
                    .buttonStyle(.paceOutline)
                    .fixedSize()
                    Button(ChatUIText.sendAgain) {
                        actions.retry(pending.clientID)
                    }
                    .buttonStyle(.paceCompact)
                    .fixedSize()
                }
            }
            .padding(.horizontal, PaceSpacing.xxs)
        }
    }
}
