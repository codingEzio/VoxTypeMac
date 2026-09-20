import Foundation

final class ArtifactDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var file: FileHandle?
    private var downloadError: Error?
    private var expectedBytes: Int64 = 0
    private var receivedBytes: Int64 = 0

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func download(from source: URL) async throws {
        try SettingsFile.requireContained(destination)
        try await withCheckedThrowingContinuation { continuation in
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.removeItem(at: destination)
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let file = try FileHandle(forWritingTo: destination)
                lock.withLock {
                    self.continuation = continuation
                    self.file = file
                }
            } catch {
                continuation.resume(throwing: error)
                return
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 1_800
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.dataTask(with: source).resume()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            lock.withLock { downloadError = RefinementError.downloadFailed }
            completionHandler(.cancel)
            return
        }
        lock.withLock { expectedBytes = response.expectedContentLength }
        completionHandler(.allow)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let progress: Double? = lock.withLock {
            do {
                try file?.write(contentsOf: data)
                receivedBytes += Int64(data.count)
                guard expectedBytes > 0 else { return nil }
                return min(1, Double(receivedBytes) / Double(expectedBytes))
            } catch {
                downloadError = error
                dataTask.cancel()
                return nil
            }
        }
        if let progress { onProgress(progress) }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let result: Result<Void, Error> = lock.withLock {
            try? file?.close()
            file = nil
            if let downloadError { return .failure(downloadError) }
            if let error { return .failure(error) }
            guard receivedBytes > 0 else { return .failure(RefinementError.downloadFailed) }
            return .success(())
        }
        if case .failure = result {
            try? FileManager.default.removeItem(at: destination)
        }
        finish(result)
    }

    private nonisolated func finish(_ result: Result<Void, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        session?.finishTasksAndInvalidate()
        continuation?.resume(with: result)
    }
}
