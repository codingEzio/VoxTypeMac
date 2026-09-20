@preconcurrency import AVFAudio
import AppKit
import CoreMedia
import Foundation
import Testing

@testable import VoxType

@Test func transcriptAccumulatorReplacesVolatileRangeAndJoinsLanguages() {
  var accumulator = TranscriptAccumulator()
  let first = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1_000))
  let second = CMTimeRange(
    start: CMTime(seconds: 1, preferredTimescale: 1_000),
    duration: CMTime(seconds: 1, preferredTimescale: 1_000)
  )
  #expect(accumulator.apply(text: "cold ex", range: first, isFinal: false).text == "cold ex")
  #expect(accumulator.apply(text: "codex", range: first, isFinal: true).text == "codex")
  #expect(accumulator.apply(text: "中文", range: second, isFinal: true).text == "codex中文")
}

@Test func transcriptAccumulatorKeepsFinalizedTextWhenVolatileNeighborOverlaps() {
  var accumulator = TranscriptAccumulator()
  let first = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1_000))
  let neighbor = CMTimeRange(
    start: CMTime(seconds: 0.95, preferredTimescale: 1_000),
    duration: CMTime(seconds: 1.05, preferredTimescale: 1_000)
  )
  #expect(accumulator.apply(text: "hello", range: first, isFinal: true).text == "hello")
  let live = accumulator.apply(text: "world", range: neighbor, isFinal: false)
  #expect(live.stableText == "hello")
  #expect(live.draftTail == "world")
  #expect(live.text == "hello world")
}

@Test func transcriptAccumulatorKeepsFinalsWhenWholeUtteranceVolatileRewrites() {
  var accumulator = TranscriptAccumulator()
  let first = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1_000))
  let whole = CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 1_000))
  #expect(accumulator.apply(text: "codex", range: first, isFinal: true).text == "codex")
  let live = accumulator.apply(text: "cold ex later", range: whole, isFinal: false)
  #expect(live.stableText == "codex")
  #expect(live.text.hasPrefix("codex"))
  #expect(accumulator.bestText == "cold ex later")
}

@Test func transcriptAccumulatorCollapsesRepeatedSpaces() {
  #expect(TranscriptAccumulator.normalize("  hello   中文 \n next ") == "hello 中文\nnext")
}

@Test func rightCommandBounceGuardAllowsShortUtterances() {
  #expect(GlobalHotkeyMonitor.tapBounceGuardSeconds < 0.15)
  #expect(GlobalHotkeyMonitor.tapBounceGuardSeconds > 0.04)
  #expect(GlobalHotkeyMonitor.rightCommandKeyCode == 54)
}

@Test func dictationShortcutPickerDefaultsToOptionPeriod() {
  #expect(DictationShortcut.default == .optionPeriod)
  #expect(DictationShortcut.optionPeriod.triggerKeyCode == 47)
  #expect(DictationShortcut.optionPeriod.matchesChord(flags: .maskAlternate))
  #expect(!DictationShortcut.optionPeriod.matchesChord(flags: [.maskAlternate, .maskCommand]))
  #expect(DictationShortcut.rightCommand.isModifierTap)
  #expect(DictationShortcut.rightCommand.triggerKeyCode == GlobalHotkeyMonitor.rightCommandKeyCode)
}

@Test func microphoneCadenceCanFeedA120HzPresentation() {
  let slowestCommonSampleRate = 44_100.0
  let callbacksPerSecond = slowestCommonSampleRate / Double(AudioCapture.inputBufferFrameCount)
  let maximumQueuedMilliseconds =
    Double(
      AudioCapture.inputBufferFrameCount
        * AVAudioFrameCount(NativeSpeechEngine.liveInputBufferLimit)
    ) / slowestCommonSampleRate * 1_000
  #expect(AudioCapture.inputBufferFrameCount == 256)
  #expect(callbacksPerSecond >= 120)
  #expect(NativeSpeechEngine.liveInputBufferLimit == 16)
  #expect(maximumQueuedMilliseconds < 100)
}

