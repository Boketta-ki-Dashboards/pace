import SwiftUI

/// Flamme der persönlichen Serie: kräftig, wenn die Serie läuft; dezent pulsierend, solange das Tagesziel heute noch
/// offen ist (nicht bei „Bewegung reduzieren“).
public struct PaceStreakFlame: View {
    private let isActive: Bool
    private let isTodayReached: Bool
    private let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isActive: Bool, isTodayReached: Bool, size: CGFloat = 44) {
        self.isActive = isActive
        self.isTodayReached = isTodayReached
        self.size = size
    }

    public var body: some View {
        Image(systemName: isActive ? "flame.fill" : "flame")
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(isActive ? PaceColor.streak : PaceColor.textSecondary)
            .symbolEffect(.pulse, options: .repeating, isActive: isActive && !isTodayReached && !reduceMotion)
            .frame(width: size, height: size)
            .background((isActive ? PaceColor.streak : PaceColor.textSecondary).opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: PaceSpacing.l) {
        PaceStreakFlame(isActive: true, isTodayReached: true)
        PaceStreakFlame(isActive: true, isTodayReached: false)
        PaceStreakFlame(isActive: false, isTodayReached: false)
    }
    .padding()
}
