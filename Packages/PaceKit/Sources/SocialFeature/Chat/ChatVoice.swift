import AVFoundation
import DesignSystem
import PaceCore
import SwiftUI

// MARK: - Audio-Sitzung

/// Die gemeinsame Audio-Sitzung für Aufnahme und Wiedergabe (siehe ``ChatAudioSessionOwnership``): Nur wer sie
/// aktiviert hat, deaktiviert sie wieder – das Stoppen der Wiedergabe beendet so nie eine laufende Aufnahme.
@MainActor
enum ChatAudioSession {
    private static var ownership = ChatAudioSessionOwnership()

    static func activate(
        for owner: ChatAudioSessionOwnership.Owner,
        category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions = []
    ) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(category, mode: mode, options: options)
        try session.setActive(true)
        ownership.take(owner)
    }

    static func release(_ owner: ChatAudioSessionOwnership.Owner) {
        guard ownership.release(owner) else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Wiedergabe

/// Spielt Sprachnachrichten ab – immer nur eine gleichzeitig (eine Instanz je Chat). Unterbrechungen (Anruf, andere
/// App) pausieren die Wiedergabe; beim Verlassen des Chats endet sie.
@MainActor
@Observable
final class ChatVoicePlayer {
    /// Nachricht (bzw. Vorschau), die gerade geladen ist.
    private(set) var currentID: UUID?
    private(set) var isPlaying = false
    /// Fortschritt 0…1 und vergangene Zeit der aktuellen Nachricht.
    private(set) var progress: Double = 0
    private(set) var elapsed: TimeInterval = 0
    /// Wird gerade geladen.
    private(set) var loadingID: UUID?
    /// Konnte nicht geladen bzw. abgespielt werden.
    private(set) var failedID: UUID?
    /// Während einer Aufnahme gesperrt (ein Wechsel der Audio-Sitzung würde die Aufnahme beenden).
    var isBlocked = false {
        didSet { if isBlocked { stop() } }
    }

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Startet bzw. pausiert die Wiedergabe; beim ersten Antippen werden die Daten geladen.
    func toggle(_ id: UUID, load: @escaping @MainActor () async -> Data?) async {
        guard !isBlocked else { return }
        if currentID == id, let player {
            if player.isPlaying {
                pause()
            } else {
                resume()
            }
            return
        }
        stop()
        loadingID = id
        failedID = nil
        let data = await load()
        // Inzwischen etwas anderes angetippt oder den Chat verlassen.
        guard loadingID == id else { return }
        loadingID = nil
        guard let data, let player = try? AVAudioPlayer(data: data) else {
            failedID = id
            return
        }
        activateSession()
        self.player = player
        currentID = id
        player.prepareToPlay()
        player.play()
        isPlaying = true
        startTicker()
    }

    /// Springt an eine Stelle (0…1) der gerade geladenen Nachricht.
    func seek(_ id: UUID, to fraction: Double) {
        guard currentID == id, let player, player.duration > 0 else { return }
        player.currentTime = min(max(fraction, 0), 1) * player.duration
        update()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
        ticker = nil
        update()
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        currentID = nil
        loadingID = nil
        isPlaying = false
        progress = 0
        elapsed = 0
        deactivateSession()
    }

    private func resume() {
        guard let player else { return }
        activateSession()
        player.play()
        isPlaying = true
        startTicker()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.update()
            }
        }
    }

    private func update() {
        guard let player else { return }
        if isPlaying, !player.isPlaying {
            // Zu Ende gespielt.
            stop()
            return
        }
        elapsed = player.currentTime
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
    }

    private func activateSession() {
        try? ChatAudioSession.activate(for: .player, category: .playback, mode: .spokenAudio)
    }

    /// Gibt die Sitzung nur ab, wenn die Wiedergabe sie hält – eine laufende Aufnahme bleibt unberührt.
    private func deactivateSession() {
        ChatAudioSession.release(.player)
    }
}

// MARK: - Aufnahme