@Test func settingsWindowUsesTheCompactDesktopSize() {
  #expect(SettingsLayout.windowWidth == 660)
  #expect(SettingsLayout.defaultHeight == 360)
  #expect(SettingsLayout.contentInset == 24)
  #expect(SettingsLayout.columnSpacing == 24)
  #expect(SettingsLayout.labelWidth == 82)
  #expect(SettingsLayout.controlWidth == 184)
}

@Test @MainActor func cursorDeliveryUsesTheMeasuredClipboardSettle() {
  #expect(OutputDispatcher.clipboardSettleNanoseconds == 20_000_000)
  #expect(OutputDispatcher.clipboardSettleNanoseconds < 33_333_334)
}

@Test func liveMeterKeepsExactlyTwelveNormalizedBins() {
  #expect(AudioMeterFrame.silence.bins.count == AudioMeterFrame.binCount)
  #expect(AudioMeterFrame.binCount == 12)
  let meter = AudioLevelMeter()
  let expected = Array(repeating: Float(0.5), count: AudioMeterFrame.binCount)
  meter.publish(expected)
  #expect(meter.snapshot().bins == expected)
}

@Test func liveMeterIngestsPCMIntoARollingWindow() {
  let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
  buffer.frameLength = 256
  for index in 0..<256 {
    buffer.floatChannelData![0][index] = sin(Float(index) * 0.18) * 0.45
  }
  let meter = AudioLevelMeter()
  meter.ingest(buffer)
  #expect(meter.snapshot().bins.count == AudioMeterFrame.binCount)
  #expect(meter.snapshotWindow().count == 256)
  #expect(meter.snapshot().bins.contains { $0 > 0 })
}

@Test func liveTranscriptDisplayKeepsTheSelectedLanguageAsDraftUntilTheFinalPass() {
  let live = LiveTranscript(text: "hello world", stableText: "hello", draftTail: "world")
  let refined = LiveTranscriptDisplay.parts(from: live, finalPass: true)
  #expect(refined.stable.isEmpty)
  #expect(refined.draft == "hello world")
  let appleOnly = LiveTranscriptDisplay.parts(from: live, finalPass: false)
  #expect(appleOnly.stable == "hello")
  #expect(appleOnly.draft == "world")
}

@Test @MainActor func displayLinkCadenceProbeWhenExplicitlyEnabled() async throws {
  guard ProcessInfo.processInfo.environment["VOXTYPE_RUN_CADENCE_PROBE"] == "1" else { return }
  guard
    let screen = NSScreen.screens.max(by: { lhs, rhs in
      lhs.maximumFramesPerSecond < rhs.maximumFramesPerSecond
    })
  else { return }

  let meter = AudioLevelMeter()
  meter.publish(Array(repeating: 0.7, count: AudioMeterFrame.binCount))
  let view = DisplayLinkedWaveformView(meter: meter, bars: 12)
  view.frame = NSRect(x: 0, y: 0, width: 160, height: 32)
  var timestamps: [CFTimeInterval] = []
  view.frameObserver = { timestamps.append($0) }

  NSApplication.shared.setActivationPolicy(.accessory)
  let window = NSPanel(
    contentRect: NSRect(origin: .zero, size: NSSize(width: 160, height: 32)),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false,
    screen: screen
  )
  window.ignoresMouseEvents = true
  window.setFrameOrigin(
    NSPoint(x: screen.visibleFrame.maxX - 180, y: screen.visibleFrame.minY + 20))
  window.isOpaque = false
  window.backgroundColor = .clear
  window.contentView = view
  window.orderFrontRegardless()
  view.update(
    color: .systemRed, bars: 12, isActive: true, reduceMotion: false)

  try await Task.sleep(for: .milliseconds(1_200))

  view.update(
    color: .systemRed, bars: 12, isActive: false, reduceMotion: false, attackSeconds: 0.008,
    releaseSeconds: 0.036)
  window.orderOut(nil)
  window.close()

  guard let first = timestamps.first, let last = timestamps.last, timestamps.count > 1 else {
    Issue.record("Display link did not fire during the cadence probe")
    return
  }
  let measuredHz = Double(timestamps.count - 1) / (last - first)
  let screenMax = Double(screen.maximumFramesPerSecond)
  print("VOXTYPE_CADENCE measured_hz=\(measuredHz) screen_max=\(screenMax)")
  if screenMax >= 120 {
    #expect(measuredHz >= min(115, screenMax - 3))
  }
}

