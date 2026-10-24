import DesignSystem
import PaceCore
import SwiftUI

/// Profil einer Person (Freund oder nicht) mit den Aktionen, die zur Beziehung passen.
struct UserProfileView: View {
    @State private var model: UserProfileViewModel
    private let social: SocialViewModel
    private let onOpen: (SocialRoute) -> Void
    private let onOpenChat: (ChatTarget) -> Void
    @State private var confirmation: Confirmation?
    @State private var showsConfirmation = false
    @State private var showsNicknameEditor = false

    private enum Confirmation: String, Identifiable {
        case removeFriend
        case block

        var id: String { rawValue }
    }

    init(
        model: UserProfileViewModel,
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
        UserProfileContent(
            model: model,
            social: social,
            onMessage: onOpenChat,
            onShare: { onOpen(.shareProfile(model.profile)) },
            onReport: { onOpen(.report(.user(model.profile))) },
            onRemoveFriend: { confirm(.removeFriend) },
            onBlock: { confirm(.block) },
            onEditNickname: { showsNicknameEditor = true }
        )
        .socialSubpageScroll()
        .sheet(isPresented: $showsNicknameEditor) {
            NicknameEditSheet(model: model)
        }
        .refreshable { [model] in await model.load() }
        .task { [model] in await model.load() }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showsConfirmation,
            titleVisibility: .visible,
            presenting: confirmation
        ) { confirmation in
            switch confirmation {
            case .removeFriend:
                Button(SocialText.removeFriend, role: .destructive) {
                    Task { await model.removeFriend() }
                }
            case .block:
                Button(SocialText.blockUser, role: .destructive) {
                    Task { await model.block() }
                }
            }
            Button(SocialText.cancel, role: .cancel) {}
        } message: { confirmation in
            switch confirmation {
            case .removeFriend: Text(SocialText.removeFriendMessage)
            case .block: Text(SocialText.blockMessage)
            }
        }
    }

    private func confirm(_ kind: Confirmation) {
        confirmation = kind
        showsConfirmation = true
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .removeFriend: SocialText.removeFriendTitle(model.profile.shownName)
        case .block: SocialText.blockTitle(model.profile.shownName)
        case nil: ""
        }
    }
}

