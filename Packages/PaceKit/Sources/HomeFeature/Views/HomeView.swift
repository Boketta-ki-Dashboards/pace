import ActivityFeature
import DesignSystem
import SwiftUI

/// Home-Screen: verbindet das ViewModel mit der Darstellung. Die Aktualisierungs-Auslöser hängen an der ganzen
/// Main App (`activityUpdates(_:)`), damit sie auch laufen, während ein anderer Tab offen ist.
public struct HomeView: View {
    private let viewModel: HomeViewModel
    private let formatter: ActivityFormatter

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
    }
}
