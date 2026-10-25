import ActivityFeature
import DesignSystem
import PaceCore
import SwiftUI

// MARK: - Aktivität & Gesundheit

/// Aktivität & Gesundheit: Verbindung zu Apple Health, Tagesziel und Kalorienschätzung.
struct ActivityHealthPage: View {
    let viewModel: ProfileViewModel
    let backTitle: String

    var body: some View {
        ProfileSubpage {
            ActivityHealthPageContent(viewModel: viewModel, backTitle: backTitle) { viewModel.open($0) }
        }
    }
}

struct ActivityHealthPageContent: View {
    let viewModel: ProfileViewModel
    let backTitle: String
    var onOpen: (ProfileRoute) -> Void = { _ in }

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.activityHealth.title)
                .padding(.bottom, PaceSpacing.xs)

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader("Apple Health")
                    ProfileInfoRow(systemImage: "heart.text.square", title: ActivityHealthTexts.connection, value: connectionText)
                    ProfileFootnote(text: ActivityHealthTexts.permissionsExplanation)
                    Button {
                        if let url = URL(string: "x-apple-health://") { openURL(url) }
                    } label: {
                        Label(ActivityHealthTexts.openHealth, systemImage: "arrow.up.forward.app")
                            .font(PaceFont.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.paceSoft)
                }
            }

            if let goal = viewModel.goalText {
                ProfileSettingsRow(
                    systemImage: "target",
                    title: ActivityHealthTexts.dailyGoal,
                    subtitle: ActivityHealthTexts.dailyGoalSubtitle,
                    value: goal
                ) { viewModel.isEditingGoal = true }
            }

            ProfileSettingsRow(
                systemImage: "flame",
                title: ProfileRoute.calorieEstimation.title,
                subtitle: ActivityHealthTexts.calorieRowSubtitle,
                value: viewModel.bodyMetrics?.metrics.isEstimationEnabled == true ? ActivityHealthTexts.on : ActivityHealthTexts.off
            ) { onOpen(.calorieEstimation) }

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(ActivityHealthTexts.howPaceCounts)
                    ProfileNoteRow(systemImage: "shoeprints.fill", text: ActivityHealthTexts.stepsSource)
                    ProfileNoteRow(systemImage: "hand.raised", text: ActivityHealthTexts.manualSteps)
                    ProfileNoteRow(systemImage: "bolt.heart", text: ActivityHealthTexts.liveSteps)
                }
            }

            #if DEBUG
            // Nur Entwicklungs-Builds: Diagnose des Live-Schrittzählers (nie im Home-Design).
            if viewModel.liveStepDiagnostics != nil {
                ProfileSettingsRow(
                    systemImage: "stethoscope",
                    title: ProfileRoute.liveStepDiagnostics.title,
                    subtitle: PaceLocalization.text(de: "Nur in Entwicklungs-Builds", en: "Development builds only", ru: "Только в сборках для разработки")
                ) { onOpen(.liveStepDiagnostics) }
            }
            #endif
        }
    }

    private var connectionText: String {
        switch viewModel.streak?.history.state {
        case .loaded: ActivityHealthTexts.connected
        case .noReadAccess: ActivityHealthTexts.noAccess
        case .failed: ActivityHealthTexts.readFailed
        case .idle, .loading, nil: ActivityHealthTexts.checking
        }
    }
}

// MARK: - Kalorienschätzung

/// Kalorienschätzung: Körpergröße, Gewicht und Ein/Aus. Die Werte bleiben auf diesem iPhone.
struct CalorieEstimationPage: View {
    let settings: BodyMetricsSettings?
    let backTitle: String

    var body: some View {
        ProfileSubpage {
            if let settings {
                CalorieEstimationPageContent(settings: settings, backTitle: backTitle)
            } else {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.calorieEstimation.title)
                    ProfileFootnote(text: ActivityHealthTexts.estimationUnavailable)
                }
            }
        }
    }
}

struct CalorieEstimationPageContent: View {
    private enum Field: Hashable {
        case height
        case weight
    }

    let settings: BodyMetricsSettings
    let backTitle: String

    @State private var heightText: String
    @State private var weightText: String
    @State private var heightError: String?
    @State private var weightError: String?
    @FocusState private var focusedField: Field?

