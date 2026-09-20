enum PermissionGuidance {
    static func recordingBlocker(in snapshot: PermissionSnapshot) -> PrivacySection? {
        if snapshot.microphone != .granted { return .microphone }
        if snapshot.speechRecognition != .granted { return .speechRecognition }
        return nil
    }

    static func recordingMessage(for section: PrivacySection) -> String {
        switch section {
        case .microphone: "Turn on \(ProductIdentity.displayName).app under Privacy & Security → Microphone"
        case .speechRecognition: "Turn on \(ProductIdentity.displayName).app under Privacy & Security → Speech Recognition"
        case .accessibility, .inputMonitoring: "Microphone and Speech Recognition are required"
        }
    }
}
