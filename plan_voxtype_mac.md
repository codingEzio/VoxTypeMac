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

## Verification boundary

Source checks, native tests, app build, signing verification, package inventory,
and clean-clone build are required. Microphone, TCC, global shortcut, text
insertion, launch-at-login, and interactive menu/HUD behavior remain installed-
app acceptance and are not claimed by headless checks.