/// Nimmt eine Sprachnachricht auf (AAC in .m4a, mono). Gedrückt halten nimmt auf, nach oben wischen sperrt, nach links
/// wischen verwirft; nach dem Loslassen bzw. „Stopp“ folgt eine Vorschau – gesendet wird nie ohne Bestätigung. Die
/// Datei bleibt bis zum Senden auf dem Gerät und wird danach bzw. beim Verwerfen gelöscht.
@MainActor
@Observable
final class ChatVoiceRecorder {
    enum Phase: Equatable {
        case idle
        /// Läuft; `locked`: ohne Festhalten (Senden, Stopp, Verwerfen als Knöpfe).
        case recording(locked: Bool)
        /// Fertig aufgenommen – anhören, senden oder verwerfen.
        case preview
    }

    /// Kürzere Aufnahmen gelten als versehentliches Antippen und werden verworfen.
    static let minimumDuration: TimeInterval = 1
    static let maximumDuration: TimeInterval = ChatRules.maximumVoiceDuration.timeInterval

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0
    /// Lautstärke 0…1 für die Anzeige.
    private(set) var level: Double = 0
    /// Hinweis nach einem Problem (zu kurz, kein Mikrofon, Fehler).
    private(set) var hint: String?
    /// Kennung der Vorschau für die Wiedergabe.
    let previewID = UUID()

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var recordedDuration: TimeInterval = 0
    @ObservationIgnored private var ticker: Task<Void, Never>?

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var isLocked: Bool { phase == .recording(locked: true) }

    /// Dauer der fertigen Aufnahme.
    var duration: TimeInterval { phase == .preview ? recordedDuration : elapsed }