@Test func reservedSpeechSessionIsFasterOnTheSecondPrepare() async throws {
  guard ProcessInfo.processInfo.environment["VOXTYPE_RUN_SPEED_PROBE"] == "1" else { return }

  let engine = NativeSpeechEngine()
  let locale = Locale(identifier: "en-US")
  let clock = ContinuousClock()

  let cold = try await clock.measure {
    _ = try await engine.prewarm(locale: locale)
  }
  let warm = try await clock.measure {
    _ = try await engine.prewarm(locale: locale)
  }

  print("VOXTYPE_SPEED_PROBE cold_prewarm=\(cold) warm_prewarm=\(warm)")
  #expect(warm < .milliseconds(80) || warm * 5 < cold)
}

@Test func speechPreparationCacheCoalescesConcurrentWarmup() async throws {
  let cache = SpeechPreparationCache()
  let counter = PreparationBuildCounter()
  let locale = Locale(identifier: "en-US")
  let builder: SpeechPreparationCache.Builder = { requestedLocale in
    await counter.increment()
    try await Task.sleep(for: .milliseconds(20))
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    return PreparedSpeechConfiguration(resolvedLocale: requestedLocale, analyzerFormat: format)
  }

  async let first = cache.configuration(for: locale, build: builder)
  async let second = cache.configuration(for: locale, build: builder)
  let (firstResult, secondResult) = try await (first, second)
  let thirdResult = try await cache.configuration(for: locale, build: builder)

  #expect(firstResult.analyzerFormat.sampleRate == 48_000)
  #expect(secondResult.analyzerFormat.sampleRate == 48_000)
  #expect(thirdResult.analyzerFormat.sampleRate == 48_000)
  #expect(await counter.value == 1)
}

@Test func syntheticLiveDictationReportsFirstUpdateLatency() async throws {
  guard let path = ProcessInfo.processInfo.environment["VOXTYPE_SYNTHETIC_AUDIO"] else {
    return
  }

  let engine = NativeSpeechEngine()
  let probe = RecognitionLatencyProbe()
  _ = try await engine.start(
    locale: Locale(identifier: "en-US"),
    onUpdate: { live in
      Task { await probe.record(live.text) }
    },
    onError: { _ in }
  )

  let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
  let frameCapacity = AudioCapture.inputBufferFrameCount
  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCapacity)!
  var sampleTime: AVAudioFramePosition = 0
  await probe.begin()

  while file.framePosition < file.length {
    try file.read(into: buffer, frameCount: frameCapacity)
    guard buffer.frameLength > 0 else { break }
    engine.consume(
      buffer,
      at: AVAudioTime(sampleTime: sampleTime, atRate: file.processingFormat.sampleRate)
    )
    sampleTime += AVAudioFramePosition(buffer.frameLength)
    try await Task.sleep(
      for: .seconds(Double(buffer.frameLength) / file.processingFormat.sampleRate)
    )
  }

  let finalizationStartedAt = Date()
  let finalText = try await engine.stop()
  let finalizationSeconds = Date().timeIntervalSince(finalizationStartedAt)
  try await Task.sleep(for: .milliseconds(50))
  let firstUpdateSeconds = await probe.firstUpdateSeconds
  print(
    "VOXTYPE_SYNTHETIC first_update=\(firstUpdateSeconds ?? -1)s "
      + "finalization=\(finalizationSeconds)s "
      + "audio=\(Double(file.length) / file.processingFormat.sampleRate)s"
  )
  #expect(firstUpdateSeconds != nil)
  #expect((firstUpdateSeconds ?? .infinity) < 2)
  #expect(finalizationSeconds < 1.5)
  #expect(!finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func sessionStoreFinishesAndReadsMetadata() async throws {
  let folder = SettingsFile.temporaryURL.appendingPathComponent("tests", isDirectory: true)
    .appendingPathComponent("VoxTypeTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let store = SessionStore()
  let draft = try await store.begin(
    in: folder, localeIdentifier: "zh-CN", targetApplication: "Test/App")
  let saved = try await store.finish(
    draft,
    transcript: "  hello 中文  ",
    durationSeconds: 1.25,
    targetApplication: "Test/App"
  )
  #expect(saved.characterCount == 8)
  #expect(saved.status == "complete")
  #expect(try String(contentsOf: saved.transcriptURL, encoding: .utf8) == "hello 中文")
  #expect(await store.recentSessions(in: folder).first?.baseName == saved.baseName)
  #expect(await store.latestTranscript(in: folder) == "hello 中文")
}

