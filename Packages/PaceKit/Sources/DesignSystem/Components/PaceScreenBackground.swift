import SwiftUI

public extension View {
    /// Standard-Hintergrund für ganze Screens.
    func paceScreenBackground() -> some View {
        background(PaceColor.background.ignoresSafeArea())
    }
}
