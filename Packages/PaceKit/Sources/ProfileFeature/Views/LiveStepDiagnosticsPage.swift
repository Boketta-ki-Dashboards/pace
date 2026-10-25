import DesignSystem
import PaceCore
import SwiftUI

/// Diagnose des Live-Schrittzählers – nur in Entwicklungs-Builds erreichbar (Profil → Aktivität & Gesundheit).
///
/// Zeigt Sensorzustand, Messwerte, HealthKit-Stände und das begrenzte Protokoll, damit sich eine Gehprobe auf dem
/// iPhone nachvollziehen lässt. Nichts davon wird hochgeladen oder im Home-Design angezeigt.
struct LiveStepDiagnosticsPage: View {
    let diagnostics: LiveStepDiagnostics
    let backTitle: String

    var body: some View {
        ProfileSubpage {
            LiveStepDiagnosticsContent(diagnostics: diagnostics, backTitle: backTitle)
        }
    }
}

struct LiveStepDiagnosticsContent: View {
    let diagnostics: LiveStepDiagnostics
    let backTitle: String

    @AppStorage(SimulatedLiveSteps.launchArgumentKey) private var simulatedStepsPerMinute: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.liveStepDiagnostics.title)
                .padding(.bottom, PaceSpacing.xs)

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(LiveStepDiagnosticsTexts.sensor)
                    ProfileInfoRow(systemImage: "sensor", title: LiveStepDiagnosticsTexts.status, value: LiveStepDiagnosticsTexts.status(diagnostics.status))
                    ProfileInfoRow(systemImage: "record.circle", title: LiveStepDiagnosticsTexts.measuring, value: diagnostics.isMeasuring ? LiveStepDiagnosticsTexts.yes : LiveStepDiagnosticsTexts.no)
                    ProfileInfoRow(systemImage: "clock", title: LiveStepDiagnosticsTexts.measuredFrom, value: diagnostics.measurementStart.map(Self.time) ?? "–")
                    ProfileInfoRow(systemImage: "number", title: LiveStepDiagnosticsTexts.readings, value: diagnostics.readingCount.paceFormatted)
                    ProfileInfoRow(
                        systemImage: "timer",
                        title: LiveStepDiagnosticsTexts.averageInterval,
                        value: diagnostics.averageReadingInterval.map { String(format: "%.1f s", $0) } ?? "–"
                    )
                    ProfileInfoRow(
                        systemImage: "shoeprints.fill",
                        title: LiveStepDiagnosticsTexts.lastReading,
                        value: diagnostics.lastReading.map { "\($0.steps.paceFormatted) · \(Self.time($0.date))" } ?? "–"
                    )
                }
            }

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(LiveStepDiagnosticsTexts.reconciliation)
                    ProfileInfoRow(systemImage: "heart.text.square", title: LiveStepDiagnosticsTexts.confirmed, value: diagnostics.estimator.confirmedSteps?.paceFormatted ?? "–")
                    ProfileInfoRow(systemImage: "eye", title: LiveStepDiagnosticsTexts.shown, value: diagnostics.estimator.steps.paceFormatted)
                    ProfileInfoRow(systemImage: "hourglass", title: LiveStepDiagnosticsTexts.unconfirmed, value: diagnostics.estimator.unconfirmedSteps.paceFormatted)
                    ProfileInfoRow(systemImage: "plus.forwardslash.minus", title: LiveStepDiagnosticsTexts.sensorSinceBase, value: diagnostics.estimator.sensorDelta.paceFormatted)
                    ProfileInfoRow(systemImage: "arrow.triangle.2.circlepath", title: LiveStepDiagnosticsTexts.lastHealthKitChange, value: diagnostics.lastHealthKitChange.map(Self.time) ?? "–")
                    ProfileFootnote(text: LiveStepDiagnosticsTexts.rankingsNote)
                }
            }

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(LiveStepDiagnosticsTexts.simulation)
                    Toggle(LiveStepDiagnosticsTexts.simulationToggle, isOn: Binding(
                        get: { simulatedStepsPerMinute > 0 },
                        set: { simulatedStepsPerMinute = $0 ? 100 : 0 }
                    ))
                    .font(PaceFont.callout)
                    .tint(PaceColor.accent)
                    ProfileFootnote(text: LiveStepDiagnosticsTexts.simulationNote)
                }
            }

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.xs) {
                    HStack {
                        PaceCardHeader(LiveStepDiagnosticsTexts.log)
                        Spacer()
                        Button(LiveStepDiagnosticsTexts.clear) { diagnostics.reset() }
                            .font(PaceFont.callout)
                            .buttonStyle(.paceSoft)
                    }
                    if diagnostics.events.isEmpty {
                        ProfileFootnote(text: LiveStepDiagnosticsTexts.emptyLog)
                    }
                    ForEach(diagnostics.events) { event in
                        HStack(spacing: PaceSpacing.xs) {
                            Text(Self.time(event.date))
                                .monospacedDigit()
                                .foregroundStyle(PaceColor.textSecondary)
                            Text(LiveStepDiagnosticsTexts.kind(event.kind))
                                .foregroundStyle(PaceColor.textPrimary)
                            Spacer(minLength: PaceSpacing.xxs)
                            if let value = event.value {
                                Text(value.paceFormatted)
                                    .monospacedDigit()
                                    .foregroundStyle(PaceColor.textSecondary)
                            }
                            Text("→ \(event.shown.paceFormatted)")
                                .monospacedDigit()
                                .foregroundStyle(PaceColor.textPrimary)
                        }
                        .font(PaceFont.caption)
                    }
                }
            }
        }
    }

    private static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }
}

