import DesignSystem
import PaceCore
import PhotosUI
import SwiftUI
import UIKit

/// „Profil bearbeiten“ (Social-Profil 2.0): oben die Vorschau mit Banner und Profilbild – antippen zum Bearbeiten
/// (Auftrag 7) –, darunter Bio, Interessen, Auszeichnungen. Namen und Konto bleiben unter „Konto & Profil“. Alles ist
/// freiwillig.
struct ProfileEditPage: View {
    let viewModel: ProfileViewModel
    let backTitle: String

    @Environment(\.paceImageLoader) private var loader
    @State private var pickerTarget: ProfilePhotoTarget?
    @State private var showsPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var cropImage: ProfilePhotoCrop?
    /// Entwürfe nur beim ersten Öffnen übernehmen – zurück von „Konto & Profil“ bleiben ungespeicherte Eingaben.
    @State private var didBeginEditing = false

    var body: some View {
        ProfileSubpage {
            ProfileEditContent(
                viewModel: viewModel,
                details: viewModel.details,
                backTitle: backTitle,
                onPickPhoto: { target in
                    pickerTarget = target
                    showsPhotoPicker = true
                },
                onOpen: { viewModel.open($0) }
            )
        }
        .task { [details = viewModel.details] in
            guard !didBeginEditing else { return }
            didBeginEditing = true
            await details.prepareEditing()
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item, let target = pickerTarget else { return }
            Task {
                defer { pickerItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    reportUnreadablePhoto(for: target)
                    return
                }
                cropImage = ProfilePhotoCrop(target: target, image: image)
            }
        }
        .sheet(item: $cropImage) { crop in
            switch crop.target {
            case .banner:
                BannerCropSheet(image: crop.image) { focus in
                    cropImage = nil
                    uploadBanner(BannerImageProcessing.bannerJPEG(from: crop.image, focusY: focus))
                } onCancel: {
                    cropImage = nil
                }
            case .avatar:
                AvatarCropSheet(image: crop.image) { focus in
                    cropImage = nil
                    uploadAvatar(AvatarImageProcessing.squareJPEG(from: crop.image, focus: focus))
                } onCancel: {
                    cropImage = nil
                }
            }
        }
    }

    private func reportUnreadablePhoto(for target: ProfilePhotoTarget) {
        switch target {
        case .banner: viewModel.details.reportUnreadablePhoto()
        case .avatar: viewModel.account.reportUnreadablePhoto()
        }
    }

    /// Über die bestehende Bannerfunktion (eigener Ordner, altes Banner erst nach Bestätigung gelöscht).
    private func uploadBanner(_ jpeg: Data?) {
        guard let jpeg else {
            viewModel.details.reportUnreadablePhoto()
            return
        }
        Task {
            if let reference = await viewModel.details.uploadBanner(jpegData: jpeg) {
                loader?.store(jpeg, for: reference)
            }
        }
    }

    /// Über den bestehenden Profilbild-Upload von „Konto & Profil“ (kein zweites Upload-System); das neue Bild liegt
    /// danach sofort im Bildspeicher.
    private func uploadAvatar(_ jpeg: Data?) {
        guard let jpeg else {
            viewModel.account.reportUnreadablePhoto()
            return
        }
        Task {
            if let reference = await viewModel.account.uploadAvatar(jpegData: jpeg) {
                loader?.store(jpeg, for: reference)
            }
        }
    }
}

/// Welches Bild bearbeitet wird.
enum ProfilePhotoTarget: Hashable {
    case avatar
    case banner
}

/// Ein ausgewähltes Foto, das noch zugeschnitten wird.
struct ProfilePhotoCrop: Identifiable {
    let id = UUID()
    let target: ProfilePhotoTarget
    let image: UIImage
}

struct ProfileEditContent: View {
    let viewModel: ProfileViewModel
    @Bindable var details: ProfileDetailsViewModel
    let backTitle: String
    var onPickPhoto: (ProfilePhotoTarget) -> Void = { _ in }
    var onOpen: (ProfileRoute) -> Void = { _ in }

