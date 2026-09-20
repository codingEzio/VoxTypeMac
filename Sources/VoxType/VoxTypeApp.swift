import AppKit
import Darwin

@main
@MainActor
enum VoxTypeApp {
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
      application.run()
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItemController: StatusItemController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    if CommandLine.arguments.contains("--migrate-login-item") {
      do {
        try LaunchAtLoginManager.migrateRegistration(
          shouldEnable: AppModel.shared.settings.launchAtLogin
        )
        print("\(ProductIdentity.displayName) login item migration completed.")
        exit(EXIT_SUCCESS)
      } catch {
        fputs("\(ProductIdentity.displayName) login item migration failed: \(error)\n", stderr)
        exit(EXIT_FAILURE)
      }
    }

    AppModel.shared.start()
    let controller = StatusItemController(model: AppModel.shared)
    statusItemController = controller
    if CommandLine.arguments.contains("--settings") {
      AppModel.shared.showSettings()
    }
    if CommandLine.arguments.contains("--recordings") {
      AppModel.shared.showRecordings()
    }
    if CommandLine.arguments.contains("--popover") || CommandLine.arguments.contains("--menu") {
      Task {
        try? await Task.sleep(for: .milliseconds(300))
        NSApp.activate()
        controller.showMenu()
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard AppModel.shared.phase == .recording else { return .terminateNow }

    Task { @MainActor in
      await AppModel.shared.stopRecording()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
