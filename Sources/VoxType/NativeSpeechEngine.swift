@preconcurrency import AVFAudio
import CoreMedia
import Foundation
@preconcurrency import Speech

final class NativeSpeechEngine: @unchecked Sendable {
    typealias UpdateHandler = @Sendable (LiveTranscript) -> Void
    typealias ErrorHandler = @Sendable (Error) -> Void

    private struct PreparedSession {
        let localeIdentifier: String
        let resolvedLocale: Locale
        let analyzer: SpeechAnalyzer
        let transcriber: DictationTranscriber
        let converter: AnalyzerInputConverter
        let analyzerFormat: AVAudioFormat
    }

    private let stateLock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var converter: AnalyzerInputConverter?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<String, Error>?
    private var errorHandler: ErrorHandler?
    private var reserved: PreparedSession?
    private var pendingPCM: [(AVAudioPCMBuffer, AVAudioTime?)] = []
    private var pendingInputs: [AnalyzerInput] = []
    private let preparationCache = SpeechPreparationCache()

    // Keep at most about 93 ms of 44.1 kHz / 256-frame input queued. If the
    // analyzer falls behind, current speech is more useful than stale audio.
    static let liveInputBufferLimit = 16

    private let options = SpeechAnalyzer.Options(
        priority: .userInitiated,
        modelRetention: .processLifetime
    )

    var isActive: Bool {
        stateLock.withLock { analyzer != nil }
    }

    func prewarm(locale requestedLocale: Locale) async throws -> String {
        try await reservePreparedSession(for: requestedLocale)
    }

    func scheduleReserve(locale requestedLocale: Locale) {
        Task { [weak self] in
            _ = try? await self?.reservePreparedSession(for: requestedLocale)
        }
    }

