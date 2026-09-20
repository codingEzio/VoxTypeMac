@preconcurrency import AVFAudio
import CoreGraphics
import Foundation
import Testing

@testable import VoxType

@Test func everyShortcutHasOneStableChord() {
  let cases: [(DictationShortcut, CGKeyCode, CGEventFlags, String)] = [
    (.optionPeriod, 47, .maskAlternate, "⌥ Period"),
    (.optionComma, 43, .maskAlternate, "⌥ Comma"),
    (.optionSlash, 44, .maskAlternate, "⌥ Slash"),
    (.optionSemicolon, 41, .maskAlternate, "⌥ Semicolon"),
    (.controlPeriod, 47, .maskControl, "⌃ Period"),
    (.controlSlash, 44, .maskControl, "⌃ Slash"),
    (.rightOption, 61, [], "Right Option"),
    (.rightCommand, 54, [], "Right Command"),
  ]

  #expect(cases.count == DictationShortcut.allCases.count)
  for (shortcut, keyCode, flags, settingsTitle) in cases {
    #expect(shortcut.triggerKeyCode == keyCode)
    #expect(shortcut.requiredFlags == flags)
    #expect(shortcut.settingsTitle == settingsTitle)
    if shortcut.isModifierTap {
      #expect(!shortcut.matchesChord(flags: flags))
    } else {
      #expect(shortcut.matchesChord(flags: flags))
      #expect(!shortcut.matchesChord(flags: [flags, .maskCommand]))
    }
  }
}

@Test func modelTitlesCoverEveryUserVisibleCase() {
  #expect(
    MotionStyle.allCases.map { $0.title(simplifiedChinese: false) }
      == ["Quiet", "Liquid", "Bright"])
  #expect(
    MotionStyle.allCases.map { $0.title(simplifiedChinese: true) }
      == ["克制", "液态", "鲜明"])
  #expect(
    DeliveryMode.allCases.map(\.title)
      == ["Insert at cursor", "Clipboard only", "Insert + clipboard", "Save only"])

  let phases: [(RecorderPhase, String, Bool)] = [
    (.idle, "Ready", false),
    (.preparing, "Preparing", true),
    (.recording, "Listening", true),
    (.finalizing, "Finishing transcript", true),
    (.delivering, "Sending text", true),
    (.failed("test"), "Needs attention", false),
  ]
  for (phase, title, isBusy) in phases {
    #expect(phase.title == title)
    #expect(phase.isBusy == isBusy)
  }
}

@Test func dictationLanguagesKeepBothSupportedVoiceInputsVisible() {
  #expect(DictationLanguage.allCases == [.englishUS, .simplifiedChinese])
  #expect(DictationLanguage.englishUS.locale.identifier == "en-US")
  #expect(DictationLanguage.simplifiedChinese.locale.identifier == "zh-CN")
  #expect(DictationLanguage.englishUS.title(simplifiedChinese: false) == "English (US)")
  #expect(DictationLanguage.simplifiedChinese.title(simplifiedChinese: false) == "Simplified Chinese")
  #expect(DictationLanguage.englishUS.title(simplifiedChinese: true) == "英语（美国）")
  #expect(DictationLanguage.simplifiedChinese.title(simplifiedChinese: true) == "简体中文")
  #expect(DictationLanguage.englishUS.shortTitle(simplifiedChinese: false) == "English")
  #expect(DictationLanguage.simplifiedChinese.shortTitle(simplifiedChinese: false) == "Chinese")
  #expect(DictationLanguage.englishUS.shortTitle(simplifiedChinese: true) == "英文")
  #expect(DictationLanguage.simplifiedChinese.shortTitle(simplifiedChinese: true) == "中文")
  #expect(DictationLanguage.englishUS.statusTitle(simplifiedChinese: false) == "English")
  #expect(DictationLanguage.simplifiedChinese.statusTitle(simplifiedChinese: false) == "Chinese + English")
  #expect(DictationLanguage.englishUS.statusTitle(simplifiedChinese: true) == "英文")
  #expect(DictationLanguage.simplifiedChinese.statusTitle(simplifiedChinese: true) == "中英混说")
}

@Test @MainActor func waveformOverlayJoinsOtherAppsFullScreenSpaces() {
  let behavior = HUDController.overlayCollectionBehavior
  #expect(behavior.contains(.canJoinAllApplications))
  #expect(behavior.contains(.canJoinAllSpaces))
  #expect(!behavior.contains(.fullScreenAuxiliary))
}

@Test @MainActor func waveformResamplingKeepsEverySurfaceSafe() {
  #expect(DisplayLinkedWaveformView.resampledBins([], count: 24).count == 24)
  #expect(
    DisplayLinkedWaveformView.resampledBins([0.5], count: 24)
      == Array(repeating: 0.5, count: 24)
  )
  #expect(
    DisplayLinkedWaveformView.resampledBins([0, 1], count: 4)
      == [0, 1.0 / 3, 2.0 / 3, 1]
  )
}

@Test func permissionSnapshotMapsEveryCategory() {
  let snapshot = PermissionSnapshot(
    microphone: .granted,
    speechRecognition: .denied,
    accessibility: .notDetermined,
    inputMonitoring: .granted
  )
  #expect(snapshot.state(for: .microphone) == .granted)
  #expect(snapshot.state(for: .speechRecognition) == .denied)
  #expect(snapshot.state(for: .accessibility) == .notDetermined)
  #expect(snapshot.state(for: .inputMonitoring) == .granted)
  #expect(!snapshot.canRecord)
  #expect(snapshot.canUseGlobalHotkey)
  #expect(!snapshot.canInsertText)
}

@Test @MainActor func coreErrorsKeepActionableMessages() {
  let deliveryErrors: [OutputDispatcher.DeliveryError] = [
    .accessibilityPermissionMissing,
    .emptyTranscript,
    .originalInputUnavailable,
    .pasteEventUnavailable,
    .pasteCouldNotBeConfirmed,
  ]
  let refinementErrors: [RefinementError] = [
    .modelUnavailable,
    .downloadFailed,
    .checksumMismatch,
    .missingRuntime,
    .timedOut,
    .helperFailed,
    .emptyResult,
  ]

  for error in deliveryErrors {
    #expect(!(error.errorDescription ?? "").isEmpty)
  }
  for error in refinementErrors {
    #expect(!(error.errorDescription ?? "").isEmpty)
  }
  #expect(!(AudioCapture.CaptureError.invalidInputFormat.errorDescription ?? "").isEmpty)
  #expect(!(NativeSpeechEngine.EngineError.audioFormatUnavailable.errorDescription ?? "").isEmpty)
  #expect(
    (NativeSpeechEngine.EngineError.unsupportedLocale("xx").errorDescription ?? "")
      .contains("xx"))
}

@Test func stoppingIdleAudioCaptureIsAZeroResult() {
  let result = AudioCapture().stop()
  #expect(result.durationSeconds == 0)
  #expect(result.writeErrorDescription == nil)
}
