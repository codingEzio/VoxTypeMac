import CoreGraphics
import Foundation
import QuartzCore

public enum DictationShortcut: String, CaseIterable, Identifiable, Sendable {
  case optionPeriod = "option-period"
  case optionComma = "option-comma"
  case optionSlash = "option-slash"
  case optionSemicolon = "option-semicolon"
  case controlPeriod = "control-period"
  case controlSlash = "control-slash"
  case rightOption = "right-option"
  case rightCommand = "right-command"

  public var id: String { rawValue }
  public static let `default` = optionPeriod
  static let rightCommandKeyCode = CGKeyCode(54)
  static let rightOptionKeyCode = CGKeyCode(61)
  static let periodKeyCode = CGKeyCode(47)

  public var title: String {
    switch self {
    case .optionPeriod: "⌥."
    case .optionComma: "⌥,"
    case .optionSlash: "⌥/"
    case .optionSemicolon: "⌥;"
    case .controlPeriod: "⌃."
    case .controlSlash: "⌃/"
    case .rightOption: "Right ⌥"
    case .rightCommand: "Right ⌘"
    }
  }

  var settingsTitle: String {
    switch self {
    case .optionPeriod: "⌥ Period"
    case .optionComma: "⌥ Comma"
    case .optionSlash: "⌥ Slash"
    case .optionSemicolon: "⌥ Semicolon"
    case .controlPeriod: "⌃ Period"
    case .controlSlash: "⌃ Slash"
    case .rightOption: "Right Option"
    case .rightCommand: "Right Command"
    }
  }

  var isModifierTap: Bool {
    self == .rightCommand || self == .rightOption
  }

  var triggerKeyCode: CGKeyCode {
    switch self {
    case .optionPeriod, .controlPeriod: Self.periodKeyCode
    case .optionComma: 43
    case .optionSlash, .controlSlash: 44
    case .optionSemicolon: 41
    case .rightOption: Self.rightOptionKeyCode
    case .rightCommand: Self.rightCommandKeyCode
    }
  }

  var requiredFlags: CGEventFlags {
    switch self {
    case .optionPeriod, .optionComma, .optionSlash, .optionSemicolon:
      .maskAlternate
    case .controlPeriod, .controlSlash:
      .maskControl
    case .rightOption, .rightCommand:
      []
    }
  }

  func matchesChord(flags: CGEventFlags) -> Bool {
    guard !isModifierTap else { return false }
    let held = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
    return held == requiredFlags
  }
}

public enum UILanguage: String, CaseIterable, Identifiable, Sendable {
  case english = "en"
  case simplifiedChinese = "zh-Hans"

  public var id: String { rawValue }
  public var title: String { self == .english ? "English" : "简体中文" }
}

public enum DictationLanguage: String, CaseIterable, Identifiable, Sendable {
  case englishUS = "en-US"
  case simplifiedChinese = "zh-CN"

  public var id: String { rawValue }

  public var locale: Locale {
    Locale(identifier: rawValue)
  }

  func title(simplifiedChinese: Bool) -> String {
    switch self {
    case .englishUS:
      simplifiedChinese ? "英语（美国）" : "English (US)"
    case .simplifiedChinese:
      simplifiedChinese ? "简体中文" : "Simplified Chinese"
    }
  }

  func shortTitle(simplifiedChinese: Bool) -> String {
    switch self {
    case .englishUS:
      simplifiedChinese ? "英文" : "English"
    case .simplifiedChinese:
      simplifiedChinese ? "中文" : "Chinese"
    }
  }

  func statusTitle(simplifiedChinese: Bool) -> String {
    switch self {
    case .englishUS:
      simplifiedChinese ? "英文" : "English"
    case .simplifiedChinese:
      simplifiedChinese ? "中英混说" : "Chinese + English"
    }
  }
}

public enum MotionStyle: String, CaseIterable, Identifiable, Sendable {
  case quiet
  case liquid
  case bright

  public var id: String { rawValue }