    /// Auswahl „Ändern“ / „Entfernen“ nach dem Antippen eines vorhandenen Bilds.
    @State private var photoActions: ProfilePhotoTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.editProfile.title)
                .padding(.bottom, PaceSpacing.xs)

            picturesCard

            switch details.availability {
            case .unknown:
                // Erstes Laden: Ladeanzeige statt deaktivierter Felder ohne Erklärung.
                PaceCard {
                    HStack(spacing: PaceSpacing.s) {
                        ProgressView()
                        Text(PaceLocalization.text(de: "Wird geladen …", en: "Loading …", ru: "Загрузка …"))
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .unavailable:
                PaceCard {
                    ProfileFootnote(text: ProfileDetailsTexts.unavailable)
                }
            case .failed(let message):
                PaceCard {
                    VStack(alignment: .leading, spacing: PaceSpacing.s) {
                        ProfileFootnote(text: message, isError: true)
                        Button(ProfileDetailsTexts.retry) {
                            Task { await details.prepareEditing() }
                        }
                        .buttonStyle(.paceCompact)
                    }
                }
            case .available:
                EmptyView()
            }
            nameCard
            if details.isAvailable {
                bioCard
                interestsCard
                achievementsCard
                if let error = details.errorMessage {
                    ProfileFootnote(text: error, isError: true)
                } else if details.didSave, !details.hasChanges {
                    Label(ProfileDetailsTexts.saved, systemImage: "checkmark.circle.fill")
                        .font(PaceFont.callout.weight(.semibold))
                        .foregroundStyle(PaceColor.accent)
                }
                Button {
                    Task { await details.save() }
                } label: {
                    HStack {
                        if details.isSaving { ProgressView().tint(PaceColor.onAccent) }
                        Text(ProfileDetailsTexts.save)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pacePrimary)
                .disabled(!details.canSave)
                if details.hasChanges {
                    ProfileFootnote(text: ProfileDetailsTexts.unsavedHint)
                    Button(ProfileDetailsTexts.discard, role: .destructive) { details.discardChanges() }
                        .buttonStyle(.paceSecondary)
                        .disabled(details.isBusy)
                }
            }
        }
    }

    // MARK: Profilbild und Banner (antippen zum Bearbeiten)

    /// Vorschau wie das Profil: Banner und überlappendes Profilbild. Antippen öffnet die Fotoauswahl mit Zuschnitt
    /// (vorhandenes Bild: erst „Ändern“ oder „Entfernen“) – höchstens zwei Schritte bis zur Bildauswahl.
    private var picturesCard: some View {
        let account = viewModel.account
        let isBusy = account.isAvatarBusy || details.isBusy
        return PaceCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button { tapped(.banner) } label: {
                    PaceProfileBanner(reference: details.details.banner)
                        .frame(maxWidth: .infinity)
                        .frame(height: 112)
                        .clipped()
                        .overlay {
                            if details.bannerActivity != .idle { ProfilePhotoBusyOverlay() }
                        }
                        .overlay(alignment: .topTrailing) {
                            if details.isAvailable { ProfilePhotoEditBadge().padding(PaceSpacing.s) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .disabled(!details.isAvailable || isBusy)
                .accessibilityLabel(ProfileDetailsTexts.banner)
                .accessibilityHint(ProfileDetailsTexts.tapToEdit)

                HStack(alignment: .bottom, spacing: PaceSpacing.s) {
                    Button { tapped(.avatar) } label: {
                        PaceAvatar(name: account.displayName, seed: account.avatarSeed, size: 84, image: account.avatar)
                            .padding(3)
                            .background(PaceColor.surface, in: Circle())
                            .overlay {
                                if account.isAvatarBusy { ProfilePhotoBusyOverlay().clipShape(Circle()) }
                            }
                            .overlay(alignment: .bottomTrailing) { ProfilePhotoEditBadge() }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.pacePressable)
                    .disabled(!account.supportsAvatar || isBusy)
                    .accessibilityLabel(ProfileDetailsTexts.profilePicture)
                    .accessibilityHint(ProfileDetailsTexts.tapToEdit)
                    .offset(y: -30)
                    .padding(.bottom, -30)

                    Text(ProfileDetailsTexts.picturesHint)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, PaceSpacing.xxs)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, PaceSpacing.m)
                .padding(.bottom, PaceSpacing.s)

                if let error = account.avatarError {
                    ProfileFootnote(text: error, isError: true)
                        .padding(.horizontal, PaceSpacing.m)
                        .padding(.bottom, PaceSpacing.s)
                }
            }
            // Banner an den runden Ecken der Karte zuschneiden.
            .clipShape(RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
        }
        .confirmationDialog(
            ProfileDetailsTexts.editPicture,
            isPresented: Binding(get: { photoActions != nil }, set: { if !$0 { photoActions = nil } }),
            titleVisibility: .hidden,
            presenting: photoActions
        ) { target in
            Button(target == .avatar ? ProfileDetailsTexts.changePhoto : ProfileDetailsTexts.changeBanner) {
                onPickPhoto(target)
            }
            Button(target == .avatar ? ProfileDetailsTexts.removePhoto : ProfileDetailsTexts.removeBanner, role: .destructive) {
                Task {
                    switch target {
                    case .avatar: await account.removeAvatar()
                    case .banner: await details.removeBanner()
                    }
                }
            }
        }
    }

    /// Ohne Bild direkt zur Fotoauswahl, mit Bild erst „Ändern“ oder „Entfernen“.
    private func tapped(_ target: ProfilePhotoTarget) {
        let hasImage = switch target {
        case .avatar: viewModel.account.avatar != nil
        case .banner: details.details.banner != nil
        }
        if hasImage { photoActions = target } else { onPickPhoto(target) }
    }

    // MARK: Namen und Konto (unverändert unter „Konto & Profil“; das Profilbild auch dort)

    private var nameCard: some View {
        Button {
            onOpen(.account)
        } label: {
            ActivityRow(
                systemImage: "person.crop.circle",
                title: PaceLocalization.text(de: "Namen & Konto", en: "Names & account", ru: "Имена и аккаунт"),
                value: viewModel.username,
                showsChevron: true
            )
        }
        .buttonStyle(.pacePressable)
    }

    // MARK: Bio

    private var bioCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack {
                    PaceCardHeader(ProfileDetailsTexts.bio)
                    Spacer()
                    Text(verbatim: "\(details.bioLength)/\(ProfileBioRules.maximumLength)")
                        .font(PaceFont.caption.monospacedDigit())
                        .foregroundStyle(details.bioProblem == nil ? PaceColor.textSecondary : PaceColor.danger)
                        .accessibilityLabel(PaceLocalization.text(
                            de: "\(details.bioLength) von \(ProfileBioRules.maximumLength) Zeichen",
                            en: "\(details.bioLength) of \(ProfileBioRules.maximumLength) characters",
                            ru: "\(details.bioLength) из \(ProfileBioRules.maximumLength) символов"
                        ))
                }
                TextField(ProfileDetailsTexts.bioPlaceholder, text: $details.draftBio, axis: .vertical)
                    .lineLimit(3...ProfileBioRules.maximumLines)
                    .padding(PaceSpacing.s)
                    .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                if let problem = details.bioProblem {
                    ProfileFootnote(text: ProfileBioRules.message(for: problem), isError: true)
                }
                if !details.draftBio.isEmpty {
                    Button(ProfileDetailsTexts.removeBio, role: .destructive) { details.removeBio() }
                        .font(PaceFont.callout)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    // MARK: Interessen

    private var interestsCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack {
                    PaceCardHeader(ProfileDetailsTexts.interests)
                    Spacer()
                    Text(ProfileDetailsTexts.interestsHint(selected: details.draftInterests.count))
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
                PaceFlowLayout(spacing: PaceSpacing.xs) {
                    ForEach(ProfileInterest.allCases) { interest in
                        let isSelected = details.isSelected(interest)
                        Button {
                            details.toggleInterest(interest)
                        } label: {
                            Label(interest.title, systemImage: isSelected ? "checkmark" : interest.systemImage)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, PaceSpacing.s)
                                .frame(minHeight: 36)
                                .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textPrimary)
                                .background(isSelected ? PaceColor.selectionFill : PaceColor.fieldBackground, in: Capsule())
                                .overlay(Capsule().strokeBorder(isSelected ? PaceColor.accent : PaceColor.border, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pacePressable)
                        .disabled(!isSelected && !details.canAddInterest)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityHint(!isSelected && !details.canAddInterest ? PaceLocalization.text(
                            de: "Höchstens 5 Interessen. Wähle zuerst eines ab.",
                            en: "At most 5 interests. Deselect one first.",
                            ru: "Не больше 5 интересов. Сначала сними один."
                        ) : "")
                    }
                }
            }
        }
    }

    // MARK: Auszeichnungen

    private var achievementsCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader(ProfileDetailsTexts.achievements)
                Toggle(ProfileDetailsTexts.showAchievements, isOn: $details.draftShowsAchievements)
                    .tint(PaceColor.actionFill)
                    .font(PaceFont.callout)
                let earned = details.earned
                if earned.isEmpty {
                    ProfileFootnote(text: ProfileDetailsTexts.noAchievementsYet)
                } else {
                    PaceFlowLayout(spacing: PaceSpacing.xs) {
                        ForEach(earned) { achievement in
                            PaceProfileChip(title: achievement.title, systemImage: achievement.systemImage, isAchievement: true)
                        }
                    }
                    .opacity(details.draftShowsAchievements ? 1 : 0.5)
                }
                ProfileFootnote(text: ProfileDetailsTexts.achievementsNote)
            }
        }
    }
}

