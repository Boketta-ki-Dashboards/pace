import DesignSystem
import PaceCore
import SwiftUI

/// „Profil teilen“: Empfängerauswahl (Freunde und eigene Gruppen) und Link zum Teilen außerhalb von Pace.
struct ShareProfileView: View {
    @State private var model: ShareProfileViewModel
    /// Ging das Profil an genau einen Chat, öffnet dieser Chat statt der vorigen Seite.
    private let onSentToSingleChat: ((ChatTarget) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(model: ShareProfileViewModel, onSentToSingleChat: ((ChatTarget) -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onSentToSingleChat = onSentToSingleChat
    }

    var body: some View {
        ShareProfileContent(model: model) {
            Task {
                let targets = model.selectedTargets
                guard await model.send() else { return }
                if targets.count == 1, let target = targets.first, let onSentToSingleChat {
                    onSentToSingleChat(target)
                } else {
                    dismiss()
                }
            }
        }
        .socialSubpageScroll()
    }
}

/// Inhalt der Empfängerauswahl mit Kopfzeile (ohne Scrollen) – auch für Snapshot-Tests.
struct ShareProfileContent: View {
    let model: ShareProfileViewModel
    var onSend: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: SocialText.social, title: SocialText.shareProfile)
            sharedProfile
            if let error = model.errorMessage {
                NoticeBanner(notice: SocialViewModel.Notice(text: error, isError: true)) { model.dismissError() }
            }
            ShareLink(item: model.shareURL, message: Text(model.shareText)) {
                Label(SocialText.shareLink, systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.paceSecondary)

            SocialSectionTitle(SocialText.shareInPace)
            if !model.canShareInPace {
                SocialEmptyCard(systemImage: "bubble.left.and.bubble.right", title: SocialText.shareInPace, message: SocialText.shareChatsUnavailable)
            } else if !model.hasRecipients {
                SocialEmptyCard(systemImage: "person.2", title: SocialText.shareInPace, message: SocialText.noShareRecipients)
            } else {
                Text(SocialText.shareRecipientsHint)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                recipients(SocialText.friends, model.friendRecipients)
                recipients(SocialText.groups, model.groupRecipients)
                Button(action: onSend) {
                    if model.isSending {
                        ProgressView().tint(PaceColor.onAccent)
                    } else {
                        Text(model.selection.isEmpty ? SocialText.chooseRecipients : model.sendTitle)
                    }
                }
                .buttonStyle(.pacePrimary)
                .disabled(!model.canSend)
                .padding(.top, PaceSpacing.xs)
            }
        }
    }

    private var sharedProfile: some View {
        HStack(spacing: PaceSpacing.s) {
            PaceAvatar(name: model.profile.displayName, seed: model.profile.publicID.uuidString, size: 52, image: model.profile.avatar)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.profile.displayName)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                Text(verbatim: "@\(model.profile.username)")
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(PaceSpacing.s)
        .paceCardBackground(cornerRadius: PaceRadius.tile)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func recipients(_ title: String, _ recipients: [ShareProfileViewModel.Recipient]) -> some View {
        if !recipients.isEmpty {
            Text(title)
                .font(PaceFont.caption.weight(.semibold))
                .foregroundStyle(PaceColor.textSecondary)
                .padding(.top, PaceSpacing.xs)
            ForEach(recipients) { recipient in
                SocialSelectableRow(
                    title: recipient.title,
                    subtitle: subtitle(for: recipient),
                    isSelected: model.isSelected(recipient),
                    action: { model.toggle(recipient) }
                ) {
                    avatar(for: recipient)
                }
            }
        }
    }

    private func subtitle(for recipient: ShareProfileViewModel.Recipient) -> String {
        switch recipient.kind {
        case .friend(let profile): "@\(profile.username)"
        case .group(_, _, _, let memberCount): SocialText.members(memberCount)
        }
    }

    @ViewBuilder
    private func avatar(for recipient: ShareProfileViewModel.Recipient) -> some View {
        switch recipient.kind {
        case .friend(let profile):
            PaceAvatar(name: profile.displayName, seed: profile.publicID.uuidString, size: 40, image: profile.avatar)
        case .group(_, let name, let imagePath, _):
            GroupAvatar(name: name, kind: .friends, image: MediaReference.groupImage(imagePath), size: 40)
        }
    }
}
