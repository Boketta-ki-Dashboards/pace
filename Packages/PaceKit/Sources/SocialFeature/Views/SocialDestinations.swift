import DesignSystem
import PaceCore
import SwiftUI

/// Ziele der Navigation im Social-Tab. Jede Unterseite bekommt ihr ViewModel einmal beim ersten Erscheinen.
struct SocialDestination: View {
    let route: SocialRoute
    let viewModel: SocialViewModel
    let onOpen: (SocialRoute) -> Void
    let onOpenChat: (ChatTarget) -> Void
    /// Ersetzt die aktuelle Seite (z. B. „Gruppe erstellen“ → Details der neuen Gruppe).
    let onReplace: (SocialRoute) -> Void
    /// Zurück zur Hauptseite (z. B. nach dem Verlassen einer Gruppe).
    let onPopToRoot: () -> Void
    /// Ersetzt die aktuelle Seite durch einen Chat (z. B. nach „Profil teilen“ an genau einen Chat).
    var onReplaceWithChat: (ChatTarget) -> Void = { _ in }

    var body: some View {
        switch route {
        case .group(let id):
            if let detail = viewModel.detail(groupID: id) {
                GroupDetailView(viewModel: detail, onOpen: onOpen, onOpenChat: onOpenChat)
            } else {
                SocialMissingPage(kind: .group)
            }
        case .groupMembers(let id):
            if let detail = viewModel.detail(groupID: id) {
                GroupMembersView(viewModel: detail, onOpen: onOpen)
            } else {
                SocialMissingPage(kind: .group)
            }
        case .groupCalendar(let id):
            if let calendar = viewModel.groupCalendar(groupID: id) {
                GroupCalendarView(viewModel: calendar, onOpen: onOpen)
            } else {
                SocialMissingPage(kind: .group)
            }
        case .groupSettings(let id):
            if let detail = viewModel.detail(groupID: id) {
                GroupSettingsView(viewModel: detail, onOpen: onOpen, onGroupGone: onPopToRoot)
            } else {
                SocialMissingPage(kind: .group)
            }
        case .friend(let profile):
            profilePage(profile)
        case .profile(let profile):
            profilePage(profile)
        case .addFriend:
            if let search = viewModel.friendSearch() {
                AddFriendView(model: search, social: viewModel, onOpen: onOpen, onOpenChat: onOpenChat)
            } else {
                SocialMissingPage(kind: .unavailable)
            }
        case .requests:
            FriendRequestsView(viewModel: viewModel, onOpen: onOpen)
        case .createGroup:
            CreateGroupView(model: viewModel.createGroupForm(), social: viewModel) { group in
                onReplace(.group(group.id))
            }
        case .groups:
            GroupsView(viewModel: viewModel, onOpen: onOpen)
        case .friendsRanking:
            FriendsRankingView(model: viewModel.friendsRanking(), onOpen: onOpen)
        case .settings:
            SocialSettingsView(model: viewModel.settings(), social: viewModel, onOpen: onOpen)
        case .shareProfile(let profile):
            ShareProfileView(model: viewModel.shareProfile(profile), onSentToSingleChat: onReplaceWithChat)
        case .report(let subject):
            ReportView(model: viewModel.reportForm(subject), social: viewModel)
        }
    }

    @ViewBuilder
    private func profilePage(_ profile: SocialProfile) -> some View {
        if let model = viewModel.userProfile(for: profile) {
            UserProfileView(model: model, social: viewModel, onOpen: onOpen, onOpenChat: onOpenChat)
        } else {
            SocialMissingPage(kind: .unavailable)
        }
    }
}

/// Gestaltete Seite, wenn das Ziel nicht (mehr) da ist.
struct SocialMissingPage: View {
    enum Kind {
        case group
        case unavailable
    }

    let kind: Kind

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.l) {
            PaceSubpageHeader(backTitle: SocialText.social, title: kind == .group ? SocialText.group : SocialText.social)
            switch kind {
            case .group:
                PaceStatusView(systemImage: "person.3", title: SocialText.groupGoneTitle, message: SocialText.groupGoneMessage)
            case .unavailable:
                SocialUnavailableCard(message: SocialError.unavailable.message)
            }
        }
        .socialSubpageScroll()
    }
}