/// Kleiner Stift auf Profilbild und Banner: zeigt, dass sie sich durch Antippen ändern lassen.
struct ProfilePhotoEditBadge: View {
    var body: some View {
        Image(systemName: "pencil")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(PaceColor.onAccent)
            .frame(width: 28, height: 28)
            .background(PaceColor.actionFill, in: Circle())
            .overlay(Circle().strokeBorder(PaceColor.surface, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

/// Lädt gerade hoch bzw. entfernt (über dem Bild).
struct ProfilePhotoBusyOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            ProgressView().tint(.white)
        }
    }
}

/// Ausschnitt des Profilbilds wählen: quadratisch mit runder Vorschau, entlang der längeren Seite verschiebbar (Ziehen
/// oder Regler).
struct AvatarCropSheet: View {
    let image: UIImage
    let onUse: (CGFloat) -> Void
    let onCancel: () -> Void

    @State private var focus: CGFloat = 0.5
    @State private var dragStart: CGFloat?

    private var isLandscape: Bool { image.size.width > image.size.height }

    var body: some View {
        NavigationStack {
            VStack(spacing: PaceSpacing.m) {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    let scale = side / max(min(image.size.width, image.size.height), 1)
                    let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    let overflow = isLandscape ? drawn.width - side : drawn.height - side
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: drawn.width, height: drawn.height)
                        .offset(x: isLandscape ? -overflow * focus : 0, y: isLandscape ? 0 : -overflow * focus)
                        .frame(width: side, height: side, alignment: .topLeading)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(PaceColor.border, lineWidth: 1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let start = dragStart ?? focus
                                    if dragStart == nil { dragStart = focus }
                                    guard overflow > 0 else { return }
                                    let moved = isLandscape ? value.translation.width : value.translation.height
                                    focus = min(max(start - moved / overflow, 0), 1)
                                }
                                .onEnded { _ in dragStart = nil }
                        )
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, PaceSpacing.l)
                Text(isLandscape ? ProfileDetailsTexts.avatarCropHintHorizontal : ProfileDetailsTexts.avatarCropHintVertical)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .multilineTextAlignment(.center)
                Slider(value: $focus, in: 0...1)
                    .tint(PaceColor.actionFill)
                    .accessibilityLabel(ProfileDetailsTexts.avatarCropTitle)
                Spacer()
            }
            .padding(PaceSpacing.m)
            .paceScreenBackground()
            .navigationTitle(ProfileDetailsTexts.avatarCropTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ProfileDetailsTexts.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ProfileDetailsTexts.use) { onUse(focus) }
                }
            }
        }
    }
}

