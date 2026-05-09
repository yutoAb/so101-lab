#!/usr/bin/env bash
# Phase 8: ポリシー学習
#
# - HF Hub のデータセットを直接読み込んで学習
# - 学習済みは Hub に自動 push
# - ローカル GPU が無ければ Colab notebook で同等のことが可能:
#   https://huggingface.co/docs/lerobot/notebooks

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

OUTPUT_DIR="outputs/train/${POLICY_TYPE}_${TASK_NAME}"

echo "==> Training policy '$POLICY_TYPE' on dataset '$DATASET_REPO_ID'"
echo "    Output: $OUTPUT_DIR"
echo "    Will push to: $POLICY_REPO_ID"

lerobot-train \
    --dataset.repo_id="$DATASET_REPO_ID" \
    --policy.type="$POLICY_TYPE" \
    --policy.device=cuda \
    --output_dir="$OUTPUT_DIR" \
    --job_name="${POLICY_TYPE}_${TASK_NAME}" \
    --wandb.enable=true \
    --policy.repo_id="$POLICY_REPO_ID"
