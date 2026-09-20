#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_ROOT="$HOME/Library/Application Support/VoxTypeMac"
export VOXTYPE_STATE_ROOT="$STATE_ROOT"
export UV_CACHE_DIR="$STATE_ROOT/cache/uv"
export UV_PYTHON_INSTALL_DIR="$STATE_ROOT/models/python"
export HF_HOME="$STATE_ROOT/cache/huggingface"
export PYTHONPYCACHEPREFIX="$STATE_ROOT/cache/python"
export HF_HUB_DISABLE_TELEMETRY=1
mkdir -p "$STATE_ROOT/models" "$UV_CACHE_DIR" "$UV_PYTHON_INSTALL_DIR"

command -v uv >/dev/null || {
  echo "Install uv from https://docs.astral.sh/uv/ before installing Qwen3-ASR." >&2
  exit 1
}
python_executable="$STATE_ROOT/models/qwen3-asr-venv/bin/python"
if [[ ! -x "$python_executable" ]]; then
  uv venv --python 3.12.14 "$STATE_ROOT/models/qwen3-asr-venv"
fi
uv pip sync --python "$python_executable" --require-hashes "$ROOT/config/qwen-requirements.lock"
"$python_executable" "$ROOT/script/download_qwen.py"
echo "Qwen3-ASR 1.7B is installed locally. Reopen VoxTypeMac to select it automatically."
