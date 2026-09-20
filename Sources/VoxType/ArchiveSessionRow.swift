import SwiftUI

struct SessionRow: View {
  let session: SavedSession
  @ObservedObject var model: AppModel

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "waveform")
        .foregroundStyle(.secondary)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 3) {
        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
          .fontWeight(.medium)
        Text(summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      Button(model.settings.text("Open", "打开")) {
        model.openTranscript(session)
      }

      Menu {
        Button(model.settings.text("Re-transcribe", "重新识别"), systemImage: "arrow.clockwise") {
          Task { await model.retranscribe(session) }
        }
        .disabled(model.phase.isBusy)
        Button(model.settings.text("Show in Finder", "在访达中显示"), systemImage: "folder") {
          model.reveal(session)
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help(model.settings.text("More actions", "更多操作"))
    }
    .controlSize(.regular)
    .padding(.vertical, 5)
  }

  private func durationLabel(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  private var summary: String {
    [
      durationLabel(session.durationSeconds), session.localeIdentifier, session.targetApplication,
      session.status,
    ]
    .compactMap { $0 }
    .joined(separator: " · ")
  }
}
