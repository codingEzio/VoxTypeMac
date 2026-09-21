import Testing

@testable import VoxType

@Test func recordingStartsWithoutWaitingWhenLocalRefinementIsReady() {
  #expect(
    RecordingStartPolicy.mode(appleSpeechReady: true, refinementReady: true)
      == .liveSpeech
  )
  #expect(
    RecordingStartPolicy.mode(appleSpeechReady: false, refinementReady: true)
      == .deferredRefinement
  )
  #expect(
    RecordingStartPolicy.mode(appleSpeechReady: false, refinementReady: false)
      == .waitForSpeechModel
  )
}
