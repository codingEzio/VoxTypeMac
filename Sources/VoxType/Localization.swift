import Foundation

enum PluralCategory: Sendable {
  case one, few, many, other
}

enum LocalizationPlural {
  static func category(for count: Int, language: UILanguage) -> PluralCategory {
    switch language {
    case .russian, .ukrainian:
      let mod10 = count % 10
      let mod100 = count % 100
      if mod10 == 1, mod100 != 11 { return .one }
      if (2...4).contains(mod10), !(12...14).contains(mod100) { return .few }
      if mod10 == 0 || (5...9).contains(mod10) || (11...14).contains(mod100) {
        return .many
      }
      return .other
    case .english, .spanish:
      return count == 1 ? .one : .other
    case .traditionalChinese, .simplifiedChinese, .japanese, .korean:
      return .other
    }
  }
}

enum LocalizationKey: String, CaseIterable, Sendable {
  case shortcutOptionPeriod = "shortcut.option_period"
  case shortcutOptionComma = "shortcut.option_comma"
  case shortcutOptionSlash = "shortcut.option_slash"
  case shortcutOptionSemicolon = "shortcut.option_semicolon"
  case shortcutControlPeriod = "shortcut.control_period"
  case shortcutControlSlash = "shortcut.control_slash"
  case shortcutRightOption = "shortcut.right_option"
  case shortcutRightCommand = "shortcut.right_command"

  case dictationEnglishUS = "dictation.english_us"
  case dictationSimplifiedChinese = "dictation.simplified_chinese"
  case dictationEnglishShort = "dictation.english_short"
  case dictationChineseShort = "dictation.chinese_short"
  case dictationChineseEnglish = "dictation.chinese_english"
  case motionQuiet = "motion.quiet"
  case motionLiquid = "motion.liquid"
  case motionBright = "motion.bright"
  case deliveryInsert = "delivery.insert"
  case deliveryClipboard = "delivery.clipboard"
  case deliveryInsertClipboard = "delivery.insert_clipboard"
  case deliverySave = "delivery.save"
  case phaseReady = "phase.ready"
  case phasePreparing = "phase.preparing"
  case phaseListening = "phase.listening"
  case phaseFinishing = "phase.finishing"
  case phaseSending = "phase.sending"
  case phaseAttention = "phase.attention"

  case settingsTitle = "settings.title"
  case settingsGeneral = "settings.general"
  case settingsInterface = "settings.interface"
  case settingsShortcut = "settings.shortcut"
  case settingsLaunch = "settings.launch"
  case settingsAtLogin = "settings.at_login"
  case settingsDictation = "settings.dictation"
  case settingsLanguage = "settings.language"
  case settingsDictationLanguage = "settings.dictation_language"
  case settingsAccuracy = "settings.accuracy"
  case settingsOutput = "settings.output"
  case settingsSendText = "settings.send_text"
  case settingsClipboard = "settings.clipboard"
  case settingsRestoreClipboard = "settings.restore_clipboard"
  case settingsStatus = "settings.status"
  case settingsShowWhileRecording = "settings.show_while_recording"
  case settingsHUDStyle = "settings.hud_style"
  case settingsInsertDelay = "settings.insert_delay"
  case settingsManage = "settings.manage"
  case settingsRemoveModel = "settings.remove_model"
  case settingsDownloadSenseVoice = "settings.download_sensevoice"
  case settingsAccessAttentionOne = "settings.access_attention.one"
  case settingsAccessAttentionFew = "settings.access_attention.few"
  case settingsAccessAttentionMany = "settings.access_attention.many"
  case settingsAccessAttentionOther = "settings.access_attention.other"
  case settingsReviewAccess = "settings.review_access"
  case settingsRecordings = "settings.recordings"
  case settingsOpenFolder = "settings.open_folder"

  case modelNotDownloaded = "model.not_downloaded"
  case modelDownloading = "model.downloading"
  case modelDownloadingVerifying = "model.downloading_verifying"
  case modelReady = "model.ready"
  case modelUnavailable = "model.unavailable"
  case modelUnavailableDetail = "model.unavailable_detail"

