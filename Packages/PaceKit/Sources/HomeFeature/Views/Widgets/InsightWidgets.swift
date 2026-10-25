import ActivityFeature
import DesignSystem
import PaceCore
import SocialFeature
import SwiftUI

// MARK: - Tagesvergleich

/// Heute vs. gestern bis zur gleichen Uhrzeit.
/// - Klein: Unterschied in einem Satz.
/// - Mittel: Zahlen heute/gestern, Unterschied, Balken (wählbar).
/// - Groß/Max: zusätzlich „gestern insgesamt“ (wählbar), Max mit größerer Darstellung.
struct DayComparisonWidgetContent: View {
    let widget: HomeDayComparisonWidget?
    let size: HomeModuleSize
    let details: [HomeWidgetDetail]
    let unavailableText: String?

    var body: some View {
        if let widget {
            if widget.isAvailable {
                content(widget)
                    .accessibilityElement(children: .combine)
            } else {
                HomeWidgetHint(systemImage: "clock.arrow.circlepath", text: HomeDayComparisonWidget.unavailableText)
            }
        } else if let unavailableText {
            HomeWidgetHint(systemImage: "hand.raised", text: unavailableText)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    @ViewBuilder
    private func content(_ widget: HomeDayComparisonWidget) -> some View {
        switch size {
        case .small:
            HStack(spacing: PaceSpacing.s) {
                directionIcon(widget)
                VStack(alignment: .leading, spacing: 0) {
                    Text(widget.percentText ?? widget.differenceText ?? "–")
                        .font(.system(.title3, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(color(widget))
                    Text(widget.headline)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
        case .medium, .large, .max:
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: PaceSpacing.xs) {
                    Text(widget.differenceText ?? "–")
                        .font(PaceFont.metric(size: size == .max ? 40 : 32))
                        .monospacedDigit()
                        .foregroundStyle(color(widget))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let percent = widget.percentText {
                        Text(percent)
                            .font(.system(.headline, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(color(widget))
                    }
                    Spacer(minLength: 0)
                    Text(widget.timeText)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
                Text(widget.headline)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if details.contains(.comparisonBars) {
                    VStack(spacing: PaceSpacing.xs) {
                        comparisonBar(
                            title: PaceLocalization.text(de: "Heute", en: "Today", ru: "Сегодня"),
                            value: widget.todayText,
                            level: widget.todayLevel,
                            isToday: true
                        )
                        comparisonBar(
                            title: PaceLocalization.text(de: "Gestern", en: "Yesterday", ru: "Вчера"),
                            value: widget.yesterdayText ?? "–",
                            level: widget.yesterdayLevel,
                            isToday: false
                        )
                    }
                }
                if details.contains(.yesterdayTotal), let total = widget.yesterdayTotalText {
                    HomeStatTile(
                        title: PaceLocalization.text(de: "Gestern insgesamt", en: "Yesterday in total", ru: "Вчера всего"),
                        value: total,
                        systemImage: "clock.arrow.circlepath"
                    )
                }
            }
        }
    }

    private func comparisonBar(title: String, value: String, level: Double, isToday: Bool) -> some View {
        HStack(spacing: PaceSpacing.s) {
            Text(title)
                .font(PaceFont.caption)
                .foregroundStyle(PaceColor.textSecondary)
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(PaceColor.track)
                    Capsule()
                        .fill(isToday ? PaceColor.actionFill : PaceColor.accent.opacity(0.35))
                        .frame(width: max(6, proxy.size.width * level))
                }
            }
            .frame(height: 10)
            Text(value)
                .font(PaceFont.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(PaceColor.textPrimary)
                .frame(minWidth: 52, alignment: .trailing)
        }
    }

    private func directionIcon(_ widget: HomeDayComparisonWidget) -> some View {
        Image(systemName: widget.direction == .ahead ? "arrow.up.right" : widget.direction == .behind ? "arrow.down.right" : "equal")
            .font(.system(.headline, weight: .bold))
            .foregroundStyle(color(widget))
            .frame(width: 40, height: 40)
            .background(color(widget).opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }

    private func color(_ widget: HomeDayComparisonWidget) -> Color {
        switch widget.direction {
        case .ahead: PaceColor.accent
        case .behind: PaceColor.textSecondary
        case .even: PaceColor.textPrimary
        }
    }
}

// MARK: - Flammen-Woche

/// Laufende Woche Mo–So mit Ziel je Tag (bewertet mit dem damals geltenden Ziel). Serie, Rekord und nächster
/// Meilenstein sind wählbar. Tippen öffnet die Flammen-Seite.
struct StreakWeekWidgetContent: View {
    let widget: HomeStreakWidget?
    let state: ActivityHistoryStore.State
    let size: HomeModuleSize
    let details: [HomeWidgetDetail]

    var body: some View {
        if let widget {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                StreakWeekStrip(days: widget.week)
                if details.contains(.streakCount) || details.contains(.record) {
                    HStack(spacing: PaceSpacing.xs) {
                        if details.contains(.streakCount) {
                            HomeStatTile(
                                title: PaceLocalization.text(de: "Aktuelle Serie", en: "Current streak", ru: "Текущая серия"),
                                value: widget.currentText,
                                systemImage: "flame"
                            )
                        }
                        if details.contains(.record) {
                            HomeStatTile(
                                title: PaceLocalization.text(de: "Rekord", en: "Record", ru: "Рекорд"),
                                value: widget.recordText ?? "–",
                                systemImage: "trophy"
                            )
                        }
                    }
                }
                if details.contains(.milestone) {
                    Label(StreakMilestone.text(current: widget.current), systemImage: "flag.checkered")
                        .font(PaceFont.caption.weight(.semibold))
                        .foregroundStyle(PaceColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if size != .small {
                    Text(HomeTexts.goalDaysThisWeek(widget.reachedThisWeek))
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
            .accessibilityElement(children: .contain)
        } else {
            switch state {
            case .noReadAccess:
                HomeWidgetHint(
                    systemImage: "hand.raised",
                    text: PaceLocalization.text(
                        de: "Ohne Zugriff auf deine Schritte gibt es keine Flammen-Woche.",
                        en: "Without access to your steps there is no flame week.",
                        ru: "Без доступа к шагам недели огня нет."
                    )
                )
            case .failed(let message):
                HomeWidgetHint(systemImage: "arrow.clockwise", text: message)
            case .idle, .loading, .loaded:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }
}

// MARK: - Persönliche Rekorde

/// Ein gewählter Rekord groß, in größeren Größen weitere Rekorde. Zeitraum immer benannt („Letzte 12 Monate“).
struct RecordsWidgetContent: View {
    let widget: HomeRecordsWidget?
    let state: ActivityHistoryStore.State
    let size: HomeModuleSize

    var body: some View {
        if let widget {
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                if let primary = widget.primary {
                    primaryRow(primary, compact: size == .small)
                } else {
                    HomeWidgetHint(systemImage: widget.selected.systemImage, text: HomeRecordsWidget.emptyText)
                }
                let others = Array(widget.others.prefix(otherCount))
                if !others.isEmpty {
                    VStack(spacing: PaceSpacing.xs) {
                        ForEach(others) { entry in
                            otherRow(entry)
                        }
                    }
                }
                Text(HomeRecordsWidget.periodText)
                    .font(PaceFont.micro)
                    .foregroundStyle(PaceColor.textSecondary)
            }
        } else {
            switch state {
            case .noReadAccess:
                HomeWidgetHint(
                    systemImage: "hand.raised",
                    text: PaceLocalization.text(
                        de: "Ohne Zugriff auf deine Schritte gibt es keine Rekorde.",
                        en: "Without access to your steps there are no records.",
                        ru: "Без доступа к шагам рекордов нет."
                    )
                )
            case .failed(let message):
                HomeWidgetHint(systemImage: "arrow.clockwise", text: message)
            case .idle, .loading, .loaded:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    /// Klein und Mittel nur der gewählte Rekord, Groß zwei weitere, Max alle.
    private var otherCount: Int {
        switch size {
        case .small, .medium: 0
        case .large: 2
        case .max: HomeRecordKind.allCases.count
        }
    }

    private func primaryRow(_ entry: HomeRecordsWidget.Entry, compact: Bool) -> some View {
        HStack(spacing: PaceSpacing.s) {
            Image(systemName: entry.kind.systemImage)
                .font(.system(compact ? .title3 : .title2, weight: .semibold))
                .foregroundStyle(entry.kind == .longestStreak || entry.kind == .currentStreak ? PaceColor.streak : PaceColor.accent)
                .frame(width: compact ? 40 : 48, height: compact ? 40 : 48)
                .background(PaceColor.accentSoft, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title)
                    .font(PaceFont.caption.weight(.semibold))
                    .foregroundStyle(PaceColor.textSecondary)
                Text(entry.value)
                    .font(compact ? Font.system(.title3, weight: .bold) : PaceFont.metric(size: 30))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let detail = entry.detail, !compact {
                    Text(detail)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func otherRow(_ entry: HomeRecordsWidget.Entry) -> some View {
        HStack(spacing: PaceSpacing.xs) {
            Image(systemName: entry.kind.systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PaceColor.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(entry.title)
                .font(PaceFont.callout)
                .foregroundStyle(PaceColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: PaceSpacing.xs)
            VStack(alignment: .trailing, spacing: 0) {
                Text(entry.value)
                    .font(PaceFont.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(PaceColor.textPrimary)
                if let detail = entry.detail {
                    Text(detail)
                        .font(PaceFont.micro)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Aktivitätszeiten

/// Aktivität nach Tageszeiten. Klein: aktivste Tageszeit; Mittel: fünf Tageszeiten als Balken; Groß: mit Werten;
/// Max: zusätzlich alle 24 Stunden. Ohne Stundenwerte ein ehrlicher Leerzustand.
struct ActivityTimesWidgetContent: View {
    let widget: HomeActivityTimesWidget?
    let size: HomeModuleSize
    let unavailableText: String?

    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 54

    var body: some View {
        if let widget {
            if widget.isEmpty {
                HomeWidgetHint(systemImage: "clock", text: HomeActivityTimesWidget.emptyText)
            } else {
                content(widget)
            }
        } else if let unavailableText {
            HomeWidgetHint(systemImage: "hand.raised", text: unavailableText)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    @ViewBuilder
    private func content(_ widget: HomeActivityTimesWidget) -> some View {
        switch size {
        case .small:
            HStack(spacing: PaceSpacing.s) {
                Image(systemName: "clock")
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(PaceColor.accent)
                    .frame(width: 40, height: 40)
                    .background(PaceColor.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(widget.peak?.title ?? "–")
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(PaceColor.textPrimary)
                    Text(widget.peak.map { "\($0.hours) · \($0.stepsText)" } ?? "")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        case .medium, .large, .max:
            VStack(alignment: .leading, spacing: PaceSpacing.s) {
                HStack(alignment: .bottom, spacing: PaceSpacing.xs) {
                    ForEach(widget.buckets) { bucket in
                        VStack(spacing: 4) {
                            if size >= .large {
                                Text(bucket.stepsText)
                                    .font(PaceFont.micro.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(PaceColor.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(bucket.isPeak ? PaceColor.actionFill : PaceColor.accent.opacity(bucket.steps > 0 ? 0.45 : 0.15))
                                .frame(height: max(4, barHeight * bucket.level))
                                .frame(height: barHeight, alignment: .bottom)
                            Text(bucket.title)
                                .font(PaceFont.micro.weight(bucket.isCurrent ? .bold : .regular))
                                .foregroundStyle(bucket.isCurrent ? PaceColor.textPrimary : PaceColor.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(bucket.title), \(bucket.hours): \(PaceLocalization.steps(bucket.steps))")
                    }
                }
                if size == .max {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(widget.hours) { hour in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(hour.isCurrent ? PaceColor.actionFill : PaceColor.accent.opacity(hour.steps > 0 ? 0.55 : 0.12))
                                .frame(height: max(2, 36 * hour.level))
                                .frame(maxWidth: .infinity, maxHeight: 36, alignment: .bottom)
                        }
                    }
                    .accessibilityHidden(true)
                    HStack {
                        Text(verbatim: "0")
                        Spacer()
                        Text(verbatim: "6")
                        Spacer()
                        Text(verbatim: "12")
                        Spacer()
                        Text(verbatim: "18")
                        Spacer()
                        Text(verbatim: "24")
                    }
                    .font(PaceFont.micro)
                    .foregroundStyle(PaceColor.textSecondary)
                    .accessibilityHidden(true)
                }
                if let peak = widget.peakText {
                    Text(peak)
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                }
            }
        }
    }
}

// MARK: - Gruppenfortschritt

/// Tagesfortschritt einer gewählten Gruppe. Tippen öffnet die Gruppe, die Flamme den Gruppenkalender.
struct GroupProgressWidgetContent: View {
    let widget: HomeGroupProgressWidget
    let size: HomeModuleSize
    let details: [HomeWidgetDetail]
    let onOpenGroup: (UUID) -> Void
    let onOpenCalendar: (UUID) -> Void

    var body: some View {
        switch widget {
        case .group(let group, let progress):
            content(group, progress)
        case .unselected:
            HomeWidgetHint(systemImage: "person.3", text: HomeGroupProgressWidget.unselectedText)
        case .missing:
            HomeWidgetHint(systemImage: "person.crop.circle.badge.xmark", text: HomeGroupProgressWidget.missingText)
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    @ViewBuilder
    private func content(_ group: GroupSummary, _ progress: GroupDayProgress) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            HStack(alignment: .center, spacing: PaceSpacing.s) {
                Button {
                    onOpenGroup(group.id)
                } label: {
                    HStack(spacing: PaceSpacing.s) {
                        GroupAvatar(name: group.name, kind: group.kind, image: group.image, size: size == .small ? 36 : 44)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.name)
                                .font(PaceFont.headline)
                                .foregroundStyle(PaceColor.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(size == .small ? "\(progress.reached.paceFormatted)/\(progress.members.paceFormatted)" : HomeTexts.members(group.memberCount))
                                .font(PaceFont.caption)
                                .monospacedDigit()
                                .foregroundStyle(PaceColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .accessibilityLabel(group.name)

                Button {
                    onOpenCalendar(group.id)
                } label: {
                    GroupFlameCount(progress: progress)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pacePressable)
                .accessibilityLabel(PaceLocalization.text(
                    de: "Gruppenflamme: \(PaceLocalization.days(progress.streak))",
                    en: "Group flame: \(PaceLocalization.days(progress.streak))",
                    ru: "Огонь группы: \(PaceLocalization.days(progress.streak))"
                ))
                .accessibilityHint(PaceLocalization.text(
                    de: "Öffnet den Gruppenkalender", en: "Opens the group calendar", ru: "Открывает календарь группы"
                ))
            }
            if size != .small {
                Text(progress.reachedText)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GroupDayProgressBar(progress: progress, height: size == .small ? 8 : 12)
            if details.contains(.groupHint), let hint = progress.hint {
                Text(hint)
                    .font(PaceFont.caption)
                    .foregroundStyle(progress.isSecured ? PaceColor.accent : PaceColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if details.contains(.groupGoal) {
                HStack(spacing: PaceSpacing.xs) {
                    HomeStatTile(
                        title: PaceLocalization.text(de: "Tagesziel", en: "Daily goal", ru: "Дневная цель"),
                        value: group.dailyGoal.paceFormatted,
                        systemImage: "scope"
                    )
                    HomeStatTile(
                        title: PaceLocalization.text(de: "Beste Serie", en: "Best streak", ru: "Лучшая серия"),
                        value: PaceLocalization.days(group.bestStreak),
                        systemImage: "trophy"
                    )
                }
            }
        }
    }
}
