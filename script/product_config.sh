#!/usr/bin/env bash

# shellcheck disable=SC2034
load_product_config() {
  local config_file="$1"
  local line key value seen=" " required

  PROJECT_NAME=""
  DISPLAY_NAME=""
  APP_BUNDLE_NAME=""
  EXECUTABLE_NAME=""
  BUNDLE_ID=""
  VERSION=""
  BUILD_NUMBER=""
  MIN_SYSTEM_VERSION=""
  SIGNING_IDENTITY=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ""|'#'*) continue ;;
    esac
    [[ "$line" == *=* ]] || {
      echo "Invalid product config line: $line" >&2
      return 1
    }
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      PROJECT_NAME|DISPLAY_NAME|APP_BUNDLE_NAME|EXECUTABLE_NAME|BUNDLE_ID|VERSION|BUILD_NUMBER|MIN_SYSTEM_VERSION|SIGNING_IDENTITY) ;;
      *) echo "Unknown product config key: $key" >&2; return 1 ;;
    esac
    case "$seen" in
      *" $key "*) echo "Duplicate product config key: $key" >&2; return 1 ;;
    esac
    seen="$seen$key "
    if [[ "$value" == \"*\" ]]; then
      [[ "${value: -1}" == '"' && ${#value} -ge 2 ]] || {
        echo "Invalid quoted value for $key" >&2
        return 1
      }
      value="${value:1:${#value}-2}"
    elif [[ "$value" == *[[:space:]]* ]]; then
      echo "Whitespace must be quoted for $key" >&2
      return 1
    fi
    printf -v "$key" '%s' "$value"
  done < "$config_file"

  for required in PROJECT_NAME DISPLAY_NAME APP_BUNDLE_NAME EXECUTABLE_NAME BUNDLE_ID VERSION BUILD_NUMBER MIN_SYSTEM_VERSION SIGNING_IDENTITY; do
    [[ -n "${!required}" ]] || {
      echo "Missing product config key: $required" >&2
      return 1
    }
  done
}
