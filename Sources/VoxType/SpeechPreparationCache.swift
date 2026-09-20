@preconcurrency import AVFAudio
import Foundation

struct PreparedSpeechConfiguration: @unchecked Sendable {
    let resolvedLocale: Locale
    let analyzerFormat: AVAudioFormat
}

final class SpeechPreparationCache: @unchecked Sendable {
    typealias Builder = @Sendable (Locale) async throws -> PreparedSpeechConfiguration

    private enum Request {
        case ready(PreparedSpeechConfiguration)
        case pending(Task<PreparedSpeechConfiguration, Error>)
    }

    private let lock = NSLock()
    private var ready: [String: PreparedSpeechConfiguration] = [:]
    private var pending: [String: Task<PreparedSpeechConfiguration, Error>] = [:]

    func configuration(
        for requestedLocale: Locale,
        build: @escaping Builder
    ) async throws -> PreparedSpeechConfiguration {
        let key = requestedLocale.identifier
        let request = lock.withLock { () -> Request in
            if let configuration = ready[key] {
                return .ready(configuration)
            }
            if let task = pending[key] {
                return .pending(task)
            }
            let task = Task.detached(priority: .userInitiated) {
                try await build(requestedLocale)
            }
            pending[key] = task
            return .pending(task)
        }

        switch request {
        case .ready(let configuration):
            return configuration
        case .pending(let task):
            return try await finish(task, requestedKey: key)
        }
    }

    private func finish(
        _ task: Task<PreparedSpeechConfiguration, Error>,
        requestedKey: String
    ) async throws -> PreparedSpeechConfiguration {
        do {
            let configuration = try await task.value
            lock.withLock {
                ready[requestedKey] = configuration
                ready[configuration.resolvedLocale.identifier] = configuration
                pending[requestedKey] = nil
            }
            return configuration
        } catch {
            lock.withLock {
                pending[requestedKey] = nil
            }
            throw error
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