@Test func latestTranscriptWalksPastEmptyRecentSessions() async throws {
  let folder = SettingsFile.temporaryURL.appendingPathComponent("tests", isDirectory: true)
    .appendingPathComponent("LatestTranscript-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let store = SessionStore()
  let now = Date()

  for index in 0..<12 {
    try seedSavedSession(
      in: folder,
      name: String(format: "empty-%02d", index),
      startedAt: now.addingTimeInterval(TimeInterval(-index)),
      transcript: index.isMultiple(of: 2) ? "" : "   "
    )
  }
  try seedSavedSession(
    in: folder,
    name: "older-kept",
    startedAt: now.addingTimeInterval(-12),
    transcript: " kept older "
  )
  try seedUncontainedTranscriptSession(
    in: folder,
    name: "escaped",
    startedAt: now.addingTimeInterval(1)
  )

  #expect(await store.recentSessions(in: folder).count == 12)
  #expect(await store.recentSessions(in: folder).contains { $0.baseName == "older-kept" } == false)
  #expect(await store.recentSessions(in: folder, limit: -1).isEmpty)
  #expect(await store.latestTranscript(in: folder) == "kept older")
  #expect(await store.latestTranscript(in: URL(fileURLWithPath: "/tmp")) == nil)
}

@Test func latestTranscriptPrefersNewestNonEmptySession() async throws {
  let folder = SettingsFile.temporaryURL.appendingPathComponent("tests", isDirectory: true)
    .appendingPathComponent("LatestTranscriptNewest-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let store = SessionStore()
  let now = Date()
  try seedSavedSession(
    in: folder, name: "older", startedAt: now.addingTimeInterval(-2), transcript: "older text")
  try seedSavedSession(
    in: folder, name: "blank", startedAt: now.addingTimeInterval(-1), transcript: "")
  try seedSavedSession(in: folder, name: "newer", startedAt: now, transcript: "newer text")
  #expect(await store.latestTranscript(in: folder) == "newer text")
}

@Test @MainActor func idleTranscriptRestoreKeepsCurrentProcessText() {
  #expect(
    AppModel.restoredTranscript(phase: .idle, current: "", latest: "kept text") == "kept text")
  #expect(
    AppModel.restoredTranscript(phase: .idle, current: "already present", latest: "ignored") == nil)
  #expect(
    AppModel.restoredTranscript(phase: .recording, current: "", latest: "ignored") == nil)
}

