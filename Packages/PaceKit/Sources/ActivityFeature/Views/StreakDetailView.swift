import DesignSystem
import PaceCore
import SwiftUI

/// Persönliche Flamme (aus dem Flammen-Widget auf Home): aktuelle Serie, Rekord, Beginn, letzter erfolgreicher Tag,
/// Flammenkalender mit Tagesdetails, frühere Serien und die Regel. Führt nie zu einer Gruppe oder einem Chat.
public struct StreakDetailView: View {
    @State private var viewModel: StreakDetailViewModel
    private let backTitle: String

    public init(viewModel: StreakDetailViewModel, backTitle: String) {
        _viewModel = State(initialValue: viewModel)
        self.backTitle = backTitle
    }

    public var body: some View {
        ScrollView {
            StreakDetailContent(
                content: viewModel.content,
                backTitle: backTitle,
                onSelect: { viewModel.select($0) },
                onPreviousMonth: { viewModel.showPreviousMonth() },
                onNextMonth: { viewModel.showNextMonth() }
            )
            .padding(.horizontal, PaceSpacing.m)
            .padding(.bottom, PaceSpacing.l)
        }
        .scrollIndicators(.hidden)
        .paceScreenBackground()
        .paceSubpage()
        .task { [viewModel] in await viewModel.load() }
        .onChange(of: viewModel.streak.record) { viewModel.streak.saveRecordIfNeeded() }
    }
}