  case permissionMicrophone = "permission.microphone"
  case permissionSpeechRecognition = "permission.speech_recognition"
  case permissionInputMonitoring = "permission.input_monitoring"
  case permissionAccessibility = "permission.accessibility"
  case permissionEnableMicrophone = "permission.enable_microphone"
  case permissionEnableSpeechRecognition = "permission.enable_speech_recognition"
  case permissionEnableInputMonitoring = "permission.enable_input_monitoring"
  case permissionEnableAccessibility = "permission.enable_accessibility"
  case permissionHelpMicrophone = "permission.help_microphone"
  case permissionHelpSpeechRecognition = "permission.help_speech_recognition"
  case permissionHelpInputMonitoring = "permission.help_input_monitoring"
  case permissionHelpAccessibility = "permission.help_accessibility"
  case permissionRecordingRequired = "permission.recording_required"

  case menuCopyLastTranscript = "menu.copy_last_transcript"
  case menuRetryShortcut = "menu.retry_shortcut"
  case menuRecordings = "menu.recordings"
  case menuSettings = "menu.settings"
  case menuQuit = "menu.quit"
  case menuSetupRequired = "menu.setup_required"
  case menuShortcutUnavailable = "menu.shortcut_unavailable"
  case menuStartRecording = "menu.start_recording"
  case menuStopRecording = "menu.stop_recording"
  case menuDictationLanguage = "menu.dictation_language"
  case menuSessionCountOne = "menu.session_count.one"
  case menuSessionCountFew = "menu.session_count.few"
  case menuSessionCountMany = "menu.session_count.many"
  case menuSessionCountOther = "menu.session_count.other"

  case recordingsTitle = "recordings.title"
  case recordingsSavedLocally = "recordings.saved_locally"
  case recordingsRedoLatest = "recordings.redo_latest"
  case recordingsEmpty = "recordings.empty"
  case recordingsEmptyDetail = "recordings.empty_detail"
  case recordingsOpen = "recordings.open"
  case recordingsRetranscribe = "recordings.retranscribe"
  case recordingsShowInFinder = "recordings.show_in_finder"
  case recordingsMoreActions = "recordings.more_actions"

  case hudStopRecording = "hud.stop_recording"
  case hudPreparing = "hud.preparing"
  case hudFinishing = "hud.finishing"
  case hudSending = "hud.sending"
  case hudFailed = "hud.failed"
  case hudLiveRefined = "hud.live_refined"
  case hudLiveSettling = "hud.live_settling"

  case statusNothingToCopy = "status.nothing_to_copy"
  case statusTranscriptCopied = "status.transcript_copied"
  case statusNoSavedAudio = "status.no_saved_audio"
  case statusRetranscribing = "status.retranscribing"
  case statusRetranscribedCopied = "status.retranscribed_copied"
  case statusRecordingPermissionsReady = "status.recording_permissions_ready"
  case statusMicrophoneReady = "status.microphone_ready"
  case statusSpeechRecognitionReady = "status.speech_recognition_ready"
  case statusShortcutActive = "status.shortcut_active"
  case statusInputMonitoringRequired = "status.input_monitoring_required"
  case statusAccessibilityRequired = "status.accessibility_required"
  case statusHotkeyBlocked = "status.hotkey_blocked"
  case statusAccessibilityReady = "status.accessibility_ready"
  case statusLaunchAtLoginEnabled = "status.launch_at_login_enabled"
  case statusLaunchAtLoginDisabled = "status.launch_at_login_disabled"
  case statusWarmingLanguage = "status.warming_language"
  case statusWarmingEngine = "status.warming_engine"
  case statusPreparingEngine = "status.preparing_engine"
  case statusReadyShortcut = "status.ready_shortcut"
  case statusShortcutListenerFailed = "status.shortcut_listener_failed"
  case statusFinalizingWords = "status.finalizing_words"
  case statusRefining = "status.refining"
  case statusInserting = "status.inserting"
  case statusTextDeliveredArchiveFailed = "status.text_delivered_archive_failed"
  case statusTextDeliveredAudioIncomplete = "status.text_delivered_audio_incomplete"
  case statusListeningClipboardFallback = "status.listening_clipboard_fallback"
  case statusListeningReturnToApp = "status.listening_return_to_app"
  case statusListeningCopy = "status.listening_copy"
  case statusListeningSave = "status.listening_save"
  case statusInsertedSaved = "status.inserted_saved"
  case statusCopiedSaved = "status.copied_saved"
  case statusInsertedCopiedSaved = "status.inserted_copied_saved"
  case statusFinished = "status.finished"
  case statusAudioTextSaved = "status.audio_text_saved"
  case statusTranscriptionAudioIncomplete = "status.transcription_audio_incomplete"
  case statusFinalTranscriptionFailed = "status.final_transcription_failed"
  case timingStart = "timing.start"
  case timingFinish = "timing.finish"

