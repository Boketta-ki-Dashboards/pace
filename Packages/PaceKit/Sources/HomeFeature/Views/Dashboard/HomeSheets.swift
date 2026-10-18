import DesignSystem
import PaceCore
import SwiftUI

/// „Anpassen“: Module hinzufügen, entfernen, verschieben, in der Größe ändern und – beim Umfeld – die Ebene wählen.
struct HomeCustomizeSheet: View {
    let settings: HomeSettings
    /// Ranking-Ebenen, die es für die Region des Nutzers gibt.
    var availableLevels: [RegionLevel] = RegionLevel.allCases

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(settings.modules) { module in
                        ModuleRow(module: module, settings: settings, availableLevels: availableLevels)
                            .deleteDisabled(!module.kind.isRemovable)
                    }
                    .onMove { source, destination in
                        settings.moveModules(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { settings.modules[$0].id }
                        for id in ids {
                            settings.remove(id)
                        }
                    }
                } header: {
                    Text("Deine Module")
                } footer: {
                    Text("Ziehe Module in die gewünschte Reihenfolge, wähle die Größe über das Menü und entferne Module "
                        + "mit dem Minus-Zeichen. „Deine Schritte heute“ bleibt immer erhalten.")
                }

                if !settings.addableKinds.isEmpty {
                    Section("Modul hinzufügen") {
                        ForEach(settings.addableKinds) { kind in
                            Button {
                                settings.add(kind)
                            } label: {
                                HStack(spacing: PaceSpacing.s) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(PaceColor.accent)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(kind.title)
                                            .foregroundStyle(PaceColor.textPrimary)
                                        Text(kind.summary)
                                            .font(PaceFont.caption)
                                            .foregroundStyle(PaceColor.textSecondary)
                                    }
                                }
                            }
                            .accessibilityLabel("\(kind.title) hinzufügen")
                        }
                    }
                }

                Section {
                    Button("Standard wiederherstellen") {
                        settings.resetLayout()
                    }
                    .foregroundStyle(PaceColor.accent)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Home anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Eine Zeile in „Deine Module“: Symbol, Name, aktuelle Größe/Ebene und ein Menü zum Ändern.
private struct ModuleRow: View {
    let module: HomeModule
    let settings: HomeSettings
    let availableLevels: [RegionLevel]

    /// Die Ebene, die das Modul tatsächlich zeigt (siehe `RegionalStandingsViewModel.effectiveLevel`).
    private var shownLevel: RegionLevel {
        RegionalStandingsViewModel.effectiveLevel(for: module.regionLevel ?? .municipality, available: availableLevels)
    }

    private var detailText: String {
        module.kind.usesRegionScope ? "\(module.size.title) · \(shownLevel.scopeTitle)" : module.detailText
    }

    var body: some View {
        HStack(spacing: PaceSpacing.s) {
            Image(systemName: module.kind.systemImage)
                .foregroundStyle(PaceColor.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.kind.title)
                    .foregroundStyle(PaceColor.textPrimary)
                Text(detailText)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
            }
            Spacer(minLength: PaceSpacing.xs)
            Menu {
                Picker("Größe", selection: sizeBinding) {
                    ForEach(module.kind.supportedSizes) { size in
                        Text(size.title).tag(size)
                    }
                }
                if module.kind.usesRegionScope {
                    Picker("Ebene", selection: levelBinding) {
                        ForEach(availableLevels, id: \.self) { level in
                            Text(level.scopeTitle).tag(level)
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("\(module.kind.title) einstellen")
        }
        .accessibilityElement(children: .contain)
    }

    private var sizeBinding: Binding<HomeModuleSize> {
        Binding(
            get: { module.size },
            set: { [settings, id = module.id] in settings.setSize($0, for: id) }
        )
    }

    private var levelBinding: Binding<RegionLevel> {
        let shown = shownLevel
        return Binding(
            get: { shown },
            set: { [settings, id = module.id] in settings.setRegionLevel($0, for: id) }
        )
    }
}

/// Mitteilungen. Überholungen und Einladungen folgen mit Freunden und Gruppen.
struct NotificationsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PaceStatusView(
                systemImage: "bell",
                title: "Noch keine Mitteilungen",
                message: "Hier erscheinen künftig Überholungen in deinen Rankings sowie Einladungen von Freunden und Gruppen."
            )
            .frame(maxHeight: .infinity)
            .paceScreenBackground()
            .navigationTitle("Mitteilungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
