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
