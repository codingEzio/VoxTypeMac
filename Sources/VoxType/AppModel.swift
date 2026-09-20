import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
  static let shared = AppModel()

  // Setters stay module-internal so the responsibility extensions can update shared state.
  @Published var phase: RecorderPhase = .idle
  @Published var transcript = ""
  @Published var stableTranscript = ""
  @Published var draftTail = ""
  @Published var elapsedSeconds: TimeInterval = 0
  @Published var statusMessage = ""
  @Published var resolvedLocaleIdentifier = Locale.current.identifier
  @Published var isModelReady = false
  @Published var recentSessions: [SavedSession] = []
  @Published var lastSavedSession: SavedSession?
  @Published var permissionSnapshot: PermissionSnapshot
  @Published var isHotkeyActive = false
  @Published var targetApplicationName: String?
  @Published var lastFinalizationSeconds: TimeInterval?
  @Published var lastPrepareSeconds: TimeInterval?

  let settings: SettingsStore
  let permissions: PermissionsManager
  let refinement = RefinementService()

  let audioCapture = AudioCapture()
  let speechEngine = NativeSpeechEngine()
  let sessionStore = SessionStore()
  let outputDispatcher = OutputDispatcher()
  let hotkeyMonitor = GlobalHotkeyMonitor()

  var currentDraft: SessionDraft?
  var targetApplication: NSRunningApplication?
  var targetInput: OutputDispatcher.InputTarget?
  var lastExternalApplication: NSRunningApplication?
  var recordingStartedAt: Date?
  var lastPartialWriteAt = Date.distantPast
  nonisolated(unsafe) var workspaceObserver: NSObjectProtocol?
  var cancellables = Set<AnyCancellable>()
  var hudController: HUDController?
  var hasStarted = false
  var settingsWindow: NSWindow?
  var recordingsWindow: NSWindow?
  let settingsAnchor = AuxiliaryWindowAnchor()
  let recordingsAnchor = AuxiliaryWindowAnchor()
  var permissionWatchTask: Task<Void, Never>?

  private init() {
    let settings = SettingsStore()
    let permissions = PermissionsManager()
    self.settings = settings
    self.permissions = permissions
    self.permissionSnapshot = permissions.snapshot
    self.statusMessage = settings.text(.statusReadyShortcut, settings.dictationShortcut.title)

    permissions.$snapshot
      .receive(on: RunLoop.main)
      .sink { [weak self] snapshot in
        guard let self else { return }
        self.permissionSnapshot = snapshot
        if snapshot.canUseGlobalHotkey {
          self.ensureHotkeyActive()
        } else {
          self.hotkeyMonitor.stop()
          self.isHotkeyActive = false
        }
        if self.phase == .idle {
          self.statusMessage = self.readinessMessage
        }
      }
      .store(in: &cancellables)
  }

  deinit {
    if let workspaceObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
    }
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true

    NSApp.setActivationPolicy(.accessory)
    installWorkspaceTracking()

    hotkeyMonitor.shortcut = settings.dictationShortcut
    hotkeyMonitor.onToggle = { [weak self] in
      Task { @MainActor in
        await self?.toggleRecording()
      }
    }

    permissions.refresh()
    ensureHotkeyActive()
    statusMessage = readinessMessage
    applyLaunchAtLoginPreference()
    refreshRecentSessions()
    prewarmSpeechModel()
    Task { await refinement.prepare() }
  }

  func toggleRecording() async {
    switch phase {
    case .recording:
      await stopRecording()
    case .idle, .failed:
      await startRecording()
    case .preparing, .finalizing, .delivering:
      break
    }
  }
}
