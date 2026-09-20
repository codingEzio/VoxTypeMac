import Testing

@testable import VoxType

@Test func recordingPermissionBlockerIsDeterministic() {
    let states: [(PermissionState, PermissionState, PrivacySection?)] = [
        (.granted, .granted, nil),
        (.denied, .granted, .microphone),
        (.granted, .denied, .speechRecognition),
        (.notDetermined, .notDetermined, .microphone),
    ]

    for (microphone, speech, expected) in states {
        let snapshot = PermissionSnapshot(
            microphone: microphone,
            speechRecognition: speech,
            accessibility: .granted,
            inputMonitoring: .granted
        )
        #expect(PermissionGuidance.recordingBlocker(in: snapshot) == expected)
    }
}

@Test func recordingPermissionMessagesNameTheExactBlocker() {
    #expect(PermissionGuidance.recordingMessage(for: .microphone).hasSuffix("→ Microphone"))
    #expect(
        PermissionGuidance.recordingMessage(for: .speechRecognition)
            .hasSuffix("→ Speech Recognition"))
}
