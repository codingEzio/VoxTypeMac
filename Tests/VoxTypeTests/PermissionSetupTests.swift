import Testing

@testable import VoxType

@Test func accessSetupKeepsAllFourStatusesVisibleInActionOrder() {
  let snapshot = PermissionSnapshot(
    microphone: .granted,
    speechRecognition: .notDetermined,
    accessibility: .granted,
    inputMonitoring: .denied
  )

  #expect(
    PermissionSetupPlan.badges(in: snapshot)
      == [
        PermissionBadge(section: .microphone, state: .granted),
        PermissionBadge(section: .speechRecognition, state: .needsAction),
        PermissionBadge(section: .accessibility, state: .granted),
        PermissionBadge(section: .inputMonitoring, state: .needsAction),
      ])
}
