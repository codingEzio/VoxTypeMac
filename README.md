# VoxTypeMac

[English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Русский](README.ru.md) · [Українська](README.uk.md)

VoxTypeMac is a local-first macOS menu-bar dictation app for Apple Silicon.
Press the selected shortcut, speak, press it again, and the transcript is
delivered to the input field that was focused when recording began.

## Requirements

- macOS 27 or newer on Apple Silicon
- Xcode 27
- `shellcheck` for the full source verifier
- Optional: `uv` and the pinned Qwen3-ASR dependencies for the local refinement
  model

The app uses Apple Speech, AppKit, SwiftUI, AVFoundation, and Accessibility APIs.
It has no account system, analytics, cloud transcription client, or source-tree
dependency on private user data.

## Data and privacy

Recordings, transcripts, settings, downloaded models, caches, and temporary
files stay under `~/Library/Application Support/VoxTypeMac/`. The source tree
and release archives do not include that directory. Apple may download speech
assets into macOS-managed storage. TCC, login items, and system logs are also
managed by macOS.

VoxTypeMac requests Microphone and Speech Recognition access for dictation,
Input Monitoring for its global shortcut, and Accessibility for verified text
insertion. If insertion cannot be verified, the transcript remains on the
clipboard.

## Build and verify

```sh
./verify-source.sh
./build-app.sh
open "runtime/build/VoxTypeMac.app"
```

Build output stays under the ignored `runtime/` directory. Development builds
are ad-hoc signed, so macOS may require permissions again after a rebuild. A
stable distribution identity and notarization are outside this local source
candidate.

To install the built app locally:

```sh
./install.sh
```

This replaces only `~/Applications/VoxTypeMac.app`. It does not modify any
separate private installation or its data.

## Optional Qwen3-ASR refinement

```sh
./script/install-qwen.sh
```

The script installs the pinned Python runtime and model under VoxTypeMac's
Application Support directory. Network access is needed only for installation;
inference stays local. Third-party versions and licenses are listed in
`THIRD_PARTY_NOTICES.md`, `config/qwen-asr.json`, and the hash-locked Python
requirements.

## Source map

- `Sources/VoxType/`: app, menu, recording, recognition, delivery, and storage
- `Tests/VoxTypeTests/`: native functional and data-boundary checks
- `Resources/`: app metadata, entitlements, and product artwork
- `config/`: product identity and pinned optional model dependencies
- `script/`: build, package, model-install, and local run helpers

The source is available under the MIT License. Optional models and runtimes keep
their own upstream terms.