    init(settings: BodyMetricsSettings, backTitle: String) {
        self.settings = settings
        self.backTitle = backTitle
        _heightText = State(initialValue: Self.text(settings.metrics.heightCentimeters))
        _weightText = State(initialValue: Self.text(settings.metrics.weightKilograms))
    }

    /// Kennung der Karte mit den Eingabefeldern (zum Hinscrollen über die Tastatur).
    private static let bodyDataID = "calorie.bodyData"

    var body: some View {
        ScrollViewReader { proxy in
            content
                // Kleine iPhones: Die Felder liegen sonst unter der Tastatur – nach dem Einblenden hinscrollen.
                .onChange(of: focusedField) { _, field in
                    guard field != nil else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(Self.bodyDataID, anchor: .bottom)
                        }
                    }
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.s) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.calorieEstimation.title)
                .padding(.bottom, PaceSpacing.xs)

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    ProfileToggleTile(
                        title: ActivityHealthTexts.estimateToggle,
                        isOn: settings.metrics.isEstimationEnabled,
                        isHighlighted: settings.metrics.isEstimationEnabled,
                        isDisabled: false
                    ) { enabled in
                        settings.setEstimationEnabled(enabled)
                    }
                    ProfileFootnote(text: ActivityHealthTexts.estimateToggleExplanation)
                }
            }

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(ActivityHealthTexts.bodyData)
                    measurementField(
                        title: ActivityHealthTexts.height,
                        unit: ActivityHealthTexts.centimeters,
                        text: $heightText,
                        error: heightError,
                        field: .height
                    )
                    measurementField(
                        title: ActivityHealthTexts.weight,
                        unit: ActivityHealthTexts.kilograms,
                        text: $weightText,
                        error: weightError,
                        field: .weight
                    )
                    if settings.metrics.isEstimationEnabled, !settings.metrics.canEstimate {
                        ProfileFootnote(text: ActivityHealthTexts.missingBodyData, isError: true)
                    }
                    if let example = exampleText {
                        ProfileNoteRow(systemImage: "function", text: example)
                    }
                }
            }
            .id(Self.bodyDataID)

            PaceCard {
                VStack(alignment: .leading, spacing: PaceSpacing.s) {
                    PaceCardHeader(ActivityHealthTexts.howItWorks)
                    ProfileNoteRow(systemImage: "applewatch", text: ActivityHealthTexts.measuredFirst)
                    ProfileNoteRow(systemImage: "figure.walk", text: ActivityHealthTexts.model)
                    ProfileNoteRow(systemImage: "lock.shield", text: ActivityHealthTexts.privacy)
                }
            }
        }
        .onChange(of: focusedField) { previous, _ in
            if previous == .height { commitHeight() }
            if previous == .weight { commitWeight() }
        }
        // Gültige Werte gelten schon beim Tippen (der Ziffernblock hat keine Eingabetaste); Fehler erst beim Verlassen.
        .onChange(of: heightText) { _, text in
            if BodyMetricsSettings.number(from: text).flatMap({ $0 }).map({ BodyMetrics.heightRange.contains($0) }) == true {
                settings.setHeight(text)
            }
        }
        .onChange(of: weightText) { _, text in
            if BodyMetricsSettings.number(from: text).flatMap({ $0 }).map({ BodyMetrics.weightRange.contains($0) }) == true {
                settings.setWeight(text)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(ActivityHealthTexts.done) { focusedField = nil }
            }
        }
        .onDisappear {
            commitHeight()
            commitWeight()
        }
    }

    private func measurementField(
        title: String,
        unit: String,
        text: Binding<String>,
        error: String?,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xxs) {
            HStack(spacing: PaceSpacing.s) {
                Text(title)
                    .font(PaceFont.headline)
                    .foregroundStyle(PaceColor.textPrimary)
                Spacer(minLength: PaceSpacing.xs)
                TextField(ActivityHealthTexts.notSet, text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focusedField, equals: field)
                    .frame(maxWidth: 110)
                    .onSubmit {
                        focusedField = nil
                    }
                Text(unit)
                    .font(PaceFont.callout)
                    .foregroundStyle(PaceColor.textSecondary)
            }
            .padding(.horizontal, PaceSpacing.m)
            .frame(minHeight: 48)
            .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            if let error {
                ProfileFootnote(text: error, isError: true)
            }
        }
    }

    /// z. B. „Beispiel: 8.000 Schritte ≈ 262 kcal“ – nur mit gültigen Werten.
    private var exampleText: String? {
        var metrics = settings.metrics
        metrics.isEstimationEnabled = true
        guard let kilocalories = CalorieEstimator.kilocalories(automaticSteps: 8_000, measuredDistanceMeters: nil, metrics: metrics) else {
            return nil
        }
        let formatter = ActivityFormatter()
        return ActivityHealthTexts.example(steps: formatter.steps(8_000), energy: formatter.energy(.estimated(kilocalories)) ?? "")
    }

    private func commitHeight() {
        heightError = settings.setHeight(heightText).map { ActivityHealthTexts.message(for: $0, unit: ActivityHealthTexts.centimeters) }
        if heightError == nil { heightText = Self.text(settings.metrics.heightCentimeters) }
    }

    private func commitWeight() {
        weightError = settings.setWeight(weightText).map { ActivityHealthTexts.message(for: $0, unit: ActivityHealthTexts.kilograms) }
        if weightError == nil { weightText = Self.text(settings.metrics.weightKilograms) }
    }

    /// z. B. `182` oder `74,5` (Sprache der App).
    private static func text(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(PaceLocalization.shared.locale))
    }
}

