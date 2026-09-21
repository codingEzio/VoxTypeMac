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
    #expect(shortcut.localizationKey.english == settingsTitle)
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
    MotionStyle.allCases.map { $0.localizationKey.english }
      == ["Quiet", "Liquid", "Bright"])
  #expect(
    DeliveryMode.allCases.map { $0.localizationKey.english }
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
    #expect(phase.localizationKey.english == title)
    #expect(phase.isBusy == isBusy)
  }
}

@Test func dictationLanguagesKeepBothSupportedVoiceInputsVisible() {
  #expect(DictationLanguage.allCases == [.englishUS, .simplifiedChinese])
  #expect(DictationLanguage.englishUS.locale.identifier == "en-US")
  #expect(DictationLanguage.simplifiedChinese.locale.identifier == "zh-CN")
  #expect(DictationLanguage.englishUS.titleKey.english == "English (US)")
  #expect(DictationLanguage.simplifiedChinese.titleKey.english == "Simplified Chinese")
  #expect(DictationLanguage.englishUS.shortTitleKey.english == "English")
  #expect(DictationLanguage.simplifiedChinese.shortTitleKey.english == "Chinese")
  #expect(DictationLanguage.englishUS.statusTitleKey.english == "English")
  #expect(DictationLanguage.simplifiedChinese.statusTitleKey.english == "Chinese + English")
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

@Test func accessSetupKeepsOneDirectNextActionVisible() {
  var snapshot = PermissionSnapshot(
    microphone: .notDetermined,
    speechRecognition: .notDetermined,
    accessibility: .notDetermined,
    inputMonitoring: .granted
  )

  #expect(PermissionSetupPlan.nextMissing(in: snapshot) == .microphone)
  snapshot.microphone = .granted
  #expect(PermissionSetupPlan.nextMissing(in: snapshot) == .speechRecognition)
  snapshot.speechRecognition = .granted
  #expect(PermissionSetupPlan.nextMissing(in: snapshot) == .accessibility)
  snapshot.accessibility = .granted
  #expect(PermissionSetupPlan.nextMissing(in: snapshot) == nil)
}

@Test func audioCaptureRetriesOneFreshEngineAfterRouteFormatFailure() {
  let routeChangeError = NSError(
    domain: "com.apple.coreaudio.avfaudio",
    code: -10_868
  )

  #expect(AudioCapture.shouldRetryStart(after: routeChangeError, attempt: 0))
  #expect(!AudioCapture.shouldRetryStart(after: routeChangeError, attempt: 1))
  #expect(!AudioCapture.shouldRetryStart(after: CocoaError(.fileWriteNoPermission), attempt: 0))
}
