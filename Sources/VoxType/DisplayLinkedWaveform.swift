import AppKit
import QuartzCore
import SwiftUI

struct DisplayLinkedWaveform: NSViewRepresentable {
    let meter: AudioLevelMeter
    let color: NSColor
    let bars: Int
    let isActive: Bool
    let reduceMotion: Bool
    var attackSeconds: Double = 0.03
    var releaseSeconds: Double = 0.11

    func makeNSView(context: Context) -> DisplayLinkedWaveformView {
        DisplayLinkedWaveformView(meter: meter, bars: bars)
    }

    func updateNSView(_ view: DisplayLinkedWaveformView, context: Context) {
        view.update(
            color: color,
            bars: bars,
            isActive: isActive,
            reduceMotion: reduceMotion,
            attackSeconds: attackSeconds,
            releaseSeconds: releaseSeconds
        )
    }
}

final class DisplayLinkedWaveformView: NSView {
    private let meter: AudioLevelMeter
    private var displayLink: CADisplayLink?
    private let waveGlowLayer = CAShapeLayer()
    private let waveLayer = CAShapeLayer()
    private let ribbonLayers = [CAShapeLayer(), CAShapeLayer()]
    private var barLayers: [CAShapeLayer] = []
    private var barCount: Int
    private var smoothedBins = Array(repeating: CGFloat(0), count: AudioMeterFrame.binCount)
    private var lastTimestamp: CFTimeInterval?
    private var waveformColor = NSColor.controlAccentColor
    private var isActive = false
    private var reduceMotion = false
    private var attackSeconds = 0.03
    private var releaseSeconds = 0.11
    private var screenObserver: NSObjectProtocol?
    private var visibilityObserver: NSObjectProtocol?
    var frameObserver: ((CFTimeInterval) -> Void)?

