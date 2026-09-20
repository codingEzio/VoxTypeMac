#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/script/product_config.sh"
load_product_config "$ROOT/config/product.conf"
# shellcheck disable=SC1091
source "$ROOT/script/require-xcode-27.sh"

config="$ROOT/config/tool_output.json"
release_root="$ROOT/$(jq -r '.releaseRoot' "$config")"
build_app="$ROOT/$(jq -r '.appBundle' "$config")"
version="$VERSION"
package_name="$APP_BUNDLE_NAME-$version"
archive="$release_root/$package_name-macos-arm64.zip"
checksums="$release_root/SHA256SUMS"

[[ "$(git -C "$ROOT" branch --show-current)" == "main" ]] || {
  echo "Release packages must come from main." >&2
  exit 1
}
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=normal)" ]] || {
  echo "Commit or remove every source change before packaging." >&2
  exit 1
}

"$ROOT/verify-source.sh"
"$ROOT/build-app.sh"

mkdir -p "$release_root" "$ROOT/runtime/temp"
staging="$(mktemp -d "$ROOT/runtime/temp/delete_after_use_release.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
package="$staging/$package_name"
mkdir -p "$package"

git -C "$ROOT" archive HEAD | /usr/bin/tar -x -C "$package"
/usr/bin/ditto "$build_app" "$package/$APP_BUNDLE_NAME.app"

/usr/bin/codesign --verify --deep --strict "$package/$APP_BUNDLE_NAME.app"

[[ -f "$package/Package.swift" && -f "$package/external-data.json" && -f "$package/config/product.conf" ]] || {
  echo "Shared package is missing repository-root markers." >&2
  exit 1
}

rm -f -- "$archive" "$checksums"
/usr/bin/ditto -c -k --norsrc --noextattr --noacl --noqtn --keepParent "$package" "$archive"
/usr/bin/unzip -tq "$archive" >/dev/null
if /usr/bin/zipinfo -1 "$archive" | /usr/bin/grep -q '^__MACOSX/'; then
  echo "Release archive contains AppleDouble metadata." >&2
  exit 1
fi

verification="$staging/verification"
mkdir -p "$verification"
/usr/bin/ditto -x -k "$archive" "$verification"
/usr/bin/codesign --verify --deep --strict "$verification/$package_name/$APP_BUNDLE_NAME.app"

archive_hash="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
printf '%s  %s\n' "$archive_hash" "$(basename "$archive")" > "$checksums"

printf 'Release package: %s\n' "$archive"
printf 'SHA-256: %s\n' "$archive_hash"