  func title(simplifiedChinese: Bool) -> String {
    switch self {
    case .quiet: simplifiedChinese ? "克制" : "Quiet"
    case .liquid: simplifiedChinese ? "液态" : "Liquid"
    case .bright: simplifiedChinese ? "鲜明" : "Bright"
    }
  }

  var showDuration: TimeInterval {
    switch self {
    case .quiet: 0.22
    case .liquid: 0.28
    case .bright: 0.18
    }
  }

  var hideDuration: TimeInterval {
    switch self {
    case .quiet: 0.16
    case .liquid: 0.14
    case .bright: 0.10
    }
  }

  var appearScale: CGFloat {
    switch self {
    case .quiet: 0.985
    case .liquid: 0.96
    case .bright: 0.94
    }
  }

  var attackSeconds: Double {
    switch self {
    case .quiet: 0.04
    case .liquid: 0.03
    case .bright: 0.018
    }
  }

  var releaseSeconds: Double {
    switch self {
    case .quiet: 0.14
    case .liquid: 0.11
    case .bright: 0.08
    }
  }

  var breathHertz: Double {
    switch self {
    case .quiet: 0.7
    case .liquid: 1.15
    case .bright: 1.7
    }
  }

  var timingFunction: CAMediaTimingFunction {
    switch self {
    case .quiet: CAMediaTimingFunction(name: .easeOut)
    case .liquid: CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    case .bright: CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.28, 1)
    }
  }
}

public enum DeliveryMode: String, CaseIterable, Identifiable, Codable, Sendable {
  case insertOnly
  case clipboardOnly
  case insertAndClipboard
  case saveOnly

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .insertOnly: "Insert at cursor"
    case .clipboardOnly: "Clipboard only"
    case .insertAndClipboard: "Insert + clipboard"
    case .saveOnly: "Save only"
    }
  }
}

public enum RecorderPhase: Equatable, Sendable {
  case idle
  case preparing
  case recording
  case finalizing
  case delivering
  case failed(String)

  public var title: String {
    switch self {
    case .idle: "Ready"
    case .preparing: "Preparing"
    case .recording: "Listening"
    case .finalizing: "Finishing transcript"
    case .delivering: "Sending text"
    case .failed: "Needs attention"
    }
  }

  public var isBusy: Bool {
    switch self {
    case .preparing, .recording, .finalizing, .delivering: true
    case .idle, .failed: false
    }
  }

  public var isFailed: Bool {
    if case .failed = self { return true }
    return false
  }
}

public enum PermissionState: String, Sendable {
  case granted
  case denied
  case notDetermined
}

public struct PermissionSnapshot: Equatable, Sendable {
  public var microphone: PermissionState
  public var speechRecognition: PermissionState
  public var accessibility: PermissionState
  public var inputMonitoring: PermissionState

  public var canRecord: Bool {
    microphone == .granted && speechRecognition == .granted
  }

  public var canUseGlobalHotkey: Bool {
    inputMonitoring == .granted
  }

  public var canInsertText: Bool {
    accessibility == .granted
  }
}

public struct SavedSession: Identifiable, Codable, Hashable, Sendable {
  public var id: String { baseName }
  public let baseName: String
  public let startedAt: Date
  public let finishedAt: Date?
  public let localeIdentifier: String
  public let durationSeconds: Double
  public let audioPath: String
  public let transcriptPath: String
  public let metadataPath: String
  public let status: String
  public let targetApplication: String?
  public let characterCount: Int

  public var audioURL: URL { URL(fileURLWithPath: audioPath) }
  public var transcriptURL: URL { URL(fileURLWithPath: transcriptPath) }
  public var metadataURL: URL { URL(fileURLWithPath: metadataPath) }
}

public struct SessionDraft: Sendable {
  public let baseName: String
  public let startedAt: Date
  public let localeIdentifier: String
  public let folderURL: URL
  public let audioURL: URL
  public let transcriptURL: URL
  public let partialTranscriptURL: URL
  public let metadataURL: URL
}
