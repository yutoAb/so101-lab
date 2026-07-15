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
cd "$SCRIPT_DIR/.."

OUTPUT_DIR="outputs/train/${POLICY_TYPE}_${TASK_NAME}"

# 学習の入り口は2通り：
#  - ゼロから学習（ACT など）      : --policy.type=$POLICY_TYPE
#  - 事前学習ベースを fine-tune     : --policy.path=$POLICY_BASE
# SmolVLA/pi0 のような基盤 VLA は POLICY_BASE を指定して fine-tune する。
# 例（SmolVLA）: _env.sh で POLICY_TYPE=smolvla にした上で
#   POLICY_BASE=lerobot/smolvla_base TRAIN_STEPS=30000 BATCH_SIZE=64 ./scripts/train.sh
# ※ POLICY_TYPE は _env.sh が無条件 export するので、前置き override ではなく
#    _env.sh 側を書き換える（CLAUDE.md「タスク切り替え」参照）。POLICY_BASE/TRAIN_STEPS/
#    BATCH_SIZE は _env.sh に無いのでアドホック override が効く。
POLICY_BASE="${POLICY_BASE:-}"
TRAIN_STEPS="${TRAIN_STEPS:-}"
BATCH_SIZE="${BATCH_SIZE:-}"

POLICY_FLAG=(--policy.type="$POLICY_TYPE")
[[ -n "$POLICY_BASE" ]] && POLICY_FLAG=(--policy.path="$POLICY_BASE")
STEP_FLAG=();  [[ -n "$TRAIN_STEPS" ]] && STEP_FLAG=(--steps="$TRAIN_STEPS")
BATCH_FLAG=(); [[ -n "$BATCH_SIZE" ]]  && BATCH_FLAG=(--batch_size="$BATCH_SIZE")

echo "==> Training policy '$POLICY_TYPE' on dataset '$DATASET_REPO_ID'"
[[ -n "$POLICY_BASE" ]] && echo "    Fine-tuning from base: $POLICY_BASE"
echo "    Output: $OUTPUT_DIR"
echo "    Will push to: $POLICY_REPO_ID"

uv run lerobot-train \
    --dataset.repo_id="$DATASET_REPO_ID" \
    "${POLICY_FLAG[@]}" \
    "${STEP_FLAG[@]}" \
    "${BATCH_FLAG[@]}" \
    --policy.device=cuda \
    --output_dir="$OUTPUT_DIR" \
    --job_name="${POLICY_TYPE}_${TASK_NAME}" \
    --wandb.enable=true \
    --policy.repo_id="$POLICY_REPO_ID"
