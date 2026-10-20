import DesignSystem
import PaceCore
import SwiftUI

/// Erklärt, wofür Pace Health-Zugriff braucht, und startet die System-Abfrage.
public struct HealthPermissionView: View {
    private let viewModel: HealthPermissionViewModel

    public init(viewModel: HealthPermissionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpacing.xl) {
                    header
                    VStack(alignment: .leading, spacing: PaceSpacing.l) {
                        HealthPermissionPoint(
                            systemImage: "figure.walk",
                            title: PaceLocalization.text(de: "Nur Bewegungsdaten", en: "Only activity data", ru: "Только данные об активности"),
                            text: PaceLocalization.text(
                                de: "Schritte, Distanz, aktive Kalorien, Stockwerke und Trainingsminuten. Kein Schlaf, keine medizinischen Daten. "
                                    + "Puls fragt Pace nur, wenn du ihn später in den Tagesdetails ausdrücklich anzeigen möchtest.",
                                en: "Steps, distance, active calories, floors and exercise minutes. No sleep, no medical data. "
                                    + "Pace only asks for heart rate if you later choose to show it in the day details.",
                                ru: "Шаги, дистанция, активные калории, этажи и минуты тренировки. Без сна и медицинских данных. "
                                    + "Пульс Pace запросит, только если ты сам захочешь показать его в подробностях дня."
                            )
                        )
                        HealthPermissionPoint(
                            systemImage: "trophy.fill",
                            title: PaceLocalization.text(
                                de: "Nur Schritte zählen für Rankings",
                                en: "Only steps count for rankings",
                                ru: "В рейтингах учитываются только шаги"
                            ),
                            text: PaceLocalization.text(
                                de: "Geteilt wird ausschließlich deine tägliche Schrittzahl. Alle anderen Werte bleiben auf deinem iPhone.",
                                en: "Only your daily step count is shared. All other values stay on your iPhone.",
                                ru: "Передаётся только твоё количество шагов за день. Все остальные данные остаются на твоём iPhone."
                            )
                        )
                        HealthPermissionPoint(
                            systemImage: "lock.fill",
                            title: PaceLocalization.text(de: "Nur lesen", en: "Read only", ru: "Только чтение"),
                            text: PaceLocalization.text(
                                de: "Pace schreibt keine Daten in Apple Health.",
                                en: "Pace doesn't write any data to Apple Health.",
                                ru: "Pace ничего не записывает в Apple Health."
                            )
                        )
                        HealthPermissionPoint(
                            systemImage: "location.slash",
                            title: PaceLocalization.text(de: "Kein Standort nötig", en: "No location needed", ru: "Геопозиция не нужна"),
                            text: PaceLocalization.text(
                                de: "Für Schritte und Rankings brauchst du keine Standortfreigabe.",
                                en: "You don't need to share your location for steps and rankings.",
                                ru: "Для шагов и рейтингов не нужен доступ к геопозиции."
                            )
                        )
                        HealthPermissionPoint(
                            systemImage: "hand.raised.fill",
                            title: PaceLocalization.text(de: "Du behältst die Kontrolle", en: "You stay in control", ru: "Всё под твоим контролем"),
                            text: PaceLocalization.text(
                                de: "Du kannst den Zugriff jederzeit in der Health-App ändern.",
                                en: "You can change access in the Health app at any time.",
                                ru: "Доступ можно в любой момент изменить в приложении «Здоровье»."
                            )
                        )
                    }
                }
                .padding(PaceSpacing.l)
                .padding(.top, PaceSpacing.xl)
            }

            footer
        }
        .paceScreenBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.m) {
            PaceWordmark(height: 34)
                .padding(.bottom, PaceSpacing.xs)

            Image(systemName: "figure.walk")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(PaceColor.onAccent)
                .frame(width: 72, height: 72)
                .background(PaceColor.accentStrong, in: RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous))
                .accessibilityHidden(true)

            Text(PaceLocalization.text(de: "Deine Schritte zählen", en: "Your steps count", ru: "Твои шаги важны"))
                .font(PaceFont.largeTitle)
                .foregroundStyle(PaceColor.textPrimary)

            Text(PaceLocalization.text(
                de: "Verbinde Pace mit Apple Health, damit wir deine Bewegung von heute anzeigen können.",
                en: "Connect Pace to Apple Health so we can show today's activity.",
                ru: "Подключи Pace к Apple Health, чтобы видеть свою активность за сегодня."
            ))
                .font(PaceFont.body)
                .foregroundStyle(PaceColor.textSecondary)
        }
    }

    private var footer: some View {
        VStack(spacing: PaceSpacing.s) {
            if case .failed(let message) = viewModel.state {
                Text(message)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await viewModel.requestAccess() }
            } label: {
                if viewModel.isRequesting {
                    ProgressView()
                        .tint(PaceColor.onAccent)
                } else {
                    Text(PaceLocalization.text(de: "Mit Apple Health verbinden", en: "Connect to Apple Health", ru: "Подключить Apple Health"))
                }
            }
            .buttonStyle(.pacePrimary)
            .disabled(viewModel.isRequesting)
        }
        .padding(PaceSpacing.l)
    }
}

private struct HealthPermissionPoint: View {
    let systemImage: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: PaceSpacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PaceColor.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
                Text(title)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                Text(text)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
