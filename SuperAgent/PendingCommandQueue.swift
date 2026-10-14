import Foundation

enum PendingCommandQueue {
    static let commandKey = "pendingAssistantCommand"
    static let timestampKey = "pendingAssistantCommandAt"
    static let maximumAge: TimeInterval = 300
    static let maximumLength = 2000

    @discardableResult
    static func enqueue(_ raw: String, in defaults: UserDefaults, now: Date = Date()) -> Bool {
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, command.count <= maximumLength else { return false }
        if let existing = defaults.string(forKey: commandKey),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        defaults.set(command, forKey: commandKey)
        defaults.set(now.timeIntervalSince1970, forKey: timestampKey)
        return true
    }

    static func consume(from defaults: UserDefaults, now: Date = Date()) -> String? {
        defer {
            defaults.removeObject(forKey: commandKey)
            defaults.removeObject(forKey: timestampKey)
        }
        guard let command = defaults.string(forKey: commandKey),
              let queuedAt = defaults.object(forKey: timestampKey) as? Double,
              now.timeIntervalSince1970 - queuedAt <= maximumAge else { return nil }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > maximumLength ? nil : trimmed
    }
}

final class AgentLoopCancellation {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }
}
