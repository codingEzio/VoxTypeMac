#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
# shellcheck source=script/require-xcode-27.sh
source "$ROOT/script/require-xcode-27.sh"

scratch="$ROOT/runtime/temp/swiftpm"
module_cache="$ROOT/runtime/cache/clang-modules"
export CLANG_MODULE_CACHE_PATH="$module_cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$module_cache"
mkdir -p "$scratch" "$module_cache"

swift package --scratch-path "$scratch" dump-package >/dev/null
swiftc -frontend -parse Sources/VoxType/*.swift
swift test --jobs 4 -c debug --scratch-path "$scratch"
bash -n build-app.sh ensure-signing-identity.sh install.sh verify-source.sh script/*.sh
shellcheck build-app.sh ensure-signing-identity.sh install.sh verify-source.sh script/*.sh
/usr/bin/plutil -lint Resources/Info.plist Resources/VoxType.entitlements >/dev/null
for localization in Resources/*.lproj/*.strings; do
  /usr/bin/plutil -lint "$localization" >/dev/null
done
for locale in zh-Hant zh-Hans ja ko es ru uk; do
  test -f "README.$locale.md"
done

python3 - <<'PY'
from pathlib import Path
import json
import subprocess

root = Path.cwd()
manifest = json.loads((root / "external-data.json").read_text(encoding="utf-8"))
portable = next(
    source for source in manifest["sources"] if source["id"] == "portable-state-root"
)
expected_portable = {
    "id": "portable-state-root",
    "description": "Per-user VoxTypeMac data directory",
    "kind": "directory",
    "access": "read-write",
    "root": "application-support",
    "path": "VoxTypeMac",
    "required": True,
    "sensitive": True,
    "overrideEnv": "",
}
if manifest.get("schemaVersion") != 1 or manifest.get("projectId") != "client-voxtype":
    raise SystemExit("external-data.json owner or schema differs")
if portable != expected_portable:
    raise SystemExit("VoxTypeMac Application Support routing differs")

config = {}
for line in (root / "config/product.conf").read_text(encoding="utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    key, value = line.split("=", 1)
    config[key] = value.strip('"')
expected_identity = {
    "PROJECT_NAME": "VoxTypeMac",
    "DISPLAY_NAME": "VoxTypeMac",
    "APP_BUNDLE_NAME": "VoxTypeMac",
    "EXECUTABLE_NAME": "VoxType",
    "BUNDLE_ID": "app.voxtypemac.VoxTypeMac",
    "VERSION": "0.9.5",
    "BUILD_NUMBER": "21",
    "MIN_SYSTEM_VERSION": "27.0",
    "SIGNING_IDENTITY": "Alex Local Code Signing",
}
if config != expected_identity:
    raise SystemExit("product identity differs from the sanitized local candidate")

tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).split(b"\0")
forbidden_paths = {
    b"AGENTS.md", b"CHANGELOG.md", b"DEVELOPMENT.md", b"ERRORLOG.txt",
    b"HANDOFF.md", b"docs/asr-evaluation.md",
}
if forbidden_paths.intersection(tracked):
    raise SystemExit("private workflow or historical files are tracked")
forbidden_text = [
    "/" + "Users/alex/", "Y-" + "VoxTypePrivate", "X-" + "VoxType",
    "dev." + "elliot.voxtype",
    "Private" + "Gallery", "Daem0n" + "Targaryen",
]
for raw_path in tracked:
    if not raw_path:
        continue
    path = root / raw_path.decode("utf-8")
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, IsADirectoryError):
        continue
    for needle in forbidden_text:
        if needle in text:
            raise SystemExit(f"private marker {needle!r} remains in {path.relative_to(root)}")

PY

echo "VoxTypeMac source verification passed."
