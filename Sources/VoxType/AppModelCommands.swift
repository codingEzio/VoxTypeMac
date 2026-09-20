import AppKit
import Foundation

extension AppModel {
  func copyTranscript() {
    outputDispatcher.copy(transcript)
    statusMessage = transcript.isEmpty ? "Nothing to copy yet" : "Transcript copied"
  }

  func openSaveFolder() {
    let url = settings.saveFolderURL
    guard (try? SettingsFile.requireContained(url)) != nil else { return }
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    NSWorkspace.shared.open(url)
  }

  func reveal(_ session: SavedSession) {
    guard (try? SettingsFile.requireContained(session.audioURL)) != nil else { return }
    NSWorkspace.shared.activateFileViewerSelecting([session.audioURL])
  }

  func openTranscript(_ session: SavedSession) {
    guard (try? SettingsFile.requireContained(session.transcriptURL)) != nil else { return }
    NSWorkspace.shared.open(session.transcriptURL)
  }

  func retranscribeLatestAudio() async {
    guard let audioURL = await sessionStore.latestAudioURL(in: settings.saveFolderURL) else {
      statusMessage = "No saved audio found"
      return
    }
    await retranscribeAudio(at: audioURL, locale: settings.resolvedLocale)
  }

  func retranscribe(_ session: SavedSession) async {
    guard (try? SettingsFile.requireContained(session.audioURL)) != nil else { return }
    await retranscribeAudio(
      at: session.audioURL,
      locale: Locale(identifier: session.localeIdentifier)
    )
  }

  private func retranscribeAudio(at audioURL: URL, locale: Locale) async {
    guard !phase.isBusy else { return }

    phase = .finalizing
    transcript = ""
    stableTranscript = ""
    draftTail = ""
    statusMessage = "Re-transcribing \(audioURL.lastPathComponent)…"
    showHUD()
    let startedAt = Date()

    do {
      let text = try await speechEngine.transcribeFile(
        at: audioURL,
        locale: locale,
        onUpdate: { [weak self] live in
          Task { @MainActor in
            self?.transcript = live.text
            self?.stableTranscript = live.stableText
            self?.draftTail = live.draftTail
          }
        }
      )
      lastFinalizationSeconds = Date().timeIntervalSince(startedAt)
      transcript = text
      stableTranscript = text
      draftTail = ""
      lastSavedSession = try await sessionStore.replaceTranscript(for: audioURL, with: text)
      outputDispatcher.copy(text)
      statusMessage = "Re-transcribed and copied"
      phase = .idle
      hudController?.hide(after: 0.9)
      refreshRecentSessions()
    } catch {
      fail(error.localizedDescription)
    }
  }

  func requestRecordingPermissions() async {
    if await permissions.requestRecordingPermissions() {
      statusMessage = "Microphone and Speech Recognition are ready"
    } else {
      _ = presentRecordingPermissionBlocker()
    }
  }

  func grantPermission(_ section: PrivacySection) async {
    if settingsWindow == nil || settingsWindow?.isVisible != true {
      showSettings()
    }
    await permissions.grantOrOpen(section)
    keepSettingsVisible()
    permissions.refresh()
    let currentPermissions = permissions.snapshot
    switch section {
    case .microphone:
      statusMessage =
        currentPermissions.microphone == .granted
        ? "Microphone is ready"
        : "Turn on \(ProductIdentity.displayName).app under Privacy & Security → Microphone"
    case .speechRecognition:
      statusMessage =
        currentPermissions.speechRecognition == .granted
        ? "Speech Recognition is ready"
        : "Turn on \(ProductIdentity.displayName).app under Privacy & Security → Speech Recognition"
    case .inputMonitoring:
      ensureHotkeyActive()
      statusMessage =
        currentPermissions.canUseGlobalHotkey
        ? "Shortcut \(settings.dictationShortcut.title) is active"
        : "Turn on \(ProductIdentity.displayName).app under Privacy & Security → Input Monitoring. That is not Accessibility."
    case .accessibility:
      statusMessage =
        currentPermissions.canInsertText
        ? "Accessibility is ready"
        : "Turn on \(ProductIdentity.displayName).app under Privacy & Security → Accessibility. That is not Input Monitoring."
    }
    watchPermissionApproval()
  }

  func retryGlobalHotkey() {
    permissions.refresh()
    hotkeyMonitor.stop()
    ensureHotkeyActive()
    if isHotkeyActive {
      statusMessage = "Shortcut \(settings.dictationShortcut.title) is active"
    } else {
      statusMessage = "Hotkey still blocked by Input Monitoring"
    }
  }

  func refreshPermissions() {
    permissions.refresh()
  }

  func updateLaunchAtLogin(_ enabled: Bool) {
    do {
      try LaunchAtLoginManager.setEnabled(enabled)
      settings.launchAtLogin = enabled
      statusMessage =
        enabled ? "\(ProductIdentity.displayName) will launch at login" : "Launch at login disabled"
    } catch {
      settings.launchAtLogin = LaunchAtLoginManager.isEnabled
      statusMessage = error.localizedDescription
    }
  }

