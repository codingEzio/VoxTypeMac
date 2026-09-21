#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=script/product_config.sh
source "$ROOT/script/product_config.sh"
load_product_config "$ROOT/config/product.conf"

"$ROOT/build-app.sh"
built_app="$ROOT/runtime/build/$APP_BUNDLE_NAME.app"
install_root="$HOME/Applications"
installed_app="$install_root/$APP_BUNDLE_NAME.app"
staging="$(mktemp -d "$ROOT/runtime/temp/delete_after_use_install.XXXXXX")"
candidate="$staging/$APP_BUNDLE_NAME.app"
previous="$staging/Previous-$APP_BUNDLE_NAME.app"
installed=0
allow_signing_migration=0

if [[ "${1:-}" == "--allow-signing-migration" ]]; then
  allow_signing_migration=1
  shift
fi
[[ $# -eq 0 ]] || {
  echo "usage: ./install.sh [--allow-signing-migration]" >&2
  exit 2
}

designated_requirement() {
  /usr/bin/codesign -d -r- "$1" 2>&1 | /usr/bin/sed -n 's/^designated => //p'
}

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  if (( installed == 0 )) && [[ -d "$previous" ]]; then
    [[ ! -d "$installed_app" ]] || mv "$installed_app" "$staging/Failed-$APP_BUNDLE_NAME.app"
    mv "$previous" "$installed_app"
  fi
  rm -rf -- "$staging"
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$install_root"
/usr/bin/ditto "$built_app" "$candidate"
/usr/bin/codesign --verify --deep --strict "$candidate"

candidate_requirement="$(designated_requirement "$candidate")"
[[ -n "$candidate_requirement" ]] || {
  echo "Could not read the candidate signing requirement." >&2
  exit 1
}
if [[ -d "$installed_app" ]]; then
  installed_requirement="$(designated_requirement "$installed_app")"
  if [[ "$candidate_requirement" != "$installed_requirement" && $allow_signing_migration -ne 1 ]]; then
    echo "Signing requirement changed; refusing to reset macOS privacy grants." >&2
    echo "Use --allow-signing-migration only for an intentional one-time identity migration." >&2
    exit 1
  fi
fi

if pgrep -f "^$installed_app/Contents/MacOS/$EXECUTABLE_NAME([[:space:]]|$)" >/dev/null; then
  pkill -TERM -f "^$installed_app/Contents/MacOS/$EXECUTABLE_NAME([[:space:]]|$)"
  for _ in {1..20}; do
    pgrep -f "^$installed_app/Contents/MacOS/$EXECUTABLE_NAME([[:space:]]|$)" >/dev/null || break
    sleep 0.1
  done
fi
[[ ! -d "$installed_app" ]] || mv "$installed_app" "$previous"
mv "$candidate" "$installed_app"
/usr/bin/codesign --verify --deep --strict "$installed_app"
installed=1
echo "Installed $installed_app"
