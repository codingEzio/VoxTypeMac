@MainActor private var permissionApprovalWatchTask: Task<Void, Never>?

extension AppModel {
    func presentRecordingPermissionBlocker() -> String? {
        permissions.refresh()
        guard let section = PermissionGuidance.recordingBlocker(in: permissions.snapshot) else { return nil }
        let message = PermissionGuidance.recordingMessage(for: section)
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
