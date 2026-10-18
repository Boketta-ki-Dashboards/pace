import DesignSystem
import PaceCore
import SwiftUI

/// „Pfungstadt · Dein Umfeld“: die Plätze um deinen – und wie viele Schritte zum nächsten Platz fehlen.
///
/// Die Ebene (Gemeinde, Kreis, Bundesland, Land) ist pro Modul wählbar. Klein zeigt nur deinen Platz, mittel drei,
/// groß fünf Zeilen.
struct NeighborhoodCardView: View {
    let standings: RegionalStandingsViewModel
    var level: RegionLevel = .municipality
    var size: HomeModuleSize = .medium
    let onOpenRankings: (Region?) -> Void

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                Button {
                    onOpenRankings(region)
                } label: {
                    // Lange Regionsnamen („Darmstadt-Dieburg · Dein Umfeld“) dürfen zweizeilig werden statt gekürzt.
                    HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
                        Text(title)
                            .font(PaceFont.cardTitle)
                            .foregroundStyle(PaceColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: PaceSpacing.xs)
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(PaceColor.textPrimary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)

                content
            }
        }
    }

    /// Gibt es die gewählte Ebene für die Region nicht (z. B. Kreis bei einer kreisfreien Stadt), die nächst kleinere.
    private var shownLevel: RegionLevel {
        standings.effectiveLevel(for: level)
    }

    private var region: Region? {
        standings.scopes.first { $0.level == shownLevel }
    }

    private var title: String {
        region.map { "\($0.name) · Dein Umfeld" } ?? "Dein Umfeld"
    }

    private var rowCount: Int {
        switch size {
        case .small: 1
        case .medium: 3
        case .large: 5
        }
    }

    @ViewBuilder
    private var content: some View {
        switch standings.state {
        case .idle, .loading:
            if let neighborhood = standings.standings?.neighborhood(for: shownLevel, rows: rowCount) {
                rows(neighborhood)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            }

        case .failed(let message):
            hint(message, systemImage: "wifi.exclamationmark")

        case .loaded(let loaded):
            if !loaded.isParticipating {
                participationPrompt
            } else if let neighborhood = loaded.neighborhood(for: shownLevel, rows: rowCount) {
                rows(neighborhood)
            } else {
                hint(
                    "Sobald deine heutigen Schritte synchronisiert sind, siehst du hier, wer vor und hinter dir liegt.",
                    systemImage: "figure.walk"
                )
            }
        }
    }

    @ViewBuilder
    private func rows(_ neighborhood: RegionalStandings.Neighborhood) -> some View {
        VStack(spacing: PaceSpacing.xs) {
            ForEach(neighborhood.entries) { entry in
                Button {
                    onOpenRankings(neighborhood.region)
                } label: {
                    NeighborRow(entry: entry)
                }
                .buttonStyle(.pacePressable)
            }
        }
        if !neighborhood.footerText.isEmpty {
            Text(neighborhood.footerText)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
        }
    }

    private var participationPrompt: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            Text("Du erscheinst noch nicht in regionalen Rankings. Tritt an, um zu sehen, wer vor und hinter dir liegt.")
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = standings.participationError {
                Text(error)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.danger)
            }
            Button {
                Task { await standings.enableParticipation() }
            } label: {
                if standings.isUpdatingParticipation {
                    ProgressView().tint(PaceColor.onAccent)
                } else {
                    Text("Regional antreten")
                }
            }
            .buttonStyle(.paceCompact)
            .disabled(standings.isUpdatingParticipation)
        }
    }

    private func hint(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(PaceFont.callout)
            .foregroundStyle(PaceColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct NeighborRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        PaceTile(isHighlighted: entry.isCurrentUser) {
            HStack(spacing: PaceSpacing.s) {
                Text("#\(entry.rank)")
                    .font(.system(.headline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .frame(minWidth: 44, alignment: .leading)
                PaceAvatar(
                    name: entry.displayName,
                    seed: entry.publicUserID.uuidString,
                    size: 36,
                    isHighlighted: entry.isCurrentUser
                )
                Text(entry.isCurrentUser ? "DU" : entry.displayName)
                    .font(entry.isCurrentUser ? .system(.headline, weight: .bold) : PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: PaceSpacing.xs)
                Text(entry.competitionSteps.paceFormatted)
                    .font(.system(.headline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Platz \(entry.rank), \(entry.isCurrentUser ? "du" : entry.displayName), \(entry.competitionSteps.paceFormatted) Schritte")
    }
}