enum LiveStepDiagnosticsTexts {
    static var sensor: String { PaceLocalization.text(de: "Bewegungssensor", en: "Motion sensor", ru: "Датчик движения") }
    static var status: String { PaceLocalization.text(de: "Zustand", en: "Status", ru: "Состояние") }
    static var measuring: String { PaceLocalization.text(de: "Messung läuft", en: "Measuring", ru: "Измерение идёт") }
    static var measuredFrom: String { PaceLocalization.text(de: "Gemessen ab", en: "Measured from", ru: "Измеряется с") }
    static var readings: String { PaceLocalization.text(de: "Messwerte", en: "Readings", ru: "Показания") }
    static var averageInterval: String { PaceLocalization.text(de: "Ø Abstand", en: "Avg. interval", ru: "Средний интервал") }
    static var lastReading: String { PaceLocalization.text(de: "Letzter Sensorwert", en: "Last sensor value", ru: "Последнее показание") }
    static var reconciliation: String { PaceLocalization.text(de: "Abgleich mit Apple Health", en: "Reconciliation with Apple Health", ru: "Сверка с Apple Health") }
    static var confirmed: String { PaceLocalization.text(de: "Bestätigt (HealthKit)", en: "Confirmed (HealthKit)", ru: "Подтверждено (HealthKit)") }
    static var shown: String { PaceLocalization.text(de: "Angezeigt", en: "Shown", ru: "Показано") }
    static var unconfirmed: String { PaceLocalization.text(de: "Vorläufig", en: "Preliminary", ru: "Предварительно") }
    static var sensorSinceBase: String { PaceLocalization.text(de: "Sensor seit Basis", en: "Sensor since base", ru: "Датчик с базы") }
    static var lastHealthKitChange: String { PaceLocalization.text(de: "Letzte HealthKit-Änderung", en: "Last HealthKit change", ru: "Последнее изменение HealthKit") }
    static var rankingsNote: String {
        PaceLocalization.text(
            de: "Rankings, Sync und Serien verwenden nur bestätigte Schritte aus Apple Health. Vorläufige Sensorschritte sind nur Anzeige.",
            en: "Rankings, sync and streaks use only confirmed steps from Apple Health. Preliminary sensor steps are display only.",
            ru: "Рейтинги, синхронизация и серии используют только подтверждённые шаги из Apple Health. Предварительные шаги датчика только для отображения."
        )
    }
    static var simulation: String { PaceLocalization.text(de: "Simulation (nur Entwicklung)", en: "Simulation (development only)", ru: "Симуляция (только разработка)") }
    static var simulationToggle: String { PaceLocalization.text(de: "100 Schritte/min simulieren", en: "Simulate 100 steps/min", ru: "Симулировать 100 шагов/мин") }
    static var simulationNote: String {
        PaceLocalization.text(
            de: "Gilt ab dem nächsten App-Start. Der Simulator hat keinen Schrittzähler; simulierte Schritte ersetzen keinen Test auf dem iPhone.",
            en: "Takes effect on the next app launch. The Simulator has no step counter; simulated steps don't replace a test on the iPhone.",
            ru: "Действует со следующего запуска. В симуляторе нет шагомера; симуляция не заменяет проверку на iPhone."
        )
    }
    static var log: String { PaceLocalization.text(de: "Protokoll", en: "Log", ru: "Журнал") }
    static var clear: String { PaceLocalization.text(de: "Leeren", en: "Clear", ru: "Очистить") }
    static var emptyLog: String { PaceLocalization.text(de: "Noch keine Einträge.", en: "No entries yet.", ru: "Записей пока нет.") }
    static var yes: String { PaceLocalization.text(de: "Ja", en: "Yes", ru: "Да") }
    static var no: String { PaceLocalization.text(de: "Nein", en: "No", ru: "Нет") }

    static func status(_ status: LiveStepSensorStatus) -> String {
        switch status {
        case .available: PaceLocalization.text(de: "Erlaubt", en: "Allowed", ru: "Разрешено")
        case .notDetermined: PaceLocalization.text(de: "Noch nicht gefragt", en: "Not asked yet", ru: "Ещё не запрошено")
        case .denied: PaceLocalization.text(de: "Verweigert", en: "Denied", ru: "Запрещено")
        case .restricted: PaceLocalization.text(de: "Eingeschränkt", en: "Restricted", ru: "Ограничено")
        case .unsupported: PaceLocalization.text(de: "Kein Schrittzähler", en: "No step counter", ru: "Нет шагомера")
        case .simulated: PaceLocalization.text(de: "Simuliert", en: "Simulated", ru: "Симуляция")
        }
    }

    static func kind(_ kind: LiveStepDiagnostics.Event.Kind) -> String {
        switch kind {
        case .started: PaceLocalization.text(de: "Messung gestartet", en: "Measurement started", ru: "Измерение начато")
        case .sensor: PaceLocalization.text(de: "Sensor", en: "Sensor", ru: "Датчик")
        case .healthKit: "HealthKit"
        case .sensorRestarted: PaceLocalization.text(de: "Sensor neu gestartet", en: "Sensor restarted", ru: "Датчик перезапущен")
        case .unconfirmedExpired:
            PaceLocalization.text(de: "Unbestätigte Schritte verfallen", en: "Unconfirmed steps expired", ru: "Неподтверждённые шаги сброшены")
        case .dayChanged: PaceLocalization.text(de: "Neuer Tag", en: "New day", ru: "Новый день")
        case .stopped: PaceLocalization.text(de: "Messung beendet", en: "Measurement stopped", ru: "Измерение остановлено")
        case .unavailable: PaceLocalization.text(de: "Nicht verfügbar", en: "Unavailable", ru: "Недоступно")
        }
    }
}