    func start(
        locale requestedLocale: Locale,
        onUpdate: @escaping UpdateHandler,
        onError: @escaping ErrorHandler
    ) async throws -> String {
        let reservedSession = takeReservedSession(matching: requestedLocale)
        await cancelActiveSession()

        let session: PreparedSession
        if let reservedSession {
            session = reservedSession
        } else {
            do {
                session = try await makePreparedSession(for: requestedLocale)
            } catch {
                await cancelReservedSession()
                throw error
            }
        }

        armConverter(session.converter, onError: onError)

        let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.liveInputBufferLimit)
        )
        let resultsTask = Self.makeResultsTask(
            transcriber: session.transcriber,
            onUpdate: onUpdate,
            onError: onError
        )

        do {
            try await session.analyzer.start(inputSequence: inputSequence)
        } catch {
            resultsTask.cancel()
            continuation.finish()
            await session.analyzer.cancelAndFinishNow()
            if reservedSession != nil {
                return try await startFresh(
                    locale: requestedLocale,
                    onUpdate: onUpdate,
                    onError: onError
                )
            }
            throw error
        }

        attachLiveStream(
            analyzer: session.analyzer,
            continuation: continuation,
            resultsTask: resultsTask
        )
        return session.localeIdentifier
    }

    func consume(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard let converter else {
            enqueuePendingPCM(buffer, at: time)
            return
        }

        do {
            let inputs = try converter.convert(buffer, at: time)
            emit(inputs)
        } catch {
            errorHandler?(error)
        }
    }

    func stop() async throws -> String {
        let local = stateLock.withLock {
            (analyzer, converter, inputContinuation, resultsTask)
        }

        guard let analyzer = local.0 else { return "" }
        defer { clearActiveState() }

        if let converter = local.1, let continuation = local.2 {
            for input in try converter.flush() {
                continuation.yield(input)
            }
            continuation.finish()
        }

        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await local.3?.value ?? ""
    }

    func cancel() async {
        await cancelActiveSession()
        await cancelReservedSession()
    }

    func transcribeFile(
        at audioURL: URL,
        locale requestedLocale: Locale,
        onUpdate: @escaping UpdateHandler
    ) async throws -> String {
        let configuration = try await preparedConfiguration(for: requestedLocale)
        let transcriber = Self.makeLiveDictationTranscriber(locale: configuration.resolvedLocale)
        let modules: [any SpeechModule] = [transcriber]

        let file = try AVAudioFile(forReading: audioURL)
        let analyzer = SpeechAnalyzer(modules: modules, options: options)
        try await analyzer.prepareToAnalyze(in: file.processingFormat)

        let results = Task<String, Error>(priority: .userInitiated) {
            var accumulator = TranscriptAccumulator()
            for try await result in transcriber.results {
                let snapshot = accumulator.apply(
                    text: String(result.text.characters),
                    range: result.range,
                    isFinal: result.isFinal
                )
                onUpdate(snapshot)
            }
            return accumulator.bestText
        }

        do {
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            return try await results.value
        } catch {
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private func reservePreparedSession(for requestedLocale: Locale) async throws -> String {
        if let reserved = stateLock.withLock({ reserved }),
           reserved.localeIdentifier == requestedLocale.identifier
            || reserved.resolvedLocale.identifier == requestedLocale.identifier {
            return reserved.localeIdentifier
        }

        await cancelReservedSession()
        let session = try await makePreparedSession(for: requestedLocale)
        stateLock.withLock { reserved = session }
        return session.localeIdentifier
    }

    private func startFresh(
        locale requestedLocale: Locale,
        onUpdate: @escaping UpdateHandler,
        onError: @escaping ErrorHandler
    ) async throws -> String {
        await cancelActiveSession()
        let session = try await makePreparedSession(for: requestedLocale)
        armConverter(session.converter, onError: onError)

        let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.liveInputBufferLimit)
        )
        let resultsTask = Self.makeResultsTask(
            transcriber: session.transcriber,
            onUpdate: onUpdate,
            onError: onError
        )

        do {
            try await session.analyzer.start(inputSequence: inputSequence)
        } catch {
            resultsTask.cancel()
            continuation.finish()
            await session.analyzer.cancelAndFinishNow()
            throw error
        }

        attachLiveStream(
            analyzer: session.analyzer,
            continuation: continuation,
            resultsTask: resultsTask
        )
        return session.localeIdentifier
    }

    private func makePreparedSession(for requestedLocale: Locale) async throws -> PreparedSession {
        let configuration = try await preparedConfiguration(for: requestedLocale)
        let transcriber = Self.makeLiveDictationTranscriber(locale: configuration.resolvedLocale)
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: options)
        try await analyzer.prepareToAnalyze(in: configuration.analyzerFormat)
        return PreparedSession(
            localeIdentifier: configuration.resolvedLocale.identifier,
            resolvedLocale: configuration.resolvedLocale,
            analyzer: analyzer,
            transcriber: transcriber,
            converter: AnalyzerInputConverter(analyzerFormat: configuration.analyzerFormat),
            analyzerFormat: configuration.analyzerFormat
        )
    }

    private func armConverter(_ converter: AnalyzerInputConverter, onError: @escaping ErrorHandler) {
        stateLock.lock()
        defer { stateLock.unlock() }
        self.converter = converter
        self.errorHandler = onError
        flushPendingPCMLocked()
    }

    private func attachLiveStream(
        analyzer: SpeechAnalyzer,
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        resultsTask: Task<String, Error>
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        self.analyzer = analyzer
        self.inputContinuation = continuation
        self.resultsTask = resultsTask
        emit(pendingInputs)
        pendingInputs.removeAll(keepingCapacity: true)
    }

    private func emit(_ inputs: [AnalyzerInput]) {
        if let continuation = inputContinuation {
            for input in inputs {
                continuation.yield(input)
            }
            return
        }
        pendingInputs.append(contentsOf: inputs)
        if pendingInputs.count > Self.liveInputBufferLimit {
            pendingInputs.removeFirst(pendingInputs.count - Self.liveInputBufferLimit)
        }
    }

    private func enqueuePendingPCM(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {
        pendingPCM.append((buffer, time))
        if pendingPCM.count > Self.liveInputBufferLimit {
            pendingPCM.removeFirst(pendingPCM.count - Self.liveInputBufferLimit)
        }
    }

    private func flushPendingPCMLocked() {
        guard let converter else { return }
        let queued = pendingPCM
        pendingPCM.removeAll(keepingCapacity: true)
        for (buffer, time) in queued {
            do {
                emit(try converter.convert(buffer, at: time))
            } catch {
                errorHandler?(error)
            }
        }
    }

    private func takeReservedSession(matching requestedLocale: Locale) -> PreparedSession? {
        stateLock.withLock {
            guard let reserved else { return nil }
            let matches = reserved.localeIdentifier == requestedLocale.identifier
                || reserved.resolvedLocale.identifier == requestedLocale.identifier
            guard matches else { return nil }
            self.reserved = nil
            return reserved
        }
    }

    private func cancelActiveSession() async {
        let local = stateLock.withLock {
            (analyzer, inputContinuation, resultsTask)
        }
        local.1?.finish()
        if let analyzer = local.0 {
            await analyzer.cancelAndFinishNow()
        }
        local.2?.cancel()
        clearActiveState()
    }

    private func cancelReservedSession() async {
        let reservedAnalyzer = stateLock.withLock { () -> SpeechAnalyzer? in
            let analyzer = reserved?.analyzer
            reserved = nil
            return analyzer
        }
        if let reservedAnalyzer {
            await reservedAnalyzer.cancelAndFinishNow()
        }
    }

    private static func makeResultsTask(
        transcriber: DictationTranscriber,
        onUpdate: @escaping UpdateHandler,
        onError: @escaping ErrorHandler
    ) -> Task<String, Error> {
        Task<String, Error>(priority: .userInitiated) {
            var accumulator = TranscriptAccumulator()
            do {
                for try await result in transcriber.results {
                    let snapshot = accumulator.apply(
                        text: String(result.text.characters),
                        range: result.range,
                        isFinal: result.isFinal
                    )
                    onUpdate(snapshot)
                }
                return accumulator.bestText
            } catch {
                onError(error)
                throw error
            }
        }
    }

    private static func makeLiveDictationTranscriber(locale: Locale) -> DictationTranscriber {
        let preset = DictationTranscriber.Preset.progressiveShortDictation
        return DictationTranscriber(
            locale: locale,
            contentHints: preset.contentHints,
            transcriptionOptions: preset.transcriptionOptions,
            reportingOptions: preset.reportingOptions.union([.volatileResults, .frequentFinalization]),
            attributeOptions: preset.attributeOptions
        )
    }

    private func preparedConfiguration(for requestedLocale: Locale) async throws -> PreparedSpeechConfiguration {
        try await preparationCache.configuration(for: requestedLocale) { locale in
            try await Self.buildConfiguration(for: locale)
        }
    }

    private static func buildConfiguration(for requestedLocale: Locale) async throws -> PreparedSpeechConfiguration {
        let resolved = try await resolveLocale(requestedLocale)
        let transcriber = makeLiveDictationTranscriber(locale: resolved)
        let modules: [any SpeechModule] = [transcriber]
        try await ensureAssets(for: modules)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw EngineError.audioFormatUnavailable
        }
        return PreparedSpeechConfiguration(resolvedLocale: resolved, analyzerFormat: format)
    }

    private static func resolveLocale(_ requested: Locale) async throws -> Locale {
        guard let resolved = await DictationTranscriber.supportedLocale(equivalentTo: requested) else {
            throw EngineError.unsupportedLocale(requested.identifier)
        }
        return resolved
    }

    private static func ensureAssets(for modules: [any SpeechModule]) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await request.downloadAndInstall()
        }
    }

    private func clearActiveState() {
        stateLock.withLock {
            analyzer = nil
            converter = nil
            inputContinuation = nil
            resultsTask = nil
            errorHandler = nil
            pendingPCM.removeAll(keepingCapacity: true)
            pendingInputs.removeAll(keepingCapacity: true)
        }
    }

    enum EngineError: LocalizedError {
        case unsupportedLocale(String)
        case audioFormatUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale(let locale):
                "Apple Dictation does not support the selected language (\(locale))."
            case .audioFormatUnavailable:
                "The required speech model or audio format is unavailable."
            }
        }
    }
}

