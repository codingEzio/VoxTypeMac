import AppKit
import SwiftUI

@MainActor
extension AppModel {
  func refreshLocalizedPresentation() {
    settingsWindow?.title = settings.text(.settingsTitle, ProductIdentity.displayName)
    recordingsWindow?.title = settings.text(.recordingsTitle)
    if phase == .idle {
      statusMessage = readinessMessage
    }
  }

  func showSettings() {
    let window = settingsWindow ?? makeSettingsWindow()
    settingsWindow = window
    NSApp.activate()
    if let front = NSWorkspace.shared.frontmostApplication {
      _ = NSRunningApplication.current.activate(from: front, options: [.activateAllWindows])
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    permissions.refresh()
  }

  func keepSettingsVisible() {
    guard let window = settingsWindow else { return }
    window.orderFront(nil)
  }

  fileprivate func makeSettingsWindow() -> NSWindow {
    let host = NSHostingController(rootView: SettingsRootView(model: self))
    let window = NSWindow(contentViewController: host)
    window.title = settings.text(.settingsTitle, ProductIdentity.displayName)
    window.styleMask = [.titled, .closable]
    window.setContentSize(
      NSSize(width: SettingsLayout.windowWidth, height: SettingsLayout.defaultHeight))
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.delegate = settingsAnchor
    window.center()
    return window
  }
}

final class AuxiliaryWindowAnchor: NSObject, NSWindowDelegate {
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }
}