/// Inhalt der Flammen-Seite inklusive Kopf (ohne Scrollen) – auch für Snapshots.
struct StreakDetailContent: View {
    let content: StreakDetailViewModel.Content
    let backTitle: String
    var onSelect: (LocalDate) -> Void = { _ in }
    var onPreviousMonth: () -> Void = {}
    var onNextMonth: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: StreakTexts.title)
                .padding(.bottom, PaceSpacing.xs)
            switch content {
            case .loading:
                PaceCard {
                    HStack(spacing: PaceSpacing.s) {
                        ProgressView()
                        Text(PaceLocalization.text(de: "Flamme wird berechnet …", en: "Calculating flame …", ru: "Считаем серию …"))
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .noReadAccess:
                PaceStatusView(systemImage: "flame", title: StreakTexts.title, message: ActivityTexts.noReadAccessMessage)
            case .failed(let message):
                PaceStatusView(systemImage: "exclamationmark.triangle", title: StreakTexts.title, message: message)
            case .report(let report):
                hero(report)
                facts(report)
                calendarCard(report)
                if let selected = report.selected {
                    selectedCard(selected)
                }
                pastRuns(report)
                explanation(report)
            }
        }
    }

    // MARK: Kopf

    private func hero(_ report: StreakDetailReport) -> some View {
        PaceCard {
            HStack(spacing: PaceSpacing.m) {
                Image(systemName: report.currentDays > 0 ? "flame.fill" : "flame")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(report.currentDays > 0 ? PaceColor.streak : PaceColor.textSecondary)
                    .frame(width: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.currentText)
                        .font(PaceFont.metric(size: 36))
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(PaceLocalization.text(de: "Aktuelle Serie", en: "Current streak", ru: "Текущая серия"))
                        .font(PaceFont.caption.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                    Text(report.statusText)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func facts(_ report: StreakDetailReport) -> some View {
        HStack(alignment: .top, spacing: PaceSpacing.xs) {
            fact(StreakTexts.record, value: report.recordText ?? "–", detail: report.recordRangeText, systemImage: "trophy.fill")
            fact(StreakTexts.started, value: report.currentStartText ?? "–", detail: nil, systemImage: "play.fill")
            fact(StreakTexts.lastSuccess, value: report.lastReachedText ?? "–", detail: nil, systemImage: "checkmark.seal.fill")
        }
    }

    private func fact(_ title: String, value: String, detail: String?, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
            Label(title, systemImage: systemImage)
                .font(PaceFont.caption.weight(.semibold))
                .foregroundStyle(PaceColor.textSecondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(PaceFont.headline)
                .foregroundStyle(PaceColor.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(PaceSpacing.s)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .paceCardBackground(cornerRadius: PaceRadius.tile)
        .accessibilityElement(children: .combine)
    }

    // MARK: Kalender

    private func calendarCard(_ report: StreakDetailReport) -> some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(spacing: PaceSpacing.xs) {
                    VStack(alignment: .leading, spacing: 0) {
                        PaceCardHeader(StreakTexts.calendar)
                        Text(report.monthTitle)
                            .font(PaceFont.callout)
                            .foregroundStyle(PaceColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button(action: onPreviousMonth) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.paceIcon)
                    .disabled(!report.canShowPreviousMonth)
                    .accessibilityLabel(PaceLocalization.text(de: "Vorheriger Monat", en: "Previous month", ru: "Предыдущий месяц"))
                    Button(action: onNextMonth) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.paceIcon)
                    .disabled(!report.canShowNextMonth)
                    .accessibilityLabel(PaceLocalization.text(de: "Nächster Monat", en: "Next month", ru: "Следующий месяц"))
                }
                HStack(spacing: 0) {
                    ForEach(Array(report.weekdays.enumerated()), id: \.offset) { _, letter in
                        Text(letter)
                            .font(PaceFont.caption.weight(.semibold))
                            .foregroundStyle(PaceColor.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
                VStack(spacing: PaceSpacing.xxs) {
                    ForEach(Array(report.weeks.enumerated()), id: \.offset) { _, week in
                        HStack(spacing: 0) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
                                if let cell {
                                    StreakCalendarCell(cell: cell) { onSelect(cell.day) }
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                                }
                            }
                        }
                    }
                }
                // Monat wechseln wie im Kalender: Finger nach rechts = vorheriger, nach links = nächster Monat.
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                            if value.translation.width > 40 {
                                onPreviousMonth()
                            } else if value.translation.width < -40 {
                                onNextMonth()
                            }
                        }
                )
                legend
            }
        }
    }

    private var legend: some View {
        HStack(spacing: PaceSpacing.s) {
            legendItem(PaceLocalization.text(de: "Geschafft", en: "Reached", ru: "Выполнено")) {
                Image(systemName: "flame.fill").foregroundStyle(PaceColor.streak)
            }
            legendItem(PaceLocalization.text(de: "Verpasst", en: "Missed", ru: "Пропуск")) {
                Circle().fill(PaceColor.textSecondary.opacity(0.35)).frame(width: 7, height: 7)
            }
            legendItem(PaceLocalization.text(de: "Serie", en: "Streak", ru: "Серия")) {
                Capsule().fill(PaceColor.streak.opacity(0.18)).frame(width: 18, height: 10)
            }
        }
        .font(PaceFont.caption)
        .foregroundStyle(PaceColor.textSecondary)
        .accessibilityHidden(true)
    }

    private func legendItem(_ title: String, @ViewBuilder symbol: () -> some View) -> some View {
        HStack(spacing: 4) {
            symbol()
            Text(title).lineLimit(1)
        }
    }

    private func selectedCard(_ selected: StreakDetailReport.SelectedDay) -> some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                PaceCardHeader(selected.title)
                Label {
                    Text(selected.statusText)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: selected.state == .reached ? "flame.fill" : selected.state == .missed ? "flame" : "clock")
                        .foregroundStyle(selected.state == .reached ? PaceColor.streak : PaceColor.textSecondary)
                }
                .font(PaceFont.headline)
                .foregroundStyle(PaceColor.textPrimary)
                if let steps = selected.stepsText {
                    Text(steps)
                        .font(PaceFont.callout)
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.textPrimary)
                }
                Text(selected.goalText)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Frühere Serien und Erklärung

    private func pastRuns(_ report: StreakDetailReport) -> some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                PaceCardHeader(StreakTexts.pastStreaks)
                if report.pastRuns.isEmpty {
                    Text(StreakTexts.noPastStreaks)
                        .font(PaceFont.callout)
                        .foregroundStyle(PaceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(report.pastRuns) { run in
                        HStack(spacing: PaceSpacing.s) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(PaceColor.streak.opacity(0.8))
                                .accessibilityHidden(true)
                            Text(run.rangeText)
                                .font(PaceFont.callout)
                                .foregroundStyle(PaceColor.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: PaceSpacing.xs)
                            Text(run.daysText)
                                .font(PaceFont.headline)
                                .monospacedDigit()
                                .foregroundStyle(PaceColor.textPrimary)
                        }
                        .frame(minHeight: 36)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func explanation(_ report: StreakDetailReport) -> some View {
        PaceCard {
            VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                PaceCardHeader(StreakTexts.howItWorks)
                Text(StreakTexts.rule)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(StreakTexts.personalOnly)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(report.historyNote)
                    .font(PaceFont.caption)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Ein Tag im Flammenkalender: Flamme für erreichte Tage, Punkt für verpasste, Ring für heute; Serien sind durch eine
/// Fläche verbunden, die am ersten Tag beginnt und am letzten endet.
private struct StreakCalendarCell: View {
    let cell: StreakDetailReport.Cell
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack {
                    if cell.state == .reached {
                        runBackground
                    }
                    symbol
                        .frame(width: 30, height: 30)
                        .overlay {
                            if cell.isSelected {
                                Circle().strokeBorder(PaceColor.accent, lineWidth: 2)
                            } else if cell.isToday {
                                Circle().strokeBorder(PaceColor.textSecondary.opacity(0.6), lineWidth: 1)
                            }
                        }
                }
                .frame(height: 30)
                Text(cell.day.day.paceFormatted)
                    .font(PaceFont.micro.weight(cell.isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(cell.state == .future ? PaceColor.textSecondary.opacity(0.5) : PaceColor.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!cell.isSelectable)
        .accessibilityLabel(cell.accessibilityLabel)
        .accessibilityAddTraits(cell.isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var symbol: some View {
        switch cell.state {
        case .reached:
            Image(systemName: "flame.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PaceColor.streak)
        case .missed:
            Circle().fill(PaceColor.textSecondary.opacity(0.35)).frame(width: 7, height: 7)
        case .pending:
            Image(systemName: "flame")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(PaceColor.textSecondary)
        case .future:
            Color.clear
        case .noData:
            Text("–")
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary.opacity(0.6))
        }
    }

    /// Verbindende Fläche einer Serie: links offen, wenn die Serie schon vorher lief, rechts offen, wenn sie weiterläuft.
    private var runBackground: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let left: CGFloat = cell.isRunStart ? (width - 30) / 2 : 0
            let right: CGFloat = cell.isRunEnd ? (width - 30) / 2 : 0
            UnevenRoundedRectangle(
                topLeadingRadius: cell.isRunStart ? 15 : 0,
                bottomLeadingRadius: cell.isRunStart ? 15 : 0,
                bottomTrailingRadius: cell.isRunEnd ? 15 : 0,
                topTrailingRadius: cell.isRunEnd ? 15 : 0,
                style: .continuous
            )
            .fill(PaceColor.streak.opacity(0.18))
            .padding(.leading, left)
            .padding(.trailing, right)
        }
        .accessibilityHidden(true)
    }
}
