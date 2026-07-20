#!/usr/bin/env bash
# 分割推論(async)で eval：推論を GPU 機(policy_server)、実機制御を Mac(このスクリプト=robot_client)で行う。
# 重い VLA を Mac(MPS ~3Hz)で回す代わりに GPU 機で回し、30Hz を狙う。
#
# 事前準備（2つ）:
#  (1) GPU 機で policy_server を起動（例: g16 の空き GPU で）:
#        ssh g16
#        cd ~/so101-lab && CUDA_VISIBLE_DEVICES=1 HF_HUB_DISABLE_XET=1 \
#          uv run python -m lerobot.async_inference.policy_server --host=0.0.0.0 --port=8080 --fps=30
#  (2) Mac→GPU 機の SSH トンネルを張る（別ターミナルで開きっぱなし）:
#        ssh -N -L 18080:localhost:8080 g16
#      ※ Mac 側ローカルポートは 18080 を使う。8080 は VS Code(Code Helper)が
#        使っていることがあり、衝突すると gRPC が SETTINGS でタイムアウトする。
#
# 使い方（Mac、カメラ権限のある Terminal で）:
#   uv run python scripts/go_home.py           # 開始姿勢をそろえる
#   ./scripts/eval_async.sh                     # SmolVLA を GPU 機で推論して実機制御
# 別ポリシーを試す時: ASYNC_POLICY=<repo_id> POLICY_TYPE_ASYNC=<type> ./scripts/eval_async.sh
#
# SmolVLA はカメラ名 camera1/camera2 を期待するので、実機カメラをその名前で渡す（ACT は front/wrist）。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"
cd "$SCRIPT_DIR/.."

# 発話などから指示文を差し替えたい時に使う（voice_control.py が渡す）。SmolVLA の言語条件に効く。
TASK_DESCRIPTION="${TASK_OVERRIDE:-$TASK_DESCRIPTION}"

SERVER_ADDRESS="${SERVER_ADDRESS:-127.0.0.1:18080}"
ASYNC_POLICY="${ASYNC_POLICY:-abePclWaseda/so101-smolvla-cube-in-case-v2}"
POLICY_TYPE_ASYNC="${POLICY_TYPE_ASYNC:-smolvla}"
CAMERA_FRONT_KEY="${CAMERA_FRONT_KEY:-camera1}"
CAMERA_WRIST_KEY="${CAMERA_WRIST_KEY:-camera2}"
ACTIONS_PER_CHUNK="${ACTIONS_PER_CHUNK:-50}"
# チャンク集約の挙動。weighted_average は滑らかだが掴みの精密動作がなまる。
# latest_only は混ぜず最新チャンクをそのまま使う（精密だが少しカクつく）。
# 掴めない時は AGG_FN=latest_only を、寄せが弱い時は CHUNK_THRESHOLD を上げる(例:0.7)。
AGG_FN="${AGG_FN:-weighted_average}"
CHUNK_THRESHOLD="${CHUNK_THRESHOLD:-0.5}"

echo "==> async eval"
echo "    policy : $ASYNC_POLICY ($POLICY_TYPE_ASYNC) @ GPU 機"
echo "    server : $SERVER_ADDRESS (SSH トンネル経由)"
echo "    cameras: $CAMERA_FRONT_KEY / $CAMERA_WRIST_KEY"

uv run python -m lerobot.async_inference.robot_client \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id="$FOLLOWER_ID" \
    --robot.cameras="{ $CAMERA_FRONT_KEY: {type: opencv, index_or_path: $CAMERA_FRONT_INDEX, width: $CAMERA_WIDTH, height: $CAMERA_HEIGHT, fps: $CAMERA_FPS}, $CAMERA_WRIST_KEY: {type: opencv, index_or_path: $CAMERA_WRIST_INDEX, width: $CAMERA_WIDTH, height: $CAMERA_HEIGHT, fps: $CAMERA_FPS}}" \
    --task="$TASK_DESCRIPTION" \
    --server_address="$SERVER_ADDRESS" \
    --policy_type="$POLICY_TYPE_ASYNC" \
    --pretrained_name_or_path="$ASYNC_POLICY" \
    --policy_device=cuda \
    --client_device=cpu \
    --actions_per_chunk="$ACTIONS_PER_CHUNK" \
    --chunk_size_threshold="$CHUNK_THRESHOLD" \
    --fps="$CAMERA_FPS" \
    --aggregate_fn_name="$AGG_FN"
