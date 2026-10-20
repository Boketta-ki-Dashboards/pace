import DesignSystem
import Foundation
import PaceCore
import SwiftUI
import UniformTypeIdentifiers

/// Ein Widget auf Home – im Anpassen-Modus mit X zum Entfernen, Größenmenü, mint Rahmen für das aktive Widget,
/// dezentem Wackeln und Drag & Drop zum Umsortieren.
struct HomeEditableModule: View {
    let module: HomeModule
    let viewModel: HomeDashboardViewModel
    let onEdit: (HomeModule.ID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if viewModel.isEditing {
            editing
        } else {
            HomeModuleView(module: module, viewModel: viewModel, mode: .normal)
        }
    }

    private var isMenuOpen: Bool {
        viewModel.sizeMenuModuleID == module.id
    }

    private var isActive: Bool {
        isMenuOpen || viewModel.activeModuleID == module.id || viewModel.draggingModuleID == module.id
    }

    private var editing: some View {
        HomeModuleView(module: module, viewModel: viewModel, mode: .editing) {
            // Ein offenes Größenmenü schließt zuerst; sonst öffnet Antippen die Galerie zum Bearbeiten.
            viewModel.endDragging()
            if viewModel.sizeMenuModuleID != nil {
                viewModel.sizeMenuModuleID = nil
            } else {
                onEdit(module.id)
            }
        }
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous)
                    .strokeBorder(PaceColor.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if module.kind.isRemovable {
                removeButton
            }
        }
        .modifier(HomeWiggleModifier(isActive: !isMenuOpen && viewModel.draggingModuleID != module.id, seed: wiggleSeed))
        .overlay(alignment: .topTrailing) {
            if isMenuOpen {
                HomeSizeMenu(sizes: module.kind.supportedSizes, selected: module.size) { size in
                    withAnimation(reduceMotion ? nil : .snappy) {
                        viewModel.setSize(size, for: module.id)
                    }
                }
                .padding(.top, 54)
                .padding(.trailing, 30)
                .transition(.opacity)
            }
        }
        .opacity(viewModel.draggingModuleID == module.id ? 0.55 : 1)
        .onDrag {
            viewModel.sizeMenuModuleID = nil
            viewModel.draggingModuleID = module.id
            return NSItemProvider(object: module.id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: HomeModuleDropDelegate(targetID: module.id, viewModel: viewModel, animation: reduceMotion ? nil : .snappy)
        )
    }

    private var removeButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy) {
                viewModel.remove(module.id)
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PaceColor.textPrimary)
                .frame(width: 30, height: 30)
                .background(PaceColor.surfaceSecondary, in: Circle())
                .overlay(Circle().strokeBorder(PaceColor.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: -12, y: -12)
        .accessibilityLabel(HomeTexts.remove(viewModel.title(for: module)))
    }

    /// Unterschiedliche Taktung je Widget, damit nicht alle im Gleichschritt wackeln.
    private var wiggleSeed: Int {
        module.id.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 997 }
    }
}

/// Dezentes Wackeln im Anpassen-Modus (wie auf dem iPhone-Homescreen) – bei reduzierter Bewegung aus.
struct HomeWiggleModifier: ViewModifier {
    let isActive: Bool
    let seed: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    func body(content: Content) -> some View {
        let isEnabled = isActive && !reduceMotion
        content
            .rotationEffect(.degrees(isEnabled ? (phase ? angle : -angle) : 0))
            .animation(
                isEnabled ? .easeInOut(duration: duration).repeatForever(autoreverses: true) : .easeOut(duration: 0.15),
                value: phase
            )
            .onAppear {
                phase = isEnabled
            }
            .onChange(of: isEnabled) { _, newValue in
                phase = newValue
            }
    }

    private var angle: Double {
        0.45
    }

    private var duration: Double {
        0.14 + Double(seed % 4) * 0.015
    }
}

