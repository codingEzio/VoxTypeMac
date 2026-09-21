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

      accessCallout

      Divider()
      footer
    }
    .frame(width: SettingsLayout.windowWidth, height: SettingsLayout.defaultHeight)
    .onAppear {
      model.refreshPermissions()
    }
    .onChange(of: settings.uiLanguage) {
      model.refreshLocalizedPresentation()
    }
  }

  private var generalSection: some View {
    settingsSection(settings.text(.settingsGeneral)) {
      settingsRow(settings.text(.settingsInterface)) {
        Picker("", selection: $settings.uiLanguage) {
          ForEach(UILanguage.allCases) { language in
            Text(language.title).tag(language)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: SettingsLayout.controlWidth)
      }

      settingsRow(settings.text(.settingsShortcut)) {
        Picker(
          "",
          selection: Binding(
            get: { settings.dictationShortcut },
            set: { model.selectDictationShortcut($0) }
          )
        ) {
          ForEach(DictationShortcut.allCases) { shortcut in
            Text(settings.text(shortcut.localizationKey)).tag(shortcut)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: SettingsLayout.controlWidth, alignment: .leading)
        .disabled(model.phase.isBusy)
      }

      settingsRow(settings.text(.settingsLaunch)) {
        Toggle(settings.text(.settingsAtLogin), isOn: launchAtLoginBinding)
      }
    }
  }

  private var dictationSection: some View {
    settingsSection(settings.text(.settingsDictation)) {
      settingsRow(settings.text(.settingsLanguage)) {
        Picker(
          "",
          selection: Binding(
            get: { settings.dictationLanguage },
            set: { model.selectDictationLanguage($0) }
          )
        ) {
          ForEach(DictationLanguage.allCases) { language in
            Text(settings.text(language.titleKey))
              .tag(language)
          }
        }
        .labelsHidden()
        .accessibilityLabel(settings.text(.settingsDictationLanguage))
        .pickerStyle(.menu)
        .frame(width: SettingsLayout.controlWidth, alignment: .leading)
        .disabled(model.phase.isBusy)
      }

      settingsRow(settings.text(.settingsAccuracy)) {
        refinementControl
      }
    }
  }

  private var outputSection: some View {
    settingsSection(settings.text(.settingsOutput)) {
      settingsRow(settings.text(.settingsSendText)) {
        Picker("", selection: $settings.deliveryMode) {
          ForEach(DeliveryMode.allCases) { mode in
            Text(settings.deliveryTitle(mode)).tag(mode)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: SettingsLayout.controlWidth, alignment: .leading)
      }

      settingsRow(settings.text(.settingsClipboard)) {
        Toggle(
          settings.text(.settingsRestoreClipboard),
          isOn: $settings.preserveClipboard
        )
      }

      settingsRow(settings.text(.settingsStatus)) {
        Toggle(
          settings.text(.settingsShowWhileRecording),
          isOn: $settings.showFloatingHUD
        )
      }

      settingsRow(settings.text(.settingsHUDStyle)) {
        Picker("", selection: $settings.motionStyle) {
          ForEach(MotionStyle.allCases) { style in
            Text(settings.text(style.localizationKey))
              .tag(style)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: SettingsLayout.controlWidth)
      }

      settingsRow(settings.text(.settingsInsertDelay)) {
        HStack(spacing: 8) {
          Slider(value: pasteDelayBinding, in: 50...800, step: 10)
          Text(
            "\(settings.pasteDelayMilliseconds.formatted(.number.locale(settings.uiLanguage.foundationLocale))) ms"
          )
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
        Text(
          refinement.downloadProgress,
          format: .percent.precision(.fractionLength(0))
            .locale(settings.uiLanguage.foundationLocale)
        )
          .monospacedDigit()
          .foregroundStyle(.secondary)
      case .ready:
        Label(refinement.backend.title, systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Menu(settings.text(.settingsManage)) {
          Button(settings.text(.settingsRemoveModel), role: .destructive) {
            try? refinement.remove()
          }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
      case .unavailable, .failed:
        Text(refinementStateTitle)
          .foregroundStyle(.secondary)
        Button(settings.text(.settingsDownloadSenseVoice)) {
          Task { await refinement.install() }
        }
      }
    }
    .frame(width: SettingsLayout.controlWidth, alignment: .leading)
  }

  private var accessCallout: some View {
    let badges = PermissionSetupPlan.badges(in: permissions.snapshot)
    let allGranted = badges.allSatisfy { $0.state == .granted }

    return HStack(spacing: 6) {
      ForEach(badges, id: \.section) { badge in
        permissionBadge(badge)
      }
    }
    .padding(.horizontal, SettingsLayout.contentInset)
    .frame(height: 42)
    .background((allGranted ? Color.green : Color.orange).opacity(0.08))
  }

  @ViewBuilder
  private func permissionBadge(_ badge: PermissionBadge) -> some View {
    let title = permissionTitle(badge.section)
    if badge.state == .granted {
      Label(title, systemImage: "checkmark.circle.fill")
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .foregroundStyle(.green)
        .frame(maxWidth: .infinity, minHeight: 24)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityValue(settings.text(.modelReady))
    } else {
      Button {
        Task { await model.grantPermission(badge.section) }
      } label: {
        Label(title, systemImage: "circle.dashed")
          .font(.caption)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .frame(maxWidth: .infinity)
      .help(permissionHelp(badge.section))
    }
  }

  private var footer: some View {
    HStack(spacing: 18) {
      Button {
        model.showRecordings()
      } label: {
        Label(settings.text(.settingsRecordings), systemImage: "waveform")
      }

      Button {
        model.openSaveFolder()
      } label: {
        Label(settings.text(.settingsOpenFolder), systemImage: "folder")
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

  private var refinementStateTitle: String {
    switch refinement.state {
    case .unavailable: settings.text(.modelNotDownloaded)
    case .downloading: settings.text(.modelDownloading)
    case .ready: settings.text(.modelReady)
    case .failed: settings.text(.modelUnavailable)
    }
  }

  private func permissionTitle(_ section: PrivacySection) -> String {
    switch section {
    case .microphone: settings.text(.permissionMicrophone)
    case .speechRecognition: settings.text(.permissionSpeechRecognition)
    case .inputMonitoring: settings.text(.permissionInputMonitoring)
    case .accessibility: settings.text(.permissionAccessibility)
    }
  }

  private func permissionHelp(_ section: PrivacySection) -> String {
    switch section {
    case .microphone:
      settings.text(.permissionHelpMicrophone, ProductIdentity.displayName)
    case .speechRecognition:
      settings.text(.permissionHelpSpeechRecognition, ProductIdentity.displayName)
    case .inputMonitoring:
      settings.text(.permissionHelpInputMonitoring, ProductIdentity.displayName)
    case .accessibility:
      settings.text(.permissionHelpAccessibility, ProductIdentity.displayName)
    }
  }

}
