#!/usr/bin/env bash
# Phase 7: テレオペでデータセット収集 → HuggingFace Hub に push
#
# - リーダーで操作してフォロワーが動く軌跡 + カメラ映像を記録
# - ${DATASET_REPO_ID} に自動アップロード
# - エピソード数や時間は適宜調整

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

NUM_EPISODES="${NUM_EPISODES:-50}"
EPISODE_TIME_SEC="${EPISODE_TIME_SEC:-30}"
RESET_TIME_SEC="${RESET_TIME_SEC:-10}"

echo "==> Recording $NUM_EPISODES episodes for task: '$TASK_DESCRIPTION'"
echo "    Dataset will be pushed to: $DATASET_REPO_ID"

lerobot-record \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id="$FOLLOWER_ID" \
    --robot.cameras="{ front: {type: opencv, index_or_path: $CAMERA_FRONT_INDEX, width: $CAMERA_WIDTH, height: $CAMERA_HEIGHT, fps: $CAMERA_FPS}}" \
    --teleop.type=so101_leader \
    --teleop.port="$LEADER_PORT" \
    --teleop.id="$LEADER_ID" \
    --display_data=true \
    --dataset.repo_id="$DATASET_REPO_ID" \
    --dataset.num_episodes="$NUM_EPISODES" \
    --dataset.episode_time_s="$EPISODE_TIME_SEC" \
    --dataset.reset_time_s="$RESET_TIME_SEC" \
    --dataset.single_task="$TASK_DESCRIPTION" \
    --dataset.streaming_encoding=true \
    --dataset.encoder_threads=2
