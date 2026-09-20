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
        Text(
          session.startedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
              .locale(model.settings.uiLanguage.foundationLocale)
          )
        )
          .fontWeight(.medium)
        Text(summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      Button(model.settings.text(.recordingsOpen)) {
        model.openTranscript(session)
      }

      Menu {
        Button(model.settings.text(.recordingsRetranscribe), systemImage: "arrow.clockwise") {
          Task { await model.retranscribe(session) }
        }
        .disabled(model.phase.isBusy)
        Button(model.settings.text(.recordingsShowInFinder), systemImage: "folder") {
          model.reveal(session)
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help(model.settings.text(.recordingsMoreActions))
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
      model.settings.sessionStatus(session.status),
    ]
    .compactMap { $0 }
    .joined(separator: " · ")
  }
}