/// Menü „Größe auswählen“: Klein, Mittel, Groß, Max – die aktuelle Größe ist markiert. Nur unterstützte Größen.
struct HomeSizeMenu: View {
    let sizes: [HomeModuleSize]
    let selected: HomeModuleSize
    let onSelect: (HomeModuleSize) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(sizes) { size in
                Button {
                    onSelect(size)
                } label: {
                    HStack(spacing: PaceSpacing.s) {
                        Text(size.title)
                            .font(.subheadline.weight(size == selected ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer(minLength: PaceSpacing.s)
                        if size == selected {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.bold))
                        }
                    }
                    .foregroundStyle(size == selected ? PaceColor.onSelection : PaceColor.textPrimary)
                    .padding(.horizontal, PaceSpacing.s)
                    .frame(minHeight: 40)
                    .background(
                        size == selected ? PaceColor.selectionFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(size == selected ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(width: 200)
        .background(PaceColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PaceColor.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

/// Symbol für „Größe auswählen“ wie im Anpassen-Design: großes Quadrat mit offener Ecke oben rechts, darüber ein
/// kleines, versetztes Quadrat. Gezeichnet in der Vordergrundfarbe, wächst mit der Schriftgröße.
struct HomeSizeGlyph: View {
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 15

    var body: some View {
        Path { path in
            let side = size
            let radius = side * 0.16
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * side, y: y * side)
            }
            // Großes Quadrat, oben rechts offen.
            path.move(to: point(0.36, 0.08))
            path.addArc(tangent1End: point(0, 0.08), tangent2End: point(0, 1), radius: radius)
            path.addArc(tangent1End: point(0, 1), tangent2End: point(0.92, 1), radius: radius)
            path.addArc(tangent1End: point(0.92, 1), tangent2End: point(0.92, 0.6), radius: radius)
            path.addLine(to: point(0.92, 0.6))
            // Kleines Quadrat oben rechts, unten links offen.
            path.move(to: point(0.48, 0.18))
            path.addArc(tangent1End: point(0.48, 0), tangent2End: point(1, 0), radius: radius * 0.6)
            path.addArc(tangent1End: point(1, 0), tangent2End: point(1, 0.48), radius: radius * 0.6)
            path.addArc(tangent1End: point(1, 0.48), tangent2End: point(0.74, 0.48), radius: radius * 0.6)
            path.addLine(to: point(0.74, 0.48))
        }
        .stroke(style: StrokeStyle(lineWidth: max(1.4, size / 10), lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Ziel beim Umsortieren: Sobald ein gezogenes Widget über einem anderen schwebt, tauschen sie die Plätze – die
/// Reihenfolge ist sofort sichtbar und gespeichert.
struct HomeModuleDropDelegate: DropDelegate {
    let targetID: HomeModule.ID
    let viewModel: HomeDashboardViewModel
    let animation: Animation?

    /// Nur Widgets von Home – kein Text aus anderen Apps.
    func validateDrop(info: DropInfo) -> Bool {
        viewModel.draggingModuleID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let dragging = viewModel.draggingModuleID, dragging != targetID else { return }
        withAnimation(animation) {
            viewModel.moveDragged(to: targetID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.endDragging()
        return true
    }
}

/// Ablage außerhalb eines Widgets (Kopf, Zwischenräume): beendet das Ziehen, damit kein Widget halb durchsichtig
/// zurückbleibt.
struct HomeDragEndDropDelegate: DropDelegate {
    let viewModel: HomeDashboardViewModel

    func validateDrop(info: DropInfo) -> Bool {
        viewModel.draggingModuleID != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.endDragging()
        return true
    }
}

/// Mint Pille für „Fertig“ und „+ Widget hinzufügen“ im Anpassen-Modus.
struct HomePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, weight: .semibold))
            .foregroundStyle(PaceColor.onSelection)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, PaceSpacing.m)
            .frame(minHeight: 44)
            .background(PaceColor.selectionFill, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
