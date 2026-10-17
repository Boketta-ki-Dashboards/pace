import DesignSystem
import PaceCore
import SwiftUI

/// Tagesrankings: Ebene wählen, Top-Plätze und eigene Position sehen.
public struct LeaderboardView: View {
    private let viewModel: LeaderboardViewModel

    public init(viewModel: LeaderboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpacing.m) {
                    if !viewModel.scopes.isEmpty {
                        ScopePicker(
                            scopes: viewModel.scopes,
                            selectedID: viewModel.selectedScope?.id
                        ) { scope in
                            Task { await viewModel.select(scope) }
                        }
                    }

                    if !viewModel.isParticipating {
                        ParticipationBanner(viewModel: viewModel)
                    }

                    content
                }
                .padding(PaceSpacing.m)
            }
            .refreshable { await viewModel.refresh() }
            .navigationTitle("Rankings")
            .paceScreenBackground()
        }
        .task(id: viewModel.reloadKey) { [viewModel] in
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            PaceLoadingView("Ranking wird geladen …")
                .frame(minHeight: 240)

        case .failed(let message):
            PaceStatusView(
                systemImage: "wifi.exclamationmark",
                title: "Ranking nicht verfügbar",
                message: message,
                tint: PaceColor.warning
            ) {
                Button("Erneut versuchen") {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.pacePrimary)
            }

        case .loaded(let snapshot):
            LeaderboardList(snapshot: snapshot, emptyStateText: viewModel.emptyStateText)

            if viewModel.canLoadMore || viewModel.isLoadingMore {
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    if viewModel.isLoadingMore {
                        ProgressView().tint(PaceColor.accent)
                    } else {
                        Text("Weitere Plätze laden")
                    }
                }
                .buttonStyle(.paceSecondary)
                .disabled(viewModel.isLoadingMore)
            }
            if let error = viewModel.loadMoreError {
                Text(error)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.danger)
            }

            Text("Es zählen nur Wettbewerbsschritte – manuell eingetragene Schritte nicht.")
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
        }
    }
}

/// Auswahl der Ebene: Gemeinde, Kreis, Bundesland, Deutschland.
private struct ScopePicker: View {
    let scopes: [Region]
    let selectedID: RegionID?
    let onSelect: (Region) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PaceSpacing.xs) {
                ForEach(scopes) { scope in
                    let isSelected = scope.id == selectedID
                    Button {
                        onSelect(scope)
                    } label: {
                        Text(scope.displayName)
                            .font(PaceFont.callout.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, PaceSpacing.s)
                            .padding(.vertical, PaceSpacing.xs)
                            .foregroundStyle(isSelected ? PaceColor.onAccent : PaceColor.textPrimary)
                            .background(isSelected ? PaceColor.accent : PaceColor.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

/// Hinweis für Nutzer, die (noch) nicht in regionalen Rankings erscheinen.
private struct ParticipationBanner: View {
    let viewModel: LeaderboardViewModel

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                Label("Du erscheinst noch nicht in regionalen Rankings.", systemImage: "eye.slash")
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                Text("Wenn du regional antrittst, sehen andere deinen Anzeigenamen, deinen Benutzernamen und deine Wettbewerbsschritte.")
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = viewModel.participationError {
                    Text(error)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.danger)
                }
                Button {
                    Task { await viewModel.enableParticipation() }
                } label: {
                    if viewModel.isUpdatingParticipation {
                        ProgressView().tint(PaceColor.onAccent)
                    } else {
                        Text("Regional antreten")
                    }
                }
                .buttonStyle(.pacePrimary)
                .disabled(viewModel.isUpdatingParticipation)
            }
        }
    }
}

/// Die Plätze eines Rankings.
private struct LeaderboardList: View {
    let snapshot: LeaderboardSnapshot
    let emptyStateText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSectionHeader("Heute", detail: participantsText)

            if let emptyStateText {
                PaceCard {
                    Label(emptyStateText, systemImage: snapshot.isCurrentUserAlone ? "flag.checkered" : "person.2")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !snapshot.rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(snapshot.rows) { row in
                        switch row {
                        case .entry(let entry):
                            LeaderboardEntryRow(entry: entry)
                        case .gap:
                            Text("…")
                                .font(PaceFont.headline)
                                .foregroundStyle(PaceColor.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, PaceSpacing.xxs)
                                .accessibilityLabel("Weitere Plätze ausgelassen")
                        }
                    }
                }
                .background(PaceColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
            }
        }
    }

    private var participantsText: String {
        snapshot.totalParticipants == 1 ? "1 Teilnehmer" : "\(snapshot.totalParticipants.formatted(.number)) Teilnehmer"
    }
}

private struct LeaderboardEntryRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        HStack(spacing: PaceSpacing.s) {
            Text("\(entry.rank)")
                .font(PaceFont.headline.monospacedDigit())
                .foregroundStyle(entry.rank <= 3 ? PaceColor.accent : PaceColor.textSecondary)
                .frame(minWidth: 32, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: PaceSpacing.xxs) {
                    Text(entry.displayName)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                    if entry.isCurrentUser {
                        Text("Du")
                            .font(PaceFont.caption.weight(.bold))
                            .foregroundStyle(PaceColor.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(PaceColor.accent, in: Capsule())
                    }
                }
                Text("@\(entry.username)")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: PaceSpacing.xs)

            Text(entry.competitionSteps.formatted(.number))
                .font(PaceFont.headline.monospacedDigit())
                .foregroundStyle(PaceColor.textPrimary)
        }
        .padding(.horizontal, PaceSpacing.m)
        .padding(.vertical, PaceSpacing.s)
        .background(entry.isCurrentUser ? PaceColor.accent.opacity(0.12) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let name = entry.isCurrentUser ? "\(entry.displayName), du" : entry.displayName
        return "Platz \(entry.rank), \(name), \(entry.competitionSteps.formatted(.number)) Schritte"
    }
}
