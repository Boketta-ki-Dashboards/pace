import PaceCore
import SwiftUI

public extension View {
    /// Wischen durch Zeiträume wie beim Kalender-Paging: Finger nach rechts → vorheriger, nach links → nächster Tag,
    /// Woche oder Monat (Regeln siehe ``PaceSwipeNavigation``).
    ///
    /// Der Inhalt folgt dem Finger gedämpft; in eine Richtung ohne weiteren Zeitraum (z. B. nach heute) nur mit
    /// Widerstand. Beim Wechsel gleitet der neue Zeitraum von der passenden Seite herein. Senkrechtes Scrollen der Seite
    /// bleibt frei (die Geste läuft gleichzeitig mit der Scrollansicht und reagiert nur auf eindeutig waagerechte
    /// Bewegungen). Die Pfeile bzw. VoiceOver-Aktionen des Aufrufers bleiben der zugängliche Weg.
    func pacePeriodSwipe(
        canShowPrevious: Bool,
        canShowNext: Bool,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) -> some View {
        modifier(PacePeriodSwipeModifier(
            canShowPrevious: canShowPrevious,
            canShowNext: canShowNext,
            onPrevious: onPrevious,
            onNext: onNext
        ))
    }
}

private struct PacePeriodSwipeModifier: ViewModifier {
    let canShowPrevious: Bool
    let canShowNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    /// Fingerbewegung der laufenden Geste; setzt sich beim Ende oder Abbruch selbst zurück.
    @GestureState private var translation: CGSize = .zero
    /// Richtung, die zu Beginn einer Geste festgelegt wird (am Startpunkt erkannt, damit ein abgebrochener Vorgang
    /// keinen alten Zustand hinterlässt): Wer senkrecht zu scrollen beginnt, verschiebt nichts mehr waagerecht.
    @State private var gestureStart: (location: CGPoint, isHorizontal: Bool)?
    /// Rest-Verschiebung nach dem Loslassen (Zurückgleiten oder Hereingleiten des neuen Zeitraums).
    @State private var settleOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset + settleOffset)
            .simultaneousGesture(
                // Global gemessen, damit der Rand-Streifen der Zurück-Geste erkannt wird.
                DragGesture(minimumDistance: PaceSwipeNavigation.minimumDistance, coordinateSpace: .global)
                    .updating($translation) { value, state, _ in
                        state = value.translation
                    }
                    .onChanged { value in
                        if gestureStart?.location != value.startLocation {
                            // Vom linken Rand aus gehört die Bewegung der Zurück-Geste von iOS: nichts verschieben.
                            let isHorizontal = PaceSwipeNavigation.isHorizontal(value.translation)
                                && !PaceSwipeNavigation.belongsToBackSwipe(startX: value.startLocation.x)
                            gestureStart = (value.startLocation, isHorizontal)
                        }
                    }
                    .onEnded { value in finish(value) }
            )
    }

    private var isHorizontalGesture: Bool {
        gestureStart?.isHorizontal == true
    }

    private var dragOffset: CGFloat {
        guard isHorizontalGesture, !reduceMotion else { return 0 }
        return PaceSwipeNavigation.dragOffset(
            translation: translation,
            canShowPrevious: canShowPrevious,
            canShowNext: canShowNext
        )
    }

    private func finish(_ value: DragGesture.Value) {
        let wasHorizontal = gestureStart?.location == value.startLocation && gestureStart?.isHorizontal == true
        gestureStart = nil
        guard wasHorizontal else { return }
        let step = PaceSwipeNavigation.step(
            translation: value.translation,
            predictedEndTranslation: value.predictedEndTranslation,
            canShowPrevious: canShowPrevious,
            canShowNext: canShowNext
        )
        switch step {
        case .previous: onPrevious()
        case .next: onNext()
        case nil: break
        }
        guard !reduceMotion else { return }
        // Die Fingerbewegung fällt ohne Animation weg; dieselbe Stelle übernimmt die Rest-Verschiebung und gleitet
        // dann auf 0 – zurück (kein Wechsel) oder als neuer Zeitraum von der passenden Seite herein.
        let start = step.map { PaceSwipeNavigation.entryOffset(for: $0) } ?? PaceSwipeNavigation.dragOffset(
            translation: value.translation,
            canShowPrevious: canShowPrevious,
            canShowNext: canShowNext
        )
        guard start != 0 else { return }
        withTransaction(Transaction(animation: nil)) {
            settleOffset = start
        }
        // Ein Bild später (nach dem Zeichnen an der Startstelle) gleiten.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            withAnimation(.snappy(duration: 0.28)) {
                settleOffset = 0
            }
        }
    }
}
