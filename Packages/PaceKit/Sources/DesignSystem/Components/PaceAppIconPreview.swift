import SwiftUI

/// Verkleinerte Darstellung eines App-Icons für die Icon-Auswahl. Die Bilder erzeugt Branding/generate_assets.py
/// aus denselben Quellen wie die echten App-Icons.
public struct PaceAppIconPreview: View {
    public enum Variant: Sendable {
        case light
        case dark
        /// Links hell, rechts dunkel – das Icon folgt der Darstellung des Systems.
        case automatic
    }

    private let variant: Variant
    private let size: CGFloat

    public init(_ variant: Variant, size: CGFloat = 60) {
        self.variant = variant
        self.size = size
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        content
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(PaceColor.border, lineWidth: 1))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .light:
            icon("AppIconPreviewLight")
        case .dark:
            icon("AppIconPreviewDark")
        case .automatic:
            ZStack {
                icon("AppIconPreviewLight")
                icon("AppIconPreviewDark")
                    .mask(HStack(spacing: 0) {
                        Color.clear
                        Color.black
                    })
            }
        }
    }

    private func icon(_ name: String) -> some View {
        Image(name, bundle: .module)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
    }
}

#Preview {
    HStack(spacing: PaceSpacing.m) {
        PaceAppIconPreview(.automatic)
        PaceAppIconPreview(.light)
        PaceAppIconPreview(.dark)
    }
    .padding()
}
