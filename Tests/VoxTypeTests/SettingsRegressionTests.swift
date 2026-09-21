import Foundation
import Testing

@testable import VoxType

@Test func motionStylesStayDistinctAndExitFasterThanTheyEnter() {
  for style in MotionStyle.allCases {
    #expect(style.hideDuration < style.showDuration)
    #expect(style.showDuration > 0)
    #expect(style.attackSeconds > 0)
    #expect(style.releaseSeconds > style.attackSeconds)
    #expect(style.appearScale > 0.9)
    #expect(style.appearScale < 1)
  }
  #expect(MotionStyle.quiet.showDuration > MotionStyle.bright.showDuration)
  #expect(MotionStyle.bright.attackSeconds < MotionStyle.liquid.attackSeconds)
  #expect(Set(MotionStyle.allCases.map(\.rawValue)) == ["quiet", "liquid", "bright"])
}

@Test func settingsKeepOneCompactPage() {
  #expect(RefinementPolicy.timeoutSeconds == 90)
}

@Test func privacySectionsNameTheExactMacOS27Queries() {
  #expect(PrivacySection.microphone.query == "Privacy_Microphone")
  #expect(PrivacySection.speechRecognition.query == "Privacy_SpeechRecognition")
  #expect(PrivacySection.inputMonitoring.query == "Privacy_ListenEvent")
  #expect(PrivacySection.accessibility.query == "Privacy_Accessibility")
  for section in PrivacySection.allCases {
    #expect(PrivacySettingsLink.url(section).hasPrefix(PrivacySettingsLink.pane + "?"))
    #expect(!PrivacySettingsLink.url(section).contains("preference.security"))
  }
}

@Test func permissionReceiptMarksOnlyAutomationCategories() {
  var receipt = PermissionRequestReceipt(
    bundleIdentifier: "app.voxtypemac.VoxTypeMac",
    accessibility: false,
    inputMonitoring: false
  )
  #expect(!receipt.requested(for: .microphone))
  #expect(!receipt.requested(for: .speechRecognition))
  receipt = receipt.marking(.accessibility).marking(.microphone)
  #expect(receipt.requested(for: .accessibility))
  #expect(!receipt.requested(for: .inputMonitoring))
  #expect(!receipt.requested(for: .microphone))
}

@Test func permissionSnapshotReadinessIsPerCategory() {
  let denied = PermissionSnapshot(
    microphone: .granted,
    speechRecognition: .denied,
    accessibility: .granted,
    inputMonitoring: .notDetermined
  )
  #expect(!denied.canRecord)
  #expect(!denied.canUseGlobalHotkey)
  #expect(denied.canInsertText)
  #expect(denied.state(for: .speechRecognition) == .denied)
  let ready = PermissionSnapshot(
    microphone: .granted,
    speechRecognition: .granted,
    accessibility: .granted,
    inputMonitoring: .granted
  )
  #expect(ready.canRecord)
  #expect(ready.canUseGlobalHotkey)
  #expect(ready.canInsertText)
}