// MARK: - Daten, Hilfe & Rechtliches

/// Sammelseite: Datenexport und Konto löschen, Hilfe, Feedback, rechtliche Texte (bestehende Unterseiten).
struct DataHelpLegalPage: View {
    let backTitle: String
    let onOpen: (ProfileRoute) -> Void

    var body: some View {
        ProfileSubpage {
            DataHelpLegalPageContent(backTitle: backTitle, onOpen: onOpen)
        }
    }
}

struct DataHelpLegalPageContent: View {
    let backTitle: String
    var onOpen: (ProfileRoute) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: PaceSpacing.xs) {
            PaceSubpageHeader(backTitle: backTitle, title: ProfileRoute.dataHelpLegal.title)
                .padding(.bottom, PaceSpacing.s)
            ProfileSettingsRow(
                systemImage: "lock.shield",
                title: ProfileRoute.dataPrivacy.title,
                subtitle: PaceLocalization.text(
                    de: "Datenexport, Konto löschen",
                    en: "Data export, delete account",
                    ru: "Экспорт данных, удаление аккаунта"
                )
            ) { onOpen(.dataPrivacy) }
            ProfileSettingsRow(
                systemImage: "questionmark.circle",
                title: ProfileRoute.help.title,
                subtitle: PaceLocalization.text(
                    de: "Häufige Fragen, Problem melden",
                    en: "FAQ, report a problem",
                    ru: "Частые вопросы, сообщить о проблеме"
                )
            ) { onOpen(.help) }
            ProfileSettingsRow(
                systemImage: "lightbulb",
                title: FeedbackKind.idea.title,
                subtitle: PaceLocalization.text(
                    de: "Ideen und Wünsche an das Pace-Team",
                    en: "Ideas and wishes for the Pace team",
                    ru: "Идеи и пожелания команде Pace"
                )
            ) { onOpen(.feedback(.idea)) }
            ProfileSettingsRow(
                systemImage: "doc.text",
                title: ProfileRoute.legal.title,
                subtitle: PaceLocalization.text(
                    de: "Datenschutzerklärung, Impressum, Nutzungsbedingungen",
                    en: "Privacy policy, legal notice, terms of use",
                    ru: "Политика конфиденциальности, выходные данные, условия"
                )
            ) { onOpen(.legal) }
        }
    }
}

// MARK: - Texte

