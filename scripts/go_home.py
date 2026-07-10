"""フォロワーを学習データの開始姿勢（ホーム）に正確に移動させる。

eval の前に実行すると、毎回まったく同じ姿勢から始められる。手で戻すと特に
手首(flex/roll)がズレ、手首カメラの見え方が学習時と変わって掴みが数cm外れる。

target は so101-cube-in-case-v2 の全50エピソード開始姿勢の平均。データセットを
録り直したら scripts/print_start_pose.py 等で測り直して更新すること。

usage:
  cd ~/2026/personal/so101-lab && source scripts/_env.sh
  uv run python scripts/go_home.py
"""
import os
import time

from lerobot.robots.so_follower import SOFollower, SO101FollowerConfig

# 学習データ(cube-in-case-v2)の開始姿勢の平均（度）
HOME = {
    "shoulder_pan.pos": -11.9,
    "shoulder_lift.pos": -103.8,
    "elbow_flex.pos": 95.8,
    "wrist_flex.pos": 54.2,
    "wrist_roll.pos": -4.7,
    "gripper.pos": 2.5,
}


def main():
    cfg = SO101FollowerConfig(
        port=os.environ["FOLLOWER_PORT"],
        id=os.environ["FOLLOWER_ID"],
        # 移動後もトルクを保持したまま切断する。こうすると eval.sh が接続する時に
        # サーボが自律的にホーム姿勢を維持していて、そのまま推論を開始できる。
        disable_torque_on_disconnect=False,
    )
    robot = SOFollower(cfg)
    robot.connect(calibrate=False)

    pose = {k: v for k, v in robot.get_observation().items() if k.endswith(".pos")}
    print("現在:", {k.split(".")[0]: round(v, 1) for k, v in pose.items()})
    print("目標:", {k.split(".")[0]: round(v, 1) for k, v in HOME.items()})

    # 4秒かけて線形補間でゆっくり移動（急な動きは 4.6V 電源だと脱調しやすい）
    n = 120
    for i in range(1, n + 1):
        a = i / n
        robot.send_action({k: pose[k] + (HOME[k] - pose[k]) * a for k in pose})
        time.sleep(1 / 30)
    # 収束待ち
    for _ in range(20):
        robot.send_action(HOME)
        time.sleep(0.1)

    final = {k: v for k, v in robot.get_observation().items() if k.endswith(".pos")}
    print("到達:", {k.split(".")[0]: round(v, 1) for k, v in final.items()})
    err = max(abs(final[k] - HOME[k]) for k in HOME)
    print(f"最大誤差: {err:.1f}度  {'(OK)' if err < 3 else '(要確認: 電源/負荷)'}")

    # トルクを保持したまま切断（disable_torque_on_disconnect=False）
    robot.disconnect()
    print("ホーム姿勢を保持して切断しました。このまま eval.sh を実行してください。")


if __name__ == "__main__":
    main()
