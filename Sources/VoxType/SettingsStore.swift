import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let defaultFolder = SettingsFile.recordingsURL.path

    private let configURL: URL
    private var isLoading = true

    @Published var uiLanguage: UILanguage {
        didSet { persist() }
    }

    @Published var dictationLanguage: DictationLanguage {
        didSet { persist() }
    }

    @Published var deliveryMode: DeliveryMode {
        didSet { persist() }
    }

    var localeIdentifier: String { dictationLanguage.rawValue }

    var saveFolder: String { Self.defaultFolder }

    @Published var preserveClipboard: Bool {
        didSet { persist() }
    }

    @Published var showFloatingHUD: Bool {
        didSet { persist() }
    }

    @Published var launchAtLogin: Bool {
        didSet { persist() }
    }

    @Published var pasteDelayMilliseconds: Int {
        didSet {
            let clamped = min(max(pasteDelayMilliseconds, 50), 800)
            if clamped != pasteDelayMilliseconds {
                pasteDelayMilliseconds = clamped
            }
            persist()
        }
    }

    @Published var dictationShortcut: DictationShortcut {
        didSet { persist() }
    }

    @Published var motionStyle: MotionStyle {
        didSet { persist() }
    }

    init(configURL: URL = SettingsFile.configURL) {
        self.configURL = configURL
        let file = SettingsFile(url: configURL)
        self.uiLanguage = UILanguage(rawValue: file["ui_language"] ?? "") ?? .english
        self.dictationLanguage = DictationLanguage(rawValue: file["speech_mode"] ?? "")
            ?? .englishUS
        let storedMode = file["delivery_mode"]
        self.deliveryMode = DeliveryMode(rawValue: storedMode ?? "") ?? .insertOnly
        if let stored = file["preserve_clipboard"] {
            self.preserveClipboard = stored == "true"
        } else {
            self.preserveClipboard = true
        }

        if let stored = file["show_floating_hud"] {
            self.showFloatingHUD = stored == "true"
        } else {
            self.showFloatingHUD = true
        }

        self.launchAtLogin = file["launch_at_login"].map { $0 == "true" }
            ?? false
        let storedShortcut = file["dictation_shortcut"]
        self.dictationShortcut = storedShortcut.flatMap(DictationShortcut.init(rawValue:))
            ?? .default
        let delay = Int(file["paste_delay_milliseconds"] ?? "")
            ?? 0
        self.pasteDelayMilliseconds = delay == 0 ? 140 : min(max(delay, 50), 800)
        self.motionStyle = MotionStyle(rawValue: file["motion_style"] ?? "") ?? .liquid
        isLoading = false
        persist()
    }

    var resolvedLocale: Locale {
        dictationLanguage.locale
    }

    func text(_ key: LocalizationKey, _ arguments: CVarArg...) -> String {
        LocalizationCatalog.string(key, language: uiLanguage, arguments: arguments)
    }

    func accessAttention(count: Int) -> String {
        text(pluralKey(count: count, one: .settingsAccessAttentionOne,
                       few: .settingsAccessAttentionFew,
                       many: .settingsAccessAttentionMany,
                       other: .settingsAccessAttentionOther), Int64(count))
    }

    func sessionCount(_ count: Int) -> String {
        text(pluralKey(count: count, one: .menuSessionCountOne,
                       few: .menuSessionCountFew,
                       many: .menuSessionCountMany,
                       other: .menuSessionCountOther), Int64(count))
    }

    private func pluralKey(
        count: Int,
        one: LocalizationKey,
        few: LocalizationKey,
        many: LocalizationKey,
        other: LocalizationKey
    ) -> LocalizationKey {
        switch LocalizationPlural.category(for: count, language: uiLanguage) {
        case .one: one
        case .few: few
        case .many: many
        case .other: other
        }
    }

    func phaseTitle(_ phase: RecorderPhase) -> String {
        text(phase.localizationKey)
    }

    func deliveryTitle(_ mode: DeliveryMode) -> String {
        text(mode.localizationKey)
    }

    func localizedError(_ error: Error) -> String {
        switch error {
        case let error as OutputDispatcher.DeliveryError:
            switch error {
            case .accessibilityPermissionMissing: text(.errorAccessibilityRequired)
            case .emptyTranscript: text(.errorEmptyTranscript)
            case .originalInputUnavailable: text(.errorOriginalInputUnavailable)
            case .pasteEventUnavailable: text(.errorPasteUnavailable, ProductIdentity.displayName)
            case .pasteCouldNotBeConfirmed: text(.errorPasteUnconfirmed, ProductIdentity.displayName)
            }
        case let error as NativeSpeechEngine.EngineError:
            switch error {
            case .unsupportedLocale(let locale): text(.errorUnsupportedLocale, locale)
            case .audioFormatUnavailable: text(.errorSpeechFormatUnavailable)
            }
        case let error as AudioCapture.CaptureError:
            switch error {
            case .invalidInputFormat: text(.errorMicrophoneFormatUnavailable)
            }
        case let error as RefinementError:
            switch error {
            case .modelUnavailable: text(.errorRefinementModelUnavailable)
            case .downloadFailed: text(.errorRefinementDownloadFailed)
            case .checksumMismatch: text(.errorRefinementChecksum)
            case .missingRuntime: text(.errorRefinementHelperMissing)
            case .timedOut: text(.errorRefinementTimedOut)
            case .helperFailed: text(.errorRefinementHelperFailed)
            case .emptyResult: text(.errorRefinementEmpty)
            }
        default:
            error.localizedDescription
        }
    }

    func sessionStatus(_ status: String) -> String {
        if status.hasPrefix("failed: ") {
            return text(.sessionFailed, String(status.dropFirst("failed: ".count)))
        }
        let key: LocalizationKey? = switch status {
        case "recording": .sessionRecording
        case "audio-only": .sessionAudioOnly
        case "complete": .sessionComplete
        case "retranscribed": .sessionRetranscribed
        case "audio-write-warning": .sessionAudioWriteWarning
        case "partial-after-error": .sessionPartialAfterError
        case "apple-fallback": .sessionAppleFallback
        case "qwen3-refined": .sessionQwenRefined
        case "sensevoice-refined": .sessionSenseVoiceRefined
        case "sensevoice-merged": .sessionSenseVoiceMerged
        default: nil
        }
        return key.map { text($0) } ?? status
    }

    private func persist() {
        guard !isLoading else { return }
        var file = SettingsFile(url: configURL)
        file.set("2", for: "schema_version")
        file.set(uiLanguage.rawValue, for: "ui_language")
        file.set(localeIdentifier, for: "speech_mode")
        file.set(deliveryMode.rawValue, for: "delivery_mode")
        file.set(String(preserveClipboard), for: "preserve_clipboard")
        file.set(String(showFloatingHUD), for: "show_floating_hud")
        file.set(String(launchAtLogin), for: "launch_at_login")
        file.set(dictationShortcut.rawValue, for: "dictation_shortcut")
        file.set(String(pasteDelayMilliseconds), for: "paste_delay_milliseconds")
        file.set(motionStyle.rawValue, for: "motion_style")
        try? file.write(to: configURL)
    }

    var saveFolderURL: URL {
        SettingsFile.recordingsURL
    }
}
