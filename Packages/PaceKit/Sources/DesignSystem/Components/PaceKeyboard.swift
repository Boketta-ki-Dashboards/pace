import SwiftUI
import UIKit

public extension View {
    /// Meldet, ob die Bildschirmtastatur ein- oder ausgeblendet wird – zu Beginn ihrer Animation, damit sich das
    /// Layout gleichzeitig mit der Tastatur bewegt.
    func onKeyboardVisibilityChange(perform action: @escaping (_ isVisible: Bool) -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            action(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            action(false)
        }
    }
}
