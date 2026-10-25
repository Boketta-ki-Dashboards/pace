import DesignSystem
import PaceCore
import SocialFeature
import SwiftUI

/// Gruppen-Widget: eine gewählte Gruppe oder alle eigenen Gruppen mit Gruppen-Streak. Tippen öffnet die echte Gruppe.
///
/// Eine Gruppe: Klein = Name und Serie, ab Mittel die gewählten Zusatzinhalte (``HomeWidgetDetail``) – ohne eigene
/// Auswahl wie bisher: Mittel = dazu der heutige Fortschritt, Groß = dazu Tagesziel und beste Serie, Max = dazu
/// Mitglieder als Kennzahlen. Alle Gruppen: Klein = längste Serie, Mittel drei, Groß fünf, Max acht.
struct GroupsWidgetContent: View {
    let selection: HomeGroupSelection
    let state: SocialViewModel.State
    let size: HomeModuleSize
    var details: [HomeWidgetDetail] = HomeModuleKind.groups.defaultDetails(for: .medium)
    let onOpenGroup: (UUID) -> Void
    let onOpenSocial: () -> Void

    var body: some View {
        switch state {
        case .unavailable(let message):
            HomeWidgetHint(systemImage: "person.3", text: message)
        case .failed(let message) where isEmpty:
            HomeWidgetHint(systemImage: "arrow.clockwise", text: message)
        case .idle:
            HomeWidgetLoading(minHeight: size == .small ? 44 : 60)
        case .loading where isEmpty:
            HomeWidgetLoading(minHeight: size == .small ? 44 : 60)
        default:
            switch selection {
            case .single(let group):
                single(group)
            case .all(let groups):
                all(groups)
            case .missing:
                HomeWidgetHint(systemImage: "person.3", text: HomeGroupSelection.missingText)
            }
        }
    }

    private var isEmpty: Bool {
        if case .all(let groups) = selection { return groups.isEmpty }
        return false
    }

    @ViewBuilder
    private func single(_ group: GroupSummary) -> some View {
        Button {
            onOpenGroup(group.id)
        } label: {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(spacing: PaceSpacing.s) {
                    PaceAvatar(name: group.name, seed: group.id.uuidString, size: size == .small ? 40 : 48, image: group.image)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(HomeGroupTexts.members(group.memberCount))
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    Spacer(minLength: PaceSpacing.xs)
                    GroupStreakBadge(days: group.currentStreak)
                }
                if size >= .medium, details.contains(.groupProgress) {
                    VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                        PaceProgressBar(progress: progress(group), height: 10)
                        Text(HomeGroupTexts.todayProgress(group))
                            .font(PaceFont.caption)
                            .foregroundStyle(group.todayComplete ? PaceColor.accent : PaceColor.textSecondary)
                    }
                }
                if size >= .medium, details.contains(.groupGoal) {
                    HStack(spacing: PaceSpacing.xs) {
                        HomeStatTile(title: HomeGroupTexts.dailyGoal, value: PaceLocalization.steps(group.dailyGoal))
                        HomeStatTile(title: HomeGroupTexts.bestStreak, value: PaceLocalization.days(group.bestStreak))
                    }
                }
                if size >= .medium, details.contains(.groupMembers) {
                    HStack(spacing: PaceSpacing.xs) {
                        HomeStatTile(title: HomeGroupTexts.membersTitle, value: group.memberCount.paceFormatted)
                        HomeStatTile(
                            title: HomeGroupTexts.todayTitle,
                            value: "\(group.todayReachedCount.paceFormatted) / \(group.todayRequiredCount.paceFormatted)"
                        )
                    }
                    if size == .max, !group.description.isEmpty {
                        Text(group.description)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint(PaceLocalization.text(de: "Öffnet die Gruppe", en: "Opens the group", ru: "Открывает группу"))
    }

    @ViewBuilder
    private func all(_ groups: [GroupSummary]) -> some View {
        if groups.isEmpty {
            Button(action: onOpenSocial) {
                HStack(spacing: PaceSpacing.m) {
                    Image(systemName: "person.3")
                        .font(.title3)
                        .foregroundStyle(PaceColor.accent)
                        .frame(width: 48, height: 48)
                        .background(PaceColor.accentSoft, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PaceLocalization.text(de: "Noch keine Gruppen", en: "No groups yet", ru: "Пока нет групп"))
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                        Text(PaceLocalization.text(
                            de: "Erstelle eine Gruppe für Klasse, Team oder Freunde – oder tritt per Code bei.",
                            en: "Create a group for your class, team or friends – or join with a code.",
                            ru: "Создай группу для класса, команды или друзей – или вступи по коду."
                        ))
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
        } else if size == .small, let best = groups.max(by: { $0.currentStreak < $1.currentStreak }) {
            single(best)
        } else {
            VStack(spacing: PaceSpacing.xs) {
                ForEach(groups.prefix(limit)) { group in
                    Button {
                        onOpenGroup(group.id)
                    } label: {
                        GroupStreakRow(group: group, showsChevron: true)
                    }
                    .buttonStyle(.pacePressable)
                }
            }
        }
    }

    private var limit: Int {
        switch size {
        case .small: 1
        case .medium: 3
        case .large: 5
        case .max: 8
        }
    }

    private func progress(_ group: GroupSummary) -> Double {
        guard group.todayRequiredCount > 0 else { return group.todayComplete ? 1 : 0 }
        return Double(group.todayReachedCount) / Double(group.todayRequiredCount)
    }
}

/// Flamme mit Gruppen-Serie.
private struct GroupStreakBadge: View {
    let days: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: days > 0 ? "flame.fill" : "flame")
                .foregroundStyle(days > 0 ? PaceColor.streak : PaceColor.textSecondary)
                .accessibilityHidden(true)
            Text(days.paceFormatted)
                .font(.system(.headline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeGroupTexts.streak(days))
    }
}
