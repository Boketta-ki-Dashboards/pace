import DesignSystem
import PaceCore
import SwiftUI

/// Detailansicht einer Gruppe: Gruppen-Streak, Ranking, Verlauf, Einladen und Verwalten.
struct GroupDetailView: View {
    @State private var viewModel: GroupDetailViewModel
    @State private var confirmation: Confirmation?
    @State private var sheet: Sheet?
    @State private var memberToRemove: GroupRankingEntry?
    @Environment(\.dismiss) private var dismiss

    private enum Confirmation: String, Identifiable {
        case leave, delete, regenerate
        var id: String { rawValue }
    }

    private enum Sheet: String, Identifiable {
        case edit, goal
        var id: String { rawValue }
    }

    init(viewModel: @autoclosure () -> GroupDetailViewModel) {
        _viewModel = State(initialValue: viewModel())
    }

    var body: some View {
        ScrollView {
            GroupDetailContent(
                viewModel: viewModel,
                onEdit: { sheet = .edit },
                onChangeGoal: { sheet = .goal },
                onRegenerateCode: { confirmation = .regenerate },
                onDelete: { confirmation = .delete },
                onLeave: { confirmation = .leave },
                onRemoveMember: { memberToRemove = $0 }
            )
            .padding(.horizontal, PaceSpacing.m)
            .padding(.bottom, PaceSpacing.l)
        }
        .refreshable { [viewModel] in await viewModel.load() }
        .paceScreenBackground()
        .navigationTitle(viewModel.group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { [viewModel] in await viewModel.load() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit: EditGroupSheet(viewModel: viewModel)
            case .goal: GroupGoalSheet(viewModel: viewModel)
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: confirmationBinding, titleVisibility: .visible) {
            switch confirmation {
            case .leave:
                Button("Gruppe verlassen", role: .destructive) {
                    Task { if await viewModel.leave() { dismiss() } }
                }
            case .delete:
                Button("Gruppe löschen", role: .destructive) {
                    Task { if await viewModel.delete() { dismiss() } }
                }
            case .regenerate:
                Button("Neuen Code erstellen") {
                    Task { await viewModel.regenerateInviteCode() }
                }
            case nil:
                EmptyView()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .confirmationDialog(
            "Mitglied entfernen?",
            isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
            titleVisibility: .visible,
            presenting: memberToRemove
        ) { member in
            Button("\(member.profile.displayName) entfernen", role: .destructive) {
                Task { await viewModel.remove(member) }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .leave: "Gruppe verlassen?"
        case .delete: "Gruppe löschen?"
        case .regenerate: "Neuen Einladungscode erstellen?"
        case nil: ""
        }
    }

    private var confirmationMessage: String {
        switch confirmation {
        case .leave:
            viewModel.group.isOwner
                ? "Die Verwaltung geht an das am längsten beigetretene Mitglied. Bist du das letzte Mitglied, wird die Gruppe gelöscht."
                : "Du kannst später mit einem Einladungscode wieder beitreten."
        case .delete: "Die Gruppe und ihre Serie werden für alle Mitglieder gelöscht."
        case .regenerate: "Der bisherige Code funktioniert danach nicht mehr."
        case nil: ""
        }
    }
}

/// Inhalt der Gruppendetails (ohne Navigation, Scrollen, Dialoge) – auch für Snapshot-Tests.
struct GroupDetailContent: View {
    let viewModel: GroupDetailViewModel
    var onEdit: () -> Void = {}
    var onChangeGoal: () -> Void = {}
    var onRegenerateCode: () -> Void = {}
    var onDelete: () -> Void = {}
    var onLeave: () -> Void = {}
    var onRemoveMember: (GroupRankingEntry) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            if let notice = viewModel.notice {
                NoticeBanner(notice: notice) { viewModel.dismissNotice() }
            }
            switch viewModel.state {
            case .gone:
                PaceStatusView(
                    systemImage: "person.3",
                    title: "Nicht mehr in dieser Gruppe",
                    message: "Die Gruppe wurde gelöscht oder du bist kein Mitglied mehr."
                )
            case .failed(let message):
                PaceStatusView(systemImage: "wifi.exclamationmark", title: "Gruppe nicht geladen", message: message, tint: PaceColor.warning) {
                    Button("Erneut versuchen") { Task { await viewModel.load() } }
                        .buttonStyle(.pacePrimary)
                }
            case .loading, .loaded:
                header
                rankingCard
                daysCard
                inviteCard
                if viewModel.group.isOwner {
                    manageCard
                }
                Button(role: .destructive) {
                    onLeave()
                } label: {
                    Text("Gruppe verlassen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.paceSecondary)
                .padding(.top, PaceSpacing.xs)
            }
        }
    }

    // MARK: Kopf mit Gruppen-Streak

    private var header: some View {
        let group = viewModel.group
        return PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(spacing: PaceSpacing.s) {
                    Image(systemName: group.kind.systemImage)
                        .foregroundStyle(PaceColor.onAccent)
                        .frame(width: 40, height: 40)
                        .background(PaceColor.accentStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.name)
                            .font(PaceFont.cardTitle)
                            .foregroundStyle(PaceColor.textPrimary)
                        Text("\(group.kind.title) · \(group.memberCount) \(group.memberCount == 1 ? "Mitglied" : "Mitglieder")")
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                }
                if !group.description.isEmpty {
                    Text(group.description)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PaceTile(isHighlighted: group.todayComplete) {
                    HStack(spacing: PaceSpacing.s) {
                        PaceStreakFlame(isActive: group.currentStreak > 0, isTodayReached: group.todayComplete, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.currentStreak == 1 ? "1 Tag Gruppen-Serie" : "\(group.currentStreak) Tage Gruppen-Serie")
                                .font(PaceFont.headline)
                                .foregroundStyle(PaceColor.textPrimary)
                            Text(viewModel.todayText)
                                .font(PaceFont.caption)
                                .foregroundStyle(group.todayComplete ? PaceColor.accent : PaceColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Rekord: \(group.bestStreak == 1 ? "1 Tag" : "\(group.bestStreak) Tage")")
                                .font(PaceFont.caption)
                                .foregroundStyle(PaceColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, PaceSpacing.xxs)
                }
                .accessibilityElement(children: .combine)
                Text(goalText)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var goalText: String {
        let group = viewModel.group
        var text = "Gruppenziel: \(group.dailyGoal.paceFormatted) Schritte. Ein Tag zählt, wenn mindestens ein Drittel "
            + "der Mitglieder (aufgerundet) das Ziel erreicht."
        if let next = group.nextDailyGoal {
            text += " Ab morgen: \(next.paceFormatted) Schritte."
        }
        return text
    }

    // MARK: Ranking

    private var rankingCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Ranking")
                Picker("Zeitraum", selection: Binding(get: { viewModel.period }, set: { period in Task { await viewModel.select(period) } })) {
                    Text("Heute").tag(LeaderboardPeriod.daily)
                    Text("Diese Woche").tag(LeaderboardPeriod.weekly)
                }
                .pickerStyle(.segmented)
                if let ranking = viewModel.ranking {
                    ForEach(ranking.entries) { member in
                        RankingRow(
                            entry: LeaderboardEntry(
                                rank: member.rank,
                                publicUserID: member.profile.publicID,
                                username: member.profile.username,
                                displayName: member.profile.displayName,
                                competitionSteps: member.competitionSteps,
                                isCurrentUser: member.isCurrentUser
                            ),
                            reachedGoal: viewModel.period == .daily ? member.reachedGoalToday : nil
                        )
                        .contextMenu {
                            if viewModel.group.isOwner, !member.isCurrentUser {
                                Button("Aus Gruppe entfernen", systemImage: "person.badge.minus", role: .destructive) {
                                    onRemoveMember(member)
                                }
                            }
                        }
                    }
                    if viewModel.group.isOwner, ranking.entries.count > 1 {
                        Text("Halte ein Mitglied gedrückt, um es aus der Gruppe zu entfernen.")
                            .font(PaceFont.micro)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
        }
    }

    // MARK: Verlauf

    private var daysCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Letzte 14 Gruppentage")
                if viewModel.days.isEmpty {
                    Text("Noch keine abgeschlossenen Gruppentage.")
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                } else {
                    let columns = Array(repeating: GridItem(.flexible(), spacing: PaceSpacing.xs), count: 7)
                    LazyVGrid(columns: columns, spacing: PaceSpacing.xs) {
                        ForEach(viewModel.days.reversed()) { day in
                            GroupDayDot(day: day)
                        }
                    }
                    Text("Ausgefüllt: Ziel als Gruppe erreicht. Umrandet: heute, läuft noch.")
                        .font(PaceFont.micro)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
        }
    }

    // MARK: Einladen

    private var inviteCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Einladen")
                HStack(spacing: PaceSpacing.s) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Einladungscode")
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.textSecondary)
                        Text(viewModel.group.inviteCode)
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .foregroundStyle(PaceColor.textPrimary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: PaceSpacing.xs)
                    ShareLink(item: "Tritt meiner Pace-Gruppe „\(viewModel.group.name)“ bei – Code: \(viewModel.group.inviteCode)") {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.paceCompact)
                }
                if !viewModel.invitableFriends.isEmpty {
                    Text("Freunde einladen")
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                    ForEach(viewModel.invitableFriends) { friend in
                        PersonRow(profile: friend.profile) {
                            Button("Einladen") {
                                Task { await viewModel.invite(friend) }
                            }
                            .buttonStyle(.paceCompact)
                            .disabled(viewModel.isWorking)
                        }
                    }
                }
                if !viewModel.outgoingInvitations.isEmpty {
                    Text("Offene Einladungen")
                        .font(PaceFont.headline)
                        .foregroundStyle(PaceColor.textPrimary)
                    ForEach(viewModel.outgoingInvitations) { invitation in
                        PersonRow(profile: invitation.profile, detail: "eingeladen") {
                            Button("Zurückziehen") {
                                Task { await viewModel.cancel(invitation) }
                            }
                            .font(PaceFont.caption.weight(.semibold))
                            .tint(PaceColor.accent)
                            .disabled(viewModel.isWorking)
                        }
                    }
                }
            }
        }
    }

    // MARK: Verwalten

    private var manageCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                PaceCardHeader("Verwalten")
                ManageRow(systemImage: "pencil", title: "Name, Beschreibung, Art", action: onEdit)
                ManageRow(systemImage: "scope", title: "Gruppenziel ändern", action: onChangeGoal)
                ManageRow(systemImage: "arrow.triangle.2.circlepath", title: "Neuen Einladungscode erstellen", action: onRegenerateCode)
                ManageRow(systemImage: "trash", title: "Gruppe löschen", isDestructive: true, action: onDelete)
            }
            .disabled(viewModel.isWorking)
        }
    }

}

