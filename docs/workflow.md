# Workflow: テレオペ → データ収集 → 学習 → 推論（Phase 6–9）

LeRobot の美しいところは、**ハードに接続する CLI が同じインターフェースで「データ収集モード」と「推論モード」を切り替えられる**こと。`lerobot-record` に `--policy.path` を足すだけで自律実行になる。

```
Step 6: テレオペ確認        lerobot-teleoperate
              │
              ▼
Step 7: データ収集          lerobot-record (teleop あり, policy なし)
              │
              ▼
Step 8: ポリシー学習        lerobot-train
              │
              ▼
Step 9: 推論実行            lerobot-record (teleop なし, --policy.path 指定)
              │
              └────────► 失敗ケースを次のデータセットに追加 ──┐
                                                              │
              ┌───────────────────────────────────────────────┘
              ▼
        Step 7 へ戻る（継続学習ループ）
```

## Phase 6: テレオペ動作確認

```bash
bash scripts/teleoperate.sh
```

リーダー腕を手で動かしてフォロワー腕が追従すれば**初日の最終ゴール**。ここまで動けばハード側の不具合は実質ゼロ。

## Phase 7: データセット収集

カメラを設置（前方固定 1 台で OK、慣れたら手首にも追加）して：

```bash
bash scripts/record.sh
```

`scripts/record.sh` の中で以下のパラメータを調整：

| パラメータ | 役割 | 推奨初期値 |
|---|---|---|
| `--dataset.repo_id` | HF Hub 上のデータセット名 | `${HF_USER}/so101-pickup-cube` |
| `--dataset.num_episodes` | エピソード数 | 50（最初は少なめで試行） |
| `--dataset.single_task` | タスク説明（VLA 学習で言語条件として使われる） | `"Grab the black cube and put it in the box"` |
| `--robot.cameras` | カメラ設定 | 640×480@30fps から開始 |

データは自動で HF Hub に push される。プライベートにしたい場合は `--dataset.private=true`。

### タスク選びのコツ

- 最初の 1 タスクは「**ピック & プレース**」が定番（公式チュートリアルがレゴブロックでこれをやる）
- 50〜100 エピソード収集すると ACT で 90%+ 成功するレベルまで行ける
- 慣れてきたら「色違いブロックを言語指示で選別」のような VLA 向けタスクに進む

## Phase 8: ポリシー学習

```bash
bash scripts/train.sh
```

`scripts/train.sh` で `--policy.type` を切り替えて比較できる：

| ポリシー | 特徴 | 学習時間（目安・Single GPU） |
|---|---|---|
| `act` | Action Chunking Transformer。最初に試すべき定番 | 3〜6 時間 |
| `diffusion` | Diffusion Policy。マルチモーダル分布に強い | 6〜10 時間 |
| `pi0` | Physical Intelligence の VLA 基盤モデル。言語条件で動く | 数時間〜（fine-tuning） |
| `smolvla` | 軽量 VLA。エッジ推論視野ならこれ | 数時間 |

学習は研究室の `g15` で OK。ローカル PC で詰む場合は Colab で公式ノートブックを使う：
- [LeRobot Notebooks (ACT Colab)](https://huggingface.co/docs/lerobot/notebooks)

`wandb` を有効化すると損失曲線・成功率を追える（`--wandb.enable=true`）。

学習済みは自動で HF Hub に `${HF_USER}/${POLICY_REPO}` として push。

## Phase 9: 推論実行（学習済みポリシーをアームに戻す）

```bash
bash scripts/eval.sh
```

中身は **Phase 7 の `record.sh` から teleop を抜いて、`--policy.path` を指定するだけ**。これが LeRobot 設計のキモ：

```bash
lerobot-record \
  --robot.type=so101_follower --robot.port=$FOLLOWER_PORT --robot.id=$FOLLOWER_ID \
  --robot.cameras="..." \
  --policy.path=${HF_USER}/${POLICY_REPO} \
  --dataset.repo_id=${HF_USER}/eval-${TASK_NAME} \
  --dataset.single_task="..."
```

評価エピソードも HF Hub に保存されるので、成功率を後で集計しやすい。

### Python API での推論ループ

CLI でなく自前のプログラムから呼びたい場合：

```python
from lerobot.policies.act.modeling_act import ACTPolicy
from lerobot.robots.so_follower import SO101Follower, SO101FollowerConfig

policy = ACTPolicy.from_pretrained("yutoabe/so101-act-pickup-cube")
robot = SO101Follower(SO101FollowerConfig(port="/dev/ttyACM0", id="my_follower"))
robot.connect()

while True:
    obs = robot.get_observation()
    action = policy.select_action(obs)
    robot.send_action(action)
```

## 継続学習ループ（中長期）

`logs/2026-04-16-turing-visit.md` で一般化したループをここで実装する：

```
[テレオペでデータ追加収集]
       ↓
[Hub の既存データセットに追加]
       ↓
[再学習 or fine-tuning]
       ↓
[Hub のモデルバージョン更新]
       ↓
[推論で評価 → 失敗ケースを次のデータに反映]
```

これを月次で回せると、**Turing が自動運転でやってる縮小版**を手元で運用できる状態になる。
