#!/usr/bin/env bash
# Phase 6: テレオペで動作確認
#
# リーダーを動かすとフォロワーが追従するはず。これが動けば初日のゴール達成。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"
cd "$SCRIPT_DIR/.."

# カメラ表示も同時に見たい場合は --display_data=true を追加（rerun が必要）
uv run lerobot-teleoperate \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id="$FOLLOWER_ID" \
    --teleop.type=so101_leader \
    --teleop.port="$LEADER_PORT" \
    --teleop.id="$LEADER_ID"
