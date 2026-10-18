import DesignSystem
import SwiftUI

/// „Anpassen“: Bereiche des Dashboards ein-/ausblenden und umsortieren.
struct HomeCustomizeSheet: View {
    let settings: HomeSettings

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(settings.sections) { setting in
                        HStack(spacing: PaceSpacing.s) {
                            Image(systemName: setting.section.systemImage)
                                .foregroundStyle(PaceColor.accent)
                                .frame(width: 28)
                            Text(setting.section.title)
                                .foregroundStyle(PaceColor.textPrimary)
                            Spacer()
                            Toggle(setting.section.title, isOn: visibility(of: setting.section))
                                .labelsHidden()
                                .tint(PaceColor.accentStrong)
                                .disabled(!setting.section.canBeHidden)
                        }
                    }
                    .onMove { source, destination in
                        settings.moveSections(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    Text("Bereiche")
                } footer: {
                    Text("Ziehe Bereiche in die gewünschte Reihenfolge. „Deine Schritte heute“ bleibt immer sichtbar.")
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

    private func visibility(of section: HomeSection) -> Binding<Bool> {
        Binding(
            get: { settings.sections.first { $0.section == section }?.isVisible ?? true },
            set: { settings.setVisible($0, for: section) }
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
