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
# lerobot 0.5.1 はポリシー付き record のデータセット名が 'eval_' で始まることを要求する
# （control_utils.sanity_check_dataset_name）。ハイフンだと弾かれるので注意。
EVAL_DATASET_REPO_ID="${HF_USER}/eval_${TASK_NAME}"

# 評価するポリシーの上書き。_env.sh が POLICY_REPO_ID を無条件 export するため、
# コマンド前置きの override は消えてしまう。学習途中の checkpoint 等を評価したい時は
# EVAL_POLICY=<repo_id> を指定する（例: EVAL_POLICY=user/so101-act-foo-50k ./scripts/eval.sh）。
POLICY_PATH="${EVAL_POLICY:-$POLICY_REPO_ID}"

# RENAME_MAP: 実機のカメラキー(front/wrist)を、ポリシーが期待するキーに合わせる。
# SmolVLA は camera1/2/3 を期待するので学習(train.sh)と同じリネームを eval でも渡す必要がある
# （渡さないと実機の front/wrist と不一致で落ちる）。record 側の受け口は --dataset.rename_map。
# 例: RENAME_MAP='{"observation.images.front":"observation.images.camera1","observation.images.wrist":"observation.images.camera2"}'
# ACT は front/wrist をそのまま学習しているので RENAME_MAP 不要（未指定でOK）。
RENAME_MAP="${RENAME_MAP:-}"
RENAME_FLAG=(); [[ -n "$RENAME_MAP" ]] && RENAME_FLAG=(--dataset.rename_map="$RENAME_MAP")

echo "==> Running inference with policy: $POLICY_PATH"
echo "    Eval dataset will be pushed to: $EVAL_DATASET_REPO_ID"
[[ -n "$RENAME_MAP" ]] && echo "    rename_map: $RENAME_MAP"

# 前回の eval のローカルキャッシュが残っていると lerobot が FileExistsError で落ちる。
# eval データは毎回 Hub に push する使い捨てなので、開始前に消しておく。
LOCAL_EVAL_DIR="${HOME}/.cache/huggingface/lerobot/${EVAL_DATASET_REPO_ID}"
if [[ -d "$LOCAL_EVAL_DIR" ]]; then
    echo "    (既存のローカル eval データを削除: $LOCAL_EVAL_DIR)"
    rm -rf "$LOCAL_EVAL_DIR"
fi

uv run lerobot-record \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id="$FOLLOWER_ID" \
    --robot.cameras="{ front: {type: opencv, index_or_path: $CAMERA_FRONT_INDEX, width: $CAMERA_WIDTH, height: $CAMERA_HEIGHT, fps: $CAMERA_FPS}, wrist: {type: opencv, index_or_path: $CAMERA_WRIST_INDEX, width: $CAMERA_WIDTH, height: $CAMERA_HEIGHT, fps: $CAMERA_FPS}}" \
    --policy.path="$POLICY_PATH" \
    "${RENAME_FLAG[@]}" \
    --display_data=false \
    --dataset.repo_id="$EVAL_DATASET_REPO_ID" \
    --dataset.private=true \
    --dataset.vcodec=h264_videotoolbox \
    --dataset.num_episodes="$NUM_EVAL_EPISODES" \
    --dataset.episode_time_s="$EPISODE_TIME_SEC" \
    --dataset.single_task="$TASK_DESCRIPTION" \
    --dataset.streaming_encoding=true \
    --dataset.encoder_threads=2
