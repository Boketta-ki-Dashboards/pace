import DesignSystem
import PaceCore
import SocialFeature
import SwiftUI

/// „Deine Freunde“: Rangliste mit deinen Freunden (heute). Klein: dein Platz. Mittel: drei Zeilen. Groß: fünf.
struct FriendsPreviewCardView: View {
    let social: SocialViewModel
    var size: HomeModuleSize = .medium
    let onOpenSocial: () -> Void

    var body: some View {
        Button(action: onOpenSocial) {
            if size == .small {
                CompactSocialRow(systemImage: "person.2.fill", title: "Deine Freunde", detail: compactDetail)
            } else {
                PaceCard {
                    VStack(alignment: .leading, spacing: PaceSpacing.s) {
                        PaceCardHeader("Deine Freunde", actionTitle: "Alle ansehen")
                        content
                    }
                }
            }
        }
        .buttonStyle(.pacePressable)
    }

    private var hasFriends: Bool {
        social.ranking.count > 1 || !social.friends.isEmpty
    }

    private var compactDetail: String {
        switch social.state {
        case .unavailable: return "Nicht verfügbar"
        case .failed where social.ranking.isEmpty: return "Nicht geladen"
        case .idle: return "Wird geladen …"
        case .loading where social.ranking.isEmpty: return "Wird geladen …"
        default:
            guard hasFriends, let me = social.ranking.first(where: \.isCurrentUser) else { return "Noch keine Freunde" }
            return "Platz \(me.rank) von \(social.ranking.count)"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch social.state {
        case .unavailable(let message):
            SocialHint(systemImage: "person.2.slash", text: message)
        case .failed(let message):
            SocialHint(systemImage: "wifi.exclamationmark", text: message)
        case .idle:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 60)
        case .loading where social.ranking.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 60)
        default:
            if hasFriends {
                VStack(spacing: PaceSpacing.xs) {
                    ForEach(rows) { entry in
                        FriendRankRow(entry: entry)
                    }
                }
            } else {
                HStack(spacing: PaceSpacing.m) {
                    PlaceholderAvatars()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Noch keine Freunde")
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                        Text("Suche im Social-Tab nach einem Benutzernamen und vergleicht euch jeden Tag.")
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Ausschnitt um den eigenen Platz.
    private var rows: [LeaderboardEntry] {
        let count = size == .large ? 5 : 3
        let entries = social.ranking
        guard let index = entries.firstIndex(where: \.isCurrentUser), entries.count > count else {
            return Array(entries.prefix(count))
        }
        let start = min(max(index - (count - 1) / 2, 0), entries.count - count)
        return Array(entries[start..<(start + count)])
    }
}

/// „Deine Gruppen“ mit Gruppen-Streak. Klein: die längste laufende Serie. Mittel: drei Gruppen. Groß: fünf.
struct GroupsPreviewCardView: View {
    let social: SocialViewModel
    var size: HomeModuleSize = .medium
    let onOpenSocial: () -> Void

    var body: some View {
        Button(action: onOpenSocial) {
            if size == .small {
                CompactSocialRow(systemImage: "person.3.fill", title: "Deine Gruppen", detail: compactDetail)
            } else {
                PaceCard {
                    VStack(alignment: .leading, spacing: PaceSpacing.s) {
                        PaceCardHeader("Deine Gruppen", actionTitle: "Alle ansehen")
                        content
                    }
                }
            }
        }
        .buttonStyle(.pacePressable)
    }

    private var compactDetail: String {
        switch social.state {
        case .unavailable: return "Nicht verfügbar"
        case .failed where social.groups.isEmpty: return "Nicht geladen"
        case .idle: return "Wird geladen …"
        case .loading where social.groups.isEmpty: return "Wird geladen …"
        default:
            guard let best = social.groups.max(by: { $0.currentStreak < $1.currentStreak }) else { return "Noch keine Gruppen" }
            // Serie zuerst: Wird gekürzt, trifft es den Gruppennamen, nicht die Zahl.
            return "\(best.currentStreak == 1 ? "1 Tag" : "\(best.currentStreak) Tage") · \(best.name)"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch social.state {
        case .unavailable(let message):
            SocialHint(systemImage: "person.3", text: message)
        case .failed(let message):
            SocialHint(systemImage: "wifi.exclamationmark", text: message)
        case .idle:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 60)
        case .loading where social.groups.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 60)
        default:
            if social.groups.isEmpty {
                HStack(spacing: PaceSpacing.m) {
                    Image(systemName: "person.3.fill")
                        .font(.title3)
                        .foregroundStyle(PaceColor.accentStrong)
                        .frame(width: 52, height: 52)
                        .background(PaceColor.accentSoft, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Noch keine Gruppen")
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                        Text("Erstelle eine Gruppe für Klasse, Team oder Freunde – oder tritt per Code bei.")
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(spacing: PaceSpacing.xs) {
                    ForEach(social.groups.prefix(size == .large ? 5 : 3)) { group in
                        GroupStreakRow(group: group)
                    }
                }
            }
        }
    }
}

private struct FriendRankRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        PaceTile(isHighlighted: entry.isCurrentUser) {
            HStack(spacing: PaceSpacing.s) {
                Text("#\(entry.rank)")
                    .font(.system(.headline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .frame(minWidth: 36, alignment: .leading)
                PaceAvatar(name: entry.displayName, seed: entry.publicUserID.uuidString, size: 32, isHighlighted: entry.isCurrentUser)
                Text(entry.isCurrentUser ? "DU" : entry.displayName)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: PaceSpacing.xs)
                Text(entry.competitionSteps.paceFormatted)
                    .font(.system(.headline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Platz \(entry.rank), \(entry.isCurrentUser ? "du" : entry.displayName), \(entry.competitionSteps.paceFormatted) Schritte")
    }
}

private struct SocialHint: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(PaceFont.callout)
            .foregroundStyle(PaceColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Kleine Variante der Social-Module: eine Zeile, öffnet den Social-Tab.
private struct CompactSocialRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        PaceCard(padding: PaceSpacing.s) {
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                Text(title)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                Spacer(minLength: PaceSpacing.xs)
                Text(detail)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Drei angedeutete Profilbilder für Leerzustände.
private struct PlaceholderAvatars: View {
    var body: some View {
        HStack(spacing: -14) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(PaceColor.textSecondary.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .background(PaceColor.surfaceSecondary, in: Circle())
                    .overlay(Circle().strokeBorder(PaceColor.border, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .zIndex(Double(3 - index))
            }
        }
        .accessibilityHidden(true)
    }
}
