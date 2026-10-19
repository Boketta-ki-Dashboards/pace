import DesignSystem
import PaceCore
import SwiftUI

/// Gruppendetails (Referenzbild 4): Gruppen-Streak, Fortschritt des Tages, Gruppenchat, Mitglieder, Einstellungen
/// und „Heute in der Gruppe“.
struct GroupDetailView: View {
    @State private var viewModel: GroupDetailViewModel
    private let onOpen: (SocialRoute) -> Void
    private let onOpenChat: (ChatTarget) -> Void

    init(
        viewModel: GroupDetailViewModel,
        onOpen: @escaping (SocialRoute) -> Void,
        onOpenChat: @escaping (ChatTarget) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onOpen = onOpen
        self.onOpenChat = onOpenChat
    }

    var body: some View {
        GroupDetailContent(viewModel: viewModel, onOpen: onOpen, onOpenChat: onOpenChat)
            .socialSubpageScroll()
            .refreshable { [viewModel] in await viewModel.load() }
            .task { [viewModel] in await viewModel.load() }
    }
}

/// Inhalt der Gruppendetails mit Kopf (ohne Scrollen) – auch für Snapshot-Tests.
struct GroupDetailContent: View {
    let viewModel: GroupDetailViewModel
    var onOpen: (SocialRoute) -> Void = { _ in }
    var onOpenChat: (ChatTarget) -> Void = { _ in }

    private var group: GroupSummary { viewModel.group }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            SocialBackHeader(backTitle: SocialText.social)
            if viewModel.state == .gone {
                PaceStatusView(systemImage: "person.3", title: SocialText.groupGoneTitle, message: SocialText.groupGoneMessage)
            } else {
                groupHeader
                if let notice = viewModel.notice {
                    NoticeBanner(notice: notice) { viewModel.dismissNotice() }
                }
                streakCard
                progressCard
                navigationCards
                ranking
            }
        }
    }

    // MARK: Kopf

    private var groupHeader: some View {
        HStack(spacing: PaceSpacing.m) {
            GroupAvatar(name: group.name, kind: group.kind, image: group.image, size: 76)
            VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                Text(group.name)
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Label {
                    Text(SocialText.members(group.memberCount))
                } icon: {
                    Image(systemName: "person.2")
                }
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PaceSpacing.xs)
    }

    // MARK: Streak und Fortschritt

    private var streakCard: some View {
        PaceCard {
            HStack(spacing: PaceSpacing.m) {
                Image(systemName: group.currentStreak > 0 ? "flame.fill" : "flame")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(group.currentStreak > 0 ? PaceColor.streak : PaceColor.textSecondary)
                    .frame(width: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SocialText.streakTitle(group.currentStreak))
                        .font(.system(.title2, weight: .bold))
                        .foregroundStyle(PaceColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(SocialText.goalPerMember(group.dailyGoal))
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let next = group.nextDailyGoal, next != group.dailyGoal {
                        Text(SocialText.nextGoal(next))
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var progressCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                Text(viewModel.todayText)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                memberPills
                VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            requiredGoalsLabel
                            Spacer(minLength: PaceSpacing.xs)
                            flameStatusLabel
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            requiredGoalsLabel
                            flameStatusLabel
                        }
                    }
                    PaceProgressBar(progress: viewModel.requiredProgress, height: 14)
                    Text(viewModel.thirdRuleText)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(PaceSpacing.s)
                .background(PaceColor.accentSoft, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                        .strokeBorder(PaceColor.accent.opacity(0.25), lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var requiredGoalsLabel: some View {
        Text(viewModel.requiredGoalsText)
            .font(PaceFont.callout)
            .foregroundStyle(PaceColor.textPrimary)
    }

    private var flameStatusLabel: some View {
        Text(viewModel.flameStatusText)
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(group.todayComplete ? PaceColor.accent : PaceColor.textSecondary)
    }

    /// Eine Pille je Mitglied (bei sehr großen Gruppen ein Balken).
    @ViewBuilder
    private var memberPills: some View {
        let pills = viewModel.memberPills
        Group {
            if pills.isEmpty {
                Text(SocialText.noMembersToday)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
            } else if pills.count <= 20 {
                HStack(spacing: pills.count > 12 ? 4 : 6) {
                    ForEach(Array(pills.enumerated()), id: \.offset) { pill in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(pill.element ? PaceColor.goalReachedFill : PaceColor.track)
                            .frame(maxWidth: 40)
                            .frame(height: 30)
                    }
                }
            } else {
                PaceProgressBar(
                    progress: Double(group.todayReachedCount) / Double(max(group.memberCount, 1)),
                    height: 14
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.todayText)
    }

    // MARK: Navigation

    private var navigationCards: some View {
        HStack(spacing: PaceSpacing.xs) {
            navigationCard(SocialText.groupChat, systemImage: "bubble.left.and.bubble.right") {
                onOpenChat(.group(id: group.id, name: group.name))
            }
            navigationCard(SocialText.membersTitle, systemImage: "person.2") {
                onOpen(.groupMembers(group.id))
            }
            navigationCard(SocialText.settings, systemImage: "gearshape") {
                onOpen(.groupSettings(group.id))
            }
        }
    }

    private func navigationCard(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: PaceSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(PaceColor.textPrimary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, PaceSpacing.s)
            .padding(.horizontal, PaceSpacing.xxs)
            .frame(maxWidth: .infinity, minHeight: 76)
            .paceCardBackground(cornerRadius: PaceRadius.tile)
        }
        .buttonStyle(.pacePressable)
        .accessibilityLabel(title)
    }

    // MARK: Heute in der Gruppe

    @ViewBuilder
    private var ranking: some View {
        SocialSectionTitle(SocialText.todayInGroup)
        if let ranking = viewModel.currentRanking {
            if ranking.entries.isEmpty {
                Text(SocialText.noMembersToday)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
            } else {
                VStack(spacing: PaceSpacing.xs) {
                    ForEach(ranking.entries) { entry in
                        rankingRow(entry)
                    }
                }
            }
        } else if case .failed(let message) = viewModel.state {
            SocialFailedCard(message: message) {
                Task { await viewModel.load() }
            }
        } else if viewModel.rankingFailed {
            SocialFailedCard(message: SocialText.rankingNotLoaded) {
                Task { await viewModel.reloadRanking() }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    @ViewBuilder
    private func rankingRow(_ entry: GroupRankingEntry) -> some View {
        let row = PaceRankingRow(
            rank: entry.rank,
            name: entry.profile.displayName,
            steps: entry.competitionSteps,
            seed: entry.profile.publicID.uuidString,
            image: entry.profile.avatar,
            isCurrentUser: entry.isCurrentUser,
            showsStepIcon: true,
            showsChevron: !entry.isCurrentUser
        )
        if entry.isCurrentUser {
            row
        } else {
            Button {
                onOpen(.profile(entry.profile))
            } label: {
                row
            }
            .buttonStyle(.pacePressable)
        }
    }
}