enum ActivityHealthTexts {
    static var connection: String { PaceLocalization.text(de: "Schritte", en: "Steps", ru: "Шаги") }
    static var connected: String { PaceLocalization.text(de: "Verbunden", en: "Connected", ru: "Подключено") }
    static var noAccess: String { PaceLocalization.text(de: "Kein Zugriff", en: "No access", ru: "Нет доступа") }
    static var readFailed: String { PaceLocalization.text(de: "Nicht lesbar", en: "Not readable", ru: "Не читается") }
    static var checking: String { PaceLocalization.text(de: "Wird geprüft …", en: "Checking …", ru: "Проверяем …") }
    static var permissionsExplanation: String {
        PaceLocalization.text(
            de: "Welche Daten Pace lesen darf, legst du in der Health-App fest: Profilbild → Apps → Pace.",
            en: "You decide which data Pace may read in the Health app: profile picture → Apps → Pace.",
            ru: "Какие данные может читать Pace, ты задаёшь в приложении «Здоровье»: фото профиля → Приложения → Pace."
        )
    }
    static var openHealth: String { PaceLocalization.text(de: "Health-App öffnen", en: "Open Health app", ru: "Открыть «Здоровье»") }
    static var dailyGoal: String { PaceLocalization.text(de: "Tagesziel", en: "Daily goal", ru: "Цель на день") }
    static var dailyGoalSubtitle: String {
        PaceLocalization.text(de: "Gilt ab heute, frühere Tage bleiben", en: "Applies from today, past days stay", ru: "Действует с сегодня, прошлые дни не меняются")
    }
    static var calorieRowSubtitle: String {
        PaceLocalization.text(de: "Körpergröße, Gewicht, Schätzung ohne Apple Watch", en: "Height, weight, estimate without Apple Watch", ru: "Рост, вес, оценка без Apple Watch")
    }
    static var on: String { PaceLocalization.text(de: "Ein", en: "On", ru: "Вкл.") }
    static var off: String { PaceLocalization.text(de: "Aus", en: "Off", ru: "Выкл.") }
    static var howPaceCounts: String { PaceLocalization.text(de: "So zählt Pace", en: "How Pace counts", ru: "Как считает Pace") }
    static var stepsSource: String {
        PaceLocalization.text(
            de: "Schritte, Distanz und Kalorien kommen aus Apple Health. Pace erfindet keine Werte.",
            en: "Steps, distance and calories come from Apple Health. Pace never makes up values.",
            ru: "Шаги, дистанция и калории берутся из «Здоровья». Pace не придумывает значения."
        )
    }
    static var manualSteps: String {
        PaceLocalization.text(
            de: "Manuell in Apple Health eingetragene Schritte zählen nicht für Rankings, Gruppen und die Flamme.",
            en: "Steps entered manually in Apple Health don't count for rankings, groups or the flame.",
            ru: "Шаги, введённые вручную в «Здоровье», не учитываются в рейтингах, группах и серии."
        )
    }
    static var liveSteps: String {
        PaceLocalization.text(
            de: "Solange Pace offen ist, zeigt Home neue Schritte sofort über den Bewegungssensor – maßgeblich bleibt Apple Health.",
            en: "While Pace is open, Home shows new steps right away via the motion sensor – Apple Health remains authoritative.",
            ru: "Пока Pace открыт, «Главная» сразу показывает новые шаги с датчика движения – основным источником остаётся «Здоровье»."
        )
    }
    static var estimationUnavailable: String {
        PaceLocalization.text(de: "Ohne Bewegungsdaten ist keine Schätzung möglich.", en: "No estimate is possible without activity data.", ru: "Без данных об активности оценка невозможна.")
    }
    static var estimateToggle: String {
        PaceLocalization.text(de: "Aktive Kalorien schätzen", en: "Estimate active calories", ru: "Оценивать активные калории")
    }
    static var estimateToggleExplanation: String {
        PaceLocalization.text(
            de: "Nur an Tagen, an denen Apple Health keine gemessenen aktiven Kalorien hat. Geschätzte Werte stehen immer mit „≈“ und dem Hinweis „Geschätzte aktive Kalorien“.",
            en: "Only on days without measured active calories in Apple Health. Estimated values are always shown with “≈” and the note “Estimated active calories”.",
            ru: "Только в дни без измеренных активных калорий в «Здоровье». Расчётные значения всегда отмечены «≈» и подписью «Расчётные активные калории»."
        )
    }
    static var bodyData: String { PaceLocalization.text(de: "Körperdaten", en: "Body data", ru: "Данные о теле") }
    static var height: String { PaceLocalization.text(de: "Körpergröße", en: "Height", ru: "Рост") }
    static var weight: String { PaceLocalization.text(de: "Körpergewicht", en: "Weight", ru: "Вес") }
    static var notSet: String { PaceLocalization.text(de: "Nicht angegeben", en: "Not set", ru: "Не указано") }
    static var missingBodyData: String {
        PaceLocalization.text(
            de: "Für die Schätzung fehlen Körpergröße oder Gewicht.",
            en: "Height or weight is missing for the estimate.",
            ru: "Для оценки не хватает роста или веса."
        )
    }
    static var howItWorks: String { PaceLocalization.text(de: "So wird geschätzt", en: "How it's estimated", ru: "Как считается") }
    static var measuredFirst: String {
        PaceLocalization.text(
            de: "Gemessene Werte (z. B. von einer Apple Watch) haben immer Vorrang. Eine Schätzung wird nie dazugezählt.",
            en: "Measured values (e.g. from an Apple Watch) always take priority. An estimate is never added on top.",
            ru: "Измеренные значения (например, с Apple Watch) всегда важнее. Оценка никогда не прибавляется к ним."
        )
    }
    static var model: String {
        PaceLocalization.text(
            de: "Grundlage ist die ACSM-Gleichung für Gehen: etwa 0,5 kcal je Kilogramm Körpergewicht und Kilometer über dem Ruheumsatz. Die Strecke kommt aus Apple Health oder aus den automatisch erfassten Schritten und deiner Schrittlänge (≈ 41 % der Körpergröße). Steigungen und Laufen werden nicht eigens berücksichtigt.",
            en: "It's based on the ACSM walking equation: about 0.5 kcal per kilogram of body weight and kilometre above resting energy. The distance comes from Apple Health or from your automatically recorded steps and your stride length (≈ 41 % of your height). Inclines and running aren't accounted for separately.",
            ru: "Основа – формула ACSM для ходьбы: около 0,5 ккал на килограмм веса и километр сверх энергии покоя. Дистанция берётся из «Здоровья» или из автоматически записанных шагов и длины шага (≈ 41 % роста). Подъёмы и бег отдельно не учитываются."
        )
    }
    static var privacy: String {
        PaceLocalization.text(
            de: "Größe und Gewicht werden nur auf diesem iPhone gespeichert (wie andere App-Daten auch in deinen Gerätebackups und im Datenexport) und nie an Pace-Server, Freunde, Gruppen, Rankings oder Chats übertragen.",
            en: "Height and weight are stored only on this iPhone (like other app data, also in your device backups and the data export) and never sent to Pace servers, friends, groups, rankings or chats.",
            ru: "Рост и вес хранятся только на этом iPhone (как и другие данные приложения – также в резервных копиях устройства и в экспорте данных) и никогда не передаются на серверы Pace, друзьям, в группы, рейтинги или чаты."
        )
    }

    static func example(steps: String, energy: String) -> String {
        PaceLocalization.text(de: "Beispiel: \(steps) Schritte \(energy)", en: "Example: \(steps) steps \(energy)", ru: "Пример: \(steps) шагов \(energy)")
    }

    static var centimeters: String { PaceLocalization.text(de: "cm", en: "cm", ru: "см") }
    static var kilograms: String { PaceLocalization.text(de: "kg", en: "kg", ru: "кг") }
    static var done: String { PaceLocalization.text(de: "Fertig", en: "Done", ru: "Готово") }

    static func message(for error: BodyMetricsSettings.InputError, unit: String) -> String {
        switch error {
        case .notANumber:
            PaceLocalization.text(de: "Bitte eine Zahl eingeben.", en: "Please enter a number.", ru: "Введи число.")
        case .outOfRange(let range):
            PaceLocalization.text(
                de: "Bitte einen Wert zwischen \(Int(range.lowerBound)) und \(Int(range.upperBound)) \(unit) eingeben.",
                en: "Please enter a value between \(Int(range.lowerBound)) and \(Int(range.upperBound)) \(unit).",
                ru: "Введи значение от \(Int(range.lowerBound)) до \(Int(range.upperBound)) \(unit)."
            )
        }
    }
}
