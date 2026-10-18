import Foundation
import PaceCore

/// Zeichnet Icon-Wechsel auf, ohne das System zu berühren.
public final class AppIconSettingStub: AppIconSetting, Sendable {
    public struct State: Sendable {
        public var supportsAlternateIcons = true
        public var currentAlternateIconName: String?
        public var error: (any Error & Sendable)?
        public var requestedNames: [String?] = []
    }

    public let state: Locked<State>

    public init(configure: (inout State) -> Void = { _ in }) {
        var state = State()
        configure(&state)
        self.state = Locked(state)
    }

    public var supportsAlternateIcons: Bool {
        state.withLock { $0.supportsAlternateIcons }
    }

    public var currentAlternateIconName: String? {
        state.withLock { $0.currentAlternateIconName }
    }

    public func setAlternateIconName(_ name: String?) async throws {
        try state.withLock { state in
            state.requestedNames.append(name)
            if let error = state.error { throw error }
            state.currentAlternateIconName = name
        }
    }
}
