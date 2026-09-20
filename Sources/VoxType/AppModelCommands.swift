import AppKit
import Foundation

extension AppModel {
  func copyTranscript() {
    outputDispatcher.copy(transcript)
    statusMessage = settings.text(transcript.isEmpty ? .statusNothingToCopy : .statusTranscriptCopied)
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
      statusMessage = settings.text(.statusNoSavedAudio)
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
    statusMessage = settings.text(.statusRetranscribing, audioURL.lastPathComponent)
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
      statusMessage = settings.text(.statusRetranscribedCopied)
      phase = .idle
      hudController?.hide(after: 0.9)
      refreshRecentSessions()
    } catch {
      fail(settings.localizedError(error))
    }
  }

  func requestRecordingPermissions() async {
    if await permissions.requestRecordingPermissions() {
      statusMessage = settings.text(.statusRecordingPermissionsReady)
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
        ? settings.text(.statusMicrophoneReady)
        : settings.text(.permissionHelpMicrophone, "\(ProductIdentity.displayName).app")
    case .speechRecognition:
      statusMessage =
        currentPermissions.speechRecognition == .granted
        ? settings.text(.statusSpeechRecognitionReady)
        : settings.text(.permissionHelpSpeechRecognition, "\(ProductIdentity.displayName).app")
    case .inputMonitoring:
      ensureHotkeyActive()
      statusMessage =
        currentPermissions.canUseGlobalHotkey
        ? settings.text(.statusShortcutActive, settings.dictationShortcut.title)
        : settings.text(.permissionHelpInputMonitoring, "\(ProductIdentity.displayName).app")
    case .accessibility:
      statusMessage =
        currentPermissions.canInsertText
        ? settings.text(.statusAccessibilityReady)
        : settings.text(.permissionHelpAccessibility, "\(ProductIdentity.displayName).app")
    }
    watchPermissionApproval()
  }

  func retryGlobalHotkey() {
    permissions.refresh()
    hotkeyMonitor.stop()
    ensureHotkeyActive()
    if isHotkeyActive {
      statusMessage = settings.text(.statusShortcutActive, settings.dictationShortcut.title)
    } else {
      statusMessage = settings.text(.statusHotkeyBlocked)
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
        enabled
          ? settings.text(.statusLaunchAtLoginEnabled, ProductIdentity.displayName)
          : settings.text(.statusLaunchAtLoginDisabled)
    } catch {
      settings.launchAtLogin = LaunchAtLoginManager.isEnabled
      statusMessage = settings.localizedError(error)
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
    statusMessage = settings.text(.statusWarmingLanguage, settings.text(language.titleKey))
    prewarmSpeechModel()
  }

  var timingLabel: String? {
    var parts: [String] = []
    if let lastPrepareSeconds {
      parts.append(timingPhrase(lastPrepareSeconds, suffix: settings.text(.timingStart)))
    }
    if let lastFinalizationSeconds {
      parts.append(timingPhrase(lastFinalizationSeconds, suffix: settings.text(.timingFinish)))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private func timingPhrase(_ seconds: TimeInterval, suffix: String) -> String {
    if seconds < 1 {
      let milliseconds = Int((seconds * 1_000).rounded())
        .formatted(.number.locale(settings.uiLanguage.foundationLocale))
      return "\(milliseconds) ms \(suffix)"
    }
    let value = seconds.formatted(
      .number.precision(.fractionLength(2)).locale(settings.uiLanguage.foundationLocale)
    )
    return "\(value) s \(suffix)"
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
      statusMessage = settings.text(.statusWarmingEngine)
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
            self.statusMessage = self.settings.localizedError(error)
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
      return settings.text(
        .statusInputMonitoringRequired, ProductIdentity.displayName, shortcutTitle)
    }
    if !permissionSnapshot.canInsertText {
      return settings.text(.statusAccessibilityRequired, ProductIdentity.displayName)
    }
    return isHotkeyActive
      ? settings.text(.statusReadyShortcut, shortcutTitle)
      : settings.text(.statusShortcutListenerFailed)
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
