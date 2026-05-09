#!/usr/bin/env bash
# Phase 3b: リーダー腕のモーター ID & ボーレート設定
#
# ⚠️ リーダーは軸ごとにギア比が違う:
#     - shoulder_pan  : 1:191
#     - shoulder_lift : 1:345
#     - elbow_flex    : 1:191
#     - wrist_flex    : 1:147
#     - wrist_roll    : 1:147
#     - gripper       : 1:147
#
# CLI が「次は wrist_roll を繋いで」と指示してきたら、対応するギア比の
# モーターを選んで繋ぐ。間違えるとリーダーが自重を支えられなくなる。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

echo "==> Setting up leader motors on $LEADER_PORT"
echo "    Match each motor's gear ratio to the joint requested by the CLI."
echo
lerobot-setup-motors \
    --teleop.type=so101_leader \
    --teleop.port="$LEADER_PORT"
