import ActivityFeature
import Foundation
import PaceCore

/// Wiederkehrende Texte des Home-Dashboards in Deutsch, Englisch und Russisch. Alle Werte sind berechnet, damit sie
/// einem Sprachwechsel sofort folgen.
public enum HomeTexts {
    /// z. B. `3 von 4 Ebenen sichtbar`.
    public static func visibleLevels(_ count: Int, of total: Int) -> String {
        PaceLocalization.text(
            de: "\(count) von \(total) Ebenen sichtbar",
            en: "\(count) of \(total) levels shown",
            ru: "Показано уровней: \(count) из \(total)"
        )
    }

    /// z. B. `Ziel an 4 von 6 Tagen erreicht`.
    public static func goalReachedOnDays(_ reached: Int, of total: Int) -> String {
        PaceLocalization.text(
            de: "Ziel an \(reached) von \(total) Tagen erreicht",
            en: "Goal reached on \(reached) of \(total) days",
            ru: "Цель выполнена в \(reached) из \(total) " + PaceLocalization.plural(total, de: ("", ""), en: ("", ""), ru: ("дня", "дней", "дней"))
        )
    }

    public static var lastSevenDays: String {
        PaceLocalization.text(de: "Letzte 7 Tage", en: "Last 7 days", ru: "Последние 7 дней")
    }

    public static var showAllLevels: String {
        PaceLocalization.text(de: "Alle vier zeigen", en: "Show all four", ru: "Показать все четыре")
    }

    public static var levelToggleHint: String {
        PaceLocalization.text(
            de: "Tippe auf eine Ebene, um ihre Karte ein- oder auszublenden. Mindestens eine bleibt.",
            en: "Tap a level to show or hide its card. At least one stays.",
            ru: "Нажми на уровень, чтобы показать или скрыть его карточку. Минимум одна остаётся."
        )
    }

    public static var customize: String {
        PaceLocalization.text(de: "Anpassen", en: "Customize", ru: "Настроить")
    }

    public static var done: String {
        PaceLocalization.text(de: "Fertig", en: "Done", ru: "Готово")
    }

    public static var addWidget: String {
        PaceLocalization.text(de: "Widget hinzufügen", en: "Add widget", ru: "Добавить виджет")
    }

    public static var editWidget: String {
        PaceLocalization.text(de: "Widget bearbeiten", en: "Edit widget", ru: "Изменить виджет")
    }

    public static var editHint: String {
        PaceLocalization.text(
            de: "Halten und verschieben, um deine Übersicht anzupassen.",
            en: "Press, hold and drag to arrange your overview.",
            ru: "Удерживай и перетаскивай, чтобы настроить обзор."
        )
    }

    public static var chooseSize: String {
        PaceLocalization.text(de: "Größe auswählen", en: "Choose size", ru: "Выбрать размер")
    }

    public static var calendar: String {
        PaceLocalization.text(de: "Kalender", en: "Calendar", ru: "Календарь")
    }

    public static var notifications: String {
        PaceLocalization.text(de: "Mitteilungen", en: "Notifications", ru: "Уведомления")
    }

    public static var home: String {
        PaceLocalization.text(de: "Home", en: "Home", ru: "Главная")
    }

    public static var you: String {
        PaceLocalization.text(de: "DU", en: "YOU", ru: "ТЫ")
    }

    public static var dailyGoalChange: String {
        PaceLocalization.text(de: "Tagesziel ändern", en: "Change daily goal", ru: "Изменить цель")
    }

    public static var retry: String {
        PaceLocalization.text(de: "Erneut versuchen", en: "Try again", ru: "Повторить")
    }

    public static var loading: String {
        PaceLocalization.text(de: "Wird geladen …", en: "Loading …", ru: "Загрузка …")
    }

    public static var manualStepsNote: String {
        PaceLocalization.text(
            de: "Manuell eingetragene Schritte zählen nicht für Rankings.",
            en: "Manually entered steps don't count for rankings.",
            ru: "Шаги, введённые вручную, не учитываются в рейтингах."
        )
    }

