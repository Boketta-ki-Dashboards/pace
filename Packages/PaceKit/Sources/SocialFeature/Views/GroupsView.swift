import DesignSystem
import PaceCore
import SwiftUI

/// Gruppen: eigene Gruppen mit Gruppen-Streak, Einladungen annehmen oder ablehnen, per Code beitreten, neue Gruppe.
struct GroupsView: View {
    let viewModel: SocialViewModel
    let onOpen: (SocialRoute) -> Void
    @State private var inviteCode = ""

    var body: some View {
        GroupsContent(viewModel: viewModel, inviteCode: $inviteCode, onOpen: onOpen) {
            Task {
                if let group = await viewModel.join(inviteCode: inviteCode) {
                    inviteCode = ""
                    onOpen(.group(group.id))
                }
            }
        }
        .socialSubpageScroll()
        .refreshable { [viewModel] in await viewModel.load() }
        .task { [viewModel] in await viewModel.loadIfNeeded() }
    }
}

/// Inhalt der Gruppenübersicht mit Kopfzeile (ohne Scrollen) – auch für Snapshot-Tests.
struct GroupsContent: View {
    let viewModel: SocialViewModel
    @Binding var inviteCode: String
    var onOpen: (SocialRoute) -> Void = { _ in }
    var onJoin: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: SocialText.social, title: SocialText.groups)
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
                invitations
                groups
                joinCard
            }
        }
    }

    // MARK: Einladungen

    @ViewBuilder
    private var invitations: some View {
        if !viewModel.invitations.isEmpty {
            SocialSectionTitle(SocialText.sectionCount(SocialText.invitations, viewModel.invitations.count))
            ForEach(viewModel.invitations) { invitation in
                HStack(spacing: PaceSpacing.s) {
                    GroupAvatar(name: invitation.groupName, kind: invitation.groupKind, image: .groupImage(invitation.groupImagePath), size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invitation.groupName)
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(SocialText.invitedBy(invitation.inviterDisplayName, memberCount: invitation.memberCount))
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: PaceSpacing.xxs)
                    SocialStackedActions {
                        Button {
                            Task { await viewModel.respond(to: invitation, accept: true) }
                        } label: {
                            Text(SocialText.join)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.paceAction)
                        Button {
                            Task { await viewModel.respond(to: invitation, accept: false) }
                        } label: {
                            Text(SocialText.decline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.paceOutline)
                    }
                    .disabled(viewModel.busyIDs.contains(invitation.id))
                }
                .padding(PaceSpacing.s)
                .paceCardBackground()
            }
        }
    }

    // MARK: Eigene Gruppen

    @ViewBuilder
    private var groups: some View {
        SocialSectionTitle(title: SocialText.yourGroups) {
            Button {
                onOpen(.createGroup)
            } label: {
                Label(SocialText.createGroup, systemImage: "plus")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(PaceColor.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        if viewModel.groups.isEmpty {
            SocialEmptyCard(systemImage: "person.3", title: SocialText.noGroupsTitle, message: SocialText.noGroupsMessage)
        } else {
            ForEach(viewModel.groups) { group in
                Button {
                    onOpen(.group(group.id))
                } label: {
                    GroupStreakRow(group: group, showsChevron: true)
                }
                .buttonStyle(.pacePressable)
            }
        }
    }

    // MARK: Per Code beitreten

    private var joinCard: some View {
        GroupFormCard(title: SocialText.joinWithCode) {
            HStack(spacing: PaceSpacing.xs) {
                TextField(SocialText.inviteCodePlaceholder, text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .onSubmit(onJoin)
                    .modifier(GroupFieldStyle())
                Button(SocialText.join, action: onJoin)
                    .buttonStyle(.paceAction)
                    .disabled(inviteCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(SocialText.joinFooter)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, PaceSpacing.xs)
    }
}
