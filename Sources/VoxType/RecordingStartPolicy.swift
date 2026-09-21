enum RecordingStartMode: Equatable, Sendable {
  case liveSpeech
  case deferredRefinement
  case waitForSpeechModel
}

enum RecordingStartPolicy {
  static func mode(appleSpeechReady: Bool, refinementReady: Bool) -> RecordingStartMode {
    if appleSpeechReady { return .liveSpeech }
    if refinementReady { return .deferredRefinement }
    return .waitForSpeechModel
  }
}