    init(meter: AudioLevelMeter, bars: Int) {
        self.meter = meter
        self.barCount = max(1, bars)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        waveGlowLayer.fillColor = nil
        waveGlowLayer.lineJoin = .round
        waveGlowLayer.lineCap = .round
        layer?.addSublayer(waveGlowLayer)
        for ribbon in ribbonLayers {
            ribbon.fillColor = nil
            ribbon.lineJoin = .round
            ribbon.lineCap = .round
            layer?.addSublayer(ribbon)
        }
        waveLayer.fillColor = nil
        waveLayer.lineJoin = .round
        waveLayer.lineCap = .round
        layer?.addSublayer(waveLayer)
        updateBarLayers()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncLayerScale()
        observeScreenChanges()
        recreateDisplayLink()
        updateDisplayLinkState()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncLayerScale()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            invalidateDisplayLink()
            stopObservingScreenChanges()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func layout() {
        super.layout()
        render(timestamp: CACurrentMediaTime())
    }

    func update(
        color: NSColor,
        bars: Int,
        isActive: Bool,
        reduceMotion: Bool,
        attackSeconds: Double = 0.03,
        releaseSeconds: Double = 0.11
    ) {
        waveformColor = color
        let requestedBars = max(1, bars)
        if requestedBars != barCount {
            barCount = requestedBars
            updateBarLayers()
        }
        self.isActive = isActive
        if self.reduceMotion != reduceMotion { recreateDisplayLink() }
        self.reduceMotion = reduceMotion
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
        updateDisplayLinkState()
        if displayLink == nil || !isActive { render(timestamp: CACurrentMediaTime()) }
    }

    private func updateDisplayLinkState() {
        guard isActive, window?.isVisible == true, !isHiddenOrHasHiddenAncestor else {
            displayLink?.isPaused = true
            return
        }
        if displayLink == nil {
            let link = displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
            let available = Float(max(1, window?.screen?.maximumFramesPerSecond ?? 60))
            let preferred = reduceMotion ? min(30, available) : available
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: min(60, preferred),
                maximum: preferred,
                preferred: preferred
            )
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = false
    }

    private func invalidateDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    private func recreateDisplayLink() {
        invalidateDisplayLink()
    }

    private func observeScreenChanges() {
        stopObservingScreenChanges()
        guard let window else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recreateDisplayLink()
                self?.updateDisplayLinkState()
            }
        }
        visibilityObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateDisplayLinkState() }
        }
    }

    private func stopObservingScreenChanges() {
        if let visibilityObserver {
            NotificationCenter.default.removeObserver(visibilityObserver)
            self.visibilityObserver = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func updateBarLayers() {
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers = (0..<barCount).map { _ in
            let bar = CAShapeLayer()
            bar.lineCap = .round
            layer?.addSublayer(bar)
            return bar
        }
        smoothedBins = Array(repeating: 0, count: barCount)
    }

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        frameObserver?(link.timestamp)
        render(timestamp: link.targetTimestamp)
    }

    func render(timestamp: CFTimeInterval) {
        let elapsed = max(0, min(timestamp - (lastTimestamp ?? timestamp), 0.1))
        lastTimestamp = timestamp
        let source = resampledBins(meter.snapshot().bins)
        let attack = CGFloat(1 - exp(-elapsed / max(attackSeconds, 0.001)))
        let release = CGFloat(1 - exp(-elapsed / max(releaseSeconds, 0.001)))
        for index in smoothedBins.indices {
            let target = source[index].isFinite ? CGFloat(min(1, max(0, source[index]))) : 0
            if reduceMotion {
                smoothedBins[index] = target
            } else {
                let factor = target > smoothedBins[index] ? attack : release
                smoothedBins[index] += (target - smoothedBins[index]) * factor
            }
        }

        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        let showWave = isActive
        let lineWidth = min(4, max(2.4, width / 42))
        let spacing =
            (width - lineWidth * CGFloat(barLayers.count)) / CGFloat(max(barLayers.count - 1, 1))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        waveGlowLayer.isHidden = !showWave
        waveLayer.isHidden = !showWave
        ribbonLayers.forEach { $0.isHidden = !showWave }
        if showWave {
            renderWave(levels: smoothedBins, width: width, height: height, timestamp: timestamp)
        }
        for (index, bar) in barLayers.enumerated() {
            bar.isHidden = showWave
            guard !showWave else { continue }
            let level = isActive ? smoothedBins[index] : 0
            let barHeight = max(4, 4 + (height - 4) * level)
            let x = lineWidth / 2 + CGFloat(index) * (lineWidth + spacing)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: (height - barHeight) / 2))
            path.addLine(to: CGPoint(x: x, y: (height + barHeight) / 2))
            bar.path = path
            bar.lineWidth = lineWidth
            bar.strokeColor = waveformColor.withAlphaComponent(0.56 + level * 0.40).cgColor
        }
        CATransaction.commit()
    }

    private func renderWave(
        levels: [CGFloat], width: CGFloat, height: CGFloat, timestamp: CFTimeInterval
    ) {
        // Three traveling strands share the actual microphone envelope. The
        // time-based carrier keeps motion continuous between audio callbacks;
        // silence collapses every strand to the center line.
        let count = max(48, min(120, barCount * 6))
        let energy = levels.reduce(0, +) / CGFloat(max(levels.count, 1))
        let phase = reduceMotion ? 0 : timestamp * 2 * .pi * 0.72
        let layers = [waveLayer] + ribbonLayers
        for (strand, shape) in layers.enumerated() {
            let offset = Double(strand) * 2.05
            let points = (0...count).map { index -> CGPoint in
                let x = Double(index) / Double(count)
                let position = x * Double(max(levels.count - 1, 0))
                let lower = min(Int(position), levels.count - 1)
                let upper = min(lower + 1, levels.count - 1)
                let fraction = CGFloat(position - Double(lower))
                let local = levels[lower] + (levels[upper] - levels[lower]) * fraction
                let envelope = Double(energy * 0.65 + local * 0.35)
                let taper = pow(max(0, sin(.pi * x)), 0.8)
                let carrier =
                    sin(x * 3.4 * .pi - phase + offset) * 0.7
                    + sin(x * 6.2 * .pi + phase * 0.63 + offset) * 0.3
                return CGPoint(
                    x: x * width,
                    y: height / 2 + carrier * envelope * taper * (height - 4) / 2)
            }
            let path = CGMutablePath()
            Self.addSmoothCurve(through: points, to: path)
            shape.path = path
            shape.fillColor = nil
            shape.strokeColor = waveformColor.withAlphaComponent(strand == 0 ? 0.95 : 0.42).cgColor
            shape.lineWidth = strand == 0 ? 2.0 : 1.25
            if strand == 0 {
                waveGlowLayer.path = path
                waveGlowLayer.strokeColor = waveformColor.withAlphaComponent(0.12).cgColor
                waveGlowLayer.lineWidth = 5
            }
        }
    }

    private func syncLayerScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        waveGlowLayer.contentsScale = scale
        waveLayer.contentsScale = scale
        ribbonLayers.forEach { $0.contentsScale = scale }
        barLayers.forEach { $0.contentsScale = scale }
    }

    private static func addSmoothCurve(
        through points: [CGPoint],
        to path: CGMutablePath,
        startsNewSubpath: Bool = true
    ) {
        guard let first = points.first else { return }
        if startsNewSubpath {
            path.move(to: first)
        }
        guard points.count > 1 else { return }
        for index in 0..<(points.count - 1) {
            let previous = index > 0 ? points[index - 1] : points[index]
            let current = points[index]
            let next = points[index + 1]
            let following = index + 2 < points.count ? points[index + 2] : next
            let control1 = CGPoint(
                x: current.x + (next.x - previous.x) / 6,
                y: current.y + (next.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: next.x - (following.x - current.x) / 6,
                y: next.y - (following.y - current.y) / 6
            )
            path.addCurve(to: next, control1: control1, control2: control2)
        }
    }

    private func resampledBins(_ source: [Float]) -> [Float] {
        Self.resampledBins(source, count: barCount)
    }

    static func resampledBins(_ source: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard let first = source.first else {
            return Array(repeating: 0, count: count)
        }
        guard count > 1, source.count > 1 else {
            return Array(repeating: first, count: count)
        }
        return (0..<count).map { index in
            let position = Double(index) * Double(source.count - 1) / Double(count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, source.count - 1)
            let fraction = Float(position - Double(lower))
            return source[lower] + (source[upper] - source[lower]) * fraction
        }
    }
}
