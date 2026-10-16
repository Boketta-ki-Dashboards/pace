import DesignSystem
import SwiftUI

/// Home-Screen: verbindet das ViewModel mit der Darstellung und den Aktualisierungs-Auslösern.
public struct HomeView: View {
    private let viewModel: HomeViewModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    public init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            HomeContentView(
                state: viewModel.state,
                onRetry: { Task { await viewModel.retry() } },
                onOpenHealthApp: { openURL(HealthAppLink.url) }
            )
            .refreshable { [viewModel] in await viewModel.refresh() }
            .navigationTitle("Heute")
        }
        .task { [viewModel] in await viewModel.loadIfNeeded() }
        .task { [viewModel] in await viewModel.observeStepChanges() }
        .onChange(of: scenePhase) { _, newPhase in
            // Zurück aus dem Hintergrund oder aus den Einstellungen: Werte und Zugriff erneut prüfen.
            guard newPhase == .active else { return }
            Task { await viewModel.refresh() }
        }
    }
}

enum HealthAppLink {
    /// Öffnet die Health-App. Apple dokumentiert keinen direkten Link zu den Zugriffsrechten einer App.
    static let url = URL(string: "x-apple-health://")!
}
