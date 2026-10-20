import Foundation
import PaceCore

/// Gemeinsame Texte zu Bewegungsdaten – in der Sprache der App.
public enum ActivityTexts {
    /// Hinweis, wenn Health- und Wettbewerbsschritte abweichen.
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
