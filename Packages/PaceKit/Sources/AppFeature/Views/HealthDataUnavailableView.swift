import DesignSystem
import SwiftUI

/// Wird gezeigt, wenn das Gerät keine Health-Daten unterstützt.
struct HealthDataUnavailableView: View {
    var body: some View {
        PaceStatusView(
            systemImage: "heart.slash",
            title: "Apple Health nicht verfügbar",
            message: "Pace benötigt Apple Health, um deine Schritte zu lesen. Auf diesem Gerät ist Apple Health nicht verfügbar.",
            tint: PaceColor.textSecondary
        )
        .frame(maxHeight: .infinity)
        .paceScreenBackground()
    }
}

#Preview {
    HealthDataUnavailableView()
}
