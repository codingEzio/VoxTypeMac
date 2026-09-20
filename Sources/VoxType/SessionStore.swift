import Foundation

actor SessionStore {
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init() {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder
  }

  func begin(
    in folderURL: URL,
    localeIdentifier: String,
    targetApplication: String?
  ) throws -> SessionDraft {
    try SettingsFile.requireContained(folderURL)
    try FileManager.default.createDirectory(
      at: folderURL,
      withIntermediateDirectories: true
    )

    let startedAt = Date()
    let timestamp = Self.fileTimestamp.string(from: startedAt)
    let safeLocale = Self.safeFilenameComponent(localeIdentifier, fallback: "unknown-locale")
    let safeTarget = Self.safeFilenameComponent(
      targetApplication ?? "NoTarget", fallback: "NoTarget")
    let baseName = "\(timestamp)__\(safeTarget)__\(safeLocale)"

    let draft = SessionDraft(
      baseName: baseName,
      startedAt: startedAt,
      localeIdentifier: localeIdentifier,
      folderURL: folderURL,
      audioURL: folderURL.appendingPathComponent(baseName).appendingPathExtension("caf"),
      transcriptURL: folderURL.appendingPathComponent(baseName).appendingPathExtension("txt"),
      partialTranscriptURL: folderURL.appendingPathComponent(baseName).appendingPathExtension(
        "partial.txt"),
      metadataURL: folderURL.appendingPathComponent(baseName).appendingPathExtension("json")
    )

    let initial = SavedSession(
      baseName: baseName,
      startedAt: startedAt,
      finishedAt: nil,
      localeIdentifier: localeIdentifier,
      durationSeconds: 0,
      audioPath: draft.audioURL.path,
      transcriptPath: draft.transcriptURL.path,
      metadataPath: draft.metadataURL.path,
      status: "recording",
      targetApplication: targetApplication,
      characterCount: 0
    )
    try writeMetadata(initial, to: draft.metadataURL)
    return draft
  }

  func writePartial(_ text: String, for draft: SessionDraft) {
    guard !text.isEmpty else { return }
    guard (try? SettingsFile.requireContained(draft.partialTranscriptURL)) != nil else { return }
    try? text.write(to: draft.partialTranscriptURL, atomically: true, encoding: .utf8)
  }

  func finish(
    _ draft: SessionDraft,
    transcript: String,
    durationSeconds: Double,
    targetApplication: String?,
    status requestedStatus: String? = nil
  ) throws -> SavedSession {
    try SettingsFile.requireContained(draft.transcriptURL)
    try SettingsFile.requireContained(draft.metadataURL)
    let cleanText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    try cleanText.write(to: draft.transcriptURL, atomically: true, encoding: .utf8)
    try? FileManager.default.removeItem(at: draft.partialTranscriptURL)

    let completed = SavedSession(
      baseName: draft.baseName,
      startedAt: draft.startedAt,
      finishedAt: Date(),
      localeIdentifier: draft.localeIdentifier,
      durationSeconds: durationSeconds,
      audioPath: draft.audioURL.path,
      transcriptPath: draft.transcriptURL.path,
      metadataPath: draft.metadataURL.path,
      status: requestedStatus ?? (cleanText.isEmpty ? "audio-only" : "complete"),
      targetApplication: targetApplication,
      characterCount: cleanText.count
    )
    try writeMetadata(completed, to: draft.metadataURL)
    return completed
  }

  func markFailed(
    _ draft: SessionDraft,
    durationSeconds: Double,
    error: String,
    targetApplication: String?
  ) {
    guard (try? SettingsFile.requireContained(draft.metadataURL)) != nil else { return }
    let failure = SavedSession(
      baseName: draft.baseName,
      startedAt: draft.startedAt,
      finishedAt: Date(),
      localeIdentifier: draft.localeIdentifier,
      durationSeconds: durationSeconds,
      audioPath: draft.audioURL.path,
      transcriptPath: draft.transcriptURL.path,
      metadataPath: draft.metadataURL.path,
      status: "failed: \(error)",
      targetApplication: targetApplication,
      characterCount: 0
    )
    try? writeMetadata(failure, to: draft.metadataURL)
  }

  func replaceTranscript(for audioURL: URL, with text: String) throws -> SavedSession {
    try SettingsFile.requireContained(audioURL)
    let baseURL = audioURL.deletingPathExtension()
    let transcriptURL = baseURL.appendingPathExtension("txt")
    let metadataURL = baseURL.appendingPathExtension("json")
    try SettingsFile.requireContained(transcriptURL)
    try SettingsFile.requireContained(metadataURL)
    let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    try cleanText.write(to: transcriptURL, atomically: true, encoding: .utf8)

    let existing = try? decodeMetadata(at: metadataURL)
    let session = SavedSession(
      baseName: baseURL.lastPathComponent,
      startedAt: existing?.startedAt
        ?? (try? audioURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date(),
      finishedAt: Date(),
      localeIdentifier: existing?.localeIdentifier ?? Locale.current.identifier,
      durationSeconds: existing?.durationSeconds ?? 0,
      audioPath: audioURL.path,
      transcriptPath: transcriptURL.path,
      metadataPath: metadataURL.path,
      status: "retranscribed",
      targetApplication: existing?.targetApplication,
      characterCount: cleanText.count
    )
    try writeMetadata(session, to: metadataURL)
    return session
  }

  func recentSessions(in folderURL: URL, limit: Int = 12) -> [SavedSession] {
    guard (try? SettingsFile.requireContained(folderURL)) != nil else { return [] }
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: folderURL,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    return
      urls
      .filter { $0.pathExtension.lowercased() == "json" }
      .compactMap { try? decodeMetadata(at: $0) }
      .sorted { $0.startedAt > $1.startedAt }
      .prefix(max(limit, 0))
      .map { $0 }
  }

  func latestTranscript(in folderURL: URL) -> String? {
    for session in recentSessions(in: folderURL, limit: .max) {
      guard (try? SettingsFile.requireContained(session.transcriptURL)) != nil else { continue }
      let text =
        (try? String(contentsOf: session.transcriptURL, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !text.isEmpty { return text }
    }
    return nil
  }

  func latestAudioURL(in folderURL: URL) -> URL? {
    guard (try? SettingsFile.requireContained(folderURL)) != nil else { return nil }
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: folderURL,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return nil
    }

    return
      urls
      .filter { $0.pathExtension.lowercased() == "caf" }
      .sorted {
        let left =
          (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
          ?? .distantPast
        let right =
          (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
          ?? .distantPast
        return left > right
      }
      .first
  }

  private func writeMetadata(_ session: SavedSession, to url: URL) throws {
    try SettingsFile.requireContained(url)
    let data = try encoder.encode(session)
    try data.write(to: url, options: .atomic)
  }

  private func decodeMetadata(at url: URL) throws -> SavedSession {
    try SettingsFile.requireContained(url)
    let data = try Data(contentsOf: url)
    let session = try decoder.decode(SavedSession.self, from: data)
    for candidate in [session.audioURL, session.transcriptURL, session.metadataURL] {
      try SettingsFile.requireContained(candidate)
    }
    let actualMetadata = url.standardizedFileURL.resolvingSymlinksInPath()
    let declaredMetadata = session.metadataURL.standardizedFileURL.resolvingSymlinksInPath()
    guard actualMetadata == declaredMetadata,
      session.audioURL.deletingPathExtension().lastPathComponent == session.baseName,
      session.transcriptURL.deletingPathExtension().lastPathComponent == session.baseName,
      session.metadataURL.deletingPathExtension().lastPathComponent == session.baseName
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return session
  }

  private static func safeFilenameComponent(_ value: String, fallback: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    var output = ""
    var previousWasSeparator = false

    for scalar in value.unicodeScalars {
      if allowed.contains(scalar) {
        output.unicodeScalars.append(scalar)
        previousWasSeparator = false
      } else if !previousWasSeparator, !output.isEmpty {
        output.append("-")
        previousWasSeparator = true
      }
      if output.count >= 48 { break }
    }

    let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
    return trimmed.isEmpty ? fallback : trimmed
  }

  private static let fileTimestamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
    return formatter
  }()
}
