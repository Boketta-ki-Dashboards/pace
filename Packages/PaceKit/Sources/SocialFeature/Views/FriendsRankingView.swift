import DesignSystem
import PaceCore
import SwiftUI

/// Vollständiges Freundesranking („Alle ansehen“): heute oder diese Woche, gleiche Zeilen wie in Rankings und Home.
struct FriendsRankingView: View {
    @State private var model: FriendsRankingViewModel
    private let onOpen: (SocialRoute) -> Void

    init(model: FriendsRankingViewModel, onOpen: @escaping (SocialRoute) -> Void) {
        _model = State(initialValue: model)
        self.onOpen = onOpen
    }

    var body: some View {
        FriendsRankingContent(model: model, onOpen: onOpen)
            .socialSubpageScroll()
            .refreshable { [model] in await model.load() }
            .task { [model] in await model.load() }
    }
}

/// Inhalt des Freundesrankings mit Kopfzeile (ohne Scrollen) – auch für Snapshot-Tests.
struct FriendsRankingContent: View {
    let model: FriendsRankingViewModel
    var onOpen: (SocialRoute) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: SocialText.social, title: SocialText.friends)
            PaceSegmentedControl(
                options: [(value: LeaderboardPeriod.daily, title: SocialText.today), (value: LeaderboardPeriod.weekly, title: SocialText.thisWeek)],
                selection: Binding(
                    get: { [model] in model.period },
                    set: { [model] period in Task { await model.select(period) } }
                )
            )
            switch model.state {
            case .unavailable(let message):
                SocialUnavailableCard(message: message)
            case .failed(let message):
                SocialFailedCard(message: message) {
                    Task { await model.load() }
                }
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .loaded(let entries):
                if entries.contains(where: { !$0.isCurrentUser }) {
                    VStack(spacing: PaceSpacing.xs) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                } else {
                    SocialEmptyCard(systemImage: "person.2", title: SocialText.friendsEmptyTitle, message: SocialText.friendsEmptyMessage)
                    Button {
                        onOpen(.addFriend)
                    } label: {
                        Label(SocialText.addFriend, systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.pacePrimary)
                }
            }
            Label {
                Text(SocialText.friendsPrivacyNote)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(PaceFont.caption)
            .foregroundStyle(PaceColor.textSecondary)
            .padding(.top, PaceSpacing.xs)
        }
    }

    @ViewBuilder
    private func row(_ entry: LeaderboardEntry) -> some View {
        let rankingRow = PaceRankingRow(
            rank: entry.rank,
            name: entry.isCurrentUser ? SocialText.you : entry.shownName,
            steps: entry.competitionSteps,
            seed: entry.publicUserID.uuidString,
            isCurrentUser: entry.isCurrentUser,
            showsStepIcon: true,
            showsChevron: !entry.isCurrentUser
        )
        if entry.isCurrentUser {
            rankingRow
        } else {
            Button {
                onOpen(.profile(entry.socialProfile))
            } label: {
                rankingRow
            }
            .buttonStyle(.pacePressable)
        }
    }
}
