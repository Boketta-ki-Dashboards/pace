import DesignSystem
import PaceCore
import SwiftUI

/// Tagesziel auswählen (lokal gespeichert). Von Home und Profil aus erreichbar.
public struct StepGoalSheet: View {
    private let goals: StepGoalSettings

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    public init(goals: StepGoalSettings) {
        self.goals = goals
        _selection = State(initialValue: goals.currentGoal)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: PaceSpacing.m) {
                Text("Wie viele Schritte möchtest du jeden Tag schaffen?")
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .multilineTextAlignment(.center)
                Picker("Tagesziel", selection: $selection) {
                    ForEach(StepGoalRules.options, id: \.self) { goal in
                        Text("\(goal.paceFormatted) Schritte").tag(goal)
                    }
                }
                .pickerStyle(.wheel)
                Text("Das neue Ziel gilt ab heute – vergangene Tage und deine Serie behalten ihr damaliges Ziel. "
                    + "Das Tagesziel ist nur für dich sichtbar und hat keinen Einfluss auf Rankings.")
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PaceSpacing.m)
            .navigationTitle("Tagesziel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        goals.setGoal(selection)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
