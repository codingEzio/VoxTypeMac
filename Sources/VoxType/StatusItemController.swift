import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
  private let model: AppModel
  private let statusItem: NSStatusItem
  private let menu = NSMenu()
  private var cancellables = Set<AnyCancellable>()

  init(model: AppModel) {
    self.model = model
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    if let button = statusItem.button {
      button.imagePosition = .imageOnly
      button.imageScaling = .scaleProportionallyDown
      button.toolTip = ProductIdentity.displayName
      button.setAccessibilityLabel(ProductIdentity.displayName)
    }
    menu.delegate = self
    statusItem.menu = menu

    Publishers.CombineLatest3(model.$phase, model.$isHotkeyActive, model.$permissionSnapshot)
      .receive(on: RunLoop.main)
      .sink { [weak self] phase, isHotkeyActive, permissions in
        self?.updateIcon(
          phase: phase,
          needsAttention: !isHotkeyActive || !permissions.canInsertText
        )
      }
      .store(in: &cancellables)
  }

  func menuWillOpen(_ menu: NSMenu) {
    rebuildMenu()
  }

  func showMenu() {
    statusItem.button?.performClick(nil)
  }

  private func rebuildMenu() {
    menu.removeAllItems()

    let header = NSMenuItem()
    header.view = VoxTypeMenuHeaderView(
      title: model.settings.phaseTitle(model.phase),
      detail: statusDetail,
      breakdown:
        "\(model.settings.dictationLanguage.shortTitle(simplifiedChinese: isChinese)) · \(model.settings.dictationShortcut.title) · \(model.recentSessions.count) recordings"
    )
    menu.addItem(header)
    menu.addItem(.separator())

    let primary = actionItem(
      primaryActionTitle,
      symbol: model.phase == .recording ? "stop.fill" : "mic.fill",
      action: #selector(toggleRecording)
    )
    primary.isEnabled = model.phase == .idle || model.phase == .recording || model.phase.isFailed
    menu.addItem(primary)
    menu.addItem(languageMenu())
    menu.addItem(.separator())

    let copy = actionItem(
      model.settings.text("Copy Last Transcript", "复制上次识别"),
      symbol: "doc.on.doc",
      action: #selector(copyLastTranscript),
      keyEquivalent: "c"
    )
    copy.isEnabled = !model.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    menu.addItem(copy)

    if let section = blockedPermission {
      menu.addItem(.separator())
      let permission = actionItem(
        permissionActionTitle(section),
        symbol: "exclamationmark.triangle",
        action: #selector(grantPermission)
      )
      permission.representedObject = section.rawValue
      menu.addItem(permission)
    } else if !model.isHotkeyActive {
      menu.addItem(.separator())
      menu.addItem(
        actionItem(
          model.settings.text("Retry Shortcut Listener", "重试快捷键监听"),
          symbol: "arrow.clockwise",
          action: #selector(retryShortcut)
        ))
    }

    menu.addItem(.separator())
    menu.addItem(
      actionItem(
        model.settings.text("Recordings…", "录音…"),
        symbol: "waveform",
        action: #selector(openRecordings)
      ))
    menu.addItem(
      actionItem(
        model.settings.text("Settings…", "设置…"),
        symbol: "gearshape",
        action: #selector(openSettings),
        keyEquivalent: ","
      ))
    menu.addItem(.separator())

    let quit = NSMenuItem(
      title: model.settings.text(
        "Quit \(ProductIdentity.displayName)", "退出 \(ProductIdentity.displayName)"),
      action: #selector(quit),
      keyEquivalent: "q"
    )
    quit.target = self
    menu.addItem(quit)
  }

  private var isChinese: Bool {
    model.settings.uiLanguage == .simplifiedChinese
  }

  private var statusDetail: String {
    if blockedPermission != nil {
      return model.settings.text("Setup required", "需要设置")
    }
    if !model.isHotkeyActive {
      return model.settings.text("Shortcut unavailable", "快捷键不可用")
    }
    if model.phase == .recording {
      return model.elapsedLabel
    }
    return model.settings.localizedStatus(model.statusMessage)
  }

  private var primaryActionTitle: String {
    if model.phase == .recording {
      return model.settings.text("Stop Recording", "停止录音")
    }
    if model.phase.isBusy {
      return model.settings.phaseTitle(model.phase)
    }
    return model.settings.text("Start Recording", "开始录音")
  }

  private var blockedPermission: PrivacySection? {
    PrivacySection.allCases.first { model.permissionSnapshot.state(for: $0) != .granted }
  }

  private func languageMenu() -> NSMenuItem {
    let title = model.settings.text("Dictation Language", "听写语言")
    let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    root.image = symbol("character.bubble", description: title)
    let submenu = NSMenu(title: title)
    for language in DictationLanguage.allCases {
      let item = NSMenuItem(
        title: language.title(simplifiedChinese: isChinese),
        action: #selector(selectLanguage),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = language.rawValue
      item.state = language == model.settings.dictationLanguage ? .on : .off
      item.isEnabled = !model.phase.isBusy
      submenu.addItem(item)
    }
    root.submenu = submenu
    return root
  }

  private func actionItem(
    _ title: String,
    symbol symbolName: String,
    action: Selector,
    keyEquivalent: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = self
    item.image = symbol(symbolName, description: title)
    return item
  }

  private func symbol(_ name: String, description: String) -> NSImage? {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
    image?.isTemplate = true
    return image
  }

  private func permissionActionTitle(_ section: PrivacySection) -> String {
    switch section {
    case .microphone: model.settings.text("Enable Microphone…", "启用麦克风…")
    case .speechRecognition: model.settings.text("Enable Speech Recognition…", "启用语音识别…")
    case .inputMonitoring: model.settings.text("Enable Input Monitoring…", "启用输入监控…")
    case .accessibility: model.settings.text("Enable Accessibility…", "启用辅助功能…")
    }
  }

  @objc private func toggleRecording() {
    Task { await model.toggleRecording() }
  }

  @objc private func selectLanguage(_ sender: NSMenuItem) {
    guard let rawValue = sender.representedObject as? String,
      let language = DictationLanguage(rawValue: rawValue)
    else { return }
    model.selectDictationLanguage(language)
  }

  @objc private func copyLastTranscript() {
    model.copyTranscript()
  }

  @objc private func grantPermission(_ sender: NSMenuItem) {
    guard let rawValue = sender.representedObject as? String,
      let section = PrivacySection(rawValue: rawValue)
    else { return }
    Task { await model.grantPermission(section) }
  }

  @objc private func retryShortcut() {
    model.retryGlobalHotkey()
  }

  @objc private func openRecordings() {
    model.showRecordings()
  }

  @objc private func openSettings() {
    model.showSettings()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func updateIcon(phase: RecorderPhase, needsAttention: Bool) {
    guard let button = statusItem.button else { return }
    let state: StatusItemIcon.State =
      if needsAttention || phase.isFailed {
        .attention
      } else if phase == .recording {
        .recording
      } else if phase.isBusy {
        .busy
      } else {
        .idle
      }
    button.image = StatusItemIcon.make(state)
    button.imagePosition = .imageOnly
    button.title = ""
  }
}

private final class VoxTypeMenuHeaderView: NSView {
  init(title: String, detail: String, breakdown: String) {
    super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 72))
    let titleField = menuLabel(
      title, font: .systemFont(ofSize: 15, weight: .semibold), color: .labelColor)
    titleField.frame = NSRect(x: 14, y: 44, width: 252, height: 20)
    let detailField = menuLabel(
      detail,
      font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular),
      color: .secondaryLabelColor
    )
    detailField.frame = NSRect(x: 14, y: 26, width: 252, height: 16)
    let breakdownField = menuLabel(
      breakdown,
      font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular),
      color: .tertiaryLabelColor
    )
    breakdownField.frame = NSRect(x: 14, y: 8, width: 252, height: 16)
    addSubview(titleField)
    addSubview(detailField)
    addSubview(breakdownField)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var allowsVibrancy: Bool { true }
}

@MainActor
private func menuLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
  let field = NSTextField(labelWithString: text)
  field.font = font
  field.textColor = color
  field.lineBreakMode = .byTruncatingTail
  field.drawsBackground = false
  return field
}
