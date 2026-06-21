# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## このリポジトリの位置付け

HuggingFace [LeRobot](https://github.com/huggingface/lerobot) × SO-101 双腕アームの**作業ノート**。アプリケーションではなく、`lerobot-*` CLI を薄く包む bash スクリプト群と、フェーズごとの Markdown ドキュメント（`docs/setup.md`, `docs/workflow.md`）で構成される。ビルド・lint・テストは存在しない。「コード」はシェルパイプラインそのもので、成果物（データセット・学習済みポリシー）は HuggingFace Hub 側に置く。

ドキュメントとスクリプト内コメントは日本語で書かれている。編集する際もそれに合わせる。

## パイプライン全体像

すべてのスクリプトは `scripts/_env.sh`（`.gitignore` 対象。`_env.sh.example` からコピーして使う）を source する。各フェーズは順序依存で、前段が生成する値（USB ポート、キャリブレーションファイル等）を後段が消費する。

```
install.sh  →  find-port.sh  →  setup-motors-{follower,leader}.sh
                                           ↓
                                    [ 物理組立 ]
                                           ↓
                                    calibrate.sh
                                           ↓
                                   teleoperate.sh
                                           ↓
                                     record.sh   ──► HF Hub データセット
                                           ↓
                                      train.sh   ──► HF Hub ポリシー
                                           ↓
                                      eval.sh    （record.sh − teleop + --policy.path）
```

順序に関して見落としやすい制約が 2 つ：

1. **`setup-motors-*.sh` は組立前に必ず実行する**。モーター ID とボーレートはコントローラ基板に「1 個ずつ」サーボを繋ぎ替えながら個別に書き込む。組立後は配線がアーム内部を通ってしまうので、やり直すには分解が必要になる。
2. **リーダー腕は 6 軸で 3 種類のギア比のサーボを混在させている**（1:191 ×2, 1:345 ×1, 1:147 ×3）。`setup-motors-leader.sh` の CLI が「次は wrist_roll」のように関節名を指示してくるので、対応するギア比のサーボを選んで繋ぐ。詳細は `scripts/setup-motors-leader.sh` 内のテーブルと `docs/setup.md` Phase 3。間違えるとリーダーが自重を支えられなくなる。

## 「record = データ収集 + 推論」設計

`scripts/record.sh`（データ収集）と `scripts/eval.sh`（自律推論）はどちらも `lerobot-record` を呼ぶ。違いは：`record.sh` は `--teleop.*` を渡してリーダーで人が操縦（フォロワーが追従）、`eval.sh` は `--teleop.*` を落として代わりに `--policy.path=$POLICY_REPO_ID` を渡す。**片方を編集する時は、もう一方にも反映が必要かどうか必ず確認する**（カメラ設定、データセットエンコード関連フラグなど）。

## 環境変数

`scripts/_env.sh` が機材ごとの設定の唯一のソース。サンプル（`scripts/_env.sh.example`）に各スクリプトが読む変数が全部並んでいる。重要な派生値：

- `DATASET_REPO_ID="${HF_USER}/so101-${TASK_NAME}"` — HF Hub への push 先データセット
- `POLICY_REPO_ID="${HF_USER}/so101-${POLICY_TYPE}-${TASK_NAME}"` — HF Hub への push 先ポリシー
- `EVAL_DATASET_REPO_ID="${HF_USER}/eval-${TASK_NAME}"` — `eval.sh` 内でインラインで組み立てる

タスク切り替えはスクリプトを直すのではなく `_env.sh` の `TASK_NAME` / `TASK_DESCRIPTION` / `POLICY_TYPE` を書き換える。

`record.sh` と `eval.sh` はアドホックな環境変数オーバーライドも受け付ける（`NUM_EPISODES`, `EPISODE_TIME_SEC`, `RESET_TIME_SEC`, `NUM_EVAL_EPISODES`）。

## リポジトリの外に置くもの

- **キャリブレーションファイル** — `lerobot-calibrate` が `~/.cache/huggingface/lerobot/calibration/...` に書く。アーム個体ごとに異なるので意図的に `.gitignore` 対象。コミット・同期しようとしないこと。
- **データセット・学習済みポリシー** — HF Hub に push（`hf auth login` 必須。`install.sh` でチェックしている）。`outputs/`, `checkpoints/`, `wandb/`, `*.mp4`, `*.parquet` はすべて gitignore 済み。
- **`scripts/_env.sh`** — gitignore 済み（HF トークン・ポートパスを含む）。絶対にコミットしない。

## プラットフォーム差分

- USB ポート表記は OS で違う：macOS は `/dev/tty.usbmodem...`、Linux は `/dev/ttyACM*`。Linux ではアクセス権付与が必要：`sudo chmod 666 /dev/ttyACM0 /dev/ttyACM1`（`docs/setup.md` Phase 2 参照）。
- `train.sh` は `--policy.device=cuda` をハードコードしている。CUDA が無いマシンではスクリプトを書き換えるのではなく、`docs/workflow.md` Phase 8 が案内している LeRobot 公式 Colab ノートブックに逃がすのが正攻法。
