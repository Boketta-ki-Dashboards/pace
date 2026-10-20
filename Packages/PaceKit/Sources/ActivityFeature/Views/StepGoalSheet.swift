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
                Text(PaceLocalization.text(
                    de: "Wie viele Schritte möchtest du jeden Tag schaffen?",
                    en: "How many steps do you want to reach every day?",
                    ru: "Сколько шагов ты хочешь проходить каждый день?"
                ))
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .multilineTextAlignment(.center)
                Picker(Self.title, selection: $selection) {
                    ForEach(StepGoalRules.options, id: \.self) { goal in
                        Text(PaceLocalization.steps(goal)).tag(goal)
                    }
                }
                .pickerStyle(.wheel)
                Text(PaceLocalization.text(
                    de: "Das neue Ziel gilt ab heute – vergangene Tage und deine Serie behalten ihr damaliges Ziel. "
                        + "Das Tagesziel ist nur für dich sichtbar und hat keinen Einfluss auf Rankings.",
                    en: "The new goal applies from today – past days and your streak keep the goal they had back then. "
                        + "Your daily goal is only visible to you and doesn't affect rankings.",
                    ru: "Новая цель действует с сегодняшнего дня – прошлые дни и твоя серия сохраняют прежнюю цель. "
                        + "Цель на день видна только тебе и не влияет на рейтинги."
                ))
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PaceSpacing.m)
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PaceLocalization.text(de: "Abbrechen", en: "Cancel", ru: "Отмена")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(PaceLocalization.text(de: "Sichern", en: "Save", ru: "Сохранить")) {
                        goals.setGoal(selection)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static var title: String {
        PaceLocalization.text(de: "Tagesziel", en: "Daily goal", ru: "Цель на день")
    }
}