private struct ManageRow: View {
    let systemImage: String
    let title: String
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PaceTile {
                HStack(spacing: PaceSpacing.s) {
                    Image(systemName: systemImage)
                        .foregroundStyle(isDestructive ? PaceColor.danger : PaceColor.accent)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(PaceFont.callout)
                        .foregroundStyle(isDestructive ? PaceColor.danger : PaceColor.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                }
                .padding(.vertical, PaceSpacing.xxs)
            }
        }
        .buttonStyle(.pacePressable)
    }
}

private struct GroupDayDot: View {
    let day: GroupDay

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if day.reached {
                    Circle().fill(PaceColor.accentStrong)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PaceColor.onAccent)
                } else if day.isToday {
                    Circle().strokeBorder(PaceColor.accentStrong, lineWidth: 2)
                } else {
                    Circle().fill(PaceColor.track)
                }
            }
            .frame(width: 24, height: 24)
            Text("\(day.reachedCount)/\(day.requiredCount)")
                .font(PaceFont.micro)
                .monospacedDigit()
                .foregroundStyle(PaceColor.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.day.isoString): \(day.reachedCount) von \(day.requiredCount) nötigen Mitgliedern, \(day.reached ? "erreicht" : day.isToday ? "läuft noch" : "nicht erreicht")")
    }
}