/// Inhalt des Profils mit Kopfzeile (ohne Scrollen und Dialoge) – auch für Snapshot-Tests.
struct UserProfileContent: View {
    let model: UserProfileViewModel
    let social: SocialViewModel
    var onMessage: (ChatTarget) -> Void = { _ in }
    var onShare: () -> Void = {}
    var onReport: () -> Void = {}
    var onRemoveFriend: () -> Void = {}
    var onBlock: () -> Void = {}
    var onEditNickname: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: SocialText.social, title: SocialText.profile)
            identity
            if let notice = social.notice {
                NoticeBanner(notice: notice) { social.dismissNotice() }
            }
            switch model.state {
            case .loading:
                SocialLoadingCard(message: SocialText.profileLoading)
            case .failed(let message):
                SocialFailedCard(message: message) {
                    Task { await model.load() }
                }
            case .notFound:
                SocialEmptyCard(systemImage: "person.crop.circle.badge.xmark", title: SocialText.profileNotFoundTitle, message: SocialText.profileNotFoundMessage)
            case .loaded(let details):
                relationshipCard(details)
                if details.relationship == .friend, let today = details.stepsToday, let week = details.stepsWeek {
                    stepsCard(today: today, week: week)
                }
                moreActions(details)
            }
        }
    }

    private var identity: some View {
        HStack(spacing: PaceSpacing.m) {
            PaceAvatar(name: model.profile.shownName, seed: model.profile.publicID.uuidString, size: 76, image: model.profile.avatar)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.profile.shownName)
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.profile.nickname?.isEmpty == false {
                    Text(SocialText.displayNameLine(model.profile.displayName))
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: "@\(model.profile.username)")
                    .font(PaceFont.body)
                    .foregroundStyle(PaceColor.textSecondary)
                    .textSelection(.enabled)
                if let since = model.loaded?.friendsSince, model.relationship == .friend {
                    Text(SocialText.friendsSince(since))
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
        }
        .padding(.vertical, PaceSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: Beziehung und Hauptaktion

    @ViewBuilder
    private func relationshipCard(_ details: PublicProfile) -> some View {
        let isBusy = model.isBusy
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                if details.isBlockedByMe {
                    Label(SocialText.blockedByMe, systemImage: "nosign")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                    Button(SocialText.unblock) {
                        Task { await model.unblock() }
                    }
                    .buttonStyle(.paceSecondary)
                    .disabled(isBusy)
                } else {
                    switch details.relationship {
                    case .none:
                        Button {
                            Task { await model.sendRequest() }
                        } label: {
                            Label(SocialText.sendRequest, systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.pacePrimary)
                        .disabled(isBusy)
                    case .outgoingRequest:
                        SocialStatusLabel(text: SocialText.requestSent, systemImage: "clock", style: .plain)
                        Button {
                            Task { await model.withdrawRequest() }
                        } label: {
                            Label(SocialText.withdraw, systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.paceOutline)
                        .disabled(isBusy || model.requestID == nil)
                    case .incomingRequest:
                        Text(SocialText.incomingRequest)
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                        HStack(spacing: PaceSpacing.xs) {
                            Button {
                                Task { await model.respond(accept: true) }
                            } label: {
                                Label(SocialText.accept, systemImage: "person.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.paceAction)
                            Button {
                                Task { await model.respond(accept: false) }
                            } label: {
                                Label(SocialText.decline, systemImage: "person.badge.minus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.paceOutline)
                        }
                        .disabled(isBusy || model.requestID == nil)
                    case .friend:
                        SocialStatusLabel(text: SocialText.alreadyFriends, systemImage: "checkmark")
                        if let target = model.chatTarget {
                            Button {
                                onMessage(target)
                            } label: {
                                Label(SocialText.writeMessage, systemImage: "message")
                            }
                            .buttonStyle(.pacePrimary)
                        }
                    case .me:
                        Text(SocialText.thatsYou)
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    if details.relationship != .friend && details.relationship != .me {
                        Text(SocialText.stepsOnlyForFriends)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func stepsCard(today: Int, week: Int) -> some View {
        HStack(spacing: PaceSpacing.s) {
            stepsFact(title: SocialText.today, steps: today)
            stepsFact(title: SocialText.thisWeek, steps: week)
        }
    }

    private func stepsFact(title: String, steps: Int) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
            Text(title)
                .font(PaceFont.caption.weight(.semibold))
                .foregroundStyle(PaceColor.textSecondary)
            HStack(spacing: 6) {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(PaceColor.accent)
                    .accessibilityHidden(true)
                Text(steps.paceFormatted)
                    .font(.system(.title2, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(SocialText.competitionSteps)
                .font(PaceFont.micro)
                .foregroundStyle(PaceColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PaceSpacing.m)
        .paceCardBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ", " + PaceLocalization.steps(steps))
    }

    // MARK: Weitere Aktionen

    @ViewBuilder
    private func moreActions(_ details: PublicProfile) -> some View {
        if details.relationship != .me {
            VStack(spacing: 0) {
                if model.canEditNickname {
                    actionRow(
                        model.profile.nickname == nil ? SocialText.addNickname : SocialText.editNickname,
                        systemImage: "character.cursor.ibeam",
                        action: onEditNickname
                    )
                    Divider().padding(.leading, 52)
                }
                actionRow(SocialText.shareProfile, systemImage: "square.and.arrow.up", action: onShare)
                if details.relationship == .friend {
                    Divider().padding(.leading, 52)
                    actionRow(SocialText.removeFriend, systemImage: "person.badge.minus", action: onRemoveFriend)
                }
                if !details.isBlockedByMe {
                    Divider().padding(.leading, 52)
                    actionRow(SocialText.blockUser, systemImage: "nosign", isDestructive: true, action: onBlock)
                }
                Divider().padding(.leading, 52)
                actionRow(SocialText.reportUser, systemImage: "exclamationmark.bubble", isDestructive: true, action: onReport)
            }
            .paceCardBackground()
            .disabled(model.isBusy)
        }
        ShareLink(item: model.shareURL, message: Text(model.shareText)) {
            Label(SocialText.shareLink, systemImage: "link")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(PaceColor.accent)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, PaceSpacing.xxs)
    }

    private func actionRow(_ title: String, systemImage: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(title)
                    .font(PaceFont.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDestructive ? PaceColor.danger : PaceColor.textPrimary)
            .padding(.horizontal, PaceSpacing.m)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
    }
}

/// Eigenen, privaten Spitznamen für einen Freund vergeben, ändern oder entfernen.
struct NicknameEditSheet: View {
    let model: UserProfileViewModel
    @State private var input: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: UserProfileViewModel) {
        self.model = model
        _input = State(initialValue: model.profile.nickname ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    Text(SocialText.nickname)
                        .font(PaceFont.caption.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                    TextField(SocialText.nicknamePlaceholder, text: $input)
                        .textContentType(.nickname)
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit(save)
                        .font(PaceFont.body)
                        .padding(.horizontal, PaceSpacing.m)
                        .frame(minHeight: 48)
                        .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                    if let problem = model.nicknameProblem(for: input) ?? model.nicknameError {
                        Text(problem)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(SocialText.nicknamePrivacyNote)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(SocialText.displayNameLine(model.profile.displayName) + " · @" + model.profile.username)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.profile.nickname != nil {
                        Button(role: .destructive) {
                            input = ""
                            save()
                        } label: {
                            Label(SocialText.removeNickname, systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.paceOutline)
                        .disabled(model.isSavingNickname)
                        .padding(.top, PaceSpacing.xs)
                    }
                }
                .padding(PaceSpacing.l)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .paceScreenBackground()
            // Kurzer Titel, damit er zwischen „Abbrechen“ und „Speichern“ nicht abgeschnitten wird.
            .navigationTitle(SocialText.nickname)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SocialText.cancel) { dismiss() }
                        .disabled(model.isSavingNickname)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSavingNickname {
                        ProgressView()
                    } else {
                        Button(SocialText.save, action: save)
                            .disabled(!model.canSaveNickname(input))
                    }
                }
            }
        }
        .tint(PaceColor.accent)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(model.isSavingNickname)
        .onAppear { isFocused = true }
        .onDisappear { model.clearNicknameError() }
    }

    private func save() {
        Task {
            if await model.saveNickname(input) {
                dismiss()
            }
        }
    }
}