struct LiveTranscript: Equatable, Sendable {
    var text: String
    var stableText: String
    var draftTail: String

    static let empty = LiveTranscript(text: "", stableText: "", draftTail: "")
}

enum LiveTranscriptDisplay {
    static func parts(
        from live: LiveTranscript,
        finalPass: Bool
    ) -> (stable: String, draft: String) {
        if finalPass {
            return ("", live.text)
        }
        return (live.stableText, live.draftTail)
    }
}

struct TranscriptAccumulator {
    private struct Entry {
        var start: Double
        var end: Double
        var text: String
        var isFinal: Bool
    }

    private var finals: [Entry] = []
    private var volatile: Entry?
    private var rememberedBest = ""
    private(set) var text = ""
    private(set) var stableText = ""
    private(set) var draftTail = ""

    var bestText: String {
        rememberedBest.isEmpty ? text : rememberedBest
    }

    @discardableResult
    mutating func apply(text newText: String, range: CMTimeRange, isFinal: Bool) -> LiveTranscript {
        let start = range.start.seconds.isFinite ? range.start.seconds : 0
        let rawEnd = CMTimeRangeGetEnd(range).seconds
        let end = rawEnd.isFinite ? max(rawEnd, start) : start
        let cleaned = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        if isFinal {
            finals.removeAll { existing in
                Self.rangesOverlap(
                    firstStart: existing.start,
                    firstEnd: existing.end,
                    secondStart: start,
                    secondEnd: end
                )
            }
            if !cleaned.isEmpty {
                finals.append(Entry(start: start, end: end, text: cleaned, isFinal: true))
            }
            if let volatile, Self.rangesOverlap(
                firstStart: volatile.start,
                firstEnd: volatile.end,
                secondStart: start,
                secondEnd: end
            ), volatile.end <= end + 0.05 {
                self.volatile = nil
            }
        } else if !cleaned.isEmpty {
            volatile = Entry(start: start, end: end, text: cleaned, isFinal: false)
        } else {
            volatile = nil
        }

        finals.sort { lhs, rhs in
            if lhs.start == rhs.start { return lhs.end < rhs.end }
            return lhs.start < rhs.start
        }
        stableText = Self.normalize(smartJoin(finals.map(\.text)))
        draftTail = Self.draftTail(
            stable: stableText,
            volatileText: volatile?.text ?? "",
            volatileStart: volatile?.start ?? 0,
            lastFinalEnd: finals.map(\.end).max() ?? 0
        )
        text = Self.normalize(smartJoin([stableText, draftTail].filter { !$0.isEmpty }))
        rememberBestHypothesis()
        return LiveTranscript(text: text, stableText: stableText, draftTail: draftTail)
    }