// MARK: - Sheets

/// Neue Gruppe anlegen.
struct CreateGroupSheet: View {
    let viewModel: SocialViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var draft = GroupDraft()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (3–40 Zeichen)", text: $draft.name)
                    TextField("Beschreibung (optional)", text: $draft.description, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Art", selection: $draft.kind) {
                        ForEach(GroupKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    Picker("Gruppenziel", selection: $draft.dailyGoal) {
                        ForEach(StepGoalRules.options, id: \.self) { goal in
                            Text("\(goal.paceFormatted) Schritte").tag(goal)
                        }
                    }
                } footer: {
                    Text("Ein Gruppentag zählt, wenn mindestens ein Drittel der Mitglieder (aufgerundet) das Gruppenziel "
                        + "erreicht. Der Gruppentag richtet sich nach der Zeitzone deines iPhones. Mitglieder sehen "
                        + "Anzeigenamen, Benutzernamen und Wettbewerbsschritte der anderen.")
                }
                if let notice = viewModel.notice, notice.isError {
                    Section {
                        Text(notice.text)
                            .foregroundStyle(PaceColor.danger)
                    }
                }
            }
            .navigationTitle("Gruppe erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Erstellen") {
                            Task {
                                isSaving = true
                                let created = await viewModel.createGroup(draft)
                                isSaving = false
                                if created != nil { dismiss() }
                            }
                        }
                        .disabled(draft.validName == nil)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onAppear { viewModel.dismissNotice() }
    }
}

