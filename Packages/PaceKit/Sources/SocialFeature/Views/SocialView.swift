import DesignSystem
import PaceCore
import SwiftUI

/// Ziel einer Navigation im Social-Tab.
public enum SocialRoute: Hashable, Sendable {
    case group(UUID)
    case friend(SocialProfile)
}

/// Social-Tab: Freunde finden, Anfragen, Freundesranking, Gruppen mit Gruppen-Streak und Einladungen.
/// Einen Gruppenchat gibt es bewusst (noch) nicht – siehe docs/SOCIAL.md.
public struct SocialView: View {
    @Bindable private var viewModel: SocialViewModel
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case createGroup
        case joinGroup

        var id: String { rawValue }
    }

    public init(viewModel: SocialViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                SocialContent(
                    viewModel: viewModel,
                    onCreateGroup: { sheet = .createGroup },
                    onJoinGroup: { sheet = .joinGroup }
                )
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { [viewModel] in await viewModel.load() }
            .paceScreenBackground()
            .navigationTitle("Social")
            .navigationDestination(for: SocialRoute.self) { route in
                switch route {
                case .group(let id):
                    if let group = viewModel.groups.first(where: { $0.id == id }), let detail = viewModel.detail(for: group) {
                        GroupDetailView(viewModel: detail)
                    } else {
                        PaceStatusView(
                            systemImage: "person.3",
                            title: "Gruppe nicht gefunden",
                            message: "Du bist kein Mitglied dieser Gruppe mehr."
                        )
                    }
                case .friend(let profile):
                    if let friend = viewModel.profile(for: profile) {
                        FriendProfileView(viewModel: friend)
                    }
                }
            }
        }
        .task { [viewModel] in await viewModel.loadIfNeeded() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .createGroup:
                CreateGroupSheet(viewModel: viewModel)
            case .joinGroup:
                JoinGroupSheet(viewModel: viewModel)
            }
        }
    }
}