  case sessionRecording = "session.recording"
  case sessionAudioOnly = "session.audio_only"
  case sessionComplete = "session.complete"
  case sessionRetranscribed = "session.retranscribed"
  case sessionFailed = "session.failed"
  case sessionAudioWriteWarning = "session.audio_write_warning"
  case sessionPartialAfterError = "session.partial_after_error"
  case sessionAppleFallback = "session.apple_fallback"
  case sessionQwenRefined = "session.qwen_refined"
  case sessionSenseVoiceRefined = "session.sensevoice_refined"
  case sessionSenseVoiceMerged = "session.sensevoice_merged"

  case errorAccessibilityRequired = "error.accessibility_required"
  case errorEmptyTranscript = "error.empty_transcript"
  case errorOriginalInputUnavailable = "error.original_input_unavailable"
  case errorPasteUnavailable = "error.paste_unavailable"
  case errorPasteUnconfirmed = "error.paste_unconfirmed"
  case errorUnsupportedLocale = "error.unsupported_locale"
  case errorSpeechFormatUnavailable = "error.speech_format_unavailable"
  case errorMicrophoneFormatUnavailable = "error.microphone_format_unavailable"
  case errorRefinementModelUnavailable = "error.refinement_model_unavailable"
  case errorRefinementDownloadFailed = "error.refinement_download_failed"
  case errorRefinementChecksum = "error.refinement_checksum"
  case errorRefinementHelperMissing = "error.refinement_helper_missing"
  case errorRefinementTimedOut = "error.refinement_timed_out"
  case errorRefinementHelperFailed = "error.refinement_helper_failed"
  case errorRefinementEmpty = "error.refinement_empty"

