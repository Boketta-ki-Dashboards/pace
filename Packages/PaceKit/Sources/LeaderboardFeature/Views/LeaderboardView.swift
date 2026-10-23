import DesignSystem
import PaceCore
import SwiftUI

/// Rankings-Tab: Pace-Wortmarke und Titel wie die anderen Tabs, Auswahl der Ebene (Gemeinde, Kreis, Bundesland,
/// Deutschland, Freunde) und die Plätze mit dem eigenen Umfeld.
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
                    // Rankings hat keine Unterseiten: erneutes Antippen scrollt nach oben.
                    .paceTabRoot(isAtRoot: true) {}
            }
            .refreshable { [viewModel] in await viewModel.refresh() }
            .paceScreenBackground()
            .paceRootPage()
        }
        .task(id: viewModel.reloadKey) { [viewModel] in
            await viewModel.loadIfNeeded()
        }
    }
}

/// Inhalt des Rankings-Tabs inklusive Kopf (ohne Navigation und Scrollen) – auch für Snapshots.
struct LeaderboardContent: View {
    let viewModel: LeaderboardViewModel

    @State private var confirmsVisibility = false

    init(viewModel: LeaderboardViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            header

            if !viewModel.scopes.isEmpty || viewModel.offersFriends {
                ScopePicker(
                    scopes: viewModel.scopes,
                    selectedID: viewModel.isShowingFriends || viewModel.isShowingGroups ? nil : viewModel.selectedScope?.id,
                    offersFriends: viewModel.offersFriends,
                    isFriendsSelected: viewModel.isShowingFriends,
                    isGroupsSelected: viewModel.isShowingGroups,
                    onSelect: { scope in
                        Task { await viewModel.select(scope) }
                    },
                    onSelectFriends: {
                        Task { await viewModel.selectFriends() }
                    },
                    onSelectGroups: {
                        Task { await viewModel.selectGroups() }
                    }
                )
            }

            if viewModel.isShowingFriends {
                friendsContent
            } else if viewModel.isShowingGroups {
                groupsContent
            } else {
                regionalContent
            }

            Label(LeaderboardTexts.competitionNote, systemImage: "checkmark.shield")
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PaceSpacing.xxs)
        }
        .confirmationDialog(
            LeaderboardTexts.enableVisibility,
            isPresented: $confirmsVisibility,
            titleVisibility: .visible
        ) {
            Button(LeaderboardTexts.enable) {
                Task { await viewModel.enableParticipation() }
            }
            Button(LeaderboardTexts.cancel, role: .cancel) {}
        } message: {
            Text(LeaderboardTexts.visibilityExplanation)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
            PaceWordmark(height: 33)
            Text(LeaderboardTexts.title)
                .font(.system(.title, weight: .bold))
                .foregroundStyle(PaceColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, PaceSpacing.xs)
    }

    // MARK: Regional

    @ViewBuilder
    private var regionalContent: some View {
        switch viewModel.state {
        case .loading:
            PaceCard {
                PaceLoadingView(LeaderboardTexts.loading)
                    .frame(minHeight: 220)
            }

        case .hidden:
            HiddenRankingCard(
                title: viewModel.selectedScope?.displayName ?? LeaderboardTexts.title,
                isUpdating: viewModel.isUpdatingParticipation,
                onEnable: { confirmsVisibility = true }
            )
            if let error = viewModel.participationError {
                Text(error)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .failed(let message):
            failedCard(message)

        case .loaded(let snapshot):
            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    RankingCardHeader(
                        title: viewModel.selectedScope?.displayName ?? LeaderboardTexts.today,
                        detail: LeaderboardTexts.todayWithParticipants(snapshot.totalParticipants)
                    )

                    if let emptyStateText = viewModel.emptyStateText {
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
                                RankingRow(entry: entry)
                            case .gap:
                                Image(systemName: "ellipsis")
                                    .font(.headline)
                                    .foregroundStyle(PaceColor.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, PaceSpacing.xxs)
                                    .accessibilityLabel(LeaderboardTexts.gap)
                            }
                        }
                    }

                    if let progress = viewModel.progressText {
                        ProgressHint(text: progress)
                    }

                    if viewModel.canLoadMore || viewModel.isLoadingMore {
                        Button {
                            Task { await viewModel.loadMore() }
                        } label: {
                            if viewModel.isLoadingMore {
                                ProgressView().tint(PaceColor.accentStrong)
                            } else {
                                Text(LeaderboardTexts.loadMore)
                            }
                        }
                        .buttonStyle(.paceSecondary)
                        .disabled(viewModel.isLoadingMore)
                    }
                    if let error = viewModel.loadMoreError {
                        Text(error)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: Freunde

    @ViewBuilder
    private var friendsContent: some View {
        switch viewModel.friends {
        case .idle, .loading:
            PaceCard {
                PaceLoadingView(LeaderboardTexts.loading)
                    .frame(minHeight: 220)
            }
        case .failed(let message):
            failedCard(message)
        case .loaded(let entries):
            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    RankingCardHeader(
                        title: LeaderboardTexts.friends,
                        detail: LeaderboardTexts.todayWithParticipants(entries.count)
                    )
                    if entries.count <= 1 {
                        Label(LeaderboardTexts.addFriendsHint, systemImage: "person.badge.plus")
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, PaceSpacing.xxs)
                    }
                    VStack(spacing: PaceSpacing.xs) {
                        ForEach(entries) { entry in
                            RankingRow(entry: entry)
                        }
                    }
                    if let progress = viewModel.friendsProgressText, entries.count > 1 {
                        ProgressHint(text: progress)
                    }
                }
            }
        }
    }

    // MARK: Gruppen

    @ViewBuilder
    private var groupsContent: some View {
        switch viewModel.groups {
        case .idle, .loading:
            PaceCard {
                PaceLoadingView(LeaderboardTexts.loading)
                    .frame(minHeight: 220)
            }
        case .failed(let message):
            failedCard(message)
        case .loaded(let standings):
            if standings.isEmpty {
                PaceCard {
                    Label(LeaderboardTexts.noGroupsHint, systemImage: "person.3")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(standings) { standing in
                    GroupStandingCard(standing: standing)
                }
            }
        }
    }

    private func failedCard(_ message: String) -> some View {
        PaceCard {
            PaceStatusView(
                systemImage: "wifi",
                title: LeaderboardTexts.unavailable,
                message: message
            ) {
                Button(LeaderboardTexts.retry) {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.pacePrimary)
            }
        }
    }
}

