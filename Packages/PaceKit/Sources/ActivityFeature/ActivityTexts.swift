import Foundation
import PaceCore

/// Gemeinsame Texte zu Bewegungsdaten – in der Sprache der App.
public enum ActivityTexts {
    /// Vorangestellt bei geschätzten Werten, z. B. `≈ 245 kcal`.
    public static let approximatelyPrefix = "≈ "

    /// Kennzeichnung gemessener aktiver Kalorien (Apple Health).
    public static var measuredActiveCalories: String {
        PaceLocalization.text(de: "Gemessen", en: "Measured", ru: "Измерено")
    }

    /// Kennzeichnung geschätzter aktiver Kalorien.
    public static var estimatedActiveCalories: String {
        PaceLocalization.text(de: "Geschätzte aktive Kalorien", en: "Estimated active calories", ru: "Расчётные активные калории")
    }

    /// Erklärung der Schätzung (Statistik, Tagesdetails).
    public static var activeEnergyEstimateNote: String {
        PaceLocalization.text(
            de: "≈ Geschätzte aktive Kalorien: Apple Health hat für diese Tage keine gemessenen Werte. Pace schätzt sie aus den automatisch erfassten Schritten bzw. der Strecke, deiner Größe und deinem Gewicht (Gehen auf ebener Strecke). Gemessene Werte haben immer Vorrang.",
            en: "≈ Estimated active calories: Apple Health has no measured values for these days. Pace estimates them from your automatically recorded steps or distance, your height and your weight (walking on level ground). Measured values always take priority.",
            ru: "≈ Расчётные активные калории: в «Здоровье» нет измеренных значений за эти дни. Pace оценивает их по автоматически записанным шагам или дистанции, твоему росту и весу (ходьба по ровной поверхности). Измеренные значения всегда имеют приоритет."
        )
    }

    /// Erklärung, wenn Apple Health für einen Tag keine aktiven Kalorien hat (und nicht geschätzt wird).
    public static var activeEnergyUnavailableNote: String {
        PaceLocalization.text(
            de: "Apple Health hat hierfür keine aktiven Kalorien. Ohne Apple Watch zeichnet das iPhone sie nur auf, wenn „Fitness-Tracking“ eingeschaltet ist und in der Health-App Angaben wie Größe und Gewicht hinterlegt sind – teils mit Verzögerung. Ohne Messwerte kann Pace aktive Kalorien schätzen: Profil → Einstellungen → Aktivität & Gesundheit → Kalorienschätzung.",
            en: "Apple Health has no active calories for this. Without an Apple Watch, the iPhone only records them if “Fitness Tracking” is on and details such as height and weight are set in the Health app – sometimes with a delay. Without measured values, Pace can estimate active calories: Profile → Settings → Activity & health → Calorie estimate.",
            ru: "В приложении «Здоровье» нет активных калорий за этот период. Без Apple Watch iPhone записывает их, только если включено «Отслеживание фитнеса» и в «Здоровье» указаны рост и вес, – иногда с задержкой. Без измерений Pace может рассчитать активные калории: Профиль → Настройки → Активность и здоровье → Оценка калорий."
        )
    }

    /// Stundenwerte gibt es nur für gemessene aktive Kalorien (Tagesansicht eines geschätzten Tages).
    public static var hourlyEnergyEstimatedNote: String {
        PaceLocalization.text(
            de: "Für geschätzte Kalorien gibt es keine Stundenwerte – nur für gemessene aus Apple Health.",
            en: "There are no hourly values for estimated calories – only for measured ones from Apple Health.",
            ru: "Для расчётных калорий нет почасовых данных – только для измеренных в «Здоровье»."
        )
    }

    /// „Nicht verfügbar“ für fehlende Gesundheitswerte (statt einer falschen 0).
    public static var notAvailable: String {
        PaceLocalization.text(de: "Nicht verfügbar", en: "Not available", ru: "Нет данных")
    }

    public static var manualStepsNote: String {
        PaceLocalization.text(
            de: "Manuell eingetragene Schritte zählen nicht für Rankings.",
            en: "Manually entered steps don't count for rankings.",
            ru: "Шаги, введённые вручную, не учитываются в рейтингах."
        )
    }

    /// „8.432 Schritte“ / „8,432 steps“ / „8 432 шага“ – Zahl im Format von `formatter`, Wort in der passenden
    /// Pluralform der App-Sprache.
    public static func steps(_ count: Int, formatter: ActivityFormatter) -> String {
        "\(formatter.steps(count)) \(stepsWord(count))"
    }

    /// Nur das Wort, passend zur Zahl: `Schritt` / `Schritte`, `step` / `steps`, `шаг` / `шага` / `шагов`.
    public static func stepsWord(_ count: Int) -> String {
        PaceLocalization.plural(count, de: ("Schritt", "Schritte"), en: ("step", "steps"), ru: ("шаг", "шага", "шагов"))
    }

    /// „5 Tage“ / „5 days“ / „5 дней“.
    public static func days(_ count: Int) -> String {
        PaceLocalization.days(count)
    }

    /// Hinweis, wenn eine Kennzahl gar nicht lesbar ist.
    static var noReadAccessMessage: String {
        PaceLocalization.text(
            de: "Pace hat keinen Zugriff auf deine Schritte. Erlaube den Zugriff in der Health-App unter „Datenschutz“ → „Apps“ → „Pace“.",
            en: "Pace can't read your steps. Allow access in the Health app under “Privacy” → “Apps” → “Pace”.",
            ru: "У Pace нет доступа к твоим шагам. Разреши доступ в приложении «Здоровье»: «Конфиденциальность» → «Приложения» → «Pace»."
        )
    }

    /// Verlauf konnte nicht geladen werden.
    static var historyFailedMessage: String {
        PaceLocalization.text(
            de: "Der Verlauf konnte nicht geladen werden. Bitte versuche es erneut.",
            en: "Your history couldn't be loaded. Please try again.",
            ru: "Не удалось загрузить историю. Попробуй ещё раз."
        )
    }
}