    private mutating func rememberBestHypothesis() {
        if text.count >= rememberedBest.count {
            rememberedBest = text
        }
        guard let volatile else { return }
        let hypothesis = Self.normalize(volatile.text)
        guard !hypothesis.isEmpty else { return }
        let firstFinalStart = finals.map(\.start).min() ?? volatile.start
        let lastFinalEnd = finals.map(\.end).max() ?? 0
        let coversUtterance = volatile.start <= firstFinalStart + 0.2
            && volatile.end >= lastFinalEnd - 0.2
        if coversUtterance && hypothesis.count >= max(stableText.count / 2, rememberedBest.count) {
            rememberedBest = hypothesis
        }
    }

    private static func draftTail(
        stable: String,
        volatileText: String,
        volatileStart: Double,
        lastFinalEnd: Double
    ) -> String {
        let stable = normalize(stable)
        let hypothesis = normalize(volatileText)
        if hypothesis.isEmpty || hypothesis == stable { return "" }
        if stable.isEmpty { return hypothesis }
        if hypothesis.hasPrefix(stable) {
            return String(hypothesis.dropFirst(stable.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if stable.contains(hypothesis) { return "" }
        if volatileStart >= lastFinalEnd - 0.15 { return hypothesis }
        return ""
    }

    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: #"[^\S\n]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rangesOverlap(
        firstStart: Double,
        firstEnd: Double,
        secondStart: Double,
        secondEnd: Double
    ) -> Bool {
        let epsilon = 0.002
        return firstStart < secondEnd - epsilon && secondStart < firstEnd - epsilon
            || abs(firstStart - secondStart) <= epsilon
    }

    private func smartJoin(_ pieces: [String]) -> String {
        var output = ""
        for piece in pieces where !piece.isEmpty {
            guard let first = piece.first else { continue }
            if let last = output.last, shouldInsertSpace(after: last, before: first) {
                output.append(" ")
            }
            output.append(piece)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldInsertSpace(after left: Character, before right: Character) -> Bool {
        if left.isWhitespace || right.isWhitespace { return false }
        if Self.noLeadingSpace.contains(right) || Self.noTrailingSpace.contains(left) { return false }
        if isCJK(left) || isCJK(right) { return false }
        return true
    }

    private func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
                true
            default:
                false
            }
        }
    }

    private static let noLeadingSpace = Set<Character>(",.!?:;%)]}，。！？：；％）】》」』、")
    private static let noTrailingSpace = Set<Character>("([{（【《「『")
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
