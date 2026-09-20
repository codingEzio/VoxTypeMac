import Foundation

enum PrivacySection: String, CaseIterable, Sendable {
    case microphone
    case speechRecognition
    case accessibility
    case inputMonitoring

    var query: String {
        switch self {
        case .microphone: "Privacy_Microphone"
        case .speechRecognition: "Privacy_SpeechRecognition"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
    }
}

enum PrivacySettingsLink {
    static let pane = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"

    static func url(_ section: PrivacySection) -> String {
        "\(pane)?\(section.query)"
    }
}

enum PermissionRequestDecision: Equatable, Sendable {
    case alreadyGranted
    case requestNow
    case openSettings
}

enum PermissionRequestPolicy {
    static func decide(osGranted: Bool, alreadyRequested: Bool) -> PermissionRequestDecision {
        if osGranted { return .alreadyGranted }
        return alreadyRequested ? .openSettings : .requestNow
    }

    static func displayedState(osGranted: Bool, alreadyRequested: Bool) -> PermissionState {
        if osGranted { return .granted }
        return alreadyRequested ? .denied : .notDetermined
    }

    static func decideRecording(authorized: Bool, notDetermined: Bool) -> PermissionRequestDecision {
        if authorized { return .alreadyGranted }
        return notDetermined ? .requestNow : .openSettings
    }
}

struct PermissionRequestReceipt: Equatable, Sendable, Codable {
    var schemaVersion: Int
    var bundleIdentifier: String
    var accessibility: Bool
    var inputMonitoring: Bool

    static let legacySchemaVersion = 1
    static let currentSchemaVersion = 2

    init(
        schemaVersion: Int = currentSchemaVersion,
        bundleIdentifier: String,
        accessibility: Bool,
        inputMonitoring: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.bundleIdentifier = bundleIdentifier
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, bundleIdentifier, accessibility, inputMonitoring
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.legacySchemaVersion
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? ""
        accessibility = try container.decodeIfPresent(Bool.self, forKey: .accessibility) ?? false
        inputMonitoring = try container.decodeIfPresent(Bool.self, forKey: .inputMonitoring) ?? false
    }

    func requested(for section: PrivacySection) -> Bool {
        switch section {
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        case .microphone, .speechRecognition: false
        }
    }

    func marking(_ section: PrivacySection) -> PermissionRequestReceipt {
        var next = self
        switch section {
        case .accessibility: next.accessibility = true
        case .inputMonitoring: next.inputMonitoring = true
        case .microphone, .speechRecognition: break
        }
        return next
    }
}

enum PermissionRequestStore {
    static func matchesIdentity(_ receipt: PermissionRequestReceipt?, bundleIdentifier: String) -> Bool {
        guard let receipt else { return false }
        return receipt.schemaVersion == PermissionRequestReceipt.currentSchemaVersion
            && receipt.bundleIdentifier == bundleIdentifier
    }
}
