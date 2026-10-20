import Foundation
import PaceCore

/// Texte von Kalender und Tagesdetails – in der Sprache der App (beim Zeichnen gelesen, nie eingefroren).
enum CalendarTexts {
    static var home: String { PaceLocalization.text(de: "Home", en: "Home", ru: "Главная") }
    static var title: String { PaceLocalization.text(de: "Kalender", en: "Calendar", ru: "Календарь") }
    static var goalReached: String { PaceLocalization.text(de: "Tagesziel erreicht", en: "Daily goal reached", ru: "Цель дня достигнута") }
    static var previousMonth: String { PaceLocalization.text(de: "Vorheriger Monat", en: "Previous month", ru: "Предыдущий месяц") }
    static var nextMonth: String { PaceLocalization.text(de: "Nächster Monat", en: "Next month", ru: "Следующий месяц") }
    static var loading: String { PaceLocalization.text(de: "Kalender wird geladen …", en: "Loading calendar …", ru: "Календарь загружается…") }
    static var openDetailsHint: String {
        PaceLocalization.text(de: "Öffnet die Tagesdetails.", en: "Opens the day details.", ru: "Открывает подробности дня.")
    }
    static var noAccessTitle: String {
        PaceLocalization.text(de: "Keine Schrittdaten lesbar", en: "No step data readable", ru: "Данные о шагах недоступны")
    }
    static var noAccessMessage: String { ActivityTexts.noReadAccessMessage }
    static var failedTitle: String {
        PaceLocalization.text(de: "Verlauf nicht verfügbar", en: "History unavailable", ru: "История недоступна")
    }
    static var retry: String { PaceLocalization.text(de: "Erneut versuchen", en: "Try again", ru: "Повторить") }

    // MARK: Tagesdetails

    static var dayDetailsTitle: String { PaceLocalization.text(de: "Tagesdetails", en: "Day details", ru: "Подробности дня") }
    static var dayDetailsLoading: String {
        PaceLocalization.text(de: "Tagesdetails werden geladen …", en: "Loading day details …", ru: "Подробности загружаются…")
    }
    static var hourlyTitle: String {
        PaceLocalization.text(de: "Aktivität im Tagesverlauf", en: "Activity throughout the day", ru: "Активность в течение дня")
    }
    static var hourlyFailed: String {
        PaceLocalization.text(
            de: "Die Stundenwerte konnten nicht geladen werden.",
            en: "The hourly values couldn't be loaded.",
            ru: "Не удалось загрузить почасовые данные."
        )
    }
    static var hourlyUnavailable: String {
        PaceLocalization.text(de: "Für diesen Tag liegen keine Daten vor.", en: "There is no data for this day.", ru: "Для этого дня нет данных.")
    }
    static var streakTitle: String { PaceLocalization.text(de: "Deine Streak", en: "Your streak", ru: "Твоя серия") }
    static var lastSevenDaysTitle: String {
        PaceLocalization.text(de: "Deine letzten 7 Tage", en: "Your last 7 days", ru: "Твои последние 7 дней")
    }
    static var heartRateSource: String {
        PaceLocalization.text(
            de: "Aus Apple Health · sofern verfügbar",
            en: "From Apple Health · if available",
            ru: "Из Apple Health · если доступно"
        )
    }
    static var showHeartRate: String {
        PaceLocalization.text(de: "Puls aus Apple Health anzeigen", en: "Show heart rate from Apple Health", ru: "Показать пульс из Apple Health")
    }
    static var showHeartRateDetail: String {
        PaceLocalization.text(
            de: "Ruhepuls und Ø Puls beim Gehen. Die Werte bleiben auf deinem iPhone.",
            en: "Resting and average walking heart rate. The values stay on your iPhone.",
            ru: "Пульс в покое и средний пульс при ходьбе. Данные остаются на твоём iPhone."
        )
    }
    static var heartRateRequestFailed: String {
        PaceLocalization.text(
            de: "Die Freigabe konnte nicht angefragt werden. Bitte versuche es erneut.",
            en: "Access couldn't be requested. Please try again.",
            ru: "Не удалось запросить доступ. Попробуй ещё раз."
        )
    }
    static var noHeartRate: String {
        PaceLocalization.text(
            de: "Für diesen Tag liegen keine Pulswerte vor. Du kannst den Zugriff in der Health-App unter „Datenschutz“ → „Apps“ → „Pace“ ändern.",
            en: "There are no heart rate values for this day. You can change access in the Health app under “Privacy” → “Apps” → “Pace”.",
            ru: "Для этого дня нет данных о пульсе. Доступ можно изменить в приложении «Здоровье»: «Конфиденциальность» → «Приложения» → «Pace»."
        )
    }
}
