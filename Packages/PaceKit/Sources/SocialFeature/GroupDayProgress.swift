import Foundation
import PaceCore

/// Tagesfortschritt einer Gruppe für die kombinierte Gruppenkarte (Gruppeninfo, Gruppenchat, Home-Widget).
///
/// Nur Werte aus der vorhandenen ``GroupSummary`` – keine zusätzliche Abfrage. Wie viele Ziele die Flamme heute braucht
/// (mindestens ein Drittel der Mitglieder, aufgerundet: ⌈n/3⌉), kommt vom Server (`todayRequiredCount`).
public struct GroupDayProgress: Equatable, Sendable {
    /// Mitglieder, die heute ihr Tagesziel erreicht haben.
    public let reached: Int
    public let members: Int
    /// Für die heutige Gruppenflamme nötige Ziele (⌈n/3⌉).
    public let required: Int
    /// Laufende Gruppenflamme in Tagen.
    public let streak: Int
    /// Die Flamme ist für heute gesichert.
    public let isSecured: Bool

    public init(reached: Int, members: Int, required: Int, streak: Int, isSecured: Bool) {
        self.members = max(members, 0)
        self.reached = min(max(reached, 0), self.members)
        self.required = max(required, 0)
        self.streak = max(streak, 0)
        self.isSecured = isSecured
    }

    public init(group: GroupSummary) {
        self.init(
            reached: group.todayReachedCount,
            members: group.memberCount,
            required: group.todayRequiredCount,
            streak: group.currentStreak,
            isSecured: group.todayComplete
        )
    }

    /// Anteil der Mitglieder mit erreichtem Ziel (0…1) – der Balken.
    public var progress: Double {
        members > 0 ? Double(reached) / Double(members) : 0
    }

    /// Position der Flammen-Schwelle auf dem Balken (0…1); `nil`, wenn es keine sinnvolle Schwelle gibt.
    public var thresholdFraction: Double? {
        guard members > 0, required > 0, required < members else { return nil }
        return Double(required) / Double(members)
    }

    /// Die Flamme brennt (laufende Serie).
    public var isFlameLit: Bool {
        streak > 0
    }

    /// Ziele, die heute noch fehlen.
    public var missing: Int {
        max(required - reached, 0)
    }

    /// z. B. „4 von 12 Mitgliedern haben das Tagesziel erreicht“.
    public var reachedText: String {
        let reachedText = reached.paceFormatted
        let membersText = members.paceFormatted
        return PaceLocalization.plural(
            reached,
            de: (
                "\(reachedText) von \(membersText) Mitgliedern hat das Tagesziel erreicht",
                "\(reachedText) von \(membersText) Mitgliedern haben das Tagesziel erreicht"
            ),
            en: (
                "\(reachedText) of \(membersText) members reached the daily goal",
                "\(reachedText) of \(membersText) members reached the daily goal"
            ),
            ru: (
                "\(reachedText) из \(membersText) \(Self.russianMembersGenitive(members)) выполнил дневную цель",
                "\(reachedText) из \(membersText) \(Self.russianMembersGenitive(members)) выполнили дневную цель",
                "\(reachedText) из \(membersText) \(Self.russianMembersGenitive(members)) выполнили дневную цель"
            )
        )
    }

    /// Zahl neben der Flamme, z. B. `12`.
    public var streakText: String {
        streak.paceFormatted
    }

    /// Hinweis unter dem Balken nach der ⌈n/3⌉-Regel, z. B. „Noch 1 Mitglied bis zur heutigen Gruppenflamme“ oder
    /// „Gruppenflamme für heute gesichert“; `nil` ohne Mitglieder.
    public var hint: String? {
        guard members > 0 else { return nil }
        if isSecured || (required > 0 && reached >= required) {
            return PaceLocalization.text(
                de: "Gruppenflamme für heute gesichert",
                en: "Group flame secured for today",
                ru: "Огонь группы на сегодня сохранён"
            )
        }
        // Ohne Serverwert für die nötigen Ziele kein Hinweis – nie eine erfundene Zahl.
        guard required > 0 else { return nil }
        let count = max(missing, 1)
        let number = count.paceFormatted
        return PaceLocalization.plural(
            count,
            de: ("Noch \(number) Mitglied bis zur heutigen Gruppenflamme", "Noch \(number) Mitglieder bis zur heutigen Gruppenflamme"),
            en: ("\(number) more member for today's group flame", "\(number) more members for today's group flame"),
            ru: (
                "Ещё \(number) участник – и огонь группы на сегодня сохранён",
                "Ещё \(number) участника – и огонь группы на сегодня сохранён",
                "Ещё \(number) участников – и огонь группы на сегодня сохранён"
            )
        )
    }

    /// Für VoiceOver: Fortschritt, Flamme und Hinweis.
    public var accessibilityLabel: String {
        let flame = PaceLocalization.text(
            de: "Gruppenflamme \(PaceLocalization.days(streak))",
            en: "Group flame \(PaceLocalization.days(streak))",
            ru: "Огонь группы: \(PaceLocalization.days(streak))"
        )
        return [reachedText, flame, hint].compactMap { $0 }.joined(separator: ", ")
    }

    /// „участника“ nach „из 1/21/31 …“, sonst „участников“ (Genitiv).
    static func russianMembersGenitive(_ count: Int) -> String {
        count % 10 == 1 && count % 100 != 11 ? "участника" : "участников"
    }
}
