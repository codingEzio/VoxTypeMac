#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/script/product_config.sh"
load_product_config "$ROOT/config/product.conf"
source "$ROOT/script/require-xcode-27.sh"
SWIFT_SCRATCH="$ROOT/runtime/temp/swiftpm"
export CLANG_MODULE_CACHE_PATH="$ROOT/runtime/cache/clang-modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
DIST="$ROOT/runtime/build"
APP="$DIST/$APP_BUNDLE_NAME.app"
CONTENTS="$APP/Contents"
BINARY_NAME="$EXECUTABLE_NAME"
mkdir -p "$SWIFT_SCRATCH" "$CLANG_MODULE_CACHE_PATH"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "$DISPLAY_NAME must be built on macOS because it uses AppKit, SpeechAnalyzer, and Liquid Glass." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This build is tuned for Apple Silicon. Current architecture: $(uname -m)" >&2
  exit 1
fi

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SDK_MAJOR="${SDK_VERSION%%.*}"
if (( SDK_MAJOR < 27 )); then
  echo "$DISPLAY_NAME needs the macOS 27 SDK or newer. Found SDK $SDK_VERSION." >&2
  exit 1
fi

printf 'Building %s for arm64 with macOS SDK %s...\n' "$DISPLAY_NAME" "$SDK_VERSION"
cd "$ROOT"
mkdir -p "$SWIFT_SCRATCH" "$DIST"
xcrun swift build --jobs 4 -c release --arch arm64 --scratch-path "$SWIFT_SCRATCH"
BIN_DIR="$(xcrun swift build --jobs 4 -c release --arch arm64 --scratch-path "$SWIFT_SCRATCH" --show-bin-path)"
BINARY="$BIN_DIR/$BINARY_NAME"

if [[ ! -x "$BINARY" ]]; then
  echo "Swift build succeeded but the VoxType executable was not found at: $BINARY" >&2
  exit 1
fi

printf 'Recreating app bundle at: %s\n' "$APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

/usr/bin/ditto "$BINARY" "$CONTENTS/MacOS/$BINARY_NAME"
/usr/bin/ditto "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
/usr/bin/ditto "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
/usr/bin/ditto "$ROOT/external-data.json" "$CONTENTS/Resources/external-data.json"
/usr/bin/ditto "$ROOT/config/qwen-asr.json" "$CONTENTS/Resources/qwen-asr.json"
/usr/bin/ditto "$ROOT/script/qwen_refine.py" "$CONTENTS/Resources/qwen_refine.py"
for localization in "$ROOT"/Resources/*.lproj; do
  /usr/bin/ditto "$localization" "$CONTENTS/Resources/$(basename "$localization")"
done
chmod 755 "$CONTENTS/MacOS/$BINARY_NAME"

/usr/bin/plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleExecutable -string "$EXECUTABLE_NAME" "$CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleName -string "$PROJECT_NAME" "$CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS/Info.plist"
/usr/bin/plutil -replace LSMinimumSystemVersion -string "$MIN_SYSTEM_VERSION" "$CONTENTS/Info.plist"

/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null

printf 'Signing %s with: %s\n' "$DISPLAY_NAME" "$SIGNING_IDENTITY"
/usr/bin/codesign \
  --force \
  --deep \
  --sign "$SIGNING_IDENTITY" \
  --entitlements "$ROOT/Resources/VoxType.entitlements" \
  "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

signed_identifier="$(/usr/bin/codesign -d --verbose=4 "$APP" 2>&1 | /usr/bin/awk -F= '/^Identifier=/ && !found {print $2; found=1}')"
[[ "$signed_identifier" == "$BUNDLE_ID" ]] || {
  echo "Signed bundle identifier differs: $signed_identifier" >&2
  exit 1
}
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  signed_authority="$(/usr/bin/codesign -d --verbose=4 "$APP" 2>&1 | /usr/bin/awk -F= '/^Authority=/ && !found {print $2; found=1}')"
  [[ "$signed_authority" == "$SIGNING_IDENTITY" ]] || {
    echo "Signed authority differs: $signed_authority" >&2
    exit 1
  }
fi

printf '\nBuilt successfully:\n  %s\n\n' "$APP"
printf 'Run it with:\n  open "%s"\n' "$APP"