@Test func settingsFileRoundTripsPortableValues() throws {
  let folder = SettingsFile.temporaryURL.appendingPathComponent("tests", isDirectory: true)
    .appendingPathComponent("VoxTypeConfigTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let url = folder.appendingPathComponent("config.toml")
  var file = SettingsFile(url: url)
  file.set("zh-Hans", for: "ui_language")
  file.set("en-US", for: "speech_mode")
  file.set("option-period", for: "dictation_shortcut")
  file.set("liquid", for: "motion_style")
  try file.write(to: url)
  let loaded = SettingsFile(url: url)
  #expect(loaded["ui_language"] == "zh-Hans")
  #expect(loaded["speech_mode"] == "en-US")
  #expect(loaded["dictation_shortcut"] == "option-period")
  #expect(loaded["motion_style"] == "liquid")
}

@Test func externalDataManifestOwnsThePortableStateRoot() throws {
  let folder = SettingsFile.temporaryURL.appendingPathComponent("tests", isDirectory: true)
    .appendingPathComponent("VoxTypeExternalData-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: folder) }
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let manifest = folder.appendingPathComponent("external-data.json")
  let source: [String: Any] = [
    "id": "portable-state-root",
    "description": "Portable VoxType state",
    "kind": "directory",
    "access": "read-write",
    "root": "application-support",
    "path": "VoxTypeMac",
    "required": true,
    "sensitive": true,
    "overrideEnv": "",
  ]
  let value: [String: Any] = [
    "schemaVersion": 1,
    "projectId": "client-voxtype",
    "sources": [source],
  ]
  try JSONSerialization.data(withJSONObject: value).write(to: manifest)
  let declared = try VoxTypeExternalData.portableStateRoot(
    manifestURL: manifest,
    applicationSupportRoot: folder
  )

  #expect(declared.path == folder.appendingPathComponent("VoxTypeMac").path)

  var invalidSource = source
  invalidSource["path"] = "data"
  let invalidValue: [String: Any] = [
    "schemaVersion": 1,
    "projectId": "client-voxtype",
    "sources": [invalidSource],
  ]
  try JSONSerialization.data(withJSONObject: invalidValue).write(to: manifest)
  var rejectedWrongRuntimeName = false
  do {
    _ = try VoxTypeExternalData.portableStateRoot(
      manifestURL: manifest,
      applicationSupportRoot: folder
    )
  } catch {
    rejectedWrongRuntimeName = true
  }
  #expect(rejectedWrongRuntimeName)

  try JSONSerialization.data(withJSONObject: value).write(to: manifest)
  let outside = FileManager.default.temporaryDirectory
    .appendingPathComponent("delete_after_use_voxtype_manifest_escape", isDirectory: true)
  let runtimeLink = folder.appendingPathComponent("VoxTypeMac", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: outside) }
  try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
  try FileManager.default.createSymbolicLink(at: runtimeLink, withDestinationURL: outside)
  var rejectedSymlinkEscape = false
  do {
    _ = try VoxTypeExternalData.portableStateRoot(
      manifestURL: manifest,
      applicationSupportRoot: folder
    )
  } catch {
    rejectedSymlinkEscape = true
  }
  #expect(rejectedSymlinkEscape)
}

private actor PreparationBuildCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}

private actor RecognitionLatencyProbe {
  private var startedAt: Date?
  private(set) var firstUpdateSeconds: TimeInterval?

  func begin() {
    startedAt = Date()
    firstUpdateSeconds = nil
  }

  func record(_ text: String) {
    guard firstUpdateSeconds == nil,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let startedAt
    else {
      return
    }
    firstUpdateSeconds = Date().timeIntervalSince(startedAt)
  }
}

@Test func failedOrEmptyRefinementAlwaysKeepsAppleTranscript() {
  let failed = senseVoiceSelection(apple: "Apple kept this", refined: nil)
  #expect(failed.text == "Apple kept this")
  #expect(failed.status == "apple-fallback")
  let empty = senseVoiceSelection(apple: "Apple kept this", refined: "  \n")
  #expect(empty.text == "Apple kept this")
  let refined = senseVoiceSelection(apple: "Apple", refined: "  SenseVoice  ")
  #expect(refined.text == "SenseVoice")
  #expect(refined.status == "sensevoice-refined")
}

@Test func englishModeDoesNotAcceptChineseRefinement() {
  let selected = senseVoiceSelection(
    apple: "This is an English sentence",
    refined: "这是一句中文",
    language: .englishUS
  )
  #expect(selected.text == "This is an English sentence")
  #expect(selected.status == "apple-fallback")
}

