import DesignSystem
import PaceCore
import PhotosUI
import SwiftUI

/// Unterseiten der Gruppeneinstellungen.
enum GroupSettingsSubpage: Hashable {
    case privacy
    case goal
}

/// Gruppeneinstellungen: Name, Beschreibung, Typ, Privatsphäre, Bild und Tagesziel (wer die Gruppe verwaltet),
/// Einladungscode, Gruppe verlassen, löschen oder melden.
struct GroupSettingsView: View {
    @State private var viewModel: GroupDetailViewModel
    private let onOpen: (SocialRoute) -> Void
    private let onGroupGone: () -> Void
    @State private var form: GroupSettingsForm
    @State private var subpage: GroupSettingsSubpage?
    @State private var confirmation: GroupSettingsConfirmation?
    @State private var showsConfirmation = false
    @State private var showsPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem?

    init(viewModel: GroupDetailViewModel, onOpen: @escaping (SocialRoute) -> Void, onGroupGone: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onOpen = onOpen
        self.onGroupGone = onGroupGone
        _form = State(initialValue: GroupSettingsForm(group: viewModel.group))
    }

    var body: some View {
        GroupSettingsContent(
            viewModel: viewModel,
            form: $form,
            onOpen: { subpage = $0 },
            onPickImage: { showsPhotoPicker = true },
            onConfirm: { kind in
                confirmation = kind
                showsConfirmation = true
            },
            onReport: { onOpen(.report(.group(id: viewModel.group.id, name: viewModel.group.name))) }
        )
        .socialSubpageScroll()
        .task { [viewModel] in
            if viewModel.state != .loaded { await viewModel.load() }
        }
        .onChange(of: viewModel.group) { old, new in
            // Neuer Stand vom Server: übernehmen, solange nichts ungespeichert geändert wurde.
            if form == GroupSettingsForm(group: old) { form = GroupSettingsForm(group: new) }
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickerItem = nil
                if let data, let upload = GroupImageProcessing.upload(from: data) {
                    await viewModel.setImage(upload)
                } else {
                    viewModel.show(SocialViewModel.Notice(text: SocialText.imageNotLoaded, isError: true))
                }
            }
        }
        .navigationDestination(item: $subpage) { page in
            switch page {
            case .privacy:
                GroupPrivacyPage(backTitle: SocialText.settings, selection: $form.privacy)
            case .goal:
                GroupGoalPage(
                    backTitle: SocialText.settings,
                    goal: viewModel.group.nextDailyGoal ?? viewModel.group.dailyGoal,
                    hint: SocialText.goalChangeHint,
                    onSave: { await viewModel.setGoal($0) }
                )
            }
        }
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: $showsConfirmation,
            titleVisibility: .visible,
            presenting: confirmation
        ) { kind in
            switch kind {
            case .leave:
                Button(SocialText.leaveGroup, role: .destructive) {
                    Task { if await viewModel.leave() { onGroupGone() } }
                }
            case .delete:
                Button(SocialText.deleteGroup, role: .destructive) {
                    Task { if await viewModel.delete() { onGroupGone() } }
                }
            case .regenerate:
                Button(SocialText.newCode) {
                    Task { await viewModel.regenerateInviteCode() }
                }
            case .removeImage:
                Button(SocialText.removeImage, role: .destructive) {
                    Task { await viewModel.removeImage() }
                }
            }
            Button(SocialText.cancel, role: .cancel) {}
        } message: { kind in
            Text(kind.message(isOwner: viewModel.group.isOwner))
        }
    }
}

/// Bestätigungen in den Gruppeneinstellungen.
enum GroupSettingsConfirmation: String, Identifiable {
    case leave
    case delete
    case regenerate
    case removeImage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leave: SocialText.leaveGroupTitle
        case .delete: SocialText.deleteGroupTitle
        case .regenerate: SocialText.regenerateTitle
        case .removeImage: SocialText.removeImage
        }
    }

    func message(isOwner: Bool) -> String {
        switch self {
        case .leave: isOwner ? SocialText.leaveOwnerMessage : SocialText.leaveMemberMessage
        case .delete: SocialText.deleteMessage
        case .regenerate: SocialText.regenerateMessage
        case .removeImage: SocialText.removeImageMessage
        }
    }
}

