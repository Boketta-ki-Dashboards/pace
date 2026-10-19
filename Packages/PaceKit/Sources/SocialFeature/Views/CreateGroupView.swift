import DesignSystem
import PaceCore
import PhotosUI
import SwiftUI
import UIKit

/// Unterseiten von „Gruppe erstellen“.
enum CreateGroupSubpage: Hashable {
    case privacy
    case members
    case goal
}

/// „Gruppe erstellen“ (Referenzbild 3). Nach dem Anlegen öffnen sich die Details der neuen Gruppe.
struct CreateGroupView: View {
    @State private var model: CreateGroupViewModel
    private let social: SocialViewModel
    private let onCreated: (GroupSummary) -> Void
    @State private var subpage: CreateGroupSubpage?
    @State private var showsPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem?

    init(model: CreateGroupViewModel, social: SocialViewModel, onCreated: @escaping (GroupSummary) -> Void) {
        _model = State(initialValue: model)
        self.social = social
        self.onCreated = onCreated
    }

    var body: some View {
        CreateGroupContent(
            model: model,
            social: social,
            onOpen: { subpage = $0 },
            onPickImage: { showsPhotoPicker = true },
            onCreate: {
                Task {
                    if let group = await model.create() { onCreated(group) }
                }
            }
        )
        .socialSubpageScroll()
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickerItem = nil
                if let data, let upload = GroupImageProcessing.upload(from: data) {
                    model.setImage(upload)
                } else {
                    model.imageFailed()
                }
            }
        }
        .navigationDestination(item: $subpage) { page in
            switch page {
            case .privacy:
                GroupPrivacyPage(backTitle: SocialText.createGroup, selection: $model.privacy)
            case .members:
                CreateGroupInvitePage(model: model)
            case .goal:
                GroupGoalPage(
                    backTitle: SocialText.createGroup,
                    goal: model.dailyGoal,
                    hint: SocialText.goalIndependentHint,
                    onChange: { model.setGoal($0) }
                )
            }
        }
    }
}