@Test @MainActor func settingsPersistTheSelectedDictationLanguage() throws {
  let folder = SettingsFile.temporaryURL.appendingPathComponent("tests", isDirectory: true)
    .appendingPathComponent("VoxTypeSlider-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let url = folder.appendingPathComponent("config.toml")
  let store = SettingsStore(configURL: url)
  #expect(store.dictationLanguage == .englishUS)
  store.motionStyle = .bright
  store.dictationLanguage = .traditionalChinese

  let loaded = SettingsFile(url: url)
  #expect(loaded["schema_version"] == "2")
  #expect(loaded["speech_mode"] == "zh-TW")
  #expect(loaded["recognition_model"] == nil)
  #expect(loaded["accurate_chinese"] == nil)
  #expect(loaded["motion_style"] == "bright")

  let reopened = SettingsStore(configURL: url)
  #expect(reopened.dictationLanguage == .traditionalChinese)
  #expect(reopened.localeIdentifier == "zh-TW")
  #expect(reopened.motionStyle == .bright)
}

@Test @MainActor func settingsMigrateLegacyChineseModeToTaiwanTraditionalChinese() throws {
  let folder = SettingsFile.temporaryURL.appendingPathComponent("tests", isDirectory: true)
    .appendingPathComponent("VoxTypeLegacyChinese-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let url = folder.appendingPathComponent("config.toml")
  var file = SettingsFile(url: url)
  file.set("zh-CN", for: "speech_mode")
  try file.write(to: url)

  let store = SettingsStore(configURL: url)
  #expect(store.dictationLanguage == .traditionalChinese)
  #expect(store.localeIdentifier == "zh-TW")
  #expect(SettingsFile(url: url)["speech_mode"] == "zh-TW")
}

@Test func localHelperEnvironmentCannotLeakCachesOutsideRuntime() throws {
  let base = [
    "HOME": "/Users/example",
    "TMPDIR": "/tmp",
    "XDG_CACHE_HOME": "/Users/example/.cache",
    "PYTHONPATH": "/Users/example/python",
    "PYTHONHOME": "/Users/example/python-home",
    "PYTHONUSERBASE": "/Users/example/python-user",
    "DYLD_LIBRARY_PATH": "/Users/example/libraries",
  ]
  let prepared = try RefinementService.prepareHelperRuntime(baseEnvironment: base)
  let root = SettingsFile.rootURL.standardizedFileURL.path + "/"
  for key in [
    "HOME", "TMPDIR", "XDG_CACHE_HOME", "PYTHONPYCACHEPREFIX", "HF_HOME",
    "TORCH_HOME", "TRANSFORMERS_CACHE", "NUMBA_CACHE_DIR",
  ] {
    #expect(prepared.environment[key]?.hasPrefix(root) == true)
  }
  for key in ["PYTHONPATH", "PYTHONHOME", "PYTHONUSERBASE", "DYLD_LIBRARY_PATH"] {
    #expect(prepared.environment[key] == nil)
  }
  #expect(prepared.environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
  #expect(prepared.workingDirectory.path == SettingsFile.temporaryURL.path)
}

@Test func craftedSessionMetadataCannotExposeExternalFiles() async throws {
  let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
  let folder = SettingsFile.temporaryURL
    .appendingPathComponent("tests/session-metadata-\(timestamp)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

  let baseName = "2026-08-30_00-00-00-000__Tests__en-US"
  let metadata = folder.appendingPathComponent(baseName).appendingPathExtension("json")
  let session = SavedSession(
    baseName: baseName,
    startedAt: Date(timeIntervalSince1970: 1_700_000_000),
    finishedAt: nil,
    localeIdentifier: "en-US",
    durationSeconds: 1,
    audioPath: "/tmp/voxtype-external-audio.caf",
    transcriptPath: folder.appendingPathComponent(baseName).appendingPathExtension("txt").path,
    metadataPath: metadata.path,
    status: "complete",
    targetApplication: "Tests",
    characterCount: 4
  )
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  try encoder.encode(session).write(to: metadata)

  let sessions = await SessionStore().recentSessions(in: folder)
  #expect(sessions.isEmpty)
}

@Test func runtimeContainmentRejectsSymlinkEscape() throws {
  let links = SettingsFile.temporaryURL.appendingPathComponent("tests", isDirectory: true)
  let link = links.appendingPathComponent("delete_after_use_runtime_escape")
  let outside = FileManager.default.temporaryDirectory
    .appendingPathComponent("delete_after_use_voxtype_outside", isDirectory: true)
  defer {
    try? FileManager.default.removeItem(at: link)
    try? FileManager.default.removeItem(at: outside)
  }
  try FileManager.default.createDirectory(at: links, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
  var rejected = false
  do {
    try SettingsFile.requireContained(link.appendingPathComponent("escaped.txt"))
  } catch {
    rejected = true
  }
  #expect(rejected)
}

@Test func settingsAndSessionsRejectExternalWriteTargets() async throws {
  let outside = FileManager.default.temporaryDirectory
    .appendingPathComponent("delete_after_use_voxtype_external_write", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: outside) }
  var settings = SettingsFile()
  settings.set("1", for: "schema_version")
  var settingsRejected = false
  do {
    try settings.write(to: outside.appendingPathComponent("config.toml"))
  } catch {
    settingsRejected = true
  }
  #expect(settingsRejected)

  let store = SessionStore()
  var sessionRejected = false
  do {
    _ = try await store.begin(
      in: outside,
      localeIdentifier: "en-US",
      targetApplication: "Tests"
    )
  } catch {
    sessionRejected = true
  }
  #expect(sessionRejected)
}

@Test func downloaderRejectsExternalDestinationBeforeNetworkIO() async {
  let outside = FileManager.default.temporaryDirectory
    .appendingPathComponent("delete_after_use_voxtype_external_download")
  let downloader = ArtifactDownloader(destination: outside) { _ in }
  var rejected = false
  do {
    try await downloader.download(from: URL(string: "https://example.invalid/model")!)
  } catch {
    rejected = true
  }
  #expect(rejected)
  #expect(!FileManager.default.fileExists(atPath: outside.path))
}
