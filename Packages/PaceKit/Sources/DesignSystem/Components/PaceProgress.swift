import SwiftUI

/// Kreisförmiger Fortschritt mit Prozentangabe in der Mitte.
public struct PaceProgressRing: View {
    private let progress: Double
    private let label: String
    private let lineWidth: CGFloat

    /// - Parameter progress: 0…1; größere Werte werden als voller Ring dargestellt.
    public init(progress: Double, label: String, lineWidth: CGFloat = 12) {
        self.progress = progress
        self.label = label
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(PaceColor.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(PaceColor.accentStrong, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
            Text(label)
                .font(.system(.title3, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(lineWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// Waagerechter Fortschrittsbalken.
public struct PaceProgressBar: View {
    private let progress: Double
    private let height: CGFloat

    public init(progress: Double, height: CGFloat = 12) {
        self.progress = progress
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(PaceColor.track)
                Capsule()
                    .fill(PaceColor.accent)
                    .frame(width: max(height, proxy.size.width * min(max(progress, 0), 1)))
                    .opacity(progress > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.snappy, value: progress)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: PaceSpacing.l) {
        PaceProgressRing(progress: 0.84, label: "84%")
            .frame(width: 110, height: 110)
        PaceProgressBar(progress: 0.84)
    }
    .padding()
}
