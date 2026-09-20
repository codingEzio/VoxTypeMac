#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$root/script/product_config.sh"
load_product_config "$root/config/product.conf"

app="$root/runtime/build/$APP_BUNDLE_NAME.app"
executable="$app/Contents/MacOS/$EXECUTABLE_NAME"
installed_executable="$HOME/Applications/$APP_BUNDLE_NAME.app/Contents/MacOS/$EXECUTABLE_NAME"

deployment_pids() {
  for candidate in "$executable" "$installed_executable"; do
    pgrep -f "^$candidate([[:space:]]|$)" || true
  done
}

stop_existing_apps() {
  [[ -z "$(deployment_pids)" ]] && return 0
  for candidate in "$executable" "$installed_executable"; do
    pkill -TERM -f "^$candidate([[:space:]]|$)" >/dev/null 2>&1 || true
  done
  for _ in {1..10}; do
    [[ -z "$(deployment_pids)" ]] && return 0
    sleep 2
  done
  for candidate in "$executable" "$installed_executable"; do
    pkill -KILL -f "^$candidate([[:space:]]|$)" >/dev/null 2>&1 || true
  done
  for _ in {1..5}; do
    [[ -z "$(deployment_pids)" ]] && return 0
    sleep 2
  done
  echo "An existing $DISPLAY_NAME process did not exit" >&2
  return 1
}

"$root/build-app.sh"

case "$mode" in
  --stage|stage|--package|package)
    exit 0
    ;;
esac

stop_existing_apps

launch_and_verify() {
  open -n "$app"
  for _ in {1..10}; do
    pgrep -f "^$executable([[:space:]]|$)" >/dev/null && return 0
    sleep 2
  done
  echo "$DISPLAY_NAME did not launch from $app" >&2
  return 1
}

case "$mode" in
  run)
    launch_and_verify
    ;;
  --debug|debug)
    lldb -- "$executable"
    ;;
  --logs|logs)
    launch_and_verify
    /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    launch_and_verify
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.voxtypemac.VoxTypeMac"'
    ;;
  --verify|verify)
    launch_and_verify
    ;;
  *)
    echo "usage: $0 [run|--stage|--package|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