/// Inhalt von „Gruppe erstellen“ mit Kopfzeile (ohne Scrollen) – auch für Snapshot-Tests.
struct CreateGroupContent: View {
    @Bindable var model: CreateGroupViewModel
    let social: SocialViewModel
    var onOpen: (CreateGroupSubpage) -> Void = { _ in }
    var onPickImage: () -> Void = {}
    var onCreate: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: SocialText.social, title: SocialText.createGroup)
            imagePicker
                .frame(maxWidth: .infinity)
                .padding(.vertical, PaceSpacing.s)
            if let notice = social.notice, notice.isError {
                NoticeBanner(notice: notice) { social.dismissNotice() }
            }
            GroupFormCard(title: SocialText.groupName, error: model.nameError) {
                TextField(SocialText.groupNamePlaceholder, text: $model.name)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .modifier(GroupFieldStyle())
            }
            GroupFormCard(title: SocialText.groupDescription, error: model.descriptionError) {
                TextField(SocialText.descriptionPlaceholder, text: $model.description, axis: .vertical)
                    .lineLimit(2...4)
                    .modifier(GroupFieldStyle())
            }
            GroupFormCard(title: SocialText.groupType) {
                GroupKindPicker(selection: $model.kind)
            }
            GroupFormCard(title: SocialText.privacy) {
                GroupFormRow(action: { onOpen(.privacy) }) {
                    Image(systemName: model.privacy == .inviteOnly ? "lock" : "key")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(PaceColor.textPrimary)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    Text(model.privacy.title)
                        .font(PaceFont.body)
                        .foregroundStyle(PaceColor.textPrimary)
                }
            }
            GroupFormCard(title: SocialText.inviteMembers) {
                GroupFormRow(action: { onOpen(.members) }) {
                    inviteeAvatars
                }
                .accessibilityValue(model.invitees.isEmpty ? SocialText.noOneSelected : SocialText.invitedCount(model.invitees.count))
            }
            GroupFormCard(title: SocialText.dailyGoalPerMember) {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    GroupFormRow(action: { onOpen(.goal) }) {
                        Image(systemName: "shoeprints.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(PaceColor.textPrimary)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        Text(PaceLocalization.steps(model.dailyGoal))
                            .font(PaceFont.body)
                            .foregroundStyle(PaceColor.textPrimary)
                    }
                    GroupInfoBox(text: SocialText.groupStreakRule)
                }
            }
            Button(action: onCreate) {
                if model.isCreating {
                    ProgressView().tint(PaceColor.onAccent)
                } else {
                    Text(SocialText.createGroup)
                }
            }
            .buttonStyle(.pacePrimary)
            .disabled(!model.canSubmit)
            .padding(.top, PaceSpacing.xxs)
        }
    }

    // MARK: Gruppenbild

    private var imagePicker: some View {
        VStack(spacing: PaceSpacing.xs) {
            Button(action: onPickImage) {
                ZStack {
                    Circle()
                        .fill(PaceColor.selectionFill)
                    if let image = model.image, let photo = UIImage(data: image.data) {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "camera")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(PaceColor.accentStrong)
                    }
                }
                .frame(width: 84, height: 84)
                .contentShape(Circle())
            }
            .buttonStyle(.pacePressable)
            .disabled(!model.canPickImage)
            .opacity(model.canPickImage ? 1 : 0.45)
            .accessibilityLabel(model.image == nil ? SocialText.chooseGroupImage : SocialText.changeGroupImage)

            Button(model.image == nil ? SocialText.chooseGroupImage : SocialText.changeGroupImage, action: onPickImage)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.accent)
                .buttonStyle(.plain)
                .disabled(!model.canPickImage)
                .accessibilityHidden(true)
            if model.image != nil {
                Button(SocialText.removeImage) { model.removeImage() }
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .buttonStyle(.plain)
            }
            if !model.canPickImage {
                Text(SocialText.imageStorageUnavailable)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.imageError {
                Text(error)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Mitglieder

    @ViewBuilder
    private var inviteeAvatars: some View {
        let invitees = model.invitees
        HStack(spacing: PaceSpacing.xs) {
            ForEach(invitees.prefix(4)) { profile in
                PaceAvatar(name: profile.displayName, seed: profile.publicID.uuidString, size: 40, image: profile.avatar)
            }
            if invitees.count > 4 {
                Text(verbatim: "+\(invitees.count - 4)")
                    .font(PaceFont.caption.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
            }
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PaceColor.onSelection)
                .frame(width: 40, height: 40)
                .background(PaceColor.selectionFill, in: Circle())
                .accessibilityHidden(true)
            if invitees.isEmpty {
                Text(SocialText.noOneSelected)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Formular-Bausteine

/// Karte eines Formularfelds mit Titel (Referenzbild 3).
struct GroupFormCard<Content: View>: View {
    let title: String
    var error: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            Text(title)
                .font(PaceFont.headline)
                .foregroundStyle(PaceColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
            if let error {
                Text(error)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(PaceSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCardBackground(cornerRadius: PaceRadius.card)
    }
}

/// Eingabefeld im Pace-Stil: graue, abgerundete Fläche.
struct GroupFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(PaceFont.body)
            .foregroundStyle(PaceColor.textPrimary)
            .padding(.horizontal, PaceSpacing.m)
            .padding(.vertical, PaceSpacing.s)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Zeile in einer Formularkarte, die eine Auswahl-Unterseite öffnet (mit Pfeil rechts).
struct GroupFormRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                content()
                Spacer(minLength: PaceSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Hinweis mit Info-Symbol auf zartem Mint (z. B. die Drittel-Regel).
struct GroupInfoBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: PaceSpacing.s) {
            Image(systemName: "info.circle")
                .font(.system(size: 20))
                .foregroundStyle(PaceColor.accentStrong)
                .accessibilityHidden(true)
            Text(text)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.accentStrong)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(PaceSpacing.s)
        .background(PaceColor.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Gruppentyp als drei Kacheln: Freunde, Klasse, Arbeit (ältere Gruppen behalten ihre Art).
struct GroupKindPicker: View {
    @Binding var selection: GroupKind

    var body: some View {
        HStack(spacing: PaceSpacing.xs) {
            ForEach(kinds) { kind in
                let isSelected = kind == selection
                Button {
                    selection = kind
                } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: PaceSpacing.xs) { tileContent(kind) }
                        VStack(spacing: 4) { tileContent(kind) }
                    }
                    .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textPrimary)
                    .padding(.horizontal, PaceSpacing.xs)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        isSelected ? PaceColor.selectionFill : PaceColor.surface,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.clear : PaceColor.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .accessibilityLabel(kind.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            }
        }
    }

    /// Beim Erstellen die drei Arten; eine ältere Gruppe mit anderer Art zeigt ihre Art zusätzlich.
    private var kinds: [GroupKind] {
        GroupKind.selectable.contains(selection) ? GroupKind.selectable : GroupKind.selectable + [selection]
    }

    @ViewBuilder
    private func tileContent(_ kind: GroupKind) -> some View {
        Image(systemName: kind.systemImage.replacingOccurrences(of: ".fill", with: ""))
            .font(.system(size: 18, weight: .medium))
            .accessibilityHidden(true)
        Text(kind.title)
            .font(.system(.subheadline, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Unterseiten

/// Auswahl der Privatsphäre (Gruppe erstellen und Gruppeneinstellungen).
struct GroupPrivacyPage: View {
    let backTitle: String
    @Binding var selection: GroupPrivacy
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: SocialText.privacy)
            ForEach(GroupPrivacy.allCases) { privacy in
                SocialSelectableRow(
                    title: privacy.title,
                    subtitle: privacy.explanation,
                    isSelected: privacy == selection,
                    action: {
                        selection = privacy
                        dismiss()
                    }
                ) {
                    Image(systemName: privacy == .inviteOnly ? "lock" : "key")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(PaceColor.accent)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                }
            }
            Text(SocialText.groupsNeverPublic)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PaceSpacing.xxs)
        }
        .socialSubpageScroll()
    }
}

/// Freunde zum Einladen auswählen (beim Erstellen – eingeladen wird mit dem Anlegen der Gruppe).
struct CreateGroupInvitePage: View {
    let model: CreateGroupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: SocialText.createGroup, title: SocialText.inviteMembers)
            if model.friends.isEmpty {
                SocialEmptyCard(systemImage: "person.badge.plus", title: SocialText.inviteMembers, message: SocialText.noFriendsToInvite)
            } else {
                Text(SocialText.invitedCount(model.inviteeIDs.count))
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                ForEach(model.friends) { friend in
                    SocialSelectableRow(
                        title: friend.profile.displayName,
                        subtitle: "@\(friend.profile.username)",
                        isSelected: model.isInvited(friend.profile.publicID),
                        action: { model.toggleInvitee(friend.profile.publicID) }
                    ) {
                        PaceAvatar(name: friend.profile.displayName, seed: friend.profile.publicID.uuidString, size: 40, image: friend.profile.avatar)
                    }
                }
            }
        }
        .socialSubpageScroll()
    }
}

/// Tagesziel pro Mitglied: Schritte in 500er-Stufen, häufige Ziele zur Schnellauswahl.
///
/// Beim Erstellen gilt jede Änderung sofort (`onChange`); in den Einstellungen wird mit „Speichern“ übernommen
/// (`onSave`) – dort gilt das neue Ziel ab dem nächsten Gruppentag.
struct GroupGoalPage: View {
    let backTitle: String
    let hint: String
    let onChange: ((Int) -> Void)?
    let onSave: ((Int) async -> Bool)?
    @State private var goal: Int
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(
        backTitle: String,
        goal: Int,
        hint: String,
        onChange: ((Int) -> Void)? = nil,
        onSave: ((Int) async -> Bool)? = nil
    ) {
        self.backTitle = backTitle
        self.hint = hint
        self.onChange = onChange
        self.onSave = onSave
        _goal = State(initialValue: GroupGoalRules.clamped(goal))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.m) {
            PaceSubpageHeader(backTitle: backTitle, title: SocialText.dailyGoalPerMember)
            PaceCard {
                HStack(spacing: PaceSpacing.m) {
                    stepButton(systemImage: "minus", label: SocialText.decreaseGoal, delta: -GroupGoalRules.increment)
                        .disabled(goal <= GroupGoalRules.range.lowerBound)
                    VStack(spacing: 2) {
                        Text(goal.paceFormatted)
                            .font(PaceFont.metric(size: 40))
                            .monospacedDigit()
                            .foregroundStyle(PaceColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(SocialText.stepsUnit(goal))
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(PaceLocalization.steps(goal))
                    stepButton(systemImage: "plus", label: SocialText.increaseGoal, delta: GroupGoalRules.increment)
                        .disabled(goal >= GroupGoalRules.range.upperBound)
                }
            }
            Text(SocialText.goalPresets)
                .font(PaceFont.caption.weight(.semibold))
                .foregroundStyle(PaceColor.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: PaceSpacing.xs), count: 3), spacing: PaceSpacing.xs) {
                ForEach(GroupGoalRules.presets, id: \.self) { preset in
                    let isSelected = preset == goal
                    Button {
                        set(preset)
                    } label: {
                        Text(preset.paceFormatted)
                            .font(.system(.subheadline, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                isSelected ? PaceColor.selectionFill : PaceColor.surface,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(isSelected ? Color.clear : PaceColor.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.pacePressable)
                    .accessibilityLabel(PaceLocalization.steps(preset))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
                }
            }
            GroupInfoBox(text: hint)
            if let onSave {
                Button {
                    Task {
                        isSaving = true
                        let saved = await onSave(goal)
                        isSaving = false
                        if saved { dismiss() }
                    }
                } label: {
                    if isSaving {
                        ProgressView().tint(PaceColor.onAccent)
                    } else {
                        Text(SocialText.save)
                    }
                }
                .buttonStyle(.pacePrimary)
                .disabled(isSaving)
            }
        }
        .socialSubpageScroll()
    }

    private func stepButton(systemImage: String, label: String, delta: Int) -> some View {
        Button {
            set(goal + delta)
        } label: {
            Image(systemName: systemImage)
        }
        .buttonStyle(.paceIcon)
        .accessibilityLabel(label)
    }

    private func set(_ value: Int) {
        goal = GroupGoalRules.clamped(value)
        onChange?(goal)
    }
}
