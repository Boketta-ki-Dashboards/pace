import PaceCore
import SwiftUI
import UIKit

/// Rundes Profilbild: das hochgeladene Foto oder – solange keins da ist – Initialen. Der Farbton der Initialen ergibt
/// sich stabil aus `seed`, damit dieselbe Person immer gleich aussieht.
public struct PaceAvatar: View {
    private let initials: String
    private let seed: String
    private let size: CGFloat
    private let isHighlighted: Bool
    private let image: MediaReference?

    @Environment(\.paceImageLoader) private var loader
    @State private var photo: UIImage?

    /// - Parameters:
    ///   - name: Anzeigename; daraus werden bis zu zwei Initialen gebildet.
    ///   - seed: Stabiler Wert für die Farbe, z. B. die öffentliche Nutzer-ID.
    ///   - image: Profil- oder Gruppenbild aus Storage.
    public init(name: String, seed: String, size: CGFloat = 40, isHighlighted: Bool = false, image: MediaReference? = nil) {
        initials = Self.initials(of: name)
        self.seed = seed
        self.size = size
        self.isHighlighted = isHighlighted
        self.image = image
    }

    public var body: some View {
        let tone = Self.tones[Self.toneIndex(for: seed)]
        ZStack {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(isHighlighted ? PaceColor.onAccent : tone.foreground)
                    .frame(width: size, height: size)
                    .background(isHighlighted ? PaceColor.accentStrong : tone.background, in: Circle())
            }
        }
        .overlay(Circle().strokeBorder(isHighlighted ? PaceColor.accent : PaceColor.border, lineWidth: isHighlighted && photo != nil ? 2 : (isHighlighted ? 0 : 1)))
        .accessibilityHidden(true)
        .task(id: image) {
            guard let image, let loader else {
                photo = nil
                return
            }
            if let cached = loader.cachedImage(for: image) {
                photo = cached
            } else {
                photo = await loader.image(for: image)
            }
        }
    }

    static func initials(of name: String) -> String {
        let letters = name
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// Stabil über App-Starts hinweg (kein `hashValue`, das pro Prozess zufällig ist).
    static func toneIndex(for seed: String) -> Int {
        let sum = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return sum % tones.count
    }

    private struct Tone {
        let background: Color
        let foreground: Color
    }

    private static let tones: [Tone] = [
        Tone(background: Color(light: 0xDDF3E4, dark: 0x1E3A2F), foreground: Color(light: 0x0A4A31, dark: 0xBDF8D2)),
        Tone(background: Color(light: 0xE3ECF7, dark: 0x1F2D3D), foreground: Color(light: 0x24456E, dark: 0xB9D3F2)),
        Tone(background: Color(light: 0xF4E9DC, dark: 0x3A2E22), foreground: Color(light: 0x7A4A16, dark: 0xF2D3AE)),
        Tone(background: Color(light: 0xEDE4F5, dark: 0x30263D), foreground: Color(light: 0x5A3480, dark: 0xD9C2F2)),
        Tone(background: Color(light: 0xE0F1F2, dark: 0x1D3638), foreground: Color(light: 0x1C5E63, dark: 0xB3E9EC)),
    ]
}

#Preview {
    HStack {
        PaceAvatar(name: "Leon Becker", seed: "a")
        PaceAvatar(name: "Niklas", seed: "b", isHighlighted: true)
        PaceAvatar(name: "Flavio", seed: "c", size: 56)
    }
    .padding()
}
