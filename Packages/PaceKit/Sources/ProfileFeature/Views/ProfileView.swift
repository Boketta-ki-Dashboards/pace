import DesignSystem
import RegionFeature
import SwiftUI

/// Profil und Einstellungen.
public struct ProfileView: View {
    private let viewModel: ProfileViewModel

    public init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }

                Section {
                    LabeledContent("Gemeinde", value: viewModel.municipalityName ?? placeholder)
                    LabeledContent("Kreis", value: viewModel.districtName ?? placeholder)
                    LabeledContent("Bundesland", value: viewModel.stateName ?? placeholder)
                    Button("Region ändern") {
                        viewModel.beginRegionChange()
                    }
                } header: {
                    Text("Region")
                } footer: {
                    if viewModel.regionLoadFailed {
                        Text("Die Region konnte nicht geladen werden. Ziehe nach unten, um es erneut zu versuchen.")
                    } else {
                        Text("Pace speichert nur deine Gemeinde, keinen Standort.")
                    }
                }

                Section {
                    Toggle("In regionalen Rankings erscheinen", isOn: participationBinding)
                        .disabled(viewModel.isUpdatingParticipation)
                        .tint(PaceColor.accent)
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(PaceFont.caption)
                            .foregroundStyle(PaceColor.danger)
                    }
                } header: {
                    Text("Rankings")
                } footer: {
                    Text(viewModel.regionalLeaderboardEnabled
                        ? "Andere sehen in den Rankings deiner Regionen deinen Anzeigenamen, deinen Benutzernamen und deine Wettbewerbsschritte."
                        : "Du siehst die Rankings, erscheinst selbst aber nicht darin.")
                }

                Section {
                    Label("Pace überträgt nur deine Wettbewerbsschritte pro Tag. Andere Gesundheitsdaten verlassen dein iPhone nicht.", systemImage: "heart.text.square")
                    Label("Dein Pace-Konto ist an dieses iPhone gebunden. Eine Übertragung auf andere Geräte ist noch nicht möglich.", systemImage: "iphone")
                } header: {
                    Text("Daten & Konto")
                }
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textSecondary)
            }
            .navigationTitle("Profil")
            .refreshable { await viewModel.load() }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: regionSheetBinding) {
            if let search = viewModel.regionSearch {
                RegionChangeSheet(viewModel: viewModel, search: search)
            }
        }
    }

    private var header: some View {
        HStack(spacing: PaceSpacing.m) {
            Text(viewModel.initials)
                .font(PaceFont.title)
                .foregroundStyle(PaceColor.onAccent)
                .frame(width: 64, height: 64)
                .background(PaceColor.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                Text(viewModel.displayName)
                    .font(PaceFont.title)
                    .foregroundStyle(PaceColor.textPrimary)
                Text(viewModel.username)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
            }
        }
        .padding(.vertical, PaceSpacing.xs)
        .accessibilityElement(children: .combine)
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

    private var regionSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isChangingRegion },
            set: { isPresented in
                if !isPresented { viewModel.cancelRegionChange() }
            }
        )
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
