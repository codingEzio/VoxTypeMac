import CryptoKit
import Darwin
import Foundation

@MainActor
final class RefinementService: ObservableObject {
    struct HelperRuntime {
        let environment: [String: String]
        let workingDirectory: URL
    }

    enum State: Equatable {
        case unavailable
        case downloading
        case ready
        case failed(String)

        var title: String {
            switch self {
            case .unavailable: "Not downloaded"
            case .downloading: "Downloading and verifying…"
            case .ready: "Ready"
            case .failed(let message): "Unavailable · \(message)"
            }
        }
    }

    private enum Artifact {
        static let runtimeURL = URL(
            string:
                "https://github.com/FunAudioLLM/SenseVoice/releases/download/runtime-llamacpp-v0.1.4/funasr-llamacpp-macos-arm64.tar.gz"
        )!
        static let runtimeSHA256 =
            "010416baa6932c7ce67fda50eb421a65e8ae6fd248f06f8d2f7ec17d15ef2cba"
        static let runtimeExecutableSHA256 =
            "7879da5c65ff194315964edc8a10a73941dc25964a6b88daf4584cab7a5981ab"
        static let modelURL = URL(
            string:
                "https://huggingface.co/FunAudioLLM/SenseVoiceSmall-GGUF/resolve/90c1c61912018b70ada0fcc024ea24aca62f2e63/sensevoice-small-q8.gguf"
        )!
        static let modelSHA256 = "4ae45c94422de949b387e2e0fb10d7e14e4c42c69db30c3444ecc7d4b844b7c5"
    }

    @Published private(set) var state: State = .unavailable
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var backend: RefinementBackend = .senseVoice
    private var verifiedQwenIdentities: [FileIdentity]?
    private var verifiedRuntimeIdentity: FileIdentity?
    private var verifiedModelIdentity: FileIdentity?

    private let fileManager = FileManager.default
    private let cacheRoot: URL
    private var runtimeURL: URL { cacheRoot.appendingPathComponent("llama-funasr-sensevoice") }
    private var modelURL: URL { cacheRoot.appendingPathComponent("sensevoice-small-q8.gguf") }

    init() {
        cacheRoot = SettingsFile.modelsURL.appendingPathComponent("refinement", isDirectory: true)
        refreshState()
    }

    func refreshState() {
        if QwenRefinement.isReady {
            backend = .qwen3
            state = .ready
        } else {
            backend = .senseVoice
            state =
                Self.filesAreReady(runtimeURL: runtimeURL, modelURL: modelURL)
                ? .ready : .unavailable
        }
    }

    func prepare() async {
        guard state == .ready else { return }
        try? await ensureVerified()
    }