/// Inhalt des Social-Tabs (ohne Navigation und Scrollen).
struct SocialContent: View {
    @Bindable var viewModel: SocialViewModel
    var onCreateGroup: () -> Void = {}
    var onJoinGroup: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            if let notice = viewModel.notice {
                NoticeBanner(notice: notice) { viewModel.dismissNotice() }
            }
            switch viewModel.state {
            case .unavailable(let message):
                unavailableCard(message)
            case .failed(let message):
                PaceCard {
                    VStack(alignment: .leading, spacing: PaceSpacing.s) {
                        Label(message, systemImage: "wifi.exclamationmark")
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Erneut versuchen") {
                            Task { await viewModel.load() }
                        }
                        .buttonStyle(.paceSecondary)
                    }
                }
            case .idle, .loading:
                PaceCard {
                    HStack(spacing: PaceSpacing.s) {
                        ProgressView()
                        Text("Freunde und Gruppen werden geladen …")
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                }
            case .loaded:
                addFriendCard
                if !viewModel.requests.isEmpty {
                    requestsCard
                }
                if !viewModel.invitations.isEmpty {
                    invitationsCard
                }
                rankingCard
                groupsCard
                privacyNote
            }
        }
    }

    // MARK: Nicht verfügbar

    private func unavailableCard(_ message: String) -> some View {
        PaceCard {
            HStack(alignment: .top, spacing: PaceSpacing.m) {
                Image(systemName: "person.2.slash")
                    .font(.title2)
                    .foregroundStyle(PaceColor.textSecondary)
                    .frame(width: 52, height: 52)
                    .background(PaceColor.track.opacity(0.5), in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                    Text("Freunde und Gruppen")
                        .font(PaceFont.cardTitle)
                        .foregroundStyle(PaceColor.textPrimary)
                    Text(message)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Deine regionalen Rankings funktionieren unabhängig davon.")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
        }
    }

    // MARK: Freunde finden

    private var addFriendCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Freund hinzufügen")
                HStack(spacing: PaceSpacing.xs) {
                    TextField("Benutzername, z. B. mia_lauf", text: $viewModel.searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await viewModel.searchProfile() } }
                        .padding(.horizontal, PaceSpacing.s)
                        .padding(.vertical, PaceSpacing.xs)
                        .background(PaceColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
                    Button("Suchen") {
                        Task { await viewModel.searchProfile() }
                    }
                    .buttonStyle(.paceCompact)
                    .disabled(viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.search == .searching)
                }
                searchResult
                if let username = viewModel.username, let shareText = viewModel.shareText {
                    HStack {
                        Text("Dein Benutzername: \(username)")
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                            .textSelection(.enabled)
                        Spacer(minLength: PaceSpacing.xs)
                        ShareLink(item: shareText) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                                .font(PaceFont.caption.weight(.semibold))
                        }
                        .tint(PaceColor.accent)
                    }
                }
                Text("Gesucht wird nur nach dem genauen Benutzernamen – so bleibt dein Profil für Fremde unsichtbar.")
                    .font(PaceFont.micro)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var searchResult: some View {
        switch viewModel.search {
        case .idle:
            EmptyView()
        case .searching:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .notFound(let text), .failed(let text):
            Text(text)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .found(let result):
            PersonRow(profile: result.profile) {
                searchAction(result)
            }
        }
    }

    @ViewBuilder
    private func searchAction(_ result: ProfileSearchResult) -> some View {
        let isBusy = viewModel.busyIDs.contains(result.profile.publicID) || result.requestID.map(viewModel.busyIDs.contains) == true
        switch result.relationship {
        case .none:
            Button("Anfrage senden") {
                Task { await viewModel.sendRequest(to: result.profile) }
            }
            .buttonStyle(.paceCompact)
            .disabled(isBusy)
        case .incomingRequest:
            if let requestID = result.requestID {
                Button("Annehmen") {
                    let request = FriendRequest(id: requestID, direction: .incoming, profile: result.profile, createdAt: .now)
                    Task { await viewModel.respond(to: request, accept: true) }
                }
                .buttonStyle(.paceCompact)
                .disabled(isBusy)
            }
        case .outgoingRequest:
            StatusChip(text: "Angefragt", systemImage: "clock")
        case .friend:
            StatusChip(text: "Befreundet", systemImage: "checkmark")
        case .me:
            StatusChip(text: "Das bist du", systemImage: "person.fill")
        }
    }

    // MARK: Anfragen & Einladungen

    private var requestsCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Freundschaftsanfragen")
                ForEach(viewModel.incomingRequests) { request in
                    PersonRow(profile: request.profile, detail: "möchte mit dir befreundet sein") {
                        HStack(spacing: PaceSpacing.xs) {
                            Button {
                                Task { await viewModel.respond(to: request, accept: false) }
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.paceSecondary)
                            .accessibilityLabel("Anfrage von \(request.profile.displayName) ablehnen")
                            Button("Annehmen") {
                                Task { await viewModel.respond(to: request, accept: true) }
                            }
                            .buttonStyle(.paceCompact)
                        }
                        .disabled(viewModel.busyIDs.contains(request.id))
                    }
                }
                ForEach(viewModel.outgoingRequests) { request in
                    PersonRow(profile: request.profile, detail: "Anfrage gesendet") {
                        Button("Zurückziehen") {
                            Task { await viewModel.cancel(request) }
                        }
                        .font(PaceFont.caption.weight(.semibold))
                        .tint(PaceColor.accent)
                        .disabled(viewModel.busyIDs.contains(request.id))
                    }
                }
            }
        }
    }

    private var invitationsCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Gruppeneinladungen")
                ForEach(viewModel.invitations) { invitation in
                    PaceTile {
                        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                            HStack(spacing: PaceSpacing.s) {
                                Image(systemName: invitation.groupKind.systemImage)
                                    .foregroundStyle(PaceColor.accent)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(invitation.groupName)
                                        .font(PaceFont.headline)
                                        .foregroundStyle(PaceColor.textPrimary)
                                    Text("von \(invitation.inviterDisplayName) · \(invitation.memberCount) Mitglieder")
                                        .font(PaceFont.caption)
                                        .foregroundStyle(PaceColor.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            HStack(spacing: PaceSpacing.xs) {
                                Button("Ablehnen") {
                                    Task { await viewModel.respond(to: invitation, accept: false) }
                                }
                                .buttonStyle(.paceSecondary)
                                Button("Beitreten") {
                                    Task { await viewModel.respond(to: invitation, accept: true) }
                                }
                                .buttonStyle(.paceCompact)
                            }
                            .disabled(viewModel.busyIDs.contains(invitation.id))
                        }
                        .padding(.vertical, PaceSpacing.xxs)
                    }
                }
            }
        }
    }

    // MARK: Freundesranking

    private var rankingCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Freunde heute")
                if viewModel.ranking.count <= 1 && viewModel.friends.isEmpty {
                    Text("Noch keine Freunde. Suche oben nach einem Benutzernamen – sobald ihr befreundet seid, "
                        + "vergleicht ihr hier jeden Tag eure Schritte.")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(viewModel.ranking) { entry in
                        if entry.isCurrentUser {
                            RankingRow(entry: entry)
                        } else {
                            NavigationLink(value: SocialRoute.friend(SocialProfile(
                                publicID: entry.publicUserID, username: entry.username, displayName: entry.displayName
                            ))) {
                                RankingRow(entry: entry, showsChevron: true)
                            }
                            .buttonStyle(.pacePressable)
                        }
                    }
                }
            }
        }
    }

    // MARK: Gruppen

    private var groupsCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Deine Gruppen")
                if viewModel.groups.isEmpty {
                    Text("Gründe eine Gruppe für deine Klasse, dein Team oder deine Freunde – oder tritt mit einem "
                        + "Einladungscode bei. Eure Gruppen-Serie wächst jeden Tag, an dem mindestens ein Drittel "
                        + "das Gruppenziel erreicht.")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(viewModel.groups) { group in
                        NavigationLink(value: SocialRoute.group(group.id)) {
                            GroupStreakRow(group: group, showsChevron: true)
                        }
                        .buttonStyle(.pacePressable)
                    }
                }
                HStack(spacing: PaceSpacing.xs) {
                    Button(action: onCreateGroup) {
                        Label("Gruppe erstellen", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.paceCompact)
                    Button(action: onJoinGroup) {
                        Label("Mit Code beitreten", systemImage: "ticket")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.paceSecondary)
                }
            }
        }
    }

    private var privacyNote: some View {
        Label(
            "Freunde und Mitglieder deiner Gruppen sehen deinen Anzeigenamen, Benutzernamen und deine "
                + "Wettbewerbsschritte – keine anderen Gesundheitsdaten und nicht deine Gemeinde.",
            systemImage: "lock.shield"
        )
        .font(PaceFont.caption)
        .foregroundStyle(PaceColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, PaceSpacing.xxs)
    }
}

