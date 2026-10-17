import Foundation

/// Synchronisiert die Wettbewerbsschritte der letzten 7 Tage – sparsam: Der Server wird nie abgefragt, gesendet wird
/// nur, was sich geändert hat.
///
/// - Es werden nur Tage gesendet, deren Wert sich seit dem letzten erfolgreichen Sync geändert hat.
/// - HealthKit-Updates werden gedrosselt (`minimumInterval`); zurückgehaltene Werte gehen beim nächsten Anlass
///   oder bei `flush()` raus. App-Start, Rückkehr in die App und Pull-to-Refresh senden sofort.
/// - Fehler werden nicht angezeigt: Die Werte bleiben ausstehend und werden beim nächsten Anlass erneut gesendet.
public actor ActivitySyncCoordinator: ActivitySyncing {
    public enum Status: Equatable, Sendable {
        case idle
        case synced(at: Date)
        case failed(ActivitySyncError)
    }

    private let repository: any ActivitySyncRepository
    private let userID: UserID
    private let minimumInterval: TimeInterval
    private let now: @Sendable () -> Date

    /// Zuletzt erfolgreich übertragene Werte je Tag.
    private var synced: [LocalDate: Int] = [:]
    /// Noch nicht übertragene Werte je Tag.
    private var pending: [LocalDate: Int] = [:]
    private var lastAttempt: Date?
    private var lastSubmittedAt: Date?
    /// Der laufende Upload, damit `flush()` auf ihn warten kann.
    private var inFlight: Task<Void, Never>?

    public private(set) var status: Status = .idle

    public init(
        repository: any ActivitySyncRepository,
        userID: UserID,
        minimumInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.userID = userID
        self.minimumInterval = minimumInterval
        self.now = now
    }

    public func submit(_ overview: ActivityOverview, trigger: ActivitySyncTrigger) async {
        // Übergaben können in anderer Reihenfolge eintreffen; ein älterer Stand darf einen neueren nie überschreiben.
        if let lastSubmittedAt, overview.updatedAt < lastSubmittedAt {
            return
        }
        lastSubmittedAt = overview.updatedAt

        for day in overview.lastSevenDays.days {
            let steps = min(max(day.competitionSteps, 0), DailyCompetitionSteps.maximumSteps)
            if synced[day.date] == steps {
                pending[day.date] = nil
            } else {
                pending[day.date] = steps
            }
        }
        // Nur die letzten 7 Tage vorhalten; ältere Tage akzeptiert der Server ohnehin nicht mehr.
        let window = Set(overview.lastSevenDays.days.map(\.date))
        synced = synced.filter { window.contains($0.key) }
        pending = pending.filter { window.contains($0.key) }

        if trigger == .healthKitUpdate, let lastAttempt, now().timeIntervalSince(lastAttempt) < minimumInterval {
            return
        }
        await send()
    }

    /// Wartet auf einen laufenden Upload und sendet danach alles, was noch aussteht.
    public func flush() async {
        while let inFlight {
            await inFlight.value
        }
        await send()
    }

    /// Aktuell ausstehende Tage (für Tests und Diagnose).
    public var pendingDays: [DailyCompetitionSteps] {
        pending
            .map { DailyCompetitionSteps(date: $0.key, competitionSteps: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// Startet einen Upload, falls Werte ausstehen und gerade keiner läuft. Während eines Uploads geänderte Werte
    /// bleiben ausstehend und gehen beim nächsten Anlass bzw. bei `flush()` raus.
    private func send() async {
        guard !pending.isEmpty, inFlight == nil else { return }
        let task = Task {
            await upload()
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func upload() async {
        let batch = pending
        let days = batch
            .map { DailyCompetitionSteps(date: $0.key, competitionSteps: $0.value) }
            .sorted { $0.date < $1.date }
        lastAttempt = now()

        do {
            try await repository.upsert(days, for: userID)
            for (date, steps) in batch {
                synced[date] = steps
                // Nur entfernen, wenn sich der Wert während des Sendens nicht erneut geändert hat.
                if pending[date] == steps {
                    pending[date] = nil
                }
            }
            status = .synced(at: now())
        } catch let error as ActivitySyncError {
            status = .failed(error)
        } catch {
            status = .failed(.unexpected(String(describing: error)))
        }
    }
}
