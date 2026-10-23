import DesignSystem
import Foundation
import PaceCore
import SwiftUI

/// Ein Widget auf Home – im Anpassen-Modus mit X zum Entfernen, Größenmenü, mint Rahmen für das aktive Widget,
/// dezentem Wackeln und Umsortieren am Ziehgriff (``HomeReorderController``).
struct HomeEditableModule: View {
    let module: HomeModule
    let viewModel: HomeDashboardViewModel
    let onEdit: (HomeModule.ID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(HomeReorderController.self) private var reorder: HomeReorderController?

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
        isMenuOpen || viewModel.activeModuleID == module.id || isDragged
    }

    private var isDragged: Bool {
        viewModel.draggingModuleID == module.id
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
        // Layout-Rahmen im Scroll-Inhalt – vor Verschiebung und Skalierung gemessen.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(HomeReorderController.contentSpace))
        } action: { [reorder, id = module.id] frame in
            reorder?.reportFrame(frame, for: id)
        }
        .scaleEffect(isDragged && !reduceMotion ? 1.03 : 1)
        .shadow(color: .black.opacity(isDragged ? 0.22 : 0), radius: isDragged ? 18 : 0, y: isDragged ? 8 : 0)
        .offset(y: reorder?.offset(for: module.id) ?? 0)
        // Das gezogene Widget folgt dem Finger ohne Verzögerung; die anderen gleiten animiert an ihren neuen Platz.
        .transaction { [isDragged] transaction in
            if isDragged { transaction.animation = nil }
        }
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
