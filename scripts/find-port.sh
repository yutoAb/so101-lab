#!/usr/bin/env bash
# Phase 2: USB ポート特定
#
# 各コントローラ基板を別々の USB ポートに挿し、CLI の指示に従って
# 片方ずつ抜き差しする。出てきたパスを scripts/_env.sh に転記する。

set -euo pipefail

echo "==> Run lerobot-find-port for each MotorBus."
echo "    Run this script TWICE: once with leader connected, once with follower."
echo "    Then paste the discovered ports into scripts/_env.sh"
echo
lerobot-find-port
