# 実験: SmolVLA fine-tune vs ACT（分布外への強さ比較）

## 問い

ゼロから学習した ACT より、事前学習済み VLA（SmolVLA）を**同じ 102 本**で fine-tune した方が、
**学習データを置いていない右ゾーン（分布外）**に強いか？

ACT は「学習した中で一番近い軌跡」を引くだけで、右ゾーンは 0% だった
（→ [`docs/images/coverage_map_102ep.png`](../images/coverage_map_102ep.png)、
[続報記事](https://qiita.com/yuAbe/items/3e01faa4ad66ef6a6371)）。
SmolVLA は多数の他ロボット・タスクで事前学習済みなので、分布外への内挿・外挿がマシになる可能性がある。
副次的に「学習時間・推論レート・モデルサイズ」も測り、軽量化／リアルタイム推論ループの観点でも比較する。

## デザイン（変えるのはポリシーだけ）

| 固定 | 内容 |
|---|---|
| データ | `abePclWaseda/so101-cube-in-case-v2`（102 本、同一）|
| 評価 | 同じ 3×3 カバレッジマップ。`scripts/go_home.py` で開始姿勢統一、最終フレーム目視判定 |
| 実機・カメラ | front + wrist、5V（現状のまま）|
| **変数** | **ポリシーのみ**：ACT（既存 `abePclWaseda/so101-act-cube-in-case-v2-102ep`）vs SmolVLA（fine-tune）|

## 手順

### 0. 依存（両マシン）
`pyproject.toml` を `lerobot[feetech,smolvla]==0.5.1` に更新済み。学習(g27)・推論(Mac)とも `uv sync`。
（SmolVLA は言語条件付きで `transformers` が要る。学習だけでなく**推論側の Mac にも必要**。）

### 1. 学習（g27 で fine-tune）
`_env.sh` で `POLICY_TYPE=smolvla` に変更（→ `POLICY_REPO_ID` が自動で `...-smolvla-...` になる）。

```bash
POLICY_BASE=lerobot/smolvla_base \
TRAIN_STEPS=30000 \
BATCH_SIZE=64 \
./scripts/train.sh
```

- `--policy.path=lerobot/smolvla_base` で**基盤の重みを引き継いで** fine-tune（`train.sh` の `POLICY_BASE` が担保）。
  `--policy.type=smolvla` だとゼロ学習になり fine-tune の意味が消えるので注意。
- 事前学習済みなので **20–30k step で収束**見込み（ACT は 100k）。
- `BATCH_SIZE` は VRAM 次第。A6000 48GB を占有できれば 64、共有で埋まっている時は 16〜32 に落とす。
- ACT 同様、途中 checkpoint も評価する。

### 2. 評価（Mac、`eval.sh` をそのまま流用）
```bash
uv run python scripts/go_home.py
EVAL_POLICY=abePclWaseda/so101-smolvla-cube-in-case-v2 NUM_EVAL_EPISODES=1 ./scripts/eval.sh
```
3×3 各ゾーンを ACT と同じ回数だけ回し、緑赤マップをもう一枚作る。

## 成果物（この表を埋める）

| 指標 | ACT (102ep, 100k) | SmolVLA (102ep, ~30k ft) |
|---|---|---|
| 分布内成功率（左+中央）| 100% | ? |
| **分布外成功率（右）** | **0%** | **?** ← 主結果 |
| 全体 | 7/11 ≈ 64% | ? |
| 学習時間 | ~10.7h | ? |
| 推論レート（Mac 実機）| ~30Hz | ? |
| モデルサイズ | 数十MB（ResNet18）| ~450MB |

## 落とし穴

1. **`--policy.path`（type ではない）**。type だと基盤の重みを捨てる。
2. **カメラ名の不一致（実際にハマった）**。SmolVLA base は `observation.images.camera1/2/3`（3台）を
   期待するが、うちのデータは `front/wrist`（2台）。そのままだと make_policy が
   `Feature mismatch` で落ちる。バリデーションは「dataset ⊆ policy」なら通るので、
   `RENAME_MAP` で front→camera1, wrist→camera2 にリネームすれば OK（camera3 は無くてよい＝
   SmolVLA は可変カメラ対応。`empty_cameras` パディングも不要）。`train.sh` の `RENAME_MAP` で渡す。
3. **言語条件付き**：データは `TASK_DESCRIPTION` が全エピソードに付与済み。eval 時も同じ文が渡ることを確認。
4. **Mac の推論レートが最大リスク**。450M の VLA は Mac で 30Hz を割る可能性大。割ると
   チャンク開ループで補正が効かず空振りが増える（前回の 10Hz 問題と同じ機序）。Hz は必ずログで確認。
   遅すぎたら 0.5.1 の async 推論（`[async]` extra）で「推論を別マシン・実機は Mac」に分離する手がある。
   ただしまず素の数字を出す。
5. SmolVLA base の初回 DL が走る。`HF_HUB_DISABLE_XET=1` は継続。
6. **出力ディレクトリの残骸**：失敗して作られた `outputs/train/smolvla_*` が残ると
   `FileExistsError`。再実行前に `rm -rf` する。

## 実行環境メモ

ラボGPUはスケジューラ無しの共有ベアメタル。g27(A6000×2) が飽和していたので、他ノードを探して
**g16 の空き RTX 3090(24GB, idle)** で実行。ホームはノード間非共有なので g16 に repo を clone、
`_env.sh` を g27 から転送、`uv sync` してから起動。実launch:

```bash
# g16, GPU1(空き3090)。3090 24GB なので batch は控えめ（実測 batch16 で VRAM 5GB弱・98%util）
CUDA_VISIBLE_DEVICES=1 HF_HUB_DISABLE_XET=1 \
POLICY_BASE=lerobot/smolvla_base TRAIN_STEPS=30000 BATCH_SIZE=16 \
RENAME_MAP='{"observation.images.front":"observation.images.camera1","observation.images.wrist":"observation.images.camera2"}' \
nohup ./scripts/train.sh > ~/smolvla_train.log 2>&1 &
```

## ログ

- 2026-07-15: 計画策定。`pyproject` を `[feetech,smolvla]` に更新、`train.sh` を fine-tune / rename_map 対応に拡張。
- 2026-07-15: g16 の空き 3090 で fine-tune 開始（batch16, 30k step, ETA ~2.5h）。学習可能 100M / 全 450M、
  vision encoder は凍結。カメラ名不一致は `RENAME_MAP` で解決。
