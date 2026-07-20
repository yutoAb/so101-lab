#!/usr/bin/env bash
# Phase 9: 学習済みポリシーで自律推論
#
# record.sh から teleop を抜いて --policy.path を指定するだけ。
# 評価エピソードは ${HF_USER}/eval-${TASK_NAME} として Hub に保存。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"
cd "$SCRIPT_DIR/.."

# 発話などから指示文を差し替えたい時に使う（voice_control.py が渡す）。
# 未指定なら _env.sh の TASK_DESCRIPTION のまま。ACT は無視、SmolVLA は言語条件に効く。
TASK_DESCRIPTION="${TASK_OVERRIDE:-$TASK_DESCRIPTION}"

NUM_EVAL_EPISODES="${NUM_EVAL_EPISODES:-10}"
EPISODE_TIME_SEC="${EPISODE_TIME_SEC:-30}"
# lerobot 0.5.1 はポリシー付き record のデータセット名が 'eval_' で始まることを要求する
# （control_utils.sanity_check_dataset_name）。ハイフンだと弾かれるので注意。
EVAL_DATASET_REPO_ID="${HF_USER}/eval_${TASK_NAME}"

# 評価するポリシーの上書き。_env.sh が POLICY_REPO_ID を無条件 export するため、
# コマンド前置きの override は消えてしまう。学習途中の checkpoint 等を評価したい時は
# EVAL_POLICY=<repo_id> を指定する（例: EVAL_POLICY=user/so101-act-foo-50k ./scripts/eval.sh）。
POLICY_PATH="${EVAL_POLICY:-$POLICY_REPO_ID}"

# カメラのキー名。ポリシーが期待するカメラ特徴量の名前に合わせる。
#  - ACT      : front / wrist で学習しているのでデフォルトのまま。
#  - SmolVLA  : base が camera1/2/3 を期待。学習時に front→camera1, wrist→camera2 とリネームした
#               ので、eval でも実機カメラを camera1/camera2 で渡す必要がある。
# ※ eval(record) では --dataset.rename_map は make_policy の事前検証に間に合わず落ちる
#   （検証はリネーム前の ds_meta で行われる）。なのでロボットのカメラ名そのものを変えるのが正解。
# 例(SmolVLA): CAMERA_FRONT_KEY=camera1 CAMERA_WRIST_KEY=camera2 ./scripts/eval.sh
CAMERA_FRONT_KEY="${CAMERA_FRONT_KEY:-front}"
CAMERA_WRIST_KEY="${CAMERA_WRIST_KEY:-wrist}"

echo "==> Running inference with policy: $POLICY_PATH"
echo "    Eval dataset will be pushed to: $EVAL_DATASET_REPO_ID"
echo "    camera keys: $CAMERA_FRONT_KEY / $CAMERA_WRIST_KEY"

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
    --robot.cameras="{ $CAMERA_FRONT_KEY: {type: opencv, index_or_path: $CAMERA_FRONT_INDEX, width: $CAMERA_WIDTH, height: $CAMERA_HEIGHT, fps: $CAMERA_FPS}, $CAMERA_WRIST_KEY: {type: opencv, index_or_path: $CAMERA_WRIST_INDEX, width: $CAMERA_WIDTH, height: $CAMERA_HEIGHT, fps: $CAMERA_FPS}}" \
    --policy.path="$POLICY_PATH" \
    --display_data=false \
    --dataset.repo_id="$EVAL_DATASET_REPO_ID" \
    --dataset.private=true \
    --dataset.vcodec=h264_videotoolbox \
    --dataset.num_episodes="$NUM_EVAL_EPISODES" \
    --dataset.episode_time_s="$EPISODE_TIME_SEC" \
    --dataset.single_task="$TASK_DESCRIPTION" \
    --dataset.streaming_encoding=true \
    --dataset.encoder_threads=2