  func applyLaunchAtLoginPreference() {
    do {
      try LaunchAtLoginManager.setEnabled(settings.launchAtLogin)
      settings.launchAtLogin = LaunchAtLoginManager.isEnabled
    } catch {
      settings.launchAtLogin = LaunchAtLoginManager.isEnabled
    }
  }

  func selectDictationShortcut(_ shortcut: DictationShortcut) {
    guard shortcut != settings.dictationShortcut else { return }
    settings.dictationShortcut = shortcut
    hotkeyMonitor.stop()
    ensureHotkeyActive()
    if phase == .idle {
      statusMessage = readinessMessage
    }
  }

  func selectDictationLanguage(_ language: DictationLanguage) {
    guard language != settings.dictationLanguage, !phase.isBusy else { return }
    settings.dictationLanguage = language
    isModelReady = false
    resolvedLocaleIdentifier = language.locale.identifier
    statusMessage = settings.text(
      "Warming \(language.title(simplifiedChinese: false))…",
      "正在准备\(language.title(simplifiedChinese: true))…"
    )
    prewarmSpeechModel()
  }

  var timingLabel: String? {
    var parts: [String] = []
    if let lastPrepareSeconds {
      parts.append(Self.timingPhrase(lastPrepareSeconds, suffix: "start"))
    }
    if let lastFinalizationSeconds {
      parts.append(Self.timingPhrase(lastFinalizationSeconds, suffix: "finish"))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private static func timingPhrase(_ seconds: TimeInterval, suffix: String) -> String {
    if seconds < 1 {
      return "\(Int((seconds * 1_000).rounded())) ms \(suffix)"
    }
    return String(format: "%.2f s \(suffix)", seconds)
  }

  var elapsedLabel: String {
    let seconds: TimeInterval
    if let started = recordingStartedAt, phase == .recording {
      seconds = Date().timeIntervalSince(started)
    } else {
      seconds = elapsedSeconds
    }
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%02d:%02d", total / 60, total % 60)
  }

  func installWorkspaceTracking() {
    let ownBundleIdentifier = Bundle.main.bundleIdentifier
    if let current = NSWorkspace.shared.frontmostApplication,
      current.bundleIdentifier != ownBundleIdentifier
    {
      lastExternalApplication = current
    }

    workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication,
        application.bundleIdentifier != ownBundleIdentifier
      else {
        return
      }
      Task { @MainActor in
        self?.lastExternalApplication = application
      }
    }
  }

  func prewarmSpeechModel() {
    let selectedLanguage = settings.dictationLanguage
    let locale = settings.resolvedLocale
    if phase == .idle, hotkeyMonitor.isRunning {
      statusMessage = settings.text(
        "Warming the local speech engine. First use may download language assets.",
        "正在准备本地语音引擎。首次使用可能需要下载语言资源。"
      )
    }

    Task { [weak self] in
      guard let self else { return }
      do {
        let resolved = try await speechEngine.prewarm(locale: locale)
        await MainActor.run {
          guard self.settings.dictationLanguage == selectedLanguage else { return }
          self.resolvedLocaleIdentifier = resolved
          self.isModelReady = true
          if self.phase == .idle {
            self.statusMessage = self.readinessMessage
          }
        }
      } catch {
        await MainActor.run {
          guard self.settings.dictationLanguage == selectedLanguage else { return }
          self.isModelReady = false
          if self.phase == .idle, self.hotkeyMonitor.isRunning {
            self.statusMessage = error.localizedDescription
          }
        }
      }
    }
  }

  func ensureHotkeyActive() {
    hotkeyMonitor.shortcut = settings.dictationShortcut
    guard permissions.snapshot.canUseGlobalHotkey else {
      hotkeyMonitor.stop()
      isHotkeyActive = false
      return
    }
    if !hotkeyMonitor.isRunning {
      _ = hotkeyMonitor.start()
    }
    isHotkeyActive = hotkeyMonitor.isRunning
  }

  var readinessMessage: String {
    let shortcutTitle = settings.dictationShortcut.title
    if !permissionSnapshot.canUseGlobalHotkey {
      return "Turn on \(ProductIdentity.displayName).app under Privacy & Security → Input Monitoring for \(shortcutTitle)"
    }
    if !permissionSnapshot.canInsertText {
      return "Turn on \(ProductIdentity.displayName).app under Privacy & Security → Accessibility to insert text"
    }
    return isHotkeyActive
      ? "Ready · \(shortcutTitle)"
      : "Shortcut listener could not start"
  }

  func refreshRecentSessions() {
    let folder = settings.saveFolderURL
    Task { [weak self] in
      guard let self else { return }
      let sessions = await sessionStore.recentSessions(in: folder)
      let latestTranscript = await sessionStore.latestTranscript(in: folder)
      await MainActor.run {
        self.recentSessions = sessions
        self.restoreLatestTranscriptIfNeeded(latestTranscript)
      }
    }
  }

  func restoreLatestTranscriptIfNeeded(_ text: String?) {
    guard let restored = Self.restoredTranscript(phase: phase, current: transcript, latest: text)
    else {
      return
    }
    transcript = restored
  }

  static func restoredTranscript(phase: RecorderPhase, current: String, latest: String?) -> String?
  {
    guard phase == .idle || phase.isFailed else { return nil }
    guard current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    guard let latest, !latest.isEmpty else { return nil }
    return latest
  }
}