@Test func chineseModeKeepsMixedLanguageRefinement() {
  let selected = senseVoiceSelection(
    apple: "你好",
    refined: "你好 codex",
    language: .simplifiedChinese
  )
  #expect(selected.text == "你好 codex")
  #expect(selected.status == "sensevoice-refined")
}

@Test func refinementIsBounded() {
  #expect(RefinementPolicy.timeoutSeconds == 90)
  #expect(MotionStyle.allCases.count == 3)
}

@Test func truncatedChineseRefinementKeepsAppleTranscript() {
  let apple = "这是一段比较完整的中文口述内容，不应该被截断。"
  let truncated = senseVoiceSelection(
    apple: apple,
    refined: "这是",
    language: .simplifiedChinese
  )
  #expect(truncated.text == apple)
  #expect(truncated.status == "apple-fallback")
}

@Test func refinementRestoresAppleNumbersDroppedBySenseVoice() {
  let apple = "我现在中间这个波浪看起来并没有120fps，而且我说话这个内容看起来还不准确"
  let refined = "我现在中间这个波浪看起来并没有fps，而且我说话这个内容看起来还不准确"
  let merged = senseVoiceSelection(
    apple: apple,
    refined: refined,
    language: .simplifiedChinese
  )
  #expect(merged.text.contains("120"))
  #expect(merged.text.contains("fps"))
  #expect(merged.text.contains("波浪"))
  #expect(merged.status == "sensevoice-merged")
}

@Test func shortLanguageFlipKeepsAppleTranscript() {
  let english = senseVoiceSelection(apple: "hello 42 world", refined: "你好世界")
  #expect(english.text == "hello 42 world")
  #expect(english.status == "apple-fallback")
  let chinese = senseVoiceSelection(
    apple: "你好世界",
    refined: "hello world",
    language: .simplifiedChinese
  )
  #expect(chinese.text == "你好世界")
  #expect(chinese.status == "apple-fallback")
  let shortDuration = senseVoiceSelection(
    apple: "okay thanks",
    refined: "好的谢谢大家今天也是非常开心",
    durationSeconds: 1.8,
    language: .simplifiedChinese
  )
  #expect(shortDuration.text == "okay thanks")
}

@Test func privacySettingsLinksOpenExactPrivacyRows() {
  #expect(
    PrivacySettingsLink.url(.microphone)
      == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"
  )
  #expect(
    PrivacySettingsLink.url(.speechRecognition)
      == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_SpeechRecognition"
  )
  #expect(
    PrivacySettingsLink.url(.inputMonitoring)
      == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
  )
  #expect(
    PrivacySettingsLink.url(.accessibility)
      == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
  )
}

@Test func permissionPolicyRequestsOnceThenOpensSettings() {
  #expect(
    PermissionRequestPolicy.decide(osGranted: true, alreadyRequested: true) == .alreadyGranted)
  #expect(PermissionRequestPolicy.decide(osGranted: false, alreadyRequested: false) == .requestNow)
  #expect(PermissionRequestPolicy.decide(osGranted: false, alreadyRequested: true) == .openSettings)
  #expect(
    PermissionRequestPolicy.displayedState(osGranted: false, alreadyRequested: false)
      == .notDetermined)
  #expect(
    PermissionRequestPolicy.displayedState(osGranted: false, alreadyRequested: true) == .denied)
  #expect(
    PermissionRequestPolicy.decideRecording(authorized: false, notDetermined: true) == .requestNow)
  #expect(
    PermissionRequestPolicy.decideRecording(authorized: false, notDetermined: false)
      == .openSettings)
}

@Test func permissionReceiptIgnoresOtherBundleIds() throws {
  let receipt = PermissionRequestReceipt(
    bundleIdentifier: "app.voxtypemac.VoxTypeMac",
    accessibility: true,
    inputMonitoring: false
  )
  #expect(PermissionRequestStore.matchesIdentity(receipt, bundleIdentifier: "app.voxtypemac.VoxTypeMac"))
  #expect(!PermissionRequestStore.matchesIdentity(receipt, bundleIdentifier: "app.other"))
  let data = Data(
    """
    {"accessibility":true,"inputMonitoring":true}
    """.utf8)
  let legacy = try JSONDecoder().decode(PermissionRequestReceipt.self, from: data)
  #expect(legacy.schemaVersion == PermissionRequestReceipt.legacySchemaVersion)
  #expect(!PermissionRequestStore.matchesIdentity(legacy, bundleIdentifier: "app.voxtypemac.VoxTypeMac"))
}

