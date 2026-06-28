#!/usr/bin/env bash
# Phase 9: 学習済みポリシーで自律推論
#
# record.sh から teleop を抜いて --policy.path を指定するだけ。
# 評価エピソードは ${HF_USER}/eval-${TASK_NAME} として Hub に保存。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"
cd "$SCRIPT_DIR/.."

NUM_EVAL_EPISODES="${NUM_EVAL_EPISODES:-10}"
EPISODE_TIME_SEC="${EPISODE_TIME_SEC:-30}"
EVAL_DATASET_REPO_ID="${HF_USER}/eval-${TASK_NAME}"

echo "==> Running inference with policy: $POLICY_REPO_ID"
echo "    Eval dataset will be pushed to: $EVAL_DATASET_REPO_ID"

uv run lerobot-record \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id="$FOLLOWER_ID" \
    --robot.cameras="{ front: {type: opencv, index_or_path: $CAMERA_FRONT_INDEX, width: $CAMERA_WIDTH, height: $CAMERA_HEIGHT, fps: $CAMERA_FPS}}" \
    --policy.path="$POLICY_REPO_ID" \
    --display_data=true \
    --dataset.repo_id="$EVAL_DATASET_REPO_ID" \
    --dataset.private=true \
    --dataset.num_episodes="$NUM_EVAL_EPISODES" \
    --dataset.episode_time_s="$EPISODE_TIME_SEC" \
    --dataset.single_task="$TASK_DESCRIPTION" \
    --dataset.streaming_encoding=true \
    --dataset.encoder_threads=2
