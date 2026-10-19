import DesignSystem
import PaceCore
import SwiftUI

/// Mitglieder einer Gruppe: Liste mit Rollen, Freunde einladen, offene Einladungen zurückziehen und – für die Person,
/// die die Gruppe verwaltet – Mitglieder entfernen.
struct GroupMembersView: View {
    @State private var viewModel: GroupDetailViewModel
    private let onOpen: (SocialRoute) -> Void
    @State private var memberToRemove: GroupRankingEntry?
    @State private var showsRemoveDialog = false

    init(viewModel: GroupDetailViewModel, onOpen: @escaping (SocialRoute) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onOpen = onOpen
    }

    var body: some View {
        GroupMembersContent(
            viewModel: viewModel,
            onOpenProfile: { onOpen(.profile($0)) },
            onRemove: { member in
                memberToRemove = member
                showsRemoveDialog = true
            }
        )
        .socialSubpageScroll()
        .refreshable { [viewModel] in await viewModel.load() }
        .task { [viewModel] in
            if viewModel.state != .loaded { await viewModel.load() }
        }
        .confirmationDialog(
            memberToRemove.map { SocialText.removeMemberTitle($0.profile.displayName) } ?? SocialText.removeFromGroup,
            isPresented: $showsRemoveDialog,
            titleVisibility: .visible,
            presenting: memberToRemove
        ) { member in
            Button(SocialText.removeFromGroup, role: .destructive) {
                Task { await viewModel.remove(member) }
            }
            Button(SocialText.cancel, role: .cancel) {}
        } message: { _ in
            Text(SocialText.removeMemberMessage)
        }
    }
}

/// Inhalt der Mitgliederseite mit Kopfzeile (ohne Scrollen) – auch für Snapshot-Tests.
struct GroupMembersContent: View {
    let viewModel: GroupDetailViewModel
    var onOpenProfile: (SocialProfile) -> Void = { _ in }
    var onRemove: (GroupRankingEntry) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(
                backTitle: viewModel.group.name,
                title: SocialText.membersTitle,
                subtitle: SocialText.members(viewModel.group.memberCount)
            )
            if let notice = viewModel.notice {
                NoticeBanner(notice: notice) { viewModel.dismissNotice() }
            }
            switch viewModel.state {
            case .gone:
                PaceStatusView(systemImage: "person.3", title: SocialText.groupGoneTitle, message: SocialText.groupGoneMessage)
            case .failed(let message):
                SocialFailedCard(message: message) {
                    Task { await viewModel.load() }
                }
            case .loading where viewModel.ranking == nil:
                SocialLoadingCard(message: SocialText.loading)
            default:
                members
                pendingInvitations
                inviteFriends
            }
        }
    }

    // MARK: Mitglieder

    @ViewBuilder
    private var members: some View {
        VStack(spacing: PaceSpacing.xs) {
            ForEach(viewModel.members) { member in
                memberRow(member)
            }
        }
    }

    private func memberRow(_ member: GroupRankingEntry) -> some View {
        HStack(spacing: PaceSpacing.s) {
            Button {
                if !member.isCurrentUser { onOpenProfile(member.profile) }
            } label: {
                HStack(spacing: PaceSpacing.s) {
                    PaceAvatar(name: member.profile.displayName, seed: member.profile.publicID.uuidString, size: 44, image: member.profile.avatar)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: PaceSpacing.xs) {
                            Text(member.isCurrentUser ? SocialText.youName(member.profile.displayName) : member.profile.displayName)
                                .font(PaceFont.headline)
                                .foregroundStyle(member.isCurrentUser ? PaceColor.accent : PaceColor.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if member.role == .owner {
                                Text(SocialText.admin)
                                    .font(PaceFont.micro)
                                    .foregroundStyle(PaceColor.onSelection)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PaceColor.selectionFill, in: Capsule())
                            }
                        }
                        Text(verbatim: "@\(member.profile.username)")
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: PaceSpacing.xs)
                    if member.reachedGoalToday {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(PaceColor.accent)
                            .accessibilityLabel(SocialText.goalReached)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .disabled(member.isCurrentUser)
            if viewModel.canRemove(member) {
                Menu {
                    Button(role: .destructive) {
                        onRemove(member)
                    } label: {
                        Label(SocialText.removeFromGroup, systemImage: "person.badge.minus")
                    }
                } label: {
                    SocialMoreLabel()
                }
                .disabled(viewModel.busyIDs.contains(member.profile.publicID))
                .accessibilityLabel(SocialText.moreActions(for: member.profile.displayName))
            }
        }
        .padding(.horizontal, PaceSpacing.s)
        .padding(.vertical, PaceSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(
            member.isCurrentUser ? PaceColor.accentSoft : PaceColor.surface,
            in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                .strokeBorder(member.isCurrentUser ? PaceColor.accent.opacity(0.45) : PaceColor.border, lineWidth: 1)
        )
    }

    // MARK: Einladungen

    @ViewBuilder
    private var pendingInvitations: some View {
        if !viewModel.outgoingInvitations.isEmpty {
            SocialSectionTitle(SocialText.sectionCount(SocialText.pendingInvitations, viewModel.outgoingInvitations.count))
            ForEach(viewModel.outgoingInvitations) { invitation in
                SocialPersonCard(profile: invitation.profile, detail: SocialText.invited, onOpenProfile: { onOpenProfile(invitation.profile) }) {
                    if viewModel.group.isOwner {
                        Button {
                            Task { await viewModel.cancel(invitation) }
                        } label: {
                            Label(SocialText.withdraw, systemImage: "xmark")
                        }
                        .buttonStyle(.paceOutline)
                        .disabled(viewModel.busyIDs.contains(invitation.id))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inviteFriends: some View {
        SocialSectionTitle(SocialText.inviteFriends)
        let friends = viewModel.invitableFriends
        if friends.isEmpty {
            Text(SocialText.allFriendsInGroup)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PaceSpacing.xxs)
        } else {
            ForEach(friends) { friend in
                SocialPersonCard(profile: friend.profile, onOpenProfile: { onOpenProfile(friend.profile) }) {
                    Button {
                        Task { await viewModel.invite(friend) }
                    } label: {
                        Label(SocialText.invite, systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.paceAction)
                    .disabled(viewModel.busyIDs.contains(friend.profile.publicID))
                }
            }
        }
    }
}
