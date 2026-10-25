import SwiftUI

/// Kopf der Startseite eines Haupttabs: Wortmarke mit optionalen Aktionen, darunter der Titel.
///
/// Alle vier Tabs teilen dieselben Maße (Abstand oben, Zeilenhöhen, Schrift). So stehen Wortmarke und Titel beim
/// Wischen zwischen den Tabs auf derselben Höhe und springen nicht – egal ob rechts Aktionen stehen oder nicht.
public struct PaceRootHeader<Trailing: View, TitleRow: View>: View {
    /// Höhe der Wortmark-Zeile und Mindesthöhe der Titelzeile (Tippfläche der Aktionen).
    public static var rowHeight: CGFloat { 44 }

    private let trailing: Trailing
    private let titleRow: TitleRow

    /// - Parameters:
    ///   - trailing: Aktionen rechts neben der Wortmarke (z. B. Einstellungen).
    ///   - titleRow: Titelzeile, z. B. Begrüßung mit Symbolen; für einen einfachen Titel ``init(title:trailing:)``.
    public init(@ViewBuilder trailing: () -> Trailing, @ViewBuilder titleRow: () -> TitleRow) {
        self.trailing = trailing()
        self.titleRow = titleRow()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: PaceSpacing.xs) {
                PaceWordmark(height: 33)
                Spacer(minLength: PaceSpacing.s)
                trailing
            }
            .frame(minHeight: Self.rowHeight)
            titleRow
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
        }
        .padding(.top, PaceSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension PaceRootHeader where TitleRow == PaceRootHeaderTitle {
    /// Kopf mit einfachem Titel, z. B. „Rankings“.
    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.init(trailing: trailing) { PaceRootHeaderTitle(title) }
    }
}

public extension PaceRootHeader where TitleRow == PaceRootHeaderTitle, Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Titel der Startseite eines Tabs (groß, fett, Überschrift für VoiceOver).
public struct PaceRootHeaderTitle: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.system(.title, weight: .bold))
            .foregroundStyle(PaceColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }
}
