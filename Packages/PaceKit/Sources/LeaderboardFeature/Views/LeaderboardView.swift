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
                LeaderboardContent(viewModel: viewModel)
                    .padding(.horizontal, PaceSpacing.m)
                    .padding(.bottom, PaceSpacing.l)
            }
            .refreshable { [viewModel] in await viewModel.refresh() }
            .navigationTitle("Rankings")
            .paceScreenBackground()
        }
        .task(id: viewModel.reloadKey) { [viewModel] in
            await viewModel.loadIfNeeded()
        }
    }
}

/// Inhalt des Rankings-Tabs (ohne Navigation und Scrollen).
struct LeaderboardContent: View {
    let viewModel: LeaderboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
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
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            PaceCard {
                PaceLoadingView("Ranking wird geladen …")
                    .frame(minHeight: 220)
            }

        case .failed(let message):
            PaceCard {
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
            }

        case .loaded(let snapshot):
            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    LeaderboardList(
                        title: viewModel.selectedScope?.displayName ?? "Heute",
                        snapshot: snapshot,
                        emptyStateText: viewModel.emptyStateText
                    )

                    if let progress = viewModel.progressText {
                        Label(progress, systemImage: "arrow.up.forward.circle")
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if viewModel.canLoadMore || viewModel.isLoadingMore {
                        Button {
                            Task { await viewModel.loadMore() }
                        } label: {
                            if viewModel.isLoadingMore {
                                ProgressView().tint(PaceColor.accentStrong)
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
                }
            }

            Label("Es zählen nur Wettbewerbsschritte – manuell eingetragene Schritte nicht.", systemImage: "checkmark.shield")
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .padding(.horizontal, PaceSpacing.xxs)
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
                            .padding(.horizontal, PaceSpacing.m)
                            .padding(.vertical, PaceSpacing.xs + 2)
                            .foregroundStyle(isSelected ? PaceColor.onAccent : PaceColor.textPrimary)
                            .background(isSelected ? PaceColor.accentStrong : PaceColor.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : PaceColor.border, lineWidth: 1))
                    }
                    .buttonStyle(.pacePressable)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// Hinweis für Nutzer, die (noch) nicht in regionalen Rankings erscheinen.
private struct ParticipationBanner: View {
    let viewModel: LeaderboardViewModel

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(alignment: .top, spacing: PaceSpacing.s) {
                    Image(systemName: "eye.slash")
                        .font(.headline)
                        .foregroundStyle(PaceColor.accentStrong)
                        .frame(width: 36, height: 36)
                        .background(PaceColor.accentSoft, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                        Text("Du erscheinst noch nicht in regionalen Rankings.")
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                        Text("Wenn du regional antrittst, sehen andere deinen Anzeigenamen, deinen Benutzernamen und deine Wettbewerbsschritte.")
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
    let title: String
    let snapshot: LeaderboardSnapshot
    let emptyStateText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                // Lange Namen („Landkreis Mecklenburgische Seenplatte“) dürfen zweizeilig werden statt gekürzt.
                Text(title)
                    .font(PaceFont.cardTitle)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: PaceSpacing.xs)
                Text("Heute · \(participantsText)")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            if let emptyStateText {
                Label(emptyStateText, systemImage: snapshot.isCurrentUserAlone ? "flag.checkered" : "person.2")
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, PaceSpacing.xxs)
            }

            VStack(spacing: PaceSpacing.xs) {
                ForEach(snapshot.rows) { row in
                    switch row {
                    case .entry(let entry):
                        LeaderboardEntryRow(entry: entry)
                    case .gap:
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(PaceColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, PaceSpacing.xxs)
                            .accessibilityLabel("Weitere Plätze ausgelassen")
                    }
                }
            }
        }
    }

    private var participantsText: String {
        snapshot.totalParticipants == 1 ? "1 Teilnehmer" : "\(snapshot.totalParticipants.paceFormatted) Teilnehmer"
    }
}

private struct LeaderboardEntryRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        PaceTile(isHighlighted: entry.isCurrentUser) {
            HStack(spacing: PaceSpacing.s) {
                rank
                PaceAvatar(
                    name: entry.displayName,
                    seed: entry.publicUserID.uuidString,
                    size: 36,
                    isHighlighted: entry.isCurrentUser
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.isCurrentUser ? "DU" : entry.displayName)
                        .font(.system(.headline, weight: entry.isCurrentUser ? .bold : .semibold))
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                    Text("@\(entry.username)")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: PaceSpacing.xs)
                Text(entry.competitionSteps.paceFormatted)
                    .font(.system(.headline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var rank: some View {
        if entry.rank <= 3 {
            Image(systemName: "\(entry.rank).circle.fill")
                .font(.title2)
                .foregroundStyle(Self.medalColor(entry.rank))
                .frame(minWidth: 40, alignment: .leading)
        } else {
            Text("#\(entry.rank)")
                .font(.system(.headline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
                .frame(minWidth: 40, alignment: .leading)
        }
    }

    private static func medalColor(_ rank: Int) -> Color {
        switch rank {
        case 1: Color(red: 0.86, green: 0.65, blue: 0.13)
        case 2: Color(red: 0.6, green: 0.62, blue: 0.66)
        default: Color(red: 0.72, green: 0.45, blue: 0.24)
        }
    }

    private var accessibilityText: String {
        let name = entry.isCurrentUser ? "\(entry.displayName), du" : entry.displayName
        return "Platz \(entry.rank), \(name), \(entry.competitionSteps.paceFormatted) Schritte"
    }
}