/// Mit Einladungscode beitreten.
struct JoinGroupSheet: View {
    let viewModel: SocialViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Einladungscode, z. B. K7M2Q9XA", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } footer: {
                    Text("Den Code bekommst du von einem Mitglied der Gruppe. Mitglieder sehen deinen Anzeigenamen, "
                        + "Benutzernamen und deine Wettbewerbsschritte.")
                }
                if let notice = viewModel.notice, notice.isError {
                    Section {
                        Text(notice.text)
                            .foregroundStyle(PaceColor.danger)
                    }
                }
            }
            .navigationTitle("Gruppe beitreten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isJoining)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isJoining {
                        ProgressView()
                    } else {
                        Button("Beitreten") {
                            Task {
                                isJoining = true
                                let joined = await viewModel.join(inviteCode: code)
                                isJoining = false
                                if joined != nil { dismiss() }
                            }
                        }
                        .disabled(code.trimmingCharacters(in: .whitespaces).count < 6)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isJoining)
        .onAppear { viewModel.dismissNotice() }
    }
}

/// Name, Beschreibung und Art ändern (nur Verwaltung).
private struct EditGroupSheet: View {
    let viewModel: GroupDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var kind: GroupKind
    @State private var isSaving = false
    @State private var errorText: String?

    init(viewModel: GroupDetailViewModel) {
        self.viewModel = viewModel
        _name = State(initialValue: viewModel.group.name)
        _description = State(initialValue: viewModel.group.description)
        _kind = State(initialValue: viewModel.group.kind)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Beschreibung", text: $description, axis: .vertical)
                    .lineLimit(2...4)
                Picker("Art", selection: $kind) {
                    ForEach(GroupKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(kind)
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(PaceColor.danger)
                    }
                }
            }
            .navigationTitle("Gruppe bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task {
                            isSaving = true
                            errorText = nil
                            viewModel.dismissNotice()
                            let saved = await viewModel.update(name: name, description: description, kind: kind)
                            isSaving = false
                            if saved { dismiss() } else { errorText = saveErrorText(viewModel) }
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}

/// Gruppenziel ändern – gilt ab dem nächsten Gruppentag.
private struct GroupGoalSheet: View {
    let viewModel: GroupDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var goal: Int
    @State private var isSaving = false
    @State private var errorText: String?

    init(viewModel: GroupDetailViewModel) {
        self.viewModel = viewModel
        let current = viewModel.group.nextDailyGoal ?? viewModel.group.dailyGoal
        _goal = State(initialValue: StepGoalRules.options.contains(current) ? current : StepGoalRules.clamped(current))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: PaceSpacing.m) {
                Picker("Gruppenziel", selection: $goal) {
                    ForEach(StepGoalRules.options, id: \.self) { goal in
                        Text("\(goal.paceFormatted) Schritte").tag(goal)
                    }
                }
                .pickerStyle(.wheel)
                Text("Das neue Ziel gilt ab morgen. Heute und vergangene Tage behalten ihr Ziel – die Gruppen-Serie "
                    + "lässt sich dadurch nicht nachträglich retten oder verlieren.")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let errorText {
                    Text(errorText)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(PaceSpacing.m)
            .navigationTitle("Gruppenziel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task {
                            isSaving = true
                            errorText = nil
                            viewModel.dismissNotice()
                            let saved = await viewModel.setGoal(goal)
                            isSaving = false
                            if saved { dismiss() } else { errorText = saveErrorText(viewModel) }
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Fehlertext für ein Bearbeitungsblatt: Der Hinweis der Detailansicht liegt hinter dem Blatt und wäre unsichtbar.
@MainActor
private func saveErrorText(_ viewModel: GroupDetailViewModel) -> String {
    if let notice = viewModel.notice, notice.isError {
        return notice.text
    }
    return "Gerade läuft noch eine andere Änderung. Versuche es gleich noch einmal."
}
