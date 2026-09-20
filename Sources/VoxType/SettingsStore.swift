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

    func text(_ english: String, _ simplifiedChinese: String) -> String {
        uiLanguage == .simplifiedChinese ? simplifiedChinese : english
    }

    func phaseTitle(_ phase: RecorderPhase) -> String {
        guard uiLanguage == .simplifiedChinese else { return phase.title }
        return switch phase {
        case .idle: "就绪"
        case .preparing: "准备中"
        case .recording: "正在聆听"
        case .finalizing: "正在完成文字"
        case .delivering: "正在发送文字"
        case .failed: "需要处理"
        }
    }

    func deliveryTitle(_ mode: DeliveryMode) -> String {
        guard uiLanguage == .simplifiedChinese else { return mode.title }
        return switch mode {
        case .insertOnly: "插入光标位置"
        case .clipboardOnly: "仅复制到剪贴板"
        case .insertAndClipboard: "插入并保留到剪贴板"
        case .saveOnly: "仅保存"
        }
    }

    func localizedStatus(_ status: String) -> String {
        guard uiLanguage == .simplifiedChinese else { return status }
        if status.hasPrefix("Ready · ") {
            return "就绪 · \(status.dropFirst("Ready · ".count))"
        }
        if status.hasPrefix("Enable Input Monitoring for ") {
            return "请启用输入监控以使用 \(status.dropFirst("Enable Input Monitoring for ".count))"
        }
        let known = [
            "Enable Accessibility to insert text at the cursor": "请启用辅助功能以在光标处插入文字",
            "Right Command listener could not start": "右 Command 监听器无法启动",
            "Shortcut listener could not start": "快捷键监听器无法启动",
            "Preparing…": "准备中…",
            "Refining…": "正在优化…"
        ]
        return known[status] ?? status
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
