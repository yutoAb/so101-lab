#!/usr/bin/env bash
# Phase 3a: フォロワー腕のモーター ID & ボーレート設定
#
# ⚠️ 組立前に実施。コントローラ基板に「1 個ずつ」モーターを繋ぎ替えながら
#    CLI の指示に従って進める。フォロワーは 6 軸すべて 1:345 のサーボ。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_env.sh"

echo "==> Setting up follower motors on $FOLLOWER_PORT"
echo "    Connect ONE motor at a time when the CLI prompts you."
echo
lerobot-setup-motors \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT"
