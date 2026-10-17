import SwiftUI
import UIKit

/// Abstand der zusätzlichen Abfrage im Vordergrund. Der HealthKit-Observer meldet neue Samples sofort; die Abfrage
/// fängt verzögert oder gebündelt zugestellte Meldungen ab. Sie liest nur lokal aus Apple Health (kein Netzwerk).
let foregroundRefreshInterval: Duration = .seconds(15)

public extension View {
    /// Hält die Bewegungsdaten aktuell, solange die Main App sichtbar ist – unabhängig davon, welcher Tab gewählt ist:
    /// erstes Laden, HealthKit-Updates, Rückkehr in den Vordergrund, Tages- bzw. Zeitzonenwechsel und eine kurze
    /// lokale Abfrage alle 15 Sekunden im Vordergrund.
    func activityUpdates(_ viewModel: HomeViewModel) -> some View {
        modifier(ActivityUpdatesModifier(viewModel: viewModel))
    }
}

private struct ActivityUpdatesModifier: ViewModifier {
    let viewModel: HomeViewModel

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { [viewModel] in await viewModel.loadIfNeeded() }
            .task { [viewModel] in await viewModel.observeActivityChanges() }
            .task(id: scenePhase) { [viewModel, scenePhase] in
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: foregroundRefreshInterval)
                    guard !Task.isCancelled else { return }
                    await viewModel.refresh(trigger: .healthKitUpdate)
                }
            }
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
