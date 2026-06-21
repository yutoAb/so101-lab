#!/usr/bin/env bash
# Phase 1: LeRobot 環境構築 + HuggingFace 連携 + USB Web カメラ動作確認
#
# 前提: uv が入っていること（https://docs.astral.sh/uv/）
#       Python は uv が pyproject.toml の requires-python から自動で入れる

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
[[ -f "$SCRIPT_DIR/_env.sh" ]] && source "$SCRIPT_DIR/_env.sh"

echo "==> Checking uv..."
if ! command -v uv >/dev/null 2>&1; then
    echo "uv not found. Install with:"
    echo "    curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi
echo "    $(uv --version)"

echo "==> Syncing dependencies (creates .venv from pyproject.toml + uv.lock)..."
cd "$REPO_ROOT"
uv sync

echo "==> Verifying HuggingFace CLI auth..."
if ! uv run hf auth whoami >/dev/null 2>&1; then
    echo "Not logged in to HuggingFace. Run:"
    echo "    uv run hf auth login --token <YOUR_TOKEN>"
    echo "Get a write-access token at https://huggingface.co/settings/tokens"
    exit 1
fi
echo "    Logged in as: $(uv run hf auth whoami | head -n1)"

if [[ "${SKIP_CAMERA_CHECK:-0}" == "1" ]]; then
    echo "==> Skipping USB Web camera check (SKIP_CAMERA_CHECK=1)"
else
    echo "==> Verifying USB Web camera (OpenCV)..."
    uv run python - <<'PY'
import cv2
cap = cv2.VideoCapture(0)
ok, _ = cap.read()
cap.release()
print(f"    Camera index 0: {'OK' if ok else 'NOT DETECTED'}")
PY
fi

echo
echo "==> Done. Next: bash scripts/find-port.sh"
