#!/usr/bin/env bash
# Phase 7: テレオペでデータセット収集 → HuggingFace Hub に push
#
# - リーダーで操作してフォロワーが動く軌跡 + カメラ映像を記録
# - ${DATASET_REPO_ID} に自動アップロード
# - エピソード数や時間は適宜調整
#
# display_data は false 固定：rerun のライブ表示を有効にすると Mac では CPU 負荷で
# 制御ループが 30Hz を割る（実測 16〜29Hz）。映像の確認は収録後に
# lerobot-dataset-viz で行う。vcodec も CPU 節約のため Apple HW エンコーダを指定。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"
cd "$SCRIPT_DIR/.."

# セッションごとに言語ラベル（single_task）を差し替える受け口。_env.sh が
# TASK_DESCRIPTION を export するのでコマンド前置き override は消える → ここで拾い直す。
# マルチタスク収録（例: 「赤を入れて」/「青を入れて」を同一データセットに）で使う。
TASK_DESCRIPTION="${TASK_OVERRIDE:-$TASK_DESCRIPTION}"

NUM_EPISODES="${NUM_EPISODES:-50}"
EPISODE_TIME_SEC="${EPISODE_TIME_SEC:-30}"
RESET_TIME_SEC="${RESET_TIME_SEC:-10}"

# RESUME=true で既存データセットに追記する（num_episodes はデータセットの「合計」目標）。
# 例: 既存50本 + 追加100本 → RESUME=true NUM_EPISODES=150 ./scripts/record.sh
# lerobot 0.5.1 の resume は Hub キャッシュには書けないため、書き込み可能な
# DATASET_ROOT（ローカルの実体）を必ず指定する。
RESUME="${RESUME:-false}"
DATASET_ROOT="${DATASET_ROOT:-}"
RESUME_FLAG=()
ROOT_FLAG=()
[[ "$RESUME" == "true" ]] && RESUME_FLAG=(--resume=true)
[[ -n "$DATASET_ROOT" ]] && ROOT_FLAG=(--dataset.root="$DATASET_ROOT")

echo "==> Recording (target total: $NUM_EPISODES episodes, resume=$RESUME) task: '$TASK_DESCRIPTION'"
echo "    Dataset will be pushed to: $DATASET_REPO_ID"

uv run lerobot-record \
    "${RESUME_FLAG[@]}" \
    "${ROOT_FLAG[@]}" \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id="$FOLLOWER_ID" \
    --robot.cameras="{ front: {type: opencv, index_or_path: $CAMERA_FRONT_INDEX, width: $CAMERA_WIDTH, height: $CAMERA_HEIGHT, fps: $CAMERA_FPS}, wrist: {type: opencv, index_or_path: $CAMERA_WRIST_INDEX, width: $CAMERA_WIDTH, height: $CAMERA_HEIGHT, fps: $CAMERA_FPS}}" \
    --teleop.type=so101_leader \
    --teleop.port="$LEADER_PORT" \
    --teleop.id="$LEADER_ID" \
    --display_data=false \
    --dataset.repo_id="$DATASET_REPO_ID" \
    --dataset.private=true \
    --dataset.vcodec=h264_videotoolbox \
    --dataset.num_episodes="$NUM_EPISODES" \
    --dataset.episode_time_s="$EPISODE_TIME_SEC" \
    --dataset.reset_time_s="$RESET_TIME_SEC" \
    --dataset.single_task="$TASK_DESCRIPTION" \
    --dataset.streaming_encoding=true \
    --dataset.encoder_threads=2
