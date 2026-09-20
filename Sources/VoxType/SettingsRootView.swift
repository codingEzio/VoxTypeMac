import SwiftUI

struct SettingsRootView: View {
  @ObservedObject var model: AppModel
  @ObservedObject private var settings: SettingsStore
  @ObservedObject private var permissions: PermissionsManager
  @ObservedObject private var refinement: RefinementService

  init(model: AppModel) {
    self.model = model
    _settings = ObservedObject(wrappedValue: model.settings)
    _permissions = ObservedObject(wrappedValue: model.permissions)
    _refinement = ObservedObject(wrappedValue: model.refinement)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: SettingsLayout.columnSpacing) {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
          generalSection
          dictationSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)

        Divider()

        outputSection
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .padding(.horizontal, SettingsLayout.contentInset)
      .padding(.top, 22)
      .padding(.bottom, 18)

      if !missingPermissions.isEmpty {
        accessCallout
      }

      Divider()
      footer
    }
    .frame(width: SettingsLayout.windowWidth, height: SettingsLayout.defaultHeight)
    .onAppear {
      model.refreshPermissions()
      model.watchPermissionApproval()
    }
  }

  private var generalSection: some View {
    settingsSection(settings.text("General", "通用")) {
      settingsRow(settings.text("Interface", "界面")) {
        Picker("", selection: $settings.uiLanguage) {
          ForEach(UILanguage.allCases) { language in
            Text(language.title).tag(language)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: SettingsLayout.controlWidth)
      }

      settingsRow(settings.text("Shortcut", "快捷键")) {
        Picker(
          "",
          selection: Binding(
            get: { settings.dictationShortcut },
            set: { model.selectDictationShortcut($0) }
          )
        ) {
          ForEach(DictationShortcut.allCases) { shortcut in
            Text(shortcut.settingsTitle).tag(shortcut)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: SettingsLayout.controlWidth, alignment: .leading)
        .disabled(model.phase.isBusy)
      }

      settingsRow(settings.text("Launch", "启动")) {
        Toggle(settings.text("At login", "登录时"), isOn: launchAtLoginBinding)
      }
    }
  }

  private var dictationSection: some View {
    settingsSection(settings.text("Dictation", "听写")) {
      settingsRow(settings.text("Language", "语言")) {
        Picker(
          "",
          selection: Binding(
            get: { settings.dictationLanguage },
            set: { model.selectDictationLanguage($0) }
          )
        ) {
          ForEach(DictationLanguage.allCases) { language in
            Text(language.title(simplifiedChinese: settings.uiLanguage == .simplifiedChinese))
              .tag(language)
          }
        }
        .labelsHidden()
        .accessibilityLabel(settings.text("Dictation language", "听写语言"))
        .pickerStyle(.menu)
        .frame(width: SettingsLayout.controlWidth, alignment: .leading)
        .disabled(model.phase.isBusy)
      }

      settingsRow(settings.text("Accuracy", "准确度")) {
        refinementControl
      }
    }
  }

  private var outputSection: some View {
    settingsSection(settings.text("Output", "输出")) {
      settingsRow(settings.text("Send text", "发送文字")) {
        Picker("", selection: $settings.deliveryMode) {
          ForEach(DeliveryMode.allCases) { mode in
            Text(settings.deliveryTitle(mode)).tag(mode)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: SettingsLayout.controlWidth, alignment: .leading)
      }

      settingsRow(settings.text("Clipboard", "剪贴板")) {
        Toggle(
          settings.text("Restore after inserting", "插入后恢复"),
          isOn: $settings.preserveClipboard
        )
      }

      settingsRow(settings.text("Status", "状态")) {
        Toggle(
          settings.text("Show while recording", "录音时显示"),
          isOn: $settings.showFloatingHUD
        )
      }

      settingsRow(settings.text("HUD style", "浮窗样式")) {
        Picker("", selection: $settings.motionStyle) {
          ForEach(MotionStyle.allCases) { style in
            Text(style.title(simplifiedChinese: settings.uiLanguage == .simplifiedChinese))
              .tag(style)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: SettingsLayout.controlWidth)
      }

      settingsRow(settings.text("Insert delay", "插入延迟")) {
        HStack(spacing: 8) {
          Slider(value: pasteDelayBinding, in: 50...800, step: 10)
          Text("\(settings.pasteDelayMilliseconds) ms")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 56, alignment: .trailing)
        }
        .frame(width: SettingsLayout.controlWidth)
      }
    }
  }

  private var refinementControl: some View {
    HStack(spacing: 8) {
      switch refinement.state {
      case .downloading:
        ProgressView(value: refinement.downloadProgress)
          .frame(width: 92)
        Text("\(Int((refinement.downloadProgress * 100).rounded()))%")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      case .ready:
        Label(refinement.backend.title, systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Menu(settings.text("Manage", "管理")) {
          Button(settings.text("Remove Model", "移除模型"), role: .destructive) {
            try? refinement.remove()
          }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
      case .unavailable, .failed:
        Text(refinementStateTitle)
          .foregroundStyle(.secondary)
        Button(settings.text("Download SenseVoice…", "下载 SenseVoice…")) {
          Task { await refinement.install() }
        }
      }
    }
    .frame(width: SettingsLayout.controlWidth, alignment: .leading)
  }

  private var accessCallout: some View {
    HStack(spacing: 10) {
      Label(
        settings.text(
          "\(missingPermissions.count) access items need attention",
          "有 \(missingPermissions.count) 项权限需要处理"
        ),
        systemImage: "exclamationmark.triangle.fill"
      )
      .foregroundStyle(.orange)

      Spacer()

      Menu(settings.text("Review Access…", "检查权限…")) {
        ForEach(missingPermissions, id: \.self) { section in
          Button(permissionTitle(section)) {
            Task { await model.grantPermission(section) }
          }
          .help(permissionHelp(section))
        }
      }
      .fixedSize()
    }
    .padding(.horizontal, SettingsLayout.contentInset)
    .frame(height: 42)
    .background(.orange.opacity(0.08))
  }

  private var footer: some View {
    HStack(spacing: 18) {
      Button {
        model.showRecordings()
      } label: {
        Label(settings.text("Recordings…", "录音…"), systemImage: "waveform")
      }

      Button {
        model.openSaveFolder()
      } label: {
        Label(settings.text("Open Folder", "打开文件夹"), systemImage: "folder")
      }

      Spacer()
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.secondary)
    .padding(.horizontal, SettingsLayout.contentInset)
    .frame(height: 46)
  }

  private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)
      Grid(horizontalSpacing: 12, verticalSpacing: 10) {
        content()
      }
    }
  }

  private func settingsRow<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    GridRow(alignment: .center) {
      Text(title)
        .foregroundStyle(.secondary)
        .frame(width: SettingsLayout.labelWidth, alignment: .trailing)
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: 28)
  }

  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { settings.launchAtLogin },
      set: { model.updateLaunchAtLogin($0) }
    )
  }

  private var pasteDelayBinding: Binding<Double> {
    Binding(
      get: { Double(settings.pasteDelayMilliseconds) },
      set: { settings.pasteDelayMilliseconds = Int($0) }
    )
  }

  private var missingPermissions: [PrivacySection] {
    PrivacySection.allCases.filter { permissions.snapshot.state(for: $0) != .granted }
  }

  private var refinementStateTitle: String {
    switch refinement.state {
    case .unavailable: settings.text("Not downloaded", "尚未下载")
    case .downloading: settings.text("Downloading", "正在下载")
    case .ready: settings.text("Ready", "已就绪")
    case .failed: settings.text("Unavailable", "不可用")
    }
  }

  private func permissionTitle(_ section: PrivacySection) -> String {
    switch section {
    case .microphone: settings.text("Microphone", "麦克风")
    case .speechRecognition: settings.text("Speech Recognition", "语音识别")
    case .inputMonitoring: settings.text("Input Monitoring", "输入监控")
    case .accessibility: settings.text("Accessibility", "辅助功能")
    }
  }

  private func permissionHelp(_ section: PrivacySection) -> String {
    switch section {
    case .microphone:
      "Turn on \(ProductIdentity.displayName) under Privacy & Security → Microphone."
    case .speechRecognition:
      "Turn on \(ProductIdentity.displayName) under Privacy & Security → Speech Recognition."
    case .inputMonitoring:
      "Turn on \(ProductIdentity.displayName) under Privacy & Security → Input Monitoring. That is not Accessibility."
    case .accessibility:
      "Turn on \(ProductIdentity.displayName) under Privacy & Security → Accessibility. That is not Input Monitoring."
    }
  }
}