  var english: String {
    switch self {
    case .shortcutOptionPeriod: "⌥ Period"
    case .shortcutOptionComma: "⌥ Comma"
    case .shortcutOptionSlash: "⌥ Slash"
    case .shortcutOptionSemicolon: "⌥ Semicolon"
    case .shortcutControlPeriod: "⌃ Period"
    case .shortcutControlSlash: "⌃ Slash"
    case .shortcutRightOption: "Right Option"
    case .shortcutRightCommand: "Right Command"
    case .dictationEnglishUS: "English Only"
    case .dictationSimplifiedChinese: "English + Chinese"
    case .dictationEnglishShort: "English Only"
    case .dictationChineseShort: "English + Chinese"
    case .dictationChineseEnglish: "English + Chinese"
    case .motionQuiet: "Quiet"
    case .motionLiquid: "Liquid"
    case .motionBright: "Bright"
    case .deliveryInsert: "Insert at cursor"
    case .deliveryClipboard: "Clipboard only"
    case .deliveryInsertClipboard: "Insert + clipboard"
    case .deliverySave: "Save only"
    case .phaseReady: "Ready"
    case .phasePreparing: "Preparing"
    case .phaseListening: "Listening"
    case .phaseFinishing: "Finishing transcript"
    case .phaseSending: "Sending text"
    case .phaseAttention: "Needs attention"
    case .settingsTitle: "%@ Settings"
    case .settingsGeneral: "General"
    case .settingsInterface: "Interface"
    case .settingsShortcut: "Shortcut"
    case .settingsLaunch: "Launch"
    case .settingsAtLogin: "At login"
    case .settingsDictation: "Dictation"
    case .settingsLanguage: "Dictation mode"
    case .settingsDictationLanguage: "Dictation mode"
    case .settingsAccuracy: "Accuracy"
    case .settingsOutput: "Output"
    case .settingsSendText: "Send text"
    case .settingsClipboard: "Clipboard"
    case .settingsRestoreClipboard: "Restore after inserting"
    case .settingsStatus: "Status"
    case .settingsShowWhileRecording: "Show while recording"
    case .settingsHUDStyle: "HUD style"
    case .settingsInsertDelay: "Insert delay"
    case .settingsManage: "Manage"
    case .settingsRemoveModel: "Remove Model"
    case .settingsDownloadSenseVoice: "Download SenseVoice…"
    case .settingsAccessAttentionOne: "%lld access item needs attention"
    case .settingsAccessAttentionFew: "%lld access items need attention"
    case .settingsAccessAttentionMany: "%lld access items need attention"
    case .settingsAccessAttentionOther: "%lld access items need attention"
    case .settingsReviewAccess: "Review Access…"
    case .settingsRecordings: "Recordings…"
    case .settingsOpenFolder: "Open Folder"
    case .modelNotDownloaded: "Not downloaded"
    case .modelDownloading: "Downloading"
    case .modelDownloadingVerifying: "Downloading and verifying…"
    case .modelReady: "Ready"
    case .modelUnavailable: "Unavailable"
    case .modelUnavailableDetail: "Unavailable · %@"
    case .permissionMicrophone: "Microphone"
    case .permissionSpeechRecognition: "Speech Recognition"
    case .permissionInputMonitoring: "Input Monitoring"
    case .permissionAccessibility: "Accessibility"
    case .permissionEnableMicrophone: "Enable Microphone…"
    case .permissionEnableSpeechRecognition: "Enable Speech Recognition…"
    case .permissionEnableInputMonitoring: "Enable Input Monitoring…"
    case .permissionEnableAccessibility: "Enable Accessibility…"
    case .permissionHelpMicrophone: "Turn on %@ under Privacy & Security → Microphone."
    case .permissionHelpSpeechRecognition: "Turn on %@ under Privacy & Security → Speech Recognition."
    case .permissionHelpInputMonitoring: "Turn on %@ under Privacy & Security → Input Monitoring. That is not Accessibility."
    case .permissionHelpAccessibility: "Turn on %@ under Privacy & Security → Accessibility. That is not Input Monitoring."
    case .permissionRecordingRequired: "Microphone and Speech Recognition are required"
    case .menuCopyLastTranscript: "Copy Last Transcript"
    case .menuRetryShortcut: "Retry Shortcut Listener"
    case .menuRecordings: "Recordings…"
    case .menuSettings: "Settings…"
    case .menuQuit: "Quit %@"
    case .menuSetupRequired: "Setup required"
    case .menuShortcutUnavailable: "Shortcut unavailable"
    case .menuStartRecording: "Start Recording"
    case .menuStopRecording: "Stop Recording"
    case .menuDictationLanguage: "Dictation Mode"
    case .menuSessionCountOne: "Session: %lld"
    case .menuSessionCountFew, .menuSessionCountMany, .menuSessionCountOther: "Sessions: %lld"
    case .recordingsTitle: "Recordings"
    case .recordingsSavedLocally: "Saved locally"
    case .recordingsRedoLatest: "Redo Latest"
    case .recordingsEmpty: "No Recordings"
    case .recordingsEmptyDetail: "New recordings appear here automatically."
    case .recordingsOpen: "Open"
    case .recordingsRetranscribe: "Re-transcribe"
    case .recordingsShowInFinder: "Show in Finder"
    case .recordingsMoreActions: "More actions"
    case .hudStopRecording: "Stop recording"
    case .hudPreparing: "Preparing"
    case .hudFinishing: "Finishing"
    case .hudSending: "Sending"
    case .hudFailed: "Failed"
    case .hudLiveRefined: "Live %@ draft · refined after stop"
    case .hudLiveSettling: "Live %@ draft · words lock as they settle"
    case .statusNothingToCopy: "Nothing to copy yet"
    case .statusTranscriptCopied: "Transcript copied"
    case .statusNoSavedAudio: "No saved audio found"
    case .statusRetranscribing: "Re-transcribing %@…"
    case .statusRetranscribedCopied: "Re-transcribed and copied"
    case .statusRecordingPermissionsReady: "Microphone and Speech Recognition are ready"
    case .statusMicrophoneReady: "Microphone is ready"
    case .statusSpeechRecognitionReady: "Speech Recognition is ready"
    case .statusShortcutActive: "Shortcut %@ is active"
    case .statusInputMonitoringRequired: "Turn on %@.app under Privacy & Security → Input Monitoring for %@"
    case .statusAccessibilityRequired: "Turn on %@.app under Privacy & Security → Accessibility to insert text"
    case .statusHotkeyBlocked: "Hotkey still blocked by Input Monitoring"
    case .statusAccessibilityReady: "Accessibility is ready"
    case .statusLaunchAtLoginEnabled: "%@ will launch at login"
    case .statusLaunchAtLoginDisabled: "Launch at login disabled"
    case .statusWarmingLanguage: "Warming %@…"
    case .statusWarmingEngine: "Warming the local speech engine. First use may download language assets."
    case .statusPreparingEngine: "Preparing local speech engine. This may download language assets."
    case .statusReadyShortcut: "Ready · %@"
    case .statusShortcutListenerFailed: "Shortcut listener could not start"
    case .statusFinalizingWords: "Finalizing the last words…"
    case .statusRefining: "Refining…"
    case .statusInserting: "Inserting text…"
    case .statusTextDeliveredArchiveFailed: "Text delivered · archive failed: %@"
    case .statusTextDeliveredAudioIncomplete: "Text delivered · audio may be incomplete: %@"
    case .statusListeningClipboardFallback: "Listening · original input unavailable; will keep text on clipboard"
    case .statusListeningReturnToApp: "Listening · will return to the original input in %@"
    case .statusListeningCopy: "Listening · will copy the transcript"
    case .statusListeningSave: "Listening · transcript will be saved"
    case .statusInsertedSaved: "Inserted · audio and text saved"
    case .statusCopiedSaved: "Copied · audio and text saved"
    case .statusInsertedCopiedSaved: "Inserted and copied · files saved"
    case .statusFinished: "Finished"
    case .statusAudioTextSaved: "Audio and text saved"
    case .statusTranscriptionAudioIncomplete: "Transcription failed and audio may be incomplete (%@): %@"
    case .statusFinalTranscriptionFailed: "Audio was saved, but final transcription failed: %@"
    case .timingStart: "start"
    case .timingFinish: "finish"
    case .sessionRecording: "Recording"
    case .sessionAudioOnly: "Audio only"
    case .sessionComplete: "Complete"
    case .sessionRetranscribed: "Re-transcribed"
    case .sessionFailed: "Failed: %@"
    case .sessionAudioWriteWarning: "Audio write warning"
    case .sessionPartialAfterError: "Partial after error"
    case .sessionAppleFallback: "Apple fallback"
    case .sessionQwenRefined: "Qwen3 refined"
    case .sessionSenseVoiceRefined: "SenseVoice refined"
    case .sessionSenseVoiceMerged: "SenseVoice merged"
    case .errorAccessibilityRequired: "Accessibility permission is required to paste into another app. The transcript was left on your clipboard instead."
    case .errorEmptyTranscript: "There was no transcript to deliver."
    case .errorOriginalInputUnavailable: "The original input field is no longer available. The transcript was left on your clipboard instead."
    case .errorPasteUnavailable: "%@ could not send the paste command. The transcript was left on your clipboard instead."
    case .errorPasteUnconfirmed: "%@ could not confirm that the paste reached the original input field. The transcript was left on your clipboard instead."
    case .errorUnsupportedLocale: "Apple Dictation does not support the selected language (%@)."
    case .errorSpeechFormatUnavailable: "The required speech model or audio format is unavailable."
    case .errorMicrophoneFormatUnavailable: "The selected microphone did not provide a usable audio format."
    case .errorRefinementModelUnavailable: "The refinement model is not downloaded."
    case .errorRefinementDownloadFailed: "The official download failed."
    case .errorRefinementChecksum: "The downloaded file failed verification."
    case .errorRefinementHelperMissing: "The verified archive did not contain the expected helper."
    case .errorRefinementTimedOut: "Refinement timed out."
    case .errorRefinementHelperFailed: "The local refinement helper failed."
    case .errorRefinementEmpty: "Refinement returned no text."
    }
  }
}

enum LocalizationCatalog {
  private static let bundledCatalogs: [UILanguage: [String: String]] = {
    guard let resourceURL = Bundle.main.resourceURL else { return [:] }
    return (try? loadAll(from: resourceURL)) ?? [:]
  }()

  static func string(
    _ key: LocalizationKey,
    language: UILanguage,
    arguments: [CVarArg] = []
  ) -> String {
    let catalog = bundledCatalogs[language] ?? [:]
    return format(key, arguments: arguments, catalog: catalog)
  }

  static func format(
    _ key: LocalizationKey,
    arguments: [CVarArg],
    catalog: [String: String]
  ) -> String {
    let format = catalog[key.rawValue] ?? key.english
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: Locale(identifier: "en_US_POSIX"), arguments: arguments)
  }

  static func loadAll(from root: URL) throws -> [UILanguage: [String: String]] {
    var result: [UILanguage: [String: String]] = [:]
    for language in UILanguage.allCases {
      let url = root
        .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
        .appendingPathComponent("Localizable.strings")
      let data = try Data(contentsOf: url)
      guard let catalog = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: String]
      else {
        throw CocoaError(.fileReadCorruptFile)
      }
      result[language] = catalog
    }
    return result
  }
}