@Test func longerMixedRefinementStillUsesSenseVoice() {
  let apple = "我现在中间这个波浪看起来并没有120fps，而且我说话这个内容看起来还不准确"
  let refined = "我现在中间这个波浪看起来并没有120fps，而且我说话这个内容看起来还不准确"
  let kept = senseVoiceSelection(
    apple: apple,
    refined: refined,
    durationSeconds: 8,
    language: .simplifiedChinese
  )
  #expect(kept.text == refined)
  #expect(kept.status == "sensevoice-refined")
}

@Test func refinementOnlyRestoresTokensWithMatchingContext() {
  let unchanged = senseVoiceSelection(
    apple: "120 starts here and ends at 60fps",
    refined: "starts here and ends at fps"
  )
  #expect(unchanged.text == "starts here and ends at fps")
  #expect(unchanged.status == "sensevoice-refined")

  let alreadyPresent = senseVoiceSelection(
    apple: "保持 API 稳定",
    refined: "保持 api 稳定",
    language: .simplifiedChinese
  )
  #expect(alreadyPresent.text == "保持 api 稳定")
  #expect(alreadyPresent.status == "sensevoice-refined")
}

@Test func refinementSelectionTrimsInputsAndHandlesEmptyApple() {
  #expect(senseVoiceSelection(apple: "  kept  ", refined: nil).text == "kept")
  let refined = senseVoiceSelection(apple: " \n", refined: "  replacement  ")
  #expect(refined.text == "replacement")
  #expect(refined.status == "sensevoice-refined")
}

private func seedSavedSession(
  in folder: URL,
  name: String,
  startedAt: Date,
  transcript: String
) throws {
  let audioURL = folder.appendingPathComponent("\(name).caf")
  let transcriptURL = folder.appendingPathComponent("\(name).txt")
  let metadataURL = folder.appendingPathComponent("\(name).json")
  let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
  try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
  try encodeSession(
    SavedSession(
      baseName: name,
      startedAt: startedAt,
      finishedAt: startedAt,
      localeIdentifier: "en-US",
      durationSeconds: 1,
      audioPath: audioURL.path,
      transcriptPath: transcriptURL.path,
      metadataPath: metadataURL.path,
      status: clean.isEmpty ? "audio-only" : "complete",
      targetApplication: "Test",
      characterCount: clean.count
    ),
    to: metadataURL
  )
}

private func seedUncontainedTranscriptSession(in folder: URL, name: String, startedAt: Date) throws
{
  let audioURL = folder.appendingPathComponent("\(name).caf")
  let metadataURL = folder.appendingPathComponent("\(name).json")
  try encodeSession(
    SavedSession(
      baseName: name,
      startedAt: startedAt,
      finishedAt: startedAt,
      localeIdentifier: "en-US",
      durationSeconds: 1,
      audioPath: audioURL.path,
      transcriptPath: "/tmp/voxtype-escaped-transcript.txt",
      metadataPath: metadataURL.path,
      status: "complete",
      targetApplication: "Test",
      characterCount: 4
    ),
    to: metadataURL
  )
}

private func encodeSession(_ session: SavedSession, to url: URL) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  encoder.dateEncodingStrategy = .iso8601
  try encoder.encode(session).write(to: url, options: .atomic)
}

private func senseVoiceSelection(
  apple: String, refined: String?, durationSeconds: TimeInterval? = nil,
  language: DictationLanguage = .englishUS
) -> TranscriptRefinement.Selection {
  TranscriptRefinement.select(
    apple: apple, refined: refined, durationSeconds: durationSeconds,
    language: language, backend: .senseVoice)
}
