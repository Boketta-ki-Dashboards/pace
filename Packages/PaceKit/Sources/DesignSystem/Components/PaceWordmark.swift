import SwiftUI

/// Schriftzug „PACE“ für Navigationsleisten und Header.
public struct PaceWordmark: View {
    public init() {}

    public var body: some View {
        Text("PACE")
            .font(.system(.headline, design: .rounded, weight: .black))
            .tracking(3)
            .foregroundStyle(PaceColor.accent)
            .accessibilityLabel("Pace")
    }
}

#Preview {
    PaceWordmark()
}
