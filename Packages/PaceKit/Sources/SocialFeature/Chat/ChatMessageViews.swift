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
        let items = viewModel.timeline
        if items.isEmpty {
            Text(ChatUIText.emptyConversation)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PaceSpacing.xl)
        } else if isLazy {
            // Lazy: Der Auslöser für ältere Nachrichten erscheint erst, wenn man an den Anfang scrollt.
            LazyVStack(alignment: .leading, spacing: PaceSpacing.xs) {
                olderMessages
                rows(items)
            }
        } else {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                olderMessages
                rows(items)
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
        entry.sender?.shownName ?? ChatFormatting.deletedAccount
    }

    @ViewBuilder
    private var leadingAvatar: some View {
        if entry.showsSender, let sender = entry.sender {
            Button {
                actions.openProfile(sender)
            } label: {
                PaceAvatar(name: sender.shownName, seed: sender.publicID.uuidString, size: Self.avatarSize, image: sender.avatar)
            }
            .buttonStyle(.pacePressable)
            .accessibilityLabel(sender.shownName)
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
            ChatPendingContent(pending: pending, replyAuthor: pending.replyTo.map { viewModel.replyAuthor(of: $0) })
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

/// Text, Bild, GIF, geteiltes Profil oder Sprachnachricht – mit Antwort-Verweis, Kennzeichen (angepinnt, Favorit,
/// bearbeitet) und Kontextmenü (nur mögliche Aktionen).
struct ChatMessageContent: View {
    let message: ChatMessage
    let viewModel: ChatViewModel
    let actions: ChatActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHighlighted: Bool {
        viewModel.jumpRequest?.messageID == message.id
    }

    var body: some View {
        VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 4) {
            if let reply = message.replyPreview {
                ChatReplyReference(
                    author: viewModel.replyAuthor(of: reply),
                    preview: reply,
                    isOwn: message.isOwn,
                    onTap: reply.isDeleted ? nil : { actions.jumpTo(reply.id) }
                )
            }
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
            case .voice:
                ChatVoiceBubble(
                    id: message.id,
                    duration: message.mediaDuration,
                    isOwn: message.isOwn,
                    load: { [viewModel, message] in await viewModel.voiceData(for: message) }
                )
            }
            if message.isPinned || message.isFavorite || message.isEdited {
                ChatMessageMarks(isPinned: message.isPinned, isFavorite: message.isFavorite, isEdited: message.isEdited)
            }
        }
        .padding(isHighlighted ? 4 : 0)
        .background(
            PaceColor.accent.opacity(isHighlighted ? 0.18 : 0),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isHighlighted)
        .opacity(viewModel.busyMessageIDs.contains(message.id) ? 0.5 : 1)
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityActions { accessibilityMenu }
    }

    @ViewBuilder
    private var media: some View {
        let isGIF = message.kind == .gif
        let label = isGIF ? ChatUIText.gif(from: message.isOwn ? nil : message.sender?.shownName) : ChatUIText.photo(from: message.isOwn ? nil : message.sender?.shownName)
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
        let sender = message.isOwn ? nil : (message.sender?.shownName ?? ChatFormatting.deletedAccount)
        let description: String
        switch message.kind {
        case .text:
            description = message.text ?? ""
        case .image, .gif:
            description = ChatFormatting.content(kind: message.kind, text: nil) + (message.text.map { ", " + $0 } ?? "")
        case .profile:
            description = message.sharedProfile.map { ChatUIText.sharedProfileAccessibility(name: $0.shownName, username: $0.username) }
                ?? ChatUIText.profileUnavailable
        case .voice:
            description = ChatFormatting.content(kind: .voice, text: nil, duration: message.mediaDuration)
        }
        var content = description
        if let reply = message.replyPreview {
            content = ChatUIText.replyingTo(viewModel.replyAuthor(of: reply)) + ". " + content
        }
        if message.isEdited { content += ", " + ChatUIText.edited }
        if message.isPinned { content += ", " + ChatUIText.pinnedLabel }
        if message.isFavorite { content += ", " + ChatUIText.favoriteLabel }
        return ChatUIText.messageAccessibility(sender: sender, content: content, time: viewModel.time(of: message.sentAt))
    }

    @ViewBuilder
    private var menu: some View {
        ForEach(viewModel.actions(for: message), id: \.self) { action in
            Button {
                actions.messageAction(action, message)
            } label: {
                Label(Self.title(of: action), systemImage: Self.icon(of: action))
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

    static func title(of action: ChatMessageAction) -> String {
        switch action {
        case .reply: ChatUIText.reply
        case .copy: ChatUIText.copy
        case .edit: ChatUIText.edit
        case .favorite: ChatUIText.favorite
        case .unfavorite: ChatUIText.unfavorite
        case .pin: ChatUIText.pin
        case .unpin: ChatUIText.unpin
        }
    }

    static func icon(of action: ChatMessageAction) -> String {
        switch action {
        case .reply: "arrowshape.turn.up.left"
        case .copy: "doc.on.doc"
        case .edit: "pencil"
        case .favorite: "star"
        case .unfavorite: "star.slash"
        case .pin: "pin"
        case .unpin: "pin.slash"
        }
    }

    @ViewBuilder
    private var accessibilityMenu: some View {
        if let reply = message.replyPreview, !reply.isDeleted {
            Button(ChatUIText.jumpToOriginal) {
                actions.jumpTo(reply.id)
            }
        }
        ForEach(viewModel.actions(for: message), id: \.self) { action in
            Button(Self.title(of: action)) {
                actions.messageAction(action, message)
            }
        }
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
                PaceAvatar(name: profile.shownName, seed: profile.publicID.uuidString, size: 44, image: profile.avatar)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ChatUIText.sharedProfile)
                        .font(PaceFont.micro)
                        .foregroundStyle(PaceColor.textSecondary)
                    Text(profile.shownName)
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
    var replyAuthor: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let reply = pending.replyTo, let replyAuthor {
                ChatReplyReference(author: replyAuthor, preview: reply, isOwn: true, onTap: nil)
            }
            switch pending.kind {
            case .image, .gif:
                ChatMediaBubble(
                    reference: nil,
                    localData: pending.localMedia?.data,
                    isGIF: pending.kind == .gif,
                    accessibilityText: pending.kind == .gif ? ChatUIText.gif(from: nil) : ChatUIText.photo(from: nil),
                    isUploading: pending.status == .uploading
                )
            case .voice:
                ChatVoiceBubble(id: pending.clientID, duration: pending.mediaDuration, isOwn: true, load: nil)
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

// MARK: - Antworten, Kennzeichen, Pins

/// Kompakter Verweis auf die beantwortete Nachricht über der Blase; Antippen springt hin.
struct ChatReplyReference: View {
    let author: String
    let preview: ChatReplyPreview
    let isOwn: Bool
    let onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: PaceSpacing.xs) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(PaceColor.accent)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(author)
                        .font(PaceFont.caption.weight(.semibold))
                        .foregroundStyle(PaceColor.accent)
                        .lineLimit(1)
                    Text(ChatReplySnippet.text(for: preview))
                        .font(PaceFont.caption)
                        .italic(preview.isDeleted)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, PaceSpacing.xs)
            .frame(maxWidth: 260, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
        }
        .buttonStyle(.pacePressable)
        .disabled(onTap == nil)
        .accessibilityHidden(true)
    }
}

/// Einzeiliger Inhalt einer beantworteten bzw. angepinnten Nachricht.
enum ChatReplySnippet {
    static func text(for preview: ChatReplyPreview) -> String {
        guard !preview.isDeleted else { return ChatUIText.originalUnavailable }
        return ChatFormatting.content(kind: preview.kind, text: preview.text, duration: preview.mediaDuration)
    }

    static func text(for message: ChatMessage) -> String {
        ChatFormatting.content(kind: message.kind, text: message.text, duration: message.mediaDuration)
    }
}

/// Dezente Kennzeichen unter einer Nachricht: angepinnt, Favorit (nur für dich), bearbeitet.
struct ChatMessageMarks: View {
    let isPinned: Bool
    let isFavorite: Bool
    let isEdited: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isPinned {
                Image(systemName: "pin.fill")
            }
            if isFavorite {
                Image(systemName: "star.fill")
            }
            if isEdited {
                Text(ChatUIText.edited)
            }
        }
        .font(PaceFont.micro)
        .foregroundStyle(PaceColor.textSecondary)
        .padding(.horizontal, PaceSpacing.xxs)
        .accessibilityHidden(true)
    }
}