    func install() async {
        guard state != .downloading else { return }
        state = .downloading
        downloadProgress = 0
        do {
            try await Self.installArtifacts(into: cacheRoot) { [weak self] progress in
                Task { @MainActor in self?.downloadProgress = progress }
            }
            refreshState()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func remove() throws {
        let selectedRoot = backend == .qwen3 ? QwenRefinement.modelURL : cacheRoot
        try SettingsFile.requireContained(selectedRoot)
        guard fileManager.fileExists(atPath: selectedRoot.path) else { return }
        try fileManager.removeItem(at: selectedRoot)
        verifiedQwenIdentities = nil
        refreshState()
    }

    func refine(audioURL: URL, timeoutSeconds: TimeInterval = RefinementPolicy.timeoutSeconds)
        async throws -> String
    {
        guard state == .ready else { throw RefinementError.modelUnavailable }
        try await ensureVerified()
        let runtime = runtimeURL
        let selectedBackend = backend
        let selectedModel = backend == .qwen3 ? QwenRefinement.modelURL : modelURL
        return try await Task.detached(priority: .userInitiated) {
            try Self.runRefinement(
                audioURL: audioURL, runtimeURL: runtime, modelURL: selectedModel,
                backend: selectedBackend,
                timeoutSeconds: selectedBackend == .qwen3 ? timeoutSeconds : min(timeoutSeconds, 20)
            )
        }.value
    }

    nonisolated static func prepareHelperRuntime(
        baseEnvironment _: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> HelperRuntime {
        let folders = [
            "HOME": SettingsFile.stateURL.appendingPathComponent("helper-home", isDirectory: true),
            "TMPDIR": SettingsFile.temporaryURL,
            "XDG_CACHE_HOME": SettingsFile.cacheURL.appendingPathComponent(
                "xdg", isDirectory: true),
            "PYTHONPYCACHEPREFIX": SettingsFile.cacheURL.appendingPathComponent(
                "python", isDirectory: true),
            "HF_HOME": SettingsFile.cacheURL.appendingPathComponent(
                "huggingface", isDirectory: true),
            "TORCH_HOME": SettingsFile.cacheURL.appendingPathComponent("torch", isDirectory: true),
            "TRANSFORMERS_CACHE": SettingsFile.cacheURL.appendingPathComponent(
                "transformers", isDirectory: true),
            "NUMBA_CACHE_DIR": SettingsFile.cacheURL.appendingPathComponent(
                "numba", isDirectory: true),
        ]
        for folder in folders.values {
            try SettingsFile.requireContained(folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        var environment = folders.mapValues(\.path)
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["LANG"] = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["HF_HUB_OFFLINE"] = "1"
        environment["HF_DATASETS_OFFLINE"] = "1"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environment["PYTHONNOUSERSITE"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        return HelperRuntime(environment: environment, workingDirectory: SettingsFile.temporaryURL)
    }

    private func ensureVerified() async throws {
        if backend == .qwen3 {
            let config = try QwenRefinement.configuration()
            let root = QwenRefinement.modelURL
            let identities = try config.files.map {
                try Self.identity(of: root.appendingPathComponent($0.name))
            }
            guard identities != verifiedQwenIdentities else { return }
            try await Task.detached(priority: .userInitiated) {
                for artifact in config.files {
                    let url = root.appendingPathComponent(artifact.name)
                    try SettingsFile.requireContained(url)
                    if let expected = artifact.sha256 {
                        try Self.verify(url, expectedSHA256: expected)
                    } else {
                        let data = try Data(contentsOf: url)
                        var digest = Insecure.SHA1()
                        digest.update(data: Data("blob \(data.count)\0".utf8))
                        digest.update(data: data)
                        guard
                            digest.finalize().map({ String(format: "%02x", $0) }).joined()
                                == artifact.gitBlob
                        else {
                            throw RefinementError.checksumMismatch
                        }
                    }
                }
            }.value
            verifiedQwenIdentities = identities
            return
        }
        let runtimeIdentity = try Self.identity(of: runtimeURL)
        let modelIdentity = try Self.identity(of: modelURL)
        guard runtimeIdentity != verifiedRuntimeIdentity || modelIdentity != verifiedModelIdentity
        else { return }
        let runtime = runtimeURL
        let model = modelURL
        try await Task.detached(priority: .userInitiated) {
            try Self.verify(runtime, expectedSHA256: Artifact.runtimeExecutableSHA256)
            try Self.verify(model, expectedSHA256: Artifact.modelSHA256)
        }.value
        verifiedRuntimeIdentity = runtimeIdentity
        verifiedModelIdentity = modelIdentity
    }

    nonisolated private static func identity(of url: URL) throws -> FileIdentity {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileIdentity(
            size: (attributes[.size] as? NSNumber)?.int64Value ?? -1,
            modificationTime: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        )
    }

    nonisolated private static func filesAreReady(runtimeURL: URL, modelURL: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: runtimeURL.path)
            && FileManager.default.fileExists(atPath: modelURL.path)
    }

    nonisolated private static func installArtifacts(
        into destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try SettingsFile.requireContained(destination)
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        let process = ProcessInfo.processInfo.processIdentifier
        let staging = parent.appendingPathComponent(
            "refinement-download-\(timestamp)-\(process)",
            isDirectory: true
        )
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let runtimeArchive = staging.appendingPathComponent("runtime.tar.gz")
        try await download(Artifact.runtimeURL, to: runtimeArchive) { fraction in
            onProgress(fraction * 0.03)
        }
        try verify(runtimeArchive, expectedSHA256: Artifact.runtimeSHA256)
        try runProcess(
            "/usr/bin/tar", ["-xzf", runtimeArchive.path, "-C", staging.path], timeoutSeconds: 30)

        let model = staging.appendingPathComponent("sensevoice-small-q8.gguf")
        try await download(Artifact.modelURL, to: model) { fraction in
            onProgress(0.03 + fraction * 0.97)
        }
        try verify(model, expectedSHA256: Artifact.modelSHA256)

        let runtime = staging.appendingPathComponent("llama-funasr-sensevoice")
        guard fm.fileExists(atPath: runtime.path) else { throw RefinementError.missingRuntime }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
        try? fm.removeItem(at: runtimeArchive)

        let install = staging.appendingPathComponent("install", isDirectory: true)
        try fm.createDirectory(at: install, withIntermediateDirectories: true)
        try fm.moveItem(at: runtime, to: install.appendingPathComponent(runtime.lastPathComponent))
        try fm.moveItem(at: model, to: install.appendingPathComponent(model.lastPathComponent))

        let previous = parent.appendingPathComponent("refinement-previous-\(timestamp)-\(process)")
        if fm.fileExists(atPath: destination.path) {
            try fm.moveItem(at: destination, to: previous)
        }
        do {
            try fm.moveItem(at: install, to: destination)
            try? fm.removeItem(at: previous)
        } catch {
            if fm.fileExists(atPath: previous.path) {
                try? fm.moveItem(at: previous, to: destination)
            }
            throw error
        }
    }

    nonisolated private static func download(
        _ source: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await ArtifactDownloader(destination: destination, onProgress: onProgress)
            .download(from: source)
    }

    nonisolated private static func verify(_ url: URL, expectedSHA256: String) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else { throw RefinementError.checksumMismatch }
    }

    nonisolated private static func runRefinement(
        audioURL: URL,
        runtimeURL: URL,
        modelURL: URL,
        backend: RefinementBackend,
        timeoutSeconds: TimeInterval
    ) throws -> String {
        try SettingsFile.requireContained(audioURL)
        try SettingsFile.requireContained(runtimeURL)
        try SettingsFile.requireContained(modelURL)
        try FileManager.default.createDirectory(
            at: SettingsFile.temporaryURL,
            withIntermediateDirectories: true
        )
        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        let process = ProcessInfo.processInfo.processIdentifier
        let temporary = SettingsFile.temporaryURL
            .appendingPathComponent("refinement-\(timestamp)-\(process).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try runProcess(
            "/usr/bin/afconvert",
            [audioURL.path, temporary.path, "-f", "WAVE", "-d", "LEI16@16000", "-c", "1"],
            timeoutSeconds: min(timeoutSeconds, 10)
        )
        let executable = backend == .qwen3 ? QwenRefinement.pythonURL.path : runtimeURL.path
        let arguments =
            backend == .qwen3
            ? [
                QwenRefinement.helperURL.path, "--model", modelURL.path,
                "--audio", temporary.path, "--config", QwenRefinement.configurationURL.path,
            ]
            : ["-m", modelURL.path, "-a", temporary.path]
        let output = try runProcess(
            executable,
            arguments,
            timeoutSeconds: timeoutSeconds,
            captureOutput: true
        )
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw RefinementError.emptyResult }
        return cleaned
    }

    @discardableResult
    nonisolated static func runProcess(
        _ executable: String,
        _ arguments: [String],
        timeoutSeconds: TimeInterval,
        captureOutput: Bool = false
    ) throws -> String {
        let process = Process()
        let helperRuntime = try prepareHelperRuntime()
        let outputURL = helperRuntime.workingDirectory.appendingPathComponent(
            "helper-\(UUID().uuidString).stdout")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw RefinementError.helperFailed
        }
        let output = try FileHandle(forWritingTo: outputURL)
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = helperRuntime.environment
        process.currentDirectoryURL = helperRuntime.workingDirectory
        process.standardOutput = captureOutput ? output : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        if finished.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            throw RefinementError.timedOut
        }
        guard process.terminationStatus == 0 else { throw RefinementError.helperFailed }
        guard captureOutput else { return "" }
        try output.synchronize()
        let size = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1024 * 1024 else { throw RefinementError.helperFailed }
        return String(decoding: try Data(contentsOf: outputURL), as: UTF8.self)
    }
}

private struct FileIdentity: Equatable, Sendable {
    let size: Int64
    let modificationTime: TimeInterval
    let fileNumber: UInt64
}

enum RefinementError: LocalizedError {
    case modelUnavailable, downloadFailed, checksumMismatch, missingRuntime
    case timedOut, helperFailed, emptyResult

    var errorDescription: String? {
        switch self {
        case .modelUnavailable: "The refinement model is not downloaded."
        case .downloadFailed: "The official download failed."
        case .checksumMismatch: "The downloaded file failed verification."
        case .missingRuntime: "The verified archive did not contain the expected helper."
        case .timedOut: "Refinement timed out."
        case .helperFailed: "The local refinement helper failed."
        case .emptyResult: "Refinement returned no text."
        }
    }
}