/// Texte des Rankings-Tabs.
enum LeaderboardTexts {
    static var title: String { PaceLocalization.text(de: "Rankings", en: "Rankings", ru: "Рейтинги") }
    static var today: String { PaceLocalization.text(de: "Heute", en: "Today", ru: "Сегодня") }
    static var friends: String { PaceLocalization.text(de: "Freunde", en: "Friends", ru: "Друзья") }
    static var you: String { PaceLocalization.text(de: "DU", en: "YOU", ru: "ТЫ") }
    static var loading: String {
        PaceLocalization.text(de: "Ranking wird geladen …", en: "Loading ranking …", ru: "Рейтинг загружается…")
    }
    static var unavailable: String {
        PaceLocalization.text(de: "Ranking nicht verfügbar", en: "Ranking unavailable", ru: "Рейтинг недоступен")
    }
    static var retry: String { PaceLocalization.text(de: "Erneut versuchen", en: "Try again", ru: "Повторить") }
    static var loadMore: String { PaceLocalization.text(de: "Weitere Plätze laden", en: "Load more places", ru: "Показать больше мест") }
    static var gap: String { PaceLocalization.text(de: "Weitere Plätze ausgelassen", en: "More places skipped", ru: "Остальные места пропущены") }
    static var competitionNote: String {
        PaceLocalization.text(
            de: "Es zählen nur Wettbewerbsschritte – manuell eingetragene Schritte nicht.",
            en: "Only competition steps count – manually entered steps don't.",
            ru: "Учитываются только соревновательные шаги – шаги, введённые вручную, не считаются."
        )
    }
    static var hiddenTitle: String {
        PaceLocalization.text(de: "Ranking ausgeschaltet", en: "Ranking turned off", ru: "Рейтинг отключён")
    }
    static var hiddenMessage: String {
        PaceLocalization.text(
            de: "Aktiviere deine Ranking-Sichtbarkeit im Profil.",
            en: "Turn on your ranking visibility in your profile.",
            ru: "Включи видимость в рейтингах в профиле."
        )
    }
    static var enableVisibility: String {
        PaceLocalization.text(de: "Ranking-Sichtbarkeit aktivieren", en: "Turn on ranking visibility", ru: "Включить видимость в рейтингах")
    }
    static var visibilityExplanation: String {
        PaceLocalization.text(
            de: "Andere sehen dann in den regionalen Rankings deinen Anzeigenamen, deinen Benutzernamen und deine Wettbewerbsschritte. Du kannst das im Profil jederzeit wieder ausschalten.",
            en: "Others will then see your display name, your username and your competition steps in the regional rankings. You can turn this off again in your profile at any time.",
            ru: "Тогда в региональных рейтингах другие увидят твоё имя, имя пользователя и соревновательные шаги. Это можно в любой момент отключить в профиле."
        )
    }
    static var enable: String { PaceLocalization.text(de: "Aktivieren", en: "Turn on", ru: "Включить") }
    static var cancel: String { PaceLocalization.text(de: "Abbrechen", en: "Cancel", ru: "Отмена") }
    static var groups: String { PaceLocalization.text(de: "Gruppen", en: "Groups", ru: "Группы") }
    static var noGroupsHint: String {
        PaceLocalization.text(
            de: "Du bist noch in keiner Gruppe. Erstelle in Social eine Gruppe oder tritt einer bei.",
            en: "You're not in a group yet. Create or join a group in Social.",
            ru: "Ты пока не состоишь в группе. Создай группу или вступи в неё во вкладке «Друзья»."
        )
    }
    static var groupRankingUnavailable: String {
        PaceLocalization.text(
            de: "Das Ranking dieser Gruppe konnte nicht geladen werden.",
            en: "This group's ranking couldn't be loaded.",
            ru: "Не удалось загрузить рейтинг этой группы."
        )
    }

