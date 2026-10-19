import DesignSystem
import PaceCore
import SwiftUI

/// Chatliste mit Filter (Social-Hauptseite) – Vertrag; der Inhalt entsteht im Chat-Arbeitspaket.
public struct ChatListSection: View {
    private let viewModel: ChatListViewModel
    private let onOpen: (ChatTarget) -> Void

    public init(viewModel: ChatListViewModel, onOpen: @escaping (ChatTarget) -> Void) {
        self.viewModel = viewModel
        self.onOpen = onOpen
    }

    public var body: some View {
        EmptyView()
    }
}

/// Ein Chat (Referenzbild 5) – Vertrag; der Inhalt entsteht im Chat-Arbeitspaket.
public struct ChatView: View {
    private let viewModel: ChatViewModel
    private let onOpenProfile: (SocialProfile) -> Void

    public init(viewModel: ChatViewModel, onOpenProfile: @escaping (SocialProfile) -> Void) {
        self.viewModel = viewModel
        self.onOpenProfile = onOpenProfile
    }

    public var body: some View {
        PaceColor.background
            .ignoresSafeArea()
    }
}
