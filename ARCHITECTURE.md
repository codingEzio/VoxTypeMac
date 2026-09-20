# VoxTypeMac architecture

## Hot path

```text
Chosen shortcut event (default Option + .)
            │
            ▼
 GlobalHotkeyMonitor
 clean tap? ── no ──► ignore
      │ yes
      ▼
    AppModel
      │
      ├──────────────► SessionStore creates timestamped paths
      │
      ├──────────────► AudioCapture writes every buffer to .caf
      │                       │
      │                       └────► lock-protected PCM bins
      │                                      │
      │                                      └────► CADisplayLink / Liquid Glass HUD
      │
            └──────────────► NativeSpeechEngine (Apple selected-locale live)
                                      │
                                      └─ RefinementService (Qwen3-ASR MLX; SenseVoice fallback)
```

At stop:

```text
AudioCapture.stop()
  └─ drains the serial audio queue
NativeSpeechEngine.stop()
  ├─ flushes converted audio
  ├─ closes input sequence
  └─ finalizes through end of input
OutputDispatcher.deliver()
  └─ guarded clipboard / targeted Command-V / field-change confirmation
SessionStore.finish() (concurrent)
  ├─ writes .txt
  ├─ removes .partial.txt
  └─ writes final .json
```

## Why the target app is captured at recording start

Opening a menu-bar item or settings window can make VoxTypeMac temporarily active. `AppModel` tracks the last external frontmost application and records that as the paste destination. The floating HUD is a non-activating panel and does not take keyboard focus.

## Failure model

- Speech setup failure before recording: no session starts.
- Speech failure during recording: raw audio continues writing; partial text remains.
- Audio write failure: transcription continues and the session is marked `audio-write-warning`.
- Finalization failure: fallback live text is saved when available; raw audio remains.
- Missing Accessibility permission: transcript stays on the clipboard instead of being lost.
- App quit while recording: termination is delayed until `stopRecording()` finishes.

## Performance choices

- `TaskPriority.userInitiated` for analysis.
- `SpeechAnalyzer.Options.ModelRetention.processLifetime`.
- `DictationTranscriber.Preset.progressiveShortDictation`, volatile results, and frequent finalization.
- 256-frame microphone tap buffers, approximately 5.3 ms at 48 kHz.
- A high-priority recognition queue that schedules ordered archive writes onto a separate queue.
- A 16-input newest-value bound that keeps the maximum 44.1 kHz input backlog under 100 ms.
- Coalesced, process-cached locale, asset, and analyzer-format preparation.
- A reserved, already-prepared analyzer for the selected locale, rebuilt after each stop.
- Microphone capture overlapping analyzer start, with a newest-16 buffer until the live stream is attached.
- Qwen3-ASR refinement with automatic language detection overlapping Apple finalization, with Apple fallback; Chinese mode permits mixed English while English mode rejects CJK refinement.
- One retained selected-language model prewarmed on launch.
- A single view-owned `CADisplayLink` that prefers the active screen's maximum refresh rate while allowing the system to adapt down to 60 Hz.
- A smoothed meter-bin envelope with a compositor-friendly glow keeps the waveform crisp without changing the audio or speech hot path.
- A measured 20 ms pasteboard settle before targeted Command-V, with archive completion running concurrently.

Apple chooses resources for SpeechAnalyzer. The Qwen3-ASR helper explicitly uses the Metal GPU through MLX, with a bounded allocation/cache budget. Inference runs in a separate process on a detached worker, so model loading and decoding do not block the main actor.
