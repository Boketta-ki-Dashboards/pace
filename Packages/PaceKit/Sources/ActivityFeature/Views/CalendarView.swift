import DesignSystem
import PaceCore
import SwiftUI

/// Kalender (Referenzbild 9) – Vertrag für die Navigation aus Home; der Inhalt entsteht im Kalender-Arbeitspaket.
public struct CalendarView: View {
    private let viewModel: CalendarViewModel

    public init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        PaceColor.background
            .ignoresSafeArea()
    }
}
