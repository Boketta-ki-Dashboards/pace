import DesignSystem
import PaceCore
import SwiftUI

/// Widget-Galerie als Unterseite von Home („‹ Anpassen“ → pace → „Widget hinzufügen“).
struct HomeWidgetGalleryScreen: View {
    let dashboard: HomeDashboardViewModel

    @State private var gallery: HomeWidgetGalleryViewModel
    @State private var showsFriendPicker = false
    @Environment(\.dismiss) private var dismiss

    init(dashboard: HomeDashboardViewModel, route: HomeWidgetGalleryRoute) {
        self.dashboard = dashboard
        _gallery = State(initialValue: dashboard.gallery(for: route))
    }

    var body: some View {
        ScrollView {
            HomeWidgetGalleryContent(
                gallery: gallery,
                dashboard: dashboard,
                onShowAllFriends: { showsFriendPicker = true },
                onSave: { save() }
            )
            .padding(.horizontal, PaceSpacing.m)
            .padding(.bottom, PaceSpacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .paceScreenBackground()
        .paceSubpage()
        .task { [gallery] in
            await gallery.loadIfNeeded()
        }
        .sheet(isPresented: $showsFriendPicker) {
            HomeFriendPickerSheet(gallery: gallery)
        }
    }

    private func save() {
        guard gallery.save() else { return }
        dismiss()
    }
}

/// Inhalt der Widget-Galerie ohne Scrollen (auch für Snapshot-Tests).
struct HomeWidgetGalleryContent: View {
    @Bindable var gallery: HomeWidgetGalleryViewModel
    let dashboard: HomeDashboardViewModel
    var onShowAllFriends: () -> Void = {}
    var onSave: () -> Void = {}

    private let columns = [
        GridItem(.flexible(), spacing: PaceSpacing.s, alignment: .top),
        GridItem(.flexible(), spacing: PaceSpacing.s, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.m) {
            PaceSubpageHeader(backTitle: HomeTexts.customize, title: gallery.title)

            section(PaceLocalization.text(de: "Kategorie", en: "Category", ru: "Категория")) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: PaceSpacing.s) {
                    ForEach(gallery.categories) { category in
                        HomeGalleryCategoryTile(
                            category: category,
                            isSelected: gallery.selectedCategory == category,
                            isEnabled: gallery.isSelectable(category),
                            note: gallery.isAlreadyOnHome(category)
                                ? PaceLocalization.text(de: "Schon auf Home", en: "Already on Home", ru: "Уже на главной")
                                : nil
                        ) {
                            gallery.select(category)
                        }
                    }
                }
            }

            configuration

            section(PaceLocalization.text(de: "Widget-Vorschau", en: "Widget preview", ru: "Предпросмотр")) {
                HomeModuleView(module: gallery.draft, viewModel: dashboard, mode: .preview)
                    .padding(PaceSpacing.s)
                    .frame(maxWidth: .infinity)
                    .background(PaceColor.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous)
                            .strokeBorder(PaceColor.accent.opacity(0.18), lineWidth: 1)
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(PaceLocalization.text(de: "Widget-Vorschau", en: "Widget preview", ru: "Предпросмотр виджета"))
            }

            section(HomeTexts.chooseSize) {
                HStack(alignment: .top, spacing: PaceSpacing.xs) {
                    ForEach(HomeModuleSize.allCases) { size in
                        HomeGallerySizeTile(
                            size: size,
                            isSelected: gallery.draft.size == size,
                            isSupported: gallery.supportedSizes.contains(size)
                        ) {
                            HomeModuleView(module: gallery.previewModule(size: size), viewModel: dashboard, mode: .preview)
                        } onSelect: {
                            gallery.size = size
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                if let message = gallery.validationMessage {
                    Label(message, systemImage: "info.circle")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(gallery.saveTitle, action: onSave)
                    .buttonStyle(.pacePrimary)
                    .disabled(!gallery.canSave)
            }
        }
    }

    // MARK: Konfiguration je Art

    @ViewBuilder
    private var configuration: some View {
        switch gallery.kind {
        case .friends:
            configurationCard {
                Button(action: onShowAllFriends) {
                    HStack {
                        Text(PaceLocalization.text(de: "Freunde auswählen", en: "Choose friends", ru: "Выбери друзей"))
                            .font(PaceFont.cardTitle)
                            .foregroundStyle(PaceColor.textPrimary)
                        Spacer(minLength: PaceSpacing.xs)
                        HomeChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                friendChips
                if gallery.friendIDs.isEmpty {
                    Text(gallery.allFriendsHint)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(PaceLocalization.text(de: "Widget-Name", en: "Widget name", ru: "Название виджета"))
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(PaceColor.textPrimary)
                    .padding(.top, PaceSpacing.xxs)
                HStack(spacing: PaceSpacing.xs) {
                    TextField(gallery.namePlaceholder, text: $gallery.name)
                        .font(.body)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                    if !gallery.name.isEmpty {
                        Button {
                            gallery.name = ""
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PaceColor.textSecondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(PaceLocalization.text(de: "Namen löschen", en: "Clear name", ru: "Очистить название"))
                    }
                }
                .padding(.horizontal, PaceSpacing.s)
                .frame(minHeight: 48)
                .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
                .onChange(of: gallery.name) { _, newValue in
                    if newValue.count > HomeWidgetConfiguration.nameLength {
                        gallery.name = String(newValue.prefix(HomeWidgetConfiguration.nameLength))
                    }
                }
                Text(gallery.friendsHint)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .groups:
            configurationCard {
                configurationTitle(PaceLocalization.text(de: "Gruppe auswählen", en: "Choose a group", ru: "Выбери группу"))
                VStack(spacing: PaceSpacing.xs) {
                    HomeGalleryChoiceRow(
                        title: PaceLocalization.text(de: "Alle Gruppen", en: "All groups", ru: "Все группы"),
                        systemImage: "person.3",
                        isSelected: gallery.groupID == nil
                    ) {
                        gallery.groupID = nil
                    }
                    ForEach(gallery.groups) { group in
                        HomeGalleryChoiceRow(
                            title: group.name,
                            systemImage: "flame",
                            isSelected: gallery.groupID == group.id
                        ) {
                            gallery.groupID = group.id
                        }
                    }
                }
                if gallery.groups.isEmpty {
                    Text(PaceLocalization.text(
                        de: "Du bist noch in keiner Gruppe. Erstelle im Social-Tab eine Gruppe oder tritt per Code bei.",
                        en: "You're not in a group yet. Create one in the Social tab or join with a code.",
                        ru: "Ты пока не состоишь в группе. Создай группу во вкладке «Друзья» или вступи по коду."
                    ))
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .regionRanks, .neighborhood:
            configurationCard {
                configurationTitle(gallery.kind == .neighborhood
                    ? PaceLocalization.text(de: "Ranking-Ebene", en: "Ranking level", ru: "Уровень рейтинга")
                    : PaceLocalization.text(de: "Ebenen auswählen", en: "Choose levels", ru: "Выбери уровни"))
                LazyVGrid(columns: columns, alignment: .leading, spacing: PaceSpacing.xs) {
                    ForEach(gallery.levelChoices, id: \.self) { level in
                        HomeGalleryChip(
                            title: gallery.levelTitle(level),
                            systemImage: RegionRankCard.icon(for: level),
                            isSelected: gallery.isSelected(level: level)
                        ) {
                            gallery.toggleLevel(level)
                        }
                    }
                }
            }
        case .activity:
            configurationCard {
                configurationTitle(PaceLocalization.text(de: "Kennzahl auswählen", en: "Choose a metric", ru: "Выбери показатель"))
                LazyVGrid(columns: columns, alignment: .leading, spacing: PaceSpacing.xs) {
                    ForEach(HomeActivityMetric.allCases) { metric in
                        HomeGalleryChip(title: metric.title, systemImage: metric.systemImage, isSelected: gallery.metric == metric) {
                            gallery.metric = metric
                        }
                    }
                }
            }
        case .stepsToday, .week, .streak, .calendar:
            configurationCard {
                configurationTitle(gallery.kind.title)
                Text(gallery.kind == .stepsToday
                    ? PaceLocalization.text(
                        de: "Deine Schrittkarte bleibt immer auf Home. Hier wählst du ihre Größe.",
                        en: "Your steps card always stays on Home. Choose its size here.",
                        ru: "Карточка шагов всегда остаётся на главной. Здесь можно выбрать её размер."
                    )
                    : gallery.kind.summary)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var friendChips: some View {
        let chips = gallery.chipFriends
        return LazyVGrid(columns: columns, alignment: .leading, spacing: PaceSpacing.xs) {
            ForEach(chips) { profile in
                HomeGalleryChip(
                    title: profile.displayName,
                    avatar: profile,
                    isSelected: gallery.isSelected(friend: profile.publicID)
                ) {
                    gallery.toggleFriend(profile.publicID)
                }
            }
            HomeGalleryChip(
                title: gallery.additionalSelectedCount > 0
                    ? PaceLocalization.text(
                        de: "Weitere (\(gallery.additionalSelectedCount))",
                        en: "More (\(gallery.additionalSelectedCount))",
                        ru: "Ещё (\(gallery.additionalSelectedCount))"
                    )
                    : PaceLocalization.text(de: "Weitere…", en: "More…", ru: "Ещё…"),
                systemImage: "person.2",
                isSelected: false,
                action: onShowAllFriends
            )
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            Text(title)
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(PaceColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func configurationTitle(_ title: String) -> some View {
        Text(title)
            .font(PaceFont.cardTitle)
            .foregroundStyle(PaceColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func configurationCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            content()
        }
        .padding(PaceSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaceColor.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous)
                .strokeBorder(PaceColor.accent.opacity(0.18), lineWidth: 1)
        )
    }
}

/// Kachel einer Kategorie: Symbol, Name (ggf. zweite Zeile), Pfeil; die gewählte ist mint hinterlegt.
private struct HomeGalleryCategoryTile: View {
    let category: HomeModuleKind
    let isSelected: Bool
    let isEnabled: Bool
    let note: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: category.systemImage)
                    .font(.title3)
                    .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textPrimary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.galleryTitle)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = note ?? category.gallerySubtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(isSelected ? PaceColor.onSelection.opacity(0.8) : PaceColor.textSecondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PaceSpacing.s)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isSelected ? PaceColor.selectionFill : PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                    .strokeBorder(isSelected ? PaceColor.accent.opacity(0.4) : PaceColor.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Auswahl-Chip (Freund, Ebene, Kennzahl) mit Haken bzw. Plus.
private struct HomeGalleryChip: View {
    let title: String
    var systemImage: String?
    var avatar: SocialProfile?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.xs) {
                if let avatar {
                    PaceAvatar(name: avatar.displayName, seed: avatar.publicID.uuidString, size: 32, image: avatar.avatar)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body)
                        .foregroundStyle(PaceColor.textPrimary)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(isSelected ? PaceColor.actionFill : PaceColor.textSecondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PaceSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(isSelected ? PaceColor.accentSoft : PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                    .strokeBorder(isSelected ? PaceColor.accent.opacity(0.4) : PaceColor.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Zeile zur Auswahl genau einer Möglichkeit (Gruppe).
private struct HomeGalleryChoiceRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: systemImage)
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: PaceSpacing.xs)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? PaceColor.actionFill : PaceColor.textSecondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PaceSpacing.s)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(isSelected ? PaceColor.accentSoft : PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                    .strokeBorder(isSelected ? PaceColor.accent.opacity(0.4) : PaceColor.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Größen-Kachel mit verkleinerter Live-Vorschau des Widgets.
private struct HomeGallerySizeTile<Preview: View>: View {
    let size: HomeModuleSize
    let isSelected: Bool
    let isSupported: Bool
    @ViewBuilder let preview: () -> Preview
    let onSelect: () -> Void

    private let previewWidth: CGFloat = 340
    private let scale: CGFloat = 0.22
    private let previewHeight: CGFloat = 74

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: PaceSpacing.xs) {
                preview()
                    .frame(width: previewWidth)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: previewWidth * scale, height: previewHeight, alignment: .topLeading)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Text(size.title)
                    .font(.system(.subheadline, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? PaceColor.onSelection : PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, PaceSpacing.xs)
            .frame(maxWidth: .infinity)
            .background(isSelected ? PaceColor.selectionFill : PaceColor.surface, in: RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PaceRadius.tile, style: .continuous)
                    .strokeBorder(isSelected ? PaceColor.accentStrong : PaceColor.border, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .disabled(!isSupported)
        .opacity(isSupported ? 1 : 0.4)
        .accessibilityLabel(HomeTexts.size(size))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
