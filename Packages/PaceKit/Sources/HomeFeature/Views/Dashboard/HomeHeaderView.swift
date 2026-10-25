import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

/// Kopf von Home: Wortmarke und „Anpassen“, Begrüßung mit Kalender und Mitteilungen.
///
/// Im Anpassen-Modus ersetzen „Fertig“ und „+ Widget hinzufügen“ die normalen Aktionen, darunter steht der Hinweis
/// zum Verschieben.
struct HomeHeaderView: View {
    let viewModel: HomeDashboardViewModel
    let onAddWidget: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            // Gleiche Maße wie Rankings, Social und Profil: Wortmarke und Titel springen beim Tabwechsel nicht.
            PaceRootHeader {
                if viewModel.isEditing {
                    Button(HomeTexts.done) {
                        viewModel.endEditing()
                    }
                    .buttonStyle(HomePillButtonStyle())
                } else {
                    Button {
                        viewModel.beginEditing()
                    } label: {
                        Label(HomeTexts.customize, systemImage: "slider.horizontal.3")
                            .lineLimit(1)
                    }
                    .buttonStyle(.paceCompact)
                    .accessibilityHint(PaceLocalization.text(
                        de: "Widgets entfernen, verschieben und in der Größe ändern",
                        en: "Remove, move and resize widgets",
                        ru: "Удалять, перемещать и менять размер виджетов"
                    ))
                }
            } titleRow: {
                if viewModel.isEditing {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: PaceSpacing.xs) {
                            greeting.fixedSize()
                            Spacer(minLength: PaceSpacing.xs)
                            addButton.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                            greeting
                            addButton
                        }
                    }
                } else {
                    greetingRow
                }
            }

            if viewModel.isEditing {
                HStack(spacing: PaceSpacing.s) {
                    HomeDragHandle()
                    Text(HomeTexts.editHint)
                        .font(.subheadline)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, PaceSpacing.xxs)
                .padding(.bottom, PaceSpacing.xs)
            }
        }
    }

    private var greetingRow: some View {
        HStack(alignment: .center, spacing: PaceSpacing.xxs) {
            greeting
            Spacer(minLength: PaceSpacing.xs)
            NavigationLink(value: HomeRoute.calendar(CalendarRoute())) {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(PaceColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .accessibilityLabel(HomeTexts.calendar)
            NavigationLink(value: HomeRoute.notifications) {
                Image(systemName: "bell")
                    .font(.title2)
                    .foregroundStyle(PaceColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        if viewModel.notificationCount > 0 {
                            HomeBellBadge(count: viewModel.notificationCount)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pacePressable)
            .accessibilityLabel(HomeNotifications.bellAccessibilityLabel(count: viewModel.notificationCount))
        }
    }

    private var greeting: some View {
        Text(viewModel.greeting)
            .font(.system(.title, weight: .bold))
            .foregroundStyle(PaceColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }

    private var addButton: some View {
        Button(action: onAddWidget) {
            Label(HomeTexts.addWidget, systemImage: "plus")
        }
        .buttonStyle(HomePillButtonStyle())
    }
}

/// Zähler am Glocken-Symbol.
private struct HomeBellBadge: View {
    let count: Int

    var body: some View {
        Text(count > 9 ? "9+" : count.paceFormatted)
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(PaceColor.onAccent)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(PaceColor.actionFill, in: Capsule())
            .overlay(Capsule().strokeBorder(PaceColor.background, lineWidth: 1.5))
            .offset(x: 2, y: 4)
            .accessibilityHidden(true)
    }
}
