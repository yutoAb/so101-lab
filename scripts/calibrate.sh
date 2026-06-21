#!/usr/bin/env bash
# Phase 5: 双腕のキャリブレーション
#
# 組立完了後に実施。CLI が「ホームポジションへ」「最大角まで」と指示するので、
# それに従って関節を物理的に動かす。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"
cd "$SCRIPT_DIR/.."

echo "==> Calibrating follower arm..."
uv run lerobot-calibrate \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id="$FOLLOWER_ID"

echo
echo "==> Calibrating leader arm..."
uv run lerobot-calibrate \
    --teleop.type=so101_leader \
    --teleop.port="$LEADER_PORT" \
    --teleop.id="$LEADER_ID"

echo
echo "==> Done. Next: bash scripts/teleoperate.sh"
