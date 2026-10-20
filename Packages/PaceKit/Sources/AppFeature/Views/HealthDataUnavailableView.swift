import DesignSystem
import PaceCore
import SwiftUI

/// Wird gezeigt, wenn das Gerät keine Health-Daten unterstützt.
struct HealthDataUnavailableView: View {
    var body: some View {
        PaceStatusView(
            systemImage: "heart.slash",
            title: PaceLocalization.text(
                de: "Apple Health nicht verfügbar",
                en: "Apple Health not available",
                ru: "Apple Health недоступно"
            ),
            message: PaceLocalization.text(
                de: "Pace benötigt Apple Health, um deine Schritte zu lesen. Auf diesem Gerät ist Apple Health nicht verfügbar.",
                en: "Pace needs Apple Health to read your steps. Apple Health isn't available on this device.",
                ru: "Pace нужно приложение «Здоровье», чтобы считывать шаги. На этом устройстве оно недоступно."
            ),
            tint: PaceColor.textSecondary
        )
        .frame(maxHeight: .infinity)
        .paceScreenBackground()
    }
}

#Preview {
    HealthDataUnavailableView()
}
