import DesignSystem
import PaceCore
import RegionFeature
import SwiftUI

/// Profil und Einstellungen im Kartenstil des Home-Screens.
public struct ProfileView: View {
    private let viewModel: ProfileViewModel

    public init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                ProfileContent(viewModel: viewModel)
                    .padding(.horizontal, PaceSpacing.m)
                    .padding(.bottom, PaceSpacing.l)
            }
            .refreshable { [viewModel] in await viewModel.load() }
            .paceScreenBackground()
            .navigationTitle("Profil")
        }
        .task { [viewModel] in await viewModel.load() }
        .sheet(item: regionSheetBinding) { search in
            RegionChangeSheet(viewModel: viewModel, search: search)
        }
    }

    /// Mit `sheet(item:)` behält SwiftUI den Inhalt während der Schließen-Animation.
    private var regionSheetBinding: Binding<RegionSearchViewModel?> {
        Binding(
            get: { viewModel.regionSearch },
            set: { search in
                if search == nil { viewModel.cancelRegionChange() }
            }
        )
    }
}

/// Inhalt des Profil-Tabs (ohne Navigation und Scrollen).
struct ProfileContent: View {
    let viewModel: ProfileViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            header
            regionCard
            rankingsCard
            appearanceCard
            dataCard
        }
    }

    private var header: some View {
        PaceCard {
            HStack(spacing: PaceSpacing.m) {
                Text(viewModel.initials)
                    .font(.system(.title, weight: .bold))
                    .foregroundStyle(PaceColor.onAccent)
                    .frame(width: 68, height: 68)
                    .background(PaceColor.accentStrong, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                    Text(viewModel.displayName)
                        .font(PaceFont.title)
                        .foregroundStyle(PaceColor.textPrimary)
                    Text(viewModel.username)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var regionCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Deine Region")
                VStack(spacing: PaceSpacing.xs) {
                    InfoRow(systemImage: "building.2", title: "Gemeinde", value: viewModel.municipalityName ?? placeholder)
                    InfoRow(systemImage: "map", title: "Kreis", value: viewModel.districtName ?? placeholder)
                    InfoRow(systemImage: "flag", title: "Bundesland", value: viewModel.stateName ?? placeholder)
                }
                Text(viewModel.regionLoadFailed
                    ? "Die Region konnte nicht geladen werden. Ziehe nach unten, um es erneut zu versuchen."
                    : "Pace speichert nur deine Gemeinde, keinen Standort.")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                Button("Region ändern") {
                    viewModel.beginRegionChange()
                }
                .buttonStyle(.paceSecondary)
            }
        }
    }

    private var rankingsCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Sichtbarkeit in Rankings")
                PaceTile(isHighlighted: viewModel.regionalLeaderboardEnabled) {
                    Toggle(isOn: participationBinding) {
                        Text("In regionalen Rankings erscheinen")
                            .font(PaceFont.headline)
                            .foregroundStyle(PaceColor.textPrimary)
                    }
                    .tint(PaceColor.accentStrong)
                    .disabled(viewModel.isUpdatingParticipation)
                    .padding(.vertical, PaceSpacing.xxs)
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.danger)
                }
                Text(viewModel.regionalLeaderboardEnabled
                    ? "Andere sehen in den Rankings deiner Regionen deinen Anzeigenamen, deinen Benutzernamen und deine Wettbewerbsschritte."
                    : "Du siehst die Rankings, erscheinst selbst aber nicht darin.")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appearanceCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Darstellung")
                Text("App-Icon")
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .top, spacing: PaceSpacing.s) {
                    ForEach(AppIconChoice.allCases) { choice in
                        AppIconOption(
                            choice: choice,
                            isSelected: viewModel.appIcon == choice,
                            isEnabled: viewModel.supportsAppIconChange && !viewModel.isChangingAppIcon
                        ) {
                            Task { await viewModel.selectAppIcon(choice) }
                        }
                    }
                }
                if let error = viewModel.appIconError {
                    Text(error)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.danger)
                }
                Text(viewModel.supportsAppIconChange
                    ? "„Automatisch“ folgt der Darstellung deines Home-Bildschirms (hell, dunkel oder getönt, ab iOS 18)."
                    : "Auf diesem Gerät lässt sich das App-Icon nicht ändern.")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dataCard: some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                PaceCardHeader("Daten & Konto")
                NoteRow(
                    systemImage: "heart.text.square",
                    text: "Pace überträgt nur deine Wettbewerbsschritte pro Tag. Andere Gesundheitsdaten verlassen dein iPhone nicht."
                )
                NoteRow(
                    systemImage: "checkmark.shield",
                    text: "Manuell eingetragene Schritte zählen nicht für Rankings."
                )
                NoteRow(
                    systemImage: "iphone",
                    text: "Dein Pace-Konto ist an dieses iPhone gebunden. Eine Übertragung auf andere Geräte ist noch nicht möglich."
                )
            }
        }
    }

    private var placeholder: String { "–" }

    private var participationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.regionalLeaderboardEnabled },
            set: { enabled in
                Task { await viewModel.setRegionalLeaderboardEnabled(enabled) }
            }
        )
    }
}

/// Eine Icon-Variante zur Auswahl: Vorschau, Name, Auswahlmarkierung.
private struct AppIconOption: View {
    let choice: AppIconChoice
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: PaceSpacing.xs) {
                PaceAppIconPreview(variant, size: 60)
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(isSelected ? PaceColor.accentStrong : .clear, lineWidth: 2.5)
                    )
                HStack(spacing: PaceSpacing.xxs) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(PaceColor.accentStrong)
                            .accessibilityHidden(true)
                    }
                    Text(choice.title)
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(PaceFont.callout)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pacePressable)
        .disabled(!isEnabled)
        .opacity(isEnabled || isSelected ? 1 : 0.5)
        .accessibilityLabel("App-Icon \(choice.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var variant: PaceAppIconPreview.Variant {
        switch choice {
        case .automatic: .automatic
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Zeile mit Symbol, Bezeichnung und Wert.
private struct InfoRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        PaceTile {
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: systemImage)
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                Spacer(minLength: PaceSpacing.xs)
                Text(value)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, PaceSpacing.xxs)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Erklärender Hinweis mit Symbol.
private struct NoteRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: PaceSpacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(PaceColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Neue Gemeinde suchen und speichern.
private struct RegionChangeSheet: View {
    let viewModel: ProfileViewModel
    let search: RegionSearchViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpacing.l) {
                    RegionSearchView(viewModel: search)
                    if let error = viewModel.regionChangeError {
                        Text(error)
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.danger)
                    }
                    Text(viewModel.regionalLeaderboardEnabled
                        ? "Du trittst danach in den Rankings der neuen Region an."
                        : "Deine Einstellung zu regionalen Rankings bleibt unverändert.")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                    RegionPrivacyNotice()
                }
                .padding(PaceSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .paceScreenBackground()
            .navigationTitle("Region ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { viewModel.cancelRegionChange() }
                        .disabled(viewModel.isSavingRegion)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSavingRegion {
                        ProgressView()
                    } else {
                        Button("Sichern") {
                            Task { await viewModel.saveRegionChange() }
                        }
                        .disabled(!viewModel.canSaveRegion)
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSavingRegion)
    }
}