// MARK: - Bausteine

/// Rückmeldung der letzten Aktion, z. B. „Anfrage gesendet“.
struct NoticeBanner: View {
    let notice: SocialViewModel.Notice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: PaceSpacing.s) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? PaceColor.danger : PaceColor.accent)
                .accessibilityHidden(true)
            Text(notice.text)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Hinweis schließen")
        }
        .padding(PaceSpacing.s)
        .background(notice.isError ? PaceColor.danger.opacity(0.1) : PaceColor.accentSoft, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Person mit Avatar, Namen und einer Aktion rechts.
struct PersonRow<Action: View>: View {
    let profile: SocialProfile
    var detail: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        PaceTile {
            HStack(spacing: PaceSpacing.s) {
                PaceAvatar(name: profile.displayName, seed: profile.publicID.uuidString, size: 38)
                VStack(alignment: .leading, spacing: 0) {
                    Text(profile.displayName)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                    Text(detail ?? "@\(profile.username)")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: PaceSpacing.xs)
                action()
            }
            .padding(.vertical, PaceSpacing.xxs)
        }
    }
}

struct StatusChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(PaceFont.caption.weight(.semibold))
            .foregroundStyle(PaceColor.accentStrong)
            .padding(.horizontal, PaceSpacing.xs)
            .padding(.vertical, 4)
            .background(PaceColor.accentSoft, in: Capsule())
    }
}

/// Zeile im Freundes- bzw. Gruppenranking.
struct RankingRow: View {
    let entry: LeaderboardEntry
    var showsChevron = false
    var reachedGoal: Bool?

    var body: some View {
        PaceTile(isHighlighted: entry.isCurrentUser) {
            HStack(spacing: PaceSpacing.s) {
                Text("#\(entry.rank)")
                    .font(.system(.headline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .frame(minWidth: 40, alignment: .leading)
                PaceAvatar(name: entry.displayName, seed: entry.publicUserID.uuidString, size: 34, isHighlighted: entry.isCurrentUser)
                Text(entry.isCurrentUser ? "DU" : entry.displayName)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: PaceSpacing.xs)
                if reachedGoal == true {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(PaceColor.accentStrong)
                        .accessibilityLabel("Ziel erreicht")
                }
                Text(entry.competitionSteps.paceFormatted)
                    .font(.system(.headline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Zeile einer Gruppe mit Flamme, Serie und heutigem Stand (auch für das Gruppen-Modul auf Home).
public struct GroupStreakRow: View {
    private let group: GroupSummary
    private let showsChevron: Bool

    public init(group: GroupSummary, showsChevron: Bool = false) {
        self.group = group
        self.showsChevron = showsChevron
    }

    public var body: some View {
        PaceTile(isHighlighted: group.todayComplete) {
            HStack(spacing: PaceSpacing.s) {
                PaceStreakFlame(isActive: group.currentStreak > 0, isTodayReached: group.todayComplete, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                    Text("Heute \(group.todayReachedCount) von \(group.todayRequiredCount) nötig · \(group.memberCount) Mitglieder")
                        .font(PaceFont.caption)
                        .foregroundStyle(group.todayComplete ? PaceColor.accent : PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: PaceSpacing.xs)
                Text(group.currentStreak == 1 ? "1 Tag" : "\(group.currentStreak) Tage")
                    .font(PaceFont.headline)
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), Serie \(group.currentStreak) Tage, heute \(group.todayReachedCount) von \(group.todayRequiredCount) nötigen Mitgliedern")
    }
}