    public static var rankingOffTitle: String {
        PaceLocalization.text(de: "Ranking ausgeschaltet", en: "Ranking turned off", ru: "Рейтинг выключен")
    }

    public static var rankingOffMessage: String {
        PaceLocalization.text(
            de: "Aktiviere deine Ranking-Sichtbarkeit, um deine Platzierungen zu sehen.",
            en: "Turn on your ranking visibility to see your positions.",
            ru: "Включи видимость в рейтингах, чтобы видеть свои места."
        )
    }

    public static var enableRankingVisibility: String {
        PaceLocalization.text(
            de: "Ranking-Sichtbarkeit aktivieren",
            en: "Turn on ranking visibility",
            ru: "Включить видимость в рейтингах"
        )
    }

    public static var enableRankingVisibilityMessage: String {
        PaceLocalization.text(
            de: "Du erscheinst dann mit deinem Anzeigenamen und deinen Wettbewerbsschritten in den regionalen "
                + "Rankings. Du kannst das jederzeit im Profil wieder ausschalten.",
            en: "You'll then appear in regional rankings with your display name and competition steps. "
                + "You can turn this off in your profile at any time.",
            ru: "Тогда ты будешь отображаться в региональных рейтингах со своим именем и шагами. "
                + "Это можно в любой момент выключить в профиле."
        )
    }

    public static var cancel: String {
        PaceLocalization.text(de: "Abbrechen", en: "Cancel", ru: "Отмена")
    }

    public static var undo: String {
        PaceLocalization.text(de: "Rückgängig", en: "Undo", ru: "Отменить")
    }

    /// z. B. „„Deine Woche“ entfernt“.
    public static func removed(_ title: String) -> String {
        PaceLocalization.text(de: "„\(title)“ entfernt", en: "“\(title)” removed", ru: "Виджет «\(title)» удалён")
    }

    /// Begrüßung, z. B. `Hi Niklas`.
    public static func greeting(_ firstName: String) -> String {
        guard !firstName.isEmpty else {
            return PaceLocalization.text(de: "Hi", en: "Hi", ru: "Привет")
        }
        return PaceLocalization.text(de: "Hi \(firstName)", en: "Hi \(firstName)", ru: "Привет, \(firstName)")
    }

    /// VoiceOver-Name eines Widgets im Bearbeitungsmodus.
    public static func remove(_ title: String) -> String {
        PaceLocalization.text(de: "„\(title)“ entfernen", en: "Remove “\(title)”", ru: "Удалить «\(title)»")
    }

    public static var moveUp: String {
        PaceLocalization.text(de: "Nach oben verschieben", en: "Move up", ru: "Переместить вверх")
    }

    public static var moveDown: String {
        PaceLocalization.text(de: "Nach unten verschieben", en: "Move down", ru: "Переместить вниз")
    }

    /// z. B. `Größe: Mittel`.
    public static func size(_ size: HomeModuleSize) -> String {
        PaceLocalization.text(de: "Größe: \(size.title)", en: "Size: \(size.title)", ru: "Размер: \(size.title)")
    }
}

/// Formatierung, die das Home-Dashboard zusätzlich zum `ActivityFormatter` braucht.
public enum HomeFormat {
    /// Erster Buchstabe des Wochentags in der Sprache des Formatierers, z. B. `M` für Montag.
    public static func weekdayLetter(_ day: LocalDate, formatter: ActivityFormatter) -> String {
        let style = Date.FormatStyle(locale: formatter.locale, calendar: formatter.calendar.calendar, timeZone: formatter.calendar.timeZone)
            .weekday(.narrow)
        return formatter.calendar.startOfDay(day).formatted(style)
    }

    /// Tag im Monat, z. B. `16`.
    public static func dayNumber(_ day: LocalDate) -> String {
        day.day.formatted(.number.locale(PaceLocalization.shared.locale))
    }
}
