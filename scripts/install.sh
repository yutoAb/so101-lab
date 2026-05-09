#!/usr/bin/env bash
# Phase 1: LeRobot 環境構築 + HuggingFace 連携 + USB Web カメラ動作確認
#
# 前提: Python 3.10+ の venv または conda 環境が有効化されている

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/_env.sh" ]] && source "$SCRIPT_DIR/_env.sh"

echo "==> Installing LeRobot..."
pip install --upgrade lerobot

echo "==> Installing Feetech servo SDK extra..."
pip install -e ".[feetech]" || pip install "lerobot[feetech]"

echo "==> Verifying HuggingFace CLI auth..."
if ! hf auth whoami >/dev/null 2>&1; then
    echo "Not logged in to HuggingFace. Run:"
    echo "    hf auth login --token <YOUR_TOKEN>"
    echo "Get a write-access token at https://huggingface.co/settings/tokens"
    exit 1
fi
echo "    Logged in as: $(hf auth whoami | head -n1)"

echo "==> Verifying USB Web camera (OpenCV)..."
python - <<'PY'
import cv2
cap = cv2.VideoCapture(0)
ok, _ = cap.read()
cap.release()
print(f"    Camera index 0: {'OK' if ok else 'NOT DETECTED'}")
PY

echo
echo "==> Done. Next: bash scripts/find-port.sh"