/// Bearbeiteter, noch nicht gespeicherter Stand der Gruppendaten.
struct GroupSettingsForm: Equatable {
    var name: String
    var description: String
    var kind: GroupKind
    var privacy: GroupPrivacy

    init(group: GroupSummary) {
        name = group.name
        description = group.description
        kind = group.kind
        privacy = group.privacy
    }

    func differs(from group: GroupSummary) -> Bool {
        self != GroupSettingsForm(group: group)
    }
}

/// Inhalt der Gruppeneinstellungen mit Kopfzeile (ohne Scrollen und Dialoge) – auch für Snapshot-Tests.
struct GroupSettingsContent: View {
    let viewModel: GroupDetailViewModel
    @Binding var form: GroupSettingsForm
    var onOpen: (GroupSettingsSubpage) -> Void = { _ in }
    var onPickImage: () -> Void = {}
    var onConfirm: (GroupSettingsConfirmation) -> Void = { _ in }
    var onReport: () -> Void = {}

    private var group: GroupSummary { viewModel.group }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: group.name, title: SocialText.settings)
            if let notice = viewModel.notice {
                NoticeBanner(notice: notice) { viewModel.dismissNotice() }
            }
            if viewModel.state == .gone {
                PaceStatusView(systemImage: "person.3", title: SocialText.groupGoneTitle, message: SocialText.groupGoneMessage)
            } else {
                if group.isOwner {
                    imageCard
                    detailsCards
                } else {
                    GroupInfoBox(text: SocialText.onlyAdminCanChange)
                    readOnlyDetails
                }
                goalCard
                inviteCodeCard
                dangerZone
            }
        }
    }

    // MARK: Bild

    private var imageCard: some View {
        GroupFormCard(title: SocialText.groupImage) {
            HStack(spacing: PaceSpacing.m) {
                GroupAvatar(name: group.name, kind: group.kind, image: group.image, size: 64)
                VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                    Button(group.imagePath == nil ? SocialText.chooseGroupImage : SocialText.changeGroupImage, action: onPickImage)
                        .buttonStyle(.paceSoft)
                        .font(.system(.subheadline, weight: .semibold))
                        .disabled(!viewModel.canChangeImage || viewModel.isWorking)
                    if group.imagePath != nil {
                        Button(SocialText.removeImage) { onConfirm(.removeImage) }
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.danger)
                            .buttonStyle(.plain)
                            .frame(minHeight: 32)
                            .disabled(viewModel.isWorking)
                    }
                }
                Spacer(minLength: 0)
            }
            if !viewModel.canChangeImage {
                Text(SocialText.imageStorageUnavailable)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Name, Beschreibung, Typ, Privatsphäre

    @ViewBuilder
    private var detailsCards: some View {
        GroupFormCard(title: SocialText.groupName, error: GroupDraft(name: form.name).validName == nil ? SocialError.invalidName.message : nil) {
            TextField(SocialText.groupNamePlaceholder, text: $form.name)
                .modifier(GroupFieldStyle())
        }
        GroupFormCard(title: SocialText.groupDescription, error: GroupDraft(description: form.description).validDescription == nil ? SocialError.invalidDescription.message : nil) {
            TextField(SocialText.descriptionPlaceholder, text: $form.description, axis: .vertical)
                .lineLimit(2...4)
                .modifier(GroupFieldStyle())
        }
        GroupFormCard(title: SocialText.groupType) {
            GroupKindPicker(selection: $form.kind)
        }
        GroupFormCard(title: SocialText.privacy) {
            GroupFormRow(action: { onOpen(.privacy) }) {
                Image(systemName: form.privacy == .inviteOnly ? "lock" : "key")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(PaceColor.textPrimary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                Text(form.privacy.title)
                    .font(PaceFont.body)
                    .foregroundStyle(PaceColor.textPrimary)
            }
        }
        if form.differs(from: group) {
            Button {
                Task {
                    await viewModel.updateDetails(name: form.name, description: form.description, kind: form.kind, privacy: form.privacy)
                }
            } label: {
                if viewModel.isWorking {
                    ProgressView().tint(PaceColor.onAccent)
                } else {
                    Text(SocialText.save)
                }
            }
            .buttonStyle(.pacePrimary)
            .disabled(viewModel.isWorking)
        }
    }

    private var readOnlyDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            readOnlyRow(SocialText.groupName, value: group.name)
            if !group.description.isEmpty {
                Divider().padding(.leading, PaceSpacing.m)
                readOnlyRow(SocialText.groupDescription, value: group.description)
            }
            Divider().padding(.leading, PaceSpacing.m)
            readOnlyRow(SocialText.groupType, value: group.kind.title)
            Divider().padding(.leading, PaceSpacing.m)
            readOnlyRow(SocialText.privacy, value: group.privacy.title)
        }
        .paceCardBackground()
    }

    private func readOnlyRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
            Text(value)
                .font(PaceFont.body)
                .foregroundStyle(PaceColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PaceSpacing.m)
        .padding(.vertical, PaceSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Tagesziel

    private var goalCard: some View {
        GroupFormCard(title: SocialText.dailyGoalPerMember) {
            if group.isOwner {
                GroupFormRow(action: { onOpen(.goal) }) {
                    goalLabel
                }
            } else {
                goalLabel
            }
            GroupInfoBox(text: SocialText.goalIndependentHint)
        }
    }

    private var goalLabel: some View {
        HStack(spacing: PaceSpacing.s) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(PaceColor.textPrimary)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(PaceLocalization.steps(group.dailyGoal))
                    .font(PaceFont.body)
                    .foregroundStyle(PaceColor.textPrimary)
                if let next = group.nextDailyGoal, next != group.dailyGoal {
                    Text(SocialText.nextGoal(next))
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
        }
    }

    // MARK: Einladungscode

    private var inviteCodeCard: some View {
        GroupFormCard(title: SocialText.inviteCode) {
            if group.privacy == .code {
                Text(group.inviteCode)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .textSelection(.enabled)
                    .accessibilityLabel(SocialText.inviteCode + ": " + group.inviteCode.map(String.init).joined(separator: " "))
                HStack(spacing: PaceSpacing.xs) {
                    ShareLink(item: viewModel.inviteShareText) {
                        Label(SocialText.shareCode, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.paceSoft)
                    if group.isOwner {
                        Button {
                            onConfirm(.regenerate)
                        } label: {
                            Label(SocialText.newCode, systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.paceSoft)
                        .disabled(viewModel.isWorking)
                    }
                }
                .font(.system(.subheadline, weight: .semibold))
            } else {
                Text(SocialText.inviteOnlyCodeHint)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Verlassen, löschen, melden

    private var dangerZone: some View {
        VStack(spacing: 0) {
            dangerRow(SocialText.leaveGroup, systemImage: "rectangle.portrait.and.arrow.right") { onConfirm(.leave) }
            if group.isOwner {
                Divider().padding(.leading, 52)
                dangerRow(SocialText.deleteGroup, systemImage: "trash") { onConfirm(.delete) }
            } else {
                Divider().padding(.leading, 52)
                dangerRow(SocialText.reportGroup, systemImage: "exclamationmark.bubble", action: onReport)
            }
        }
        .paceCardBackground()
        .disabled(viewModel.isWorking)
        .padding(.top, PaceSpacing.xs)
    }

    private func dangerRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(title)
                    .font(PaceFont.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(PaceColor.danger)
            .padding(.horizontal, PaceSpacing.m)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
    }
}
