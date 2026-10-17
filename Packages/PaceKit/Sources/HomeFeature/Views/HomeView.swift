import ActivityFeature
import DesignSystem
import SwiftUI
import UIKit

/// Home-Screen: verbindet das ViewModel mit der Darstellung und den Aktualisierungs-Auslösern.
public struct HomeView: View {
    private let viewModel: HomeViewModel
    private let formatter: ActivityFormatter

    @Environment(\.scenePhase) private var scenePhase

    public init(viewModel: HomeViewModel, formatter: ActivityFormatter = ActivityFormatter()) {
        self.viewModel = viewModel
        self.formatter = formatter
    }

    public var body: some View {
        NavigationStack {
            HomeContentView(
                state: viewModel.state,
                manualStepsNote: viewModel.manualStepsNote,
                formatter: formatter,
                onRetry: { Task { await viewModel.retry() } }
            ) {
                ActivityDetailsView(source: viewModel, formatter: formatter)
            }
            .refreshable { [viewModel] in await viewModel.refresh() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PaceWordmark()
                }
            }
        }
        .task { [viewModel] in await viewModel.loadIfNeeded() }
        .task { [viewModel] in await viewModel.observeActivityChanges() }
        .onChange(of: scenePhase) { _, newPhase in
            // Zurück aus dem Hintergrund oder aus den Einstellungen: Werte und Zugriff erneut prüfen.
            guard newPhase == .active else { return }
            Task { await viewModel.refresh(trigger: .foreground) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // Mitternacht, Zeitzonen- oder Sommerzeitwechsel: „Heute“ und die letzten 7 Tage neu bestimmen.
            Task { await viewModel.refresh(trigger: .foreground) }
        }
    }
}