/// Hinweis oben im Chat auf die angepinnte(n) Nachricht(en) mit Vorschau des Inhalts: Text-Ausschnitt, Miniatur von
/// Foto bzw. GIF, Sprachnachricht mit Dauer oder Profilbild – platzsparend in zwei Zeilen. Antippen springt zur
/// Nachricht und hebt sie hervor; bei mehreren Pins zeigt der Hinweis danach den nächsten (Markierungen links).
struct ChatPinBanner: View {
    let preview: ChatPinPreview
    let onTap: () -> Void
    /// Lösen (nur mit Recht zum Anpinnen) – nötig für verborgene Pins, die man nicht im Verlauf findet.
    var onUnpin: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: PaceSpacing.s) {
                if preview.showsSegments {
                    segments
                }
                visual
                VStack(alignment: .leading, spacing: 1) {
                    Text(preview.title)
                        .font(PaceFont.caption.weight(.semibold))
                        .foregroundStyle(PaceColor.accent)
                        .lineLimit(1)
                    Text(preview.line)
                        .font(PaceFont.callout)
                        .italic(preview.isHidden)
                        .foregroundStyle(preview.isHidden ? PaceColor.textSecondary : PaceColor.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if preview.count > 1 {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
            .padding(.horizontal, PaceSpacing.s)
            .padding(.vertical, PaceSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .contextMenu {
            if let onUnpin {
                Button(action: onUnpin) {
                    Label(ChatUIText.unpin, systemImage: "pin.slash")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preview.accessibilityLabel)
        .accessibilityHint(ChatUIText.pinnedBannerHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            if let onUnpin {
                Button(ChatUIText.unpin, action: onUnpin)
            }
        }
    }

    /// Senkrechte Markierungen: welcher von bis zu vier Pins gerade gezeigt wird.
    private var segments: some View {
        VStack(spacing: 2) {
            ForEach(0..<preview.count, id: \.self) { position in
                Capsule()
                    .fill(position == preview.index ? PaceColor.accent : PaceColor.accent.opacity(0.25))
                    .frame(width: 3)
            }
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var visual: some View {
        switch preview.visual {
        case .image(let reference), .gif(let reference):
            ChatMediaImage(reference: reference, localData: nil, animates: false)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if case .gif = preview.visual {
                        Text(verbatim: "GIF")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .padding(2)
                    }
                }
                .accessibilityHidden(true)
        case .profile(let profile):
            PaceAvatar(name: profile.shownName, seed: profile.publicID.uuidString, size: 36, image: profile.avatar)
                .accessibilityHidden(true)
        case .voice:
            pinIcon("waveform")
        case .text, .unavailable:
            pinIcon("pin.fill")
        }
    }

    private func pinIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(PaceColor.accent)
            .frame(width: 36, height: 36)
            .background(PaceColor.accent.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}