/// Ausschnitt des Banners wählen: Querformat 3:1, senkrecht verschiebbar (Ziehen oder Regler).
struct BannerCropSheet: View {
    let image: UIImage
    let onUse: (CGFloat) -> Void
    let onCancel: () -> Void

    @State private var focus: CGFloat = 0.5
    @State private var dragStart: CGFloat?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PaceSpacing.m) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let height = width / BannerImageProcessing.aspectRatio
                    let scaledHeight = width / max(image.size.width, 1) * image.size.height
                    let overflow = max(scaledHeight - height, 0)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: max(scaledHeight, height))
                        .offset(y: -overflow * focus)
                        .frame(width: width, height: height, alignment: .top)
                        .clipShape(RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let start = dragStart ?? focus
                                    if dragStart == nil { dragStart = focus }
                                    guard overflow > 0 else { return }
                                    focus = min(max(start - value.translation.height / overflow, 0), 1)
                                }
                                .onEnded { _ in dragStart = nil }
                        )
                }
                .aspectRatio(BannerImageProcessing.aspectRatio, contentMode: .fit)
                Text(ProfileDetailsTexts.bannerCropHint)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                Slider(value: $focus, in: 0...1)
                    .tint(PaceColor.actionFill)
                    .accessibilityLabel(ProfileDetailsTexts.bannerCropTitle)
                Spacer()
            }
            .padding(PaceSpacing.m)
            .paceScreenBackground()
            .navigationTitle(ProfileDetailsTexts.bannerCropTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ProfileDetailsTexts.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ProfileDetailsTexts.use) { onUse(focus) }
                }
            }
        }
    }
}