    /// Beginnt die Aufnahme. Beim ersten Mal fragt iOS nach dem Mikrofon – dann beginnt noch nichts (der Finger ist
    /// danach meist schon weg); beim nächsten Halten geht es los.
    /// - Returns: `true`, wenn die Aufnahme läuft.
    @discardableResult
    func start() async -> Bool {
        guard phase == .idle else { return false }
        hint = nil
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            hint = granted ? ChatUIText.voiceHoldToRecord : ChatUIText.voiceMicrophoneDenied
            return false
        case .denied:
            hint = ChatUIText.voiceMicrophoneDenied
            return false
        default:
            break
        }
        do {
            try ChatAudioSession.activate(for: .recorder, category: .playAndRecord, mode: .default, options: [.defaultToSpeaker])
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pace-voice-\(UUID().uuidString.lowercased())")
                .appendingPathExtension("m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: Self.maximumDuration) else {
                throw CocoaError(.fileWriteUnknown)
            }
            self.recorder = recorder
            fileURL = url
            elapsed = 0
            level = 0
            phase = .recording(locked: false)
            startTicker()
            return true
        } catch {
            cleanUp()
            hint = ChatTexts.voiceRecordingFailed
            return false
        }
    }

    /// Nach oben gewischt: weiter aufnehmen, ohne festzuhalten.
    func lock() {
        guard phase == .recording(locked: false) else { return }
        phase = .recording(locked: true)
    }

    /// Losgelassen bzw. „Stopp“: Aufnahme beenden und als Vorschau anbieten (zu kurze werden verworfen).
    func finish() {
        guard isRecording, let recorder else { return }
        // Hat der Rekorder schon selbst gestoppt (Höchstdauer, System), ist `currentTime` 0 – dann zählt der letzte
        // gemessene Stand, damit eine volle Aufnahme nicht als „zu kurz“ verworfen wird.
        let measured = recorder.isRecording ? recorder.currentTime : 0
        recordedDuration = min(max(measured, elapsed), Self.maximumDuration)
        recorder.stop()
        ticker?.cancel()
        ticker = nil
        level = 0
        deactivateSession()
        if recordedDuration < Self.minimumDuration {
            deleteFile()
            phase = .idle
            hint = ChatUIText.voiceHoldToRecord
        } else {
            phase = .preview
        }
    }

    /// Verwerfen (nach links gewischt, Papierkorb oder Chat verlassen): Datei löschen, nichts wird hochgeladen.
    func cancel() {
        guard phase != .idle else { return }
        recorder?.stop()
        cleanUp()
    }

    /// Unterbrechung (Anruf, App im Hintergrund): Laufende Aufnahme beenden und als Vorschau behalten.
    func interrupt() {
        if isRecording {
            finish()
        }
    }

    /// Fertige Aufnahme zum Senden übernehmen; danach ist der Rekorder wieder frei und die Datei gelöscht.
    func takeRecording() -> (data: Data, duration: Duration)? {
        if isRecording { finish() }
        guard phase == .preview, let fileURL, let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            if phase == .preview { hint = ChatTexts.voiceRecordingFailed }
            cleanUp()
            return nil
        }
        let duration = Duration.milliseconds(Int((recordedDuration * 1_000).rounded()))
        cleanUp()
        return (data, duration)
    }

    /// Daten der Vorschau zum Anhören.
    func previewData() -> Data? {
        guard phase == .preview, let fileURL else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    func clearHint() {
        hint = nil
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isRecording, let recorder else { return }
        guard recorder.isRecording else {
            // Höchstdauer erreicht (oder vom System beendet): als Vorschau anbieten.
            finish()
            return
        }
        elapsed = recorder.currentTime
        recorder.updateMeters()
        // −50 dB (leise) … 0 dB (laut) auf 0…1.
        let power = Double(recorder.averagePower(forChannel: 0))
        level = min(max((power + 50) / 50, 0), 1)
    }

    private func cleanUp() {
        ticker?.cancel()
        ticker = nil
        recorder = nil
        deleteFile()
        phase = .idle
        elapsed = 0
        level = 0
        recordedDuration = 0
        deactivateSession()
    }

    private func deleteFile() {
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
    }

    /// Gibt die Sitzung nur ab, wenn die Aufnahme sie hält (z. B. nicht während die Vorschau abgespielt wird).
    private func deactivateSession() {
        ChatAudioSession.release(.recorder)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

// MARK: - Blase

/// Sprachnachricht im Verlauf: Abspielen/Pause, Fortschritt (antippen springt), Dauer bzw. vergangene Zeit.
struct ChatVoiceBubble: View {
    let id: UUID
    let duration: Duration?
    let isOwn: Bool
    /// Lädt die Audiodaten (`nil`: noch nicht abspielbar, z. B. während des Hochladens).
    let load: (@MainActor () async -> Data?)?

    @Environment(ChatVoicePlayer.self) private var player: ChatVoicePlayer?

    private var isCurrent: Bool { player?.currentID == id }
    private var isPlaying: Bool { isCurrent && player?.isPlaying == true }
    private var progress: Double { isCurrent ? (player?.progress ?? 0) : 0 }

    var body: some View {
        HStack(spacing: PaceSpacing.s) {
            Button {
                guard let player, let load else { return }
                Task { await player.toggle(id, load: load) }
            } label: {
                ZStack {
                    if player?.loadingID == id {
                        ProgressView()
                            .tint(foreground)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(isOwn ? PaceColor.selectionFill : PaceColor.onAccent)
                .frame(width: 40, height: 40)
                .background(isOwn ? PaceColor.onSelection : PaceColor.actionFill, in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.pacePressable)
            .disabled(load == nil || player == nil || player?.isBlocked == true)
            .accessibilityLabel(isPlaying ? ChatUIText.voicePause : ChatUIText.voicePlay)

            VStack(alignment: .leading, spacing: 6) {
                track
                Text(timeText)
                    .font(PaceFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(foreground.opacity(0.8))
            }
            .frame(width: 140, alignment: .leading)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(
            isOwn ? PaceColor.selectionFill : PaceColor.fieldBackground,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(alignment: .bottomTrailing) {
            if player?.failedID == id {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(PaceColor.danger)
                    .padding(6)
                    .accessibilityLabel(ChatUIText.voiceUnavailable)
            }
        }
    }

    private var foreground: Color {
        isOwn ? PaceColor.onSelection : PaceColor.textPrimary
    }

    private var timeText: String {
        let total = duration.map(ChatFormatting.voiceDuration) ?? "–"
        guard isCurrent, let player, player.elapsed > 0 else { return total }
        return ChatFormatting.voiceDuration(.milliseconds(Int(player.elapsed * 1_000))) + " / " + total
    }

    private var track: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(foreground.opacity(0.22))
                Capsule()
                    .fill(foreground)
                    .frame(width: max(4, geometry.size.width * progress))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            // Antippen springt (kein Ziehen – das würde das Scrollen des Verlaufs blockieren).
            .onTapGesture { location in
                guard isCurrent, geometry.size.width > 0 else { return }
                player?.seek(id, to: location.x / geometry.size.width)
            }
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel(ChatUIText.voicePosition)
        .accessibilityValue(Text(verbatim: "\(Int((progress * 100).rounded())) %"))
        .accessibilityAdjustableAction { direction in
            guard isCurrent else { return }
            let step = direction == .increment ? 0.1 : -0.1
            player?.seek(id, to: progress + step)
        }
    }
}

// MARK: - Aufnahme in der Eingabeleiste

/// Anzeige während der Aufnahme bzw. der Vorschau (statt des Textfelds).
struct ChatVoiceRecordingRow: View {
    let recorder: ChatVoiceRecorder
    let player: ChatVoicePlayer
    /// Wie weit der Finger nach links gewischt ist (0…1 bis zum Verwerfen).
    let cancelProgress: Double
    let onDiscard: () -> Void
    let onStop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch recorder.phase {
        case .idle:
            EmptyView()
        case .recording(let locked):
            HStack(spacing: PaceSpacing.s) {
                Circle()
                    .fill(PaceColor.danger)
                    .frame(width: 10, height: 10)
                    .scaleEffect(reduceMotion ? 1 : 0.8 + recorder.level * 0.5)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: recorder.level)
                    .accessibilityHidden(true)
                Text(ChatFormatting.voiceDuration(.milliseconds(Int(recorder.elapsed * 1_000))))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(PaceColor.textPrimary)
                    .accessibilityLabel(ChatUIText.voiceRecording(ChatFormatting.voiceDuration(.milliseconds(Int(recorder.elapsed * 1_000)))))
                Spacer(minLength: PaceSpacing.xs)
                if locked {
                    iconButton("trash", label: ChatUIText.voiceDiscard, tint: PaceColor.danger, action: onDiscard)
                    iconButton("stop.fill", label: ChatUIText.voiceStop, tint: PaceColor.textPrimary, action: onStop)
                } else {
                    Label(ChatUIText.voiceSlideToCancel, systemImage: "chevron.left")
                        .font(PaceFont.caption)
                        .foregroundStyle(PaceColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(1 - cancelProgress * 0.7)
                        .offset(x: -cancelProgress * 40)
                }
            }
            .padding(.horizontal, PaceSpacing.m)
            .frame(minHeight: 44)
            .background(PaceColor.fieldBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if !locked {
                    // Hinweis zum Sperren: nach oben wischen.
                    Image(systemName: "lock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PaceColor.textSecondary)
                        .padding(8)
                        .background(PaceColor.surface, in: Circle())
                        .overlay(Circle().strokeBorder(PaceColor.border, lineWidth: 1))
                        .offset(x: 46, y: -44)
                        .accessibilityLabel(ChatUIText.voiceLockHint)
                }
            }
        case .preview:
            HStack(spacing: PaceSpacing.xs) {
                iconButton("trash", label: ChatUIText.voiceDiscard, tint: PaceColor.danger, action: onDiscard)
                ChatVoiceBubble(
                    id: recorder.previewID,
                    duration: .milliseconds(Int(recorder.duration * 1_000)),
                    isOwn: false,
                    load: { [recorder] in recorder.previewData() }
                )
                .environment(player)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        }
    }

    private func iconButton(_ systemImage: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pacePressable)
        .accessibilityLabel(label)
    }
}
