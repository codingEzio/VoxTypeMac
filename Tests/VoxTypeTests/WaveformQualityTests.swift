import AppKit
import QuartzCore
import Testing

@testable import VoxType

@Test @MainActor func waveformMovesBetweenAudioCallbacks() {
  let meter = AudioLevelMeter()
  meter.publish(Array(repeating: 0.65, count: AudioMeterFrame.binCount))
  let view = DisplayLinkedWaveformView(meter: meter, bars: 12)
  view.frame = NSRect(x: 0, y: 0, width: 160, height: 32)
  view.update(color: .systemBlue, bars: 12, isActive: true, reduceMotion: false)
  // Let the audio envelope settle, then check two adjacent display frames.
  for index in 0..<12 { view.render(timestamp: Double(index) * 0.1) }
  let first = (view.layer?.sublayers?.first as? CAShapeLayer)?.path
  view.render(timestamp: 1.1 + 1.0 / 120.0)
  let second = (view.layer?.sublayers?.first as? CAShapeLayer)?.path
  #expect(first != nil && second != nil)
  #expect(first != second)
}

@Test @MainActor func reducedMotionHasNoTravelAndSilenceHasNoInventedActivity() {
  for level: Float in [0, 0.7] {
    let meter = AudioLevelMeter()
    meter.publish(Array(repeating: level, count: AudioMeterFrame.binCount))
    let view = DisplayLinkedWaveformView(meter: meter, bars: 12)
    view.frame = NSRect(x: 0, y: 0, width: 160, height: 32)
    view.update(color: .systemBlue, bars: 12, isActive: true, reduceMotion: level > 0)
    for index in 0..<12 { view.render(timestamp: Double(index) * 0.1) }
    let first = (view.layer?.sublayers?.first as? CAShapeLayer)?.path
    view.render(timestamp: 2)
    let second = (view.layer?.sublayers?.first as? CAShapeLayer)?.path
    #expect(first == second)
  }
}

@Test @MainActor func waveformRenderFitsTheDisplayFrameBudget() {
  let meter = AudioLevelMeter()
  meter.publish([0.1, 0.2, 0.6, 0.8, 0.7, 0.9, 0.4, 0.7, 0.5, 0.6, 0.2, 0.1])
  let view = DisplayLinkedWaveformView(meter: meter, bars: 24)
  view.frame = NSRect(x: 0, y: 0, width: 240, height: 44)
  view.update(color: .systemOrange, bars: 24, isActive: true, reduceMotion: false)
  let refreshRate = Double(NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60)
  var costs: [Double] = []
  for frame in 0..<1_000 {
    let start = CACurrentMediaTime()
    view.render(timestamp: Double(frame) / max(1, refreshRate))
    costs.append(CACurrentMediaTime() - start)
  }
  costs.sort()
  let p95 = costs[Int(Double(costs.count) * 0.95)]
  print("VOXTYPE_RENDER p95_ms=\(p95 * 1000) frame_budget_ms=\(1000 / refreshRate)")
  #expect(p95 < 1 / refreshRate)
}

@Test @MainActor func waveformAppearanceFixturesWhenExplicitlyEnabled() throws {
  guard ProcessInfo.processInfo.environment["VOXTYPE_RENDER_WAVEFORM"] == "1" else { return }
  let output = SettingsFile.stateURL.appendingPathComponent("upgrade-20260912")
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  for dark in [false, true] {
    let meter = AudioLevelMeter()
    meter.publish([0.2, 0.4, 0.7, 0.9, 0.8, 0.6, 0.7, 0.9, 0.8, 0.5, 0.3, 0.2])
    let view = DisplayLinkedWaveformView(meter: meter, bars: 24)
    view.frame = NSRect(x: 0, y: 0, width: 240, height: 44)
    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    view.update(
      color: dark ? .systemTeal : .systemBlue, bars: 24, isActive: true, reduceMotion: false)
    for frame in 0..<240 { view.render(timestamp: Double(frame) / 120) }
    let context = CGContext(
      data: nil, width: 960, height: 176, bitsPerComponent: 8,
      bytesPerRow: 960 * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: 4, y: 4)
    context.setFillColor((dark ? NSColor(calibratedWhite: 0.1, alpha: 1) : .white).cgColor)
    context.fill(view.bounds)
    view.layer?.render(in: context)
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(
      to: output.appendingPathComponent(dark ? "waveform-dark.png" : "waveform-light.png"))
  }
}