/// Bereitet ein Foto als Banner vor: Querformat 3:1 am gewählten Ausschnitt, höchstens 1.500 Pixel breit, richtig
/// gedreht (UIImage zeichnet die Ausrichtung mit), JPEG unter der Grenze des Servers (5 MB).
@MainActor
enum BannerImageProcessing {
    static let aspectRatio: CGFloat = 3
    static let maximumWidth: CGFloat = 1_500

    /// - Parameter focusY: 0 = oberer Rand, 1 = unterer Rand des Fotos.
    static func bannerJPEG(from image: UIImage, focusY: CGFloat, maximumBytes: Int = MediaRules.maximumBytes(for: .avatar)) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let targetWidth = min(image.size.width, maximumWidth).rounded()
        let targetSize = CGSize(width: targetWidth, height: (targetWidth / aspectRatio).rounded())
        // Füllend skalieren, dann senkrecht am Ausschnitt ausrichten (waagerecht mittig).
        let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let overflowY = max(drawSize.height - targetSize.height, 0)
        let origin = CGPoint(x: (targetSize.width - drawSize.width) / 2, y: -overflowY * min(max(focusY, 0), 1))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let banner = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        for quality in [0.85, 0.7, 0.55, 0.4] {
            if let jpeg = banner.jpegData(compressionQuality: quality), jpeg.count <= maximumBytes {
                return jpeg
            }
        }
        return nil
    }
}
