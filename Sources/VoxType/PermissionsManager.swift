@preconcurrency import AVFoundation
import AppKit
@preconcurrency import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import OSLog
@preconcurrency import Speech

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var snapshot = PermissionSnapshot(
        microphone: .notDetermined,
        speechRecognition: .notDetermined,
        accessibility: .notDetermined,
        inputMonitoring: .notDetermined
    )

    private let bundleIdentifier: String
    private let receiptURL: URL
    private let logger = Logger(subsystem: "app.voxtypemac.VoxTypeMac", category: "Permissions")
    private var lastLoggedSnapshot: PermissionSnapshot?

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "app.voxtypemac.VoxTypeMac",
        receiptURL: URL? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.receiptURL = receiptURL ?? Self.defaultReceiptURL
        refresh()
    }

    func refresh() {
        let receipt = loadReceipt()
        let updated = PermissionSnapshot(
            microphone: Self.mapMicrophone(AVCaptureDevice.authorizationStatus(for: .audio)),
            speechRecognition: Self.mapSpeech(SFSpeechRecognizer.authorizationStatus()),
            accessibility: PermissionRequestPolicy.displayedState(
                osGranted: AXIsProcessTrusted(),
                alreadyRequested: receipt.requested(for: .accessibility)
            ),
            inputMonitoring: PermissionRequestPolicy.displayedState(
                osGranted: CGPreflightListenEventAccess(),
                alreadyRequested: receipt.requested(for: .inputMonitoring)
            )
        )
        snapshot = updated
        if lastLoggedSnapshot != updated {
            logger.info(
                "Permissions microphone=\(updated.microphone.rawValue, privacy: .public) speech=\(updated.speechRecognition.rawValue, privacy: .public) accessibility=\(updated.accessibility.rawValue, privacy: .public) inputMonitoring=\(updated.inputMonitoring.rawValue, privacy: .public)"
            )
            lastLoggedSnapshot = updated
        }
    }

    func requestRecordingPermissions() async -> Bool {
        if PermissionRequestPolicy.decideRecording(
            authorized: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            notDetermined: AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
        ) == .requestNow {
            _ = await Self.requestMicrophone()
        }
        if PermissionRequestPolicy.decideRecording(
            authorized: SFSpeechRecognizer.authorizationStatus() == .authorized,
            notDetermined: SFSpeechRecognizer.authorizationStatus() == .notDetermined
        ) == .requestNow {
            _ = await Self.requestSpeechRecognition()
        }
        refresh()
        return snapshot.canRecord
    }

    func grantOrOpen(_ section: PrivacySection) async {
        switch section {
        case .microphone:
            if PermissionRequestPolicy.decideRecording(
                authorized: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                notDetermined: AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
            ) == .requestNow {
                _ = await Self.requestMicrophone()
            }
            refresh()
            if snapshot.microphone != .granted {
                openPrivacySettings(.microphone)
            }
        case .speechRecognition:
            if PermissionRequestPolicy.decideRecording(
                authorized: SFSpeechRecognizer.authorizationStatus() == .authorized,
                notDetermined: SFSpeechRecognizer.authorizationStatus() == .notDetermined
            ) == .requestNow {
                _ = await Self.requestSpeechRecognition()
            }
            refresh()
            if snapshot.speechRecognition != .granted {
                openPrivacySettings(.speechRecognition)
            }
        case .accessibility, .inputMonitoring:
            let receipt = loadReceipt()
            let osGranted = section == .accessibility ? AXIsProcessTrusted() : CGPreflightListenEventAccess()
            switch PermissionRequestPolicy.decide(
                osGranted: osGranted,
                alreadyRequested: receipt.requested(for: section)
            ) {
            case .alreadyGranted:
                refresh()
            case .requestNow:
                prompt(section)
                save(receipt.marking(section))
                refresh()
                if snapshot.state(for: section) != .granted {
                    openPrivacySettings(section)
                }
            case .openSettings:
                openPrivacySettings(section)
            }
        }
    }

    func openPrivacySettings(_ section: PrivacySection) {
        guard let url = URL(string: PrivacySettingsLink.url(section)) else { return }
        NSWorkspace.shared.open(url)
    }

    private func prompt(_ section: PrivacySection) {
        switch section {
        case .accessibility:
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .microphone, .speechRecognition:
            break
        }
    }

    private func loadReceipt() -> PermissionRequestReceipt {
        let empty = PermissionRequestReceipt(
            bundleIdentifier: bundleIdentifier,
            accessibility: false,
            inputMonitoring: false
        )
        guard let data = try? Data(contentsOf: receiptURL),
              let decoded = try? JSONDecoder().decode(PermissionRequestReceipt.self, from: data),
              PermissionRequestStore.matchesIdentity(decoded, bundleIdentifier: bundleIdentifier)
        else {
            return empty
        }
        return decoded
    }

    private func save(_ receipt: PermissionRequestReceipt) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(receipt),
              (try? SettingsFile.requireContained(receiptURL)) != nil
        else { return }
        try? FileManager.default.createDirectory(at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: receiptURL, options: .atomic)
    }

    private static var defaultReceiptURL: URL {
        SettingsFile.stateURL.appendingPathComponent("permission-request.json")
    }

    nonisolated private static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    nonisolated private static func requestSpeechRecognition() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func mapMicrophone(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    private static func mapSpeech(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }
}

extension PermissionSnapshot {
    func state(for section: PrivacySection) -> PermissionState {
        switch section {
        case .microphone: microphone
        case .speechRecognition: speechRecognition
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        }
    }
}
