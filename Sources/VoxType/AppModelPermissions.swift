@MainActor private var permissionApprovalWatchTask: Task<Void, Never>?

extension AppModel {
    func presentRecordingPermissionBlocker() -> String? {
        permissions.refresh()
        guard let section = PermissionGuidance.recordingBlocker(in: permissions.snapshot) else { return nil }
        let message = switch section {
        case .microphone:
            settings.text(.permissionHelpMicrophone, "\(ProductIdentity.displayName).app")
        case .speechRecognition:
            settings.text(.permissionHelpSpeechRecognition, "\(ProductIdentity.displayName).app")
        case .accessibility, .inputMonitoring:
            settings.text(.permissionRecordingRequired)
        }
        permissions.openPrivacySettings(section)
        statusMessage = message
        watchPermissionApproval()
        return message
    }

    func watchPermissionApproval() {
        permissionApprovalWatchTask?.cancel()
        permissionApprovalWatchTask = Task { [weak self] in
            for _ in 0..<90 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                permissions.refresh()
                let snapshot = permissions.snapshot
                if snapshot.canRecord, snapshot.canUseGlobalHotkey, snapshot.canInsertText { return }
            }
        }
    }
}
