#!/usr/bin/env bash

expected_xcode="$(tr -d '\n' < "$ROOT/.xcode-version")"

xcode_output="$(xcodebuild -version 2>&1 || true)"
if [[ "$xcode_output" != *"Build version "* ]]; then
  echo "VoxType requires $expected_xcode with its license accepted and developer directory selected." >&2
  echo "$xcode_output" >&2
  exit 1
fi
xcode_version="$(printf '%s\n' "$xcode_output" | sed -n 's/^Xcode //p')"
case "$xcode_version" in
  27*) ;;
  *)
    echo "VoxType requires $expected_xcode. Active toolchain: Xcode $xcode_version." >&2
    exit 1
    ;;
esac
