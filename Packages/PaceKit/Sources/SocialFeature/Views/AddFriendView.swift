import DesignSystem
import PaceCore
import SwiftUI

/// „Freund hinzufügen“ (Referenzbild 1).
struct AddFriendView: View {
    @State private var model: FriendSearchViewModel
    private let social: SocialViewModel
    private let onOpen: (SocialRoute) -> Void
    private let onOpenChat: (ChatTarget) -> Void
    @State private var blockCandidate: ProfileSearchResult?
    @State private var showsBlockDialog = false

    init(
        model: FriendSearchViewModel,
        social: SocialViewModel,
        onOpen: @escaping (SocialRoute) -> Void,
        onOpenChat: @escaping (ChatTarget) -> Void
    ) {
        _model = State(initialValue: model)
        self.social = social
        self.onOpen = onOpen
        self.onOpenChat = onOpenChat
    }

    var body: some View {
        AddFriendContent(
            model: model,
            social: social,
            onOpenProfile: { onOpen(.profile($0)) },
            onShare: { onOpen(.shareProfile($0)) },
            onMessage: onOpenChat,
            onBlock: { result in
                blockCandidate = result
                showsBlockDialog = true
            }
        )
        .socialSubpageScroll()
        .task { [model] in await model.refreshResults() }
        .confirmationDialog(
            blockCandidate.map { SocialText.blockTitle($0.profile.shownName) } ?? SocialText.blockUser,
            isPresented: $showsBlockDialog,
            titleVisibility: .visible,
            presenting: blockCandidate
        ) { result in
            Button(SocialText.blockUser, role: .destructive) {
                Task { await model.block(result) }
            }
            Button(SocialText.cancel, role: .cancel) {}
        } message: { _ in
            Text(SocialText.blockMessage)
        }
    }
}

/// Inhalt von „Freund hinzufügen“ mit Kopfzeile (ohne Scrollen) – auch für Snapshot-Tests.
struct AddFriendContent: View {
    @Bindable var model: FriendSearchViewModel
    let social: SocialViewModel
    var onOpenProfile: (SocialProfile) -> Void = { _ in }
    var onShare: (SocialProfile) -> Void = { _ in }
    var onMessage: (ChatTarget) -> Void = { _ in }
    var onBlock: (ProfileSearchResult) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: SocialText.social, title: SocialText.addFriend)
            PaceSearchField(SocialText.searchUsername, text: $model.query) {
                Task { await model.searchNow() }
            }
            .padding(.top, PaceSpacing.xs)
            if let notice = social.notice {
                NoticeBanner(notice: notice) { social.dismissNotice() }
            }
            switch model.state {
            case .idle:
                Text(SocialText.searchHint)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PaceSpacing.xxs)
            case .searching:
                HStack(spacing: PaceSpacing.s) {
                    ProgressView()
                    Text(SocialText.searching)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            case .results(let results):
                SocialSectionTitle(SocialText.searchResults)
                ForEach(results) { result in
                    resultCard(result)
                }
            case .empty(let message):
                SocialEmptyCard(systemImage: "person.crop.circle.badge.questionmark", title: SocialText.searchResults, message: message)
            case .failed(let message):
                SocialFailedCard(message: message) {
                    Task { await model.searchNow() }
                }
            }
            if let username = social.username {
                Text(SocialText.ownUsername(username))
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, PaceSpacing.xxs)
                    .padding(.top, PaceSpacing.xs)
            }
        }
    }

    private func resultCard(_ result: ProfileSearchResult) -> some View {
        SocialPersonCard(profile: result.profile, onOpenProfile: { onOpenProfile(result.profile) }, compact: true) {
            HStack(spacing: PaceSpacing.xxs) {
                primaryAction(result)
                if result.relationship != .me {
                    menu(result)
                }
            }
        }
    }

    @ViewBuilder
    private func primaryAction(_ result: ProfileSearchResult) -> some View {
        let isBusy = model.isBusy(result)
        switch result.relationship {
        case .none:
            Button {
                Task { await model.add(result) }
            } label: {
                Label(SocialText.add, systemImage: "person.badge.plus")
                    .lineLimit(1)
            }
            .buttonStyle(.paceAction)
            .disabled(isBusy)
        case .incomingRequest:
            Button {
                Task { await model.accept(result) }
            } label: {
                Label(SocialText.accept, systemImage: "person.badge.plus")
                    .lineLimit(1)
            }
            .buttonStyle(.paceAction)
            .disabled(isBusy || model.requestID(for: result) == nil)
        case .outgoingRequest:
            SocialStatusLabel(text: SocialText.requestSent, systemImage: "clock", style: .plain)
        case .friend:
            SocialStatusLabel(text: SocialText.alreadyFriends, systemImage: "checkmark")
        case .me:
            SocialStatusLabel(text: SocialText.thatsYou, systemImage: "person.fill", style: .plain)
        }
    }

    /// Genau drei Einträge: Profil teilen, Nachricht schreiben (nur Freunde), Nutzer blockieren.
    private func menu(_ result: ProfileSearchResult) -> some View {
        let chatTarget = model.chatTarget(for: result)
        return Menu {
            Button {
                onShare(result.profile)
            } label: {
                Label(SocialText.shareProfile, systemImage: "square.and.arrow.up")
            }
            Button {
                if let chatTarget { onMessage(chatTarget) }
            } label: {
                Label(SocialText.writeMessage, systemImage: "message")
            }
            .disabled(chatTarget == nil)
            Button(role: .destructive) {
                onBlock(result)
            } label: {
                Label(SocialText.blockUser, systemImage: "nosign")
            }
        } label: {
            SocialMoreLabel()
        }
        .accessibilityLabel(SocialText.moreActions(for: result.profile.shownName))
    }
}
