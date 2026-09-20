# VoxTypeMac local completion

Status: locally complete on 2026-09-20.

## Product boundary

- Keep the Mac app local-first and macOS 27 / Apple Silicon native.
- Keep private recordings, transcripts, settings, models, and old Git history
  out of this repository.
- Store app-owned state in the user's VoxTypeMac Application Support directory.
- Keep this repository local-only until remote ownership and publication are
  separately authorized.
- Do not replace or migrate the separate installed private app from this line.

## Completed

- Exported the working tracked source into an independent history.
- Renamed product-facing identity to VoxTypeMac and removed personal machine,
  signing, migration, agent-policy, and historical release material.
- Added generic ad-hoc build and local install paths.
- Added source privacy checks, native tests, release inventory checks, and a
  clean-clone verification path.

## Verified locally

- `./verify-source.sh`: passed with 60 focused native tests.
- Release app build and strict ad-hoc signature verification: passed.
- Clean, no-remote clone source verification and release build: passed.
- Release ZIP inventory and checksum verification: passed.
- Commits: `cccc4d1` and `2e0ed69`.

Microphone, TCC, global shortcut, text insertion, launch-at-login, and interactive
menu/HUD behavior remain installed-app acceptance. This task did not install or
launch the derivative, replace the private app, download models, create a remote,
push, or publish.
