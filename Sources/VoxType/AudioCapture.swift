@preconcurrency import AVFAudio
import Foundation

final class AudioCapture: @unchecked Sendable {
    typealias BufferHandler = @Sendable (AVAudioPCMBuffer, AVAudioTime?) -> Void

    static let inputBufferFrameCount: AVAudioFrameCount = 256
    let meter = AudioLevelMeter()

    private let recognitionQueue = DispatchQueue(
        label: "app.voxtypemac.VoxTypeMac.audio-recognition",
        qos: .userInteractive
    )
    private let recordingQueue = DispatchQueue(
        label: "app.voxtypemac.VoxTypeMac.audio-recording",
        qos: .userInitiated
    )

    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var bufferHandler: BufferHandler?
    private var recordedFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private var writeErrorDescription: String?

    private(set) var isRecording = false

    func start(
        writingTo url: URL,
        onBuffer: @escaping BufferHandler
    ) throws -> AVAudioFormat {
        try SettingsFile.requireContained(url)
        if isRecording {
            _ = stop()
        }

        let engine = usableEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw CaptureError.invalidInputFormat
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        self.engine = engine
        self.audioFile = file
        self.bufferHandler = onBuffer
        self.recordedFrames = 0
        self.sampleRate = format.sampleRate
        self.writeErrorDescription = nil
        meter.reset()

        try engine.inputNode.installAudioTap(
            onBus: 0,
            bufferSize: Self.inputBufferFrameCount,
            format: format
        ) { [weak self] buffer, time in
            guard let self else { return }
            let copied = AVAudioPCMBuffer(copying: buffer)
            self.meter.ingest(copied)

            self.recognitionQueue.async { [weak self] in
                guard let self else { return }
                // Recognition never waits for archive I/O. The recording queue preserves file order.
                self.bufferHandler?(copied, time)
                self.recordedFrames += AVAudioFramePosition(copied.frameLength)
                self.recordingQueue.async { [weak self] in
                    guard let self else { return }
                    do {
                        try self.audioFile?.write(from: copied)
                    } catch {
                        if self.writeErrorDescription == nil {
                            self.writeErrorDescription = error.localizedDescription
                        }
                    }
                }
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
        return format
    }

    private func usableEngine() -> AVAudioEngine {
        if let engine, engine.inputNode.outputFormat(forBus: 0).channelCount > 0 {
            return engine
        }
        let replacement = AVAudioEngine()
        self.engine = replacement
        return replacement
    }

    struct StopResult: Sendable {
        let durationSeconds: TimeInterval
        let writeErrorDescription: String?
    }

    @discardableResult
    func stop() -> StopResult {
        guard let engine else {
            return StopResult(durationSeconds: 0, writeErrorDescription: nil)
        }

        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        engine.prepare()

        recognitionQueue.sync { }
        recordingQueue.sync { }

        let duration = sampleRate > 0 ? Double(recordedFrames) / sampleRate : 0
        let writeErrorDescription = self.writeErrorDescription
        self.audioFile = nil
        self.bufferHandler = nil
        self.recordedFrames = 0
        self.sampleRate = 0
        self.writeErrorDescription = nil
        meter.reset()
        self.isRecording = false
        return StopResult(
            durationSeconds: duration,
            writeErrorDescription: writeErrorDescription
        )
    }

    enum CaptureError: LocalizedError {
        case invalidInputFormat

        var errorDescription: String? {
            switch self {
            case .invalidInputFormat:
                "The selected microphone did not provide a usable audio format."
            }
        }
    }
}

struct AudioMeterFrame: Sendable {
    static let binCount = 12
    let bins: [Float]

    static let silence = AudioMeterFrame(bins: Array(repeating: 0, count: binCount))
}

/// The audio callback appends PCM into a short rolling window. Display rendering
/// only reads the newest 12-bin frame computed from that window.
final class AudioLevelMeter: @unchecked Sendable {
    static let windowSampleCount = 4096

    private let lock = NSLock()
    private var latestFrame = AudioMeterFrame.silence
    private var samples = [Float]()

    func publish(_ bins: [Float]) {
        lock.lock()
        latestFrame = AudioMeterFrame(bins: bins)
        lock.unlock()
    }

    func ingest(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let bins = Self.normalizedMeterBins(from: buffer, appendingTo: &samples)
        latestFrame = AudioMeterFrame(bins: bins)
        lock.unlock()
    }

    func snapshot() -> AudioMeterFrame {
        lock.lock()
        defer { lock.unlock() }
        return latestFrame
    }

    func snapshotWindow() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func reset() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        latestFrame = .silence
        lock.unlock()
    }

    nonisolated static func normalizedMeterBins(
        from buffer: AVAudioPCMBuffer,
        appendingTo window: inout [Float]
    ) -> [Float] {
        buffer.appendNormalizedSamples(to: &window, limit: windowSampleCount)
        return window.normalizedMeterBins()
    }
}

private extension AVAudioPCMBuffer {
    func normalizedMeterBins() -> [Float] {
        guard floatChannelData != nil, frameLength > 0 else {
            return AudioMeterFrame.silence.bins
        }
        var window = [Float]()
        window.reserveCapacity(Int(frameLength))
        appendNormalizedSamples(to: &window, limit: Int(frameLength))
        return window.normalizedMeterBins()
    }

    func appendNormalizedSamples(to window: inout [Float], limit: Int) {
        guard let channels = floatChannelData, frameLength > 0 else { return }
        let incoming = UnsafeBufferPointer(start: channels[0], count: Int(frameLength))
        window.append(contentsOf: incoming)
        if window.count > limit {
            window.removeFirst(window.count - limit)
        }
    }
}

private extension Array where Element == Float {
    func normalizedMeterBins() -> [Float] {
        let sampleCount = count
        guard sampleCount > 0 else { return AudioMeterFrame.silence.bins }
        let bins = AudioMeterFrame.binCount
        return (0..<bins).map { bin in
            let lower = bin * sampleCount / bins
            let upper = Swift.max(lower + 1, (bin + 1) * sampleCount / bins)
            var sum: Double = 0
            for index in lower..<Swift.min(upper, sampleCount) {
                let value = Double(self[index])
                sum += value * value
            }
            let rms = sqrt(sum / Double(Swift.max(upper - lower, 1)))
            guard rms > 0.000_001 else { return 0 }
            let decibels = 20 * log10(rms)
            return Float(Swift.min(Swift.max((decibels + 58) / 58, 0), 1))
        }
    }
}
