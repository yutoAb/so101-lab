# 実験(Phase B): 言語で対象を出し分けられるか（色選択）

## 問い

**同じ場面（赤と青のブロックが両方ある）で、喋る言葉だけを変えたら、掴む対象は変わるか？**

- 「赤いブロックをカップに入れて」→ 赤を掴む
- 「青いブロックをカップに入れて」→ 青を掴む

これは言語条件付け（language-conditioned manipulation）の核心テスト。SmolVLA が
**本当に言葉を聞いて行動を選ぶ**のか、それとも視覚の多数派パターンに潰れるのかを、
実機で正面から測る。どちらに転んでも結果は意味を持つ：

- **出し分けられる** → 言語グラウンディングが（この規模の fine-tune でも）効く＝強い成果＋映える動画
- **出し分けられない**（常に同じ色/同じ side を掴む）→ ゼロショット実験と地続きの誠実な否定的結果

前提: [smolvla-vs-act.md](smolvla-vs-act.md)（言語=What は通じるが行動=How は fine-tune が要る）、
[voice-control.md](../voice-control.md)（発話→`TASK_OVERRIDE`→policy）。

## 実験を"ズルできない"ものにする鍵

**色と位置を相関させない。** もし収録で赤を常に左に置くと、policy は「左を掴む」を学習してしまい、
言語ではなく位置で正解してしまう。これを防ぐため：

- **各エピソードで赤/青の左右をランダムに入れ替える**（約 50/50）。
- 位置は信頼できる**左〜中央ゾーンのみ**（右ゾーンは OOD の別変数なので今回混ぜない）。
- カップ（置き先）は固定。距離要因を減らす。
- フロントカメラに**人が写り込まない**（[operator-in-frame の過学習](../../) 参照）。

## データ収集（2 セッションを 1 データセットに追記）

`_env.sh` を色選択タスク用にする（新しい `TASK_NAME`）：

```bash
# _env.sh
export TASK_NAME="color-select"
export POLICY_TYPE="smolvla"
# TASK_DESCRIPTION は下の TASK_OVERRIDE で毎回上書きするのでダミーで可
```

**セッション A（赤・新規作成、~50 本）**：赤と青を置く（左右ランダム）。**赤を**掴んでカップに入れる。

```bash
TASK_OVERRIDE="赤いブロックをカップに入れて" \
NUM_EPISODES=50 \
DATASET_ROOT=~/lerobot_data/so101-color-select \
./scripts/record.sh
```

**セッション B（青・追記、合計 100 本まで）**：同様に左右ランダム。**青を**掴んでカップに入れる。

```bash
RESUME=true \
DATASET_ROOT=~/lerobot_data/so101-color-select \
TASK_OVERRIDE="青いブロックをカップに入れて" \
NUM_EPISODES=100 \
./scripts/record.sh
```

これで各エピソードに言語ラベルが付いた 2 タスク混在データセット
（`${HF_USER}/so101-color-select`, 赤 50 / 青 50）ができる。

## 学習（SmolVLA fine-tune、前回と同じ）

```bash
CUDA_VISIBLE_DEVICES=1 HF_HUB_DISABLE_XET=1 \
POLICY_BASE=lerobot/smolvla_base TRAIN_STEPS=30000 BATCH_SIZE=16 \
RENAME_MAP='{"observation.images.front":"observation.images.camera1","observation.images.wrist":"observation.images.camera2"}' \
nohup ./scripts/train.sh > ~/color_train.log 2>&1 &
```

→ `${HF_USER}/so101-smolvla-color-select`。ラボ GPU 運用は [smolvla-vs-act.md](smolvla-vs-act.md) 参照。

## 評価（音声 or eval.sh で言語を振る）

同じ場面（赤・青を両方置く）で言葉だけ変える。カメラ名は SmolVLA なので camera1/camera2：

```bash
uv run python scripts/go_home.py
# 赤を指示
EVAL_POLICY=abePclWaseda/so101-smolvla-color-select \
CAMERA_FRONT_KEY=camera1 CAMERA_WRIST_KEY=camera2 \
TASK_OVERRIDE="赤いブロックをカップに入れて" NUM_EVAL_EPISODES=1 ./scripts/eval.sh
# 青を指示（同じ/近い配置で）
TASK_OVERRIDE="青いブロックをカップに入れて" ...
```

音声 UI（`voice_web.py`）でも同様に「赤を…」「青を…」と喋れば `TASK_OVERRIDE` として効く。

### 測る指標

1. **命令色 × 掴んだ色の 2×2 混同行列**（対角＝言語に従った）。各色 10 試行程度。
2. **位置対照**：命令色が「少数派の側／掴みにくい側」にある場合でも色に従うか（位置で正解していない証明）。
3. **同一シーン反転デモ**：赤左・青右に固定 → 「赤」で左、「青」で右を掴む＝**同じピクセルで言葉だけで逆の行動**。
   これが取れたら記事のメイン GIF。

## 成果物（埋める）

| 指標 | 結果 |
|---|---|
| 「赤」命令で赤を掴んだ率 | __ / __ |
| 「青」命令で青を掴んだ率 | __ / __ |
| 命令と逆の色を掴んだ（言語無視）率 | __ |
| 同一シーン反転が成立したか | __ |

## ログ

- 2026-07-20: 計画策定。`record.sh` に `TASK_OVERRIDE` を追加（2 言語を 1 データセットに追記可能に）。