    /// `Heute · 6 Mitglieder`
    static func todayWithMembers(_ count: Int) -> String {
        let members = PaceLocalization.plural(
            count,
            de: ("Mitglied", "Mitglieder"),
            en: ("member", "members"),
            ru: ("участник", "участника", "участников")
        )
        return "\(today) · \(count.paceFormatted) \(members)"
    }

    static var addFriendsHint: String {
        PaceLocalization.text(
            de: "Füge in Social Freunde hinzu, um dich mit ihnen zu vergleichen.",
            en: "Add friends in Social to compare yourself with them.",
            ru: "Добавь друзей во вкладке «Друзья», чтобы соревноваться с ними."
        )
    }

    /// `Heute · 1.240 Teilnehmer`
    static func todayWithParticipants(_ count: Int) -> String {
        let participants = PaceLocalization.plural(
            count,
            de: ("Teilnehmer", "Teilnehmer"),
            en: ("participant", "participants"),
            ru: ("участник", "участника", "участников")
        )
        return "\(today) · \(count.paceFormatted) \(participants)"
    }
}

extension RegionLevel {
    /// `Stadt`, `Landkreis`, `Bundesland`, `Land` – wie auf den Home-Karten.
    var rankingTitle: String {
        switch self {
        case .municipality: PaceLocalization.text(de: "Stadt", en: "City", ru: "Город")
        case .district: PaceLocalization.text(de: "Landkreis", en: "District", ru: "Район")
        case .state: PaceLocalization.text(de: "Bundesland", en: "State", ru: "Земля")
        case .country: PaceLocalization.text(de: "Land", en: "Country", ru: "Страна")
        }
    }
}

