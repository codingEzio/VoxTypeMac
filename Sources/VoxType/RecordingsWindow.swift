import AppKit
import SwiftUI

@MainActor
extension AppModel {
  func showRecordings() {
    let window = recordingsWindow ?? makeRecordingsWindow()
    recordingsWindow = window
    refreshRecentSessions()
    NSApp.activate()
    if let front = NSWorkspace.shared.frontmostApplication {
      _ = NSRunningApplication.current.activate(from: front, options: [.activateAllWindows])
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  fileprivate func makeRecordingsWindow() -> NSWindow {
    let host = NSHostingController(rootView: RecordingsRootView(model: self))
    let window = NSWindow(contentViewController: host)
    window.title = settings.text("Recordings", "录音")
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.contentMinSize = NSSize(width: 560, height: 300)
    window.setContentSize(NSSize(width: 660, height: 420))
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.delegate = recordingsAnchor
    window.center()
    return window
  }
}

private struct RecordingsRootView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(model.settings.text("Saved locally", "保存在本机"))
            .font(.headline)
          Text(model.settings.saveFolder)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
        Spacer()
        Button(model.settings.text("Open Folder", "打开文件夹"), systemImage: "folder") {
          model.openSaveFolder()
        }
        Button(model.settings.text("Redo Latest", "重新识别最新"), systemImage: "arrow.clockwise") {
          Task { await model.retranscribeLatestAudio() }
        }
        .disabled(model.phase.isBusy || model.recentSessions.isEmpty)
      }
      .controlSize(.regular)
      .padding(16)

      Divider()

      if model.recentSessions.isEmpty {
        ContentUnavailableView(
          model.settings.text("No Recordings", "还没有录音"),
          systemImage: "waveform",
          description: Text(
            model.settings.text(
              "New recordings appear here automatically.",
              "新的录音会自动显示在这里。"
            ))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(model.recentSessions) { session in
          SessionRow(session: session, model: model)
        }
        .listStyle(.inset)
      }
    }
  }
}
