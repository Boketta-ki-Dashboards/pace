import Foundation

/// Mediendaten eines Chats (gerade hochgeladene Bilder, gerade aufgenommene oder abgespielte Sprachnachrichten), damit
/// sie nicht noch einmal übertragen werden. Nach Bytes begrenzt: Die zuerst gespeicherten fallen zuerst heraus und
/// werden bei Bedarf wieder vom Server geladen.
struct ChatMediaDataCache {
    /// Obergrenze je Chat.
    static let defaultByteLimit = 24 * 1_024 * 1_024

    let byteLimit: Int
    private var entries: [String: Data] = [:]
    private var order: [String] = []
    private(set) var totalBytes = 0

    init(byteLimit: Int = ChatMediaDataCache.defaultByteLimit) {
        self.byteLimit = byteLimit
    }

    subscript(path: String) -> Data? {
        get { entries[path] }
        set {
            if let old = entries.removeValue(forKey: path) {
                totalBytes -= old.count
                order.removeAll { $0 == path }
            }
            guard let newValue else { return }
            entries[path] = newValue
            order.append(path)
            totalBytes += newValue.count
            // Älteste zuerst entfernen; der gerade gespeicherte Eintrag bleibt immer.
            while totalBytes > byteLimit, order.count > 1 {
                let oldest = order.removeFirst()
                totalBytes -= entries.removeValue(forKey: oldest)?.count ?? 0
            }
        }
    }

    var count: Int { entries.count }
}