/// Auswahl der Ebene: Gemeinde, Kreis, Bundesland, Deutschland und Freunde.
private struct ScopePicker: View {
    let scopes: [Region]
    let selectedID: RegionID?
    let offersFriends: Bool
    let isFriendsSelected: Bool
    let isGroupsSelected: Bool
    let onSelect: (Region) -> Void
    let onSelectFriends: () -> Void
    let onSelectGroups: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PaceSpacing.xs) {
                ForEach(scopes) { scope in
                    chip(level: scope.level.rankingTitle, name: scope.displayName, isSelected: scope.id == selectedID) {
                        onSelect(scope)
                    }
                }
                if offersFriends {
                    chip(level: nil, name: LeaderboardTexts.friends, isSelected: isFriendsSelected, action: onSelectFriends)
                    chip(level: nil, name: LeaderboardTexts.groups, isSelected: isGroupsSelected, action: onSelectGroups)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(level: String?, name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                if let level {
                    Text(level)
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(isSelected ? PaceColor.onAccent.opacity(0.85) : PaceColor.textSecondary)
                }
                Text(name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(isSelected ? PaceColor.onAccent : PaceColor.textPrimary)
            }
            .lineLimit(1)
            .padding(.horizontal, PaceSpacing.s)
            .frame(minHeight: 44)
            .background(
                isSelected ? PaceColor.accentStrong : PaceColor.surface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : PaceColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Titel der Ranking-Karte; lange Namen („Landkreis Mecklenburgische Seenplatte“) brechen um statt gekürzt zu werden.
private struct RankingCardHeader: View {
    let title: String
    let detail: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                titleText
                Spacer(minLength: PaceSpacing.xs)
                detailText
            }
            VStack(alignment: .leading, spacing: 2) {
                titleText
                detailText
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(PaceFont.cardTitle)
            .foregroundStyle(PaceColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var detailText: some View {
        Text(detail)
            .font(PaceFont.caption)
            .foregroundStyle(PaceColor.textSecondary)
            .lineLimit(1)
    }
}

/// Eine Ranking-Zeile wie auf Home und in den Gruppendetails; die eigene Zeile heißt „DU“ und ist dezent grün.
private struct RankingRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        PaceRankingRow(
            rank: entry.rank,
            name: entry.isCurrentUser ? LeaderboardTexts.you : entry.shownName,
            steps: entry.competitionSteps,
            seed: entry.publicUserID.uuidString,
            image: entry.avatar,
            isCurrentUser: entry.isCurrentUser,
            showsChevron: false,
            detail: entry.isCurrentUser ? nil : "@\(entry.username)"
        )
    }
}

/// Eine eigene Gruppe: Name, Mitglieder, die oberen Plätze und – falls weiter unten – die eigene Zeile.
private struct GroupStandingCard: View {
    let standing: LeaderboardViewModel.GroupStanding

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                RankingCardHeader(
                    title: standing.group.name,
                    detail: LeaderboardTexts.todayWithMembers(standing.group.memberCount)
                )
                if standing.ranking == nil {
                    Text(LeaderboardTexts.groupRankingUnavailable)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    let entries = standing.visibleEntries
                    VStack(spacing: PaceSpacing.xs) {
                        ForEach(entries) { entry in
                            if entry.isCurrentUser, standing.hasGap {
                                Image(systemName: "ellipsis")
                                    .font(.headline)
                                    .foregroundStyle(PaceColor.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityLabel(LeaderboardTexts.gap)
                            }
                            PaceRankingRow(
                                rank: entry.rank,
                                name: entry.isCurrentUser ? LeaderboardTexts.you : entry.profile.shownName,
                                steps: entry.competitionSteps,
                                seed: entry.profile.publicID.uuidString,
                                image: entry.profile.avatar,
                                isCurrentUser: entry.isCurrentUser,
                                showsStepIcon: true,
                                showsChevron: false
                            )
                        }
                    }
                }
            }
        }
    }
}

/// Aufstiegshinweis, z. B. „Noch 280 Schritte bis Platz #11“.
private struct ProgressHint: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "arrow.up.forward.circle")
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(PaceColor.accent)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Ranking ausgeschaltet: Grundstruktur der Karte mit neutralen Platzhaltern unter einer dezenten Unschärfe – ohne
/// echte Rankingdaten (sie werden gar nicht geladen).
private struct HiddenRankingCard: View {
    let title: String
    let isUpdating: Bool
    let onEnable: () -> Void

    var body: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                Text(title)
                    .font(PaceFont.cardTitle)
                    .foregroundStyle(PaceColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                PaceLockedCard(
                    title: LeaderboardTexts.hiddenTitle,
                    message: LeaderboardTexts.hiddenMessage,
                    actionTitle: isUpdating ? nil : LeaderboardTexts.enableVisibility,
                    action: isUpdating ? nil : onEnable
                ) {
                    VStack(spacing: PaceSpacing.xs) {
                        ForEach(0..<4, id: \.self) { index in
                            placeholderRow(highlighted: index == 2)
                        }
                    }
                }
                .overlay {
                    if isUpdating {
                        ProgressView()
                    }
                }
            }
        }
    }

    private func placeholderRow(highlighted: Bool) -> some View {
        HStack(spacing: PaceSpacing.s) {
            PacePlaceholderBar(width: 32, height: 14)
            Circle()
                .fill(PaceColor.track)
                .frame(width: 36, height: 36)
            PacePlaceholderBar(width: 110, height: 14)
            Spacer(minLength: PaceSpacing.xs)
            PacePlaceholderBar(width: 56, height: 14)
        }
        .padding(.horizontal, PaceSpacing.s)
        .frame(minHeight: 52)
        .background(
            highlighted ? PaceColor.accentSoft : PaceColor.surfaceSecondary,
            in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
        )
    }
}
