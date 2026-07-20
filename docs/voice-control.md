# 音声操作（Phase A: オーケストレーション）

マイクの発話で SO-101 を動かす。第一段階は「音声オーケストレーション」＝
**既存の推論スクリプトを声で起動・停止する**司令塔だけを足す。ロボット制御ロジックは
一切いじらないので、安全に載せられる。

入口は 2 つ。**推奨は Web UI**（ブラウザのマイク許可が確実に通り、画面で認識結果が見える）。

```
[ブラウザ getUserMedia] → 録音 → ローカル FastAPI → faster-whisper → 発話テキスト
        → コマンド判定 → 子プロセス（eval.sh / go_home.py）を起動・停止
```

司令ロジックは `scripts/_orchestrate.py` に集約し、Web 版（`voice_web.py`）と
CLI 版（`voice_control.py`）で共有している。

## Web UI（推奨）

```bash
cd ~/2026/personal/so101-lab
source scripts/_env.sh
uv run --extra voice python scripts/voice_web.py
# → ブラウザで http://127.0.0.1:8600 を開く
```

- **マイクボタンを押している間だけ録音**（押して話す＝プッシュトゥトーク）。離すと認識。
  VAD 不要で誤爆しにくい。ブラウザが `getUserMedia` でマイク許可プロンプトを出すので、
  **Terminal のマイク権限問題（無音=ゼロで無反応）を回避できる**。
- 音声が滑っても **開始／ホーム／ストップのボタン**でフォールバックできる。タスク文の
  テキスト入力もあり、`TASK_OVERRIDE` として子に渡る（SmolVLA の言語条件に効く）。
- 認識結果・判定コマンド・実行状態（待機/実行中）・ログが画面に出る。
- サーバは **127.0.0.1 のみで待受**（ロボット制御を LAN に晒さない）。初回に Chrome/Safari の
  マイク許可を「許可」する。`localhost` は安全なコンテキスト扱いなので HTTP でもマイクが使える。

環境変数: `VOICE_WEB_PORT`（既定 8600）、`VOICE_MODEL`（既定 small）、
`VOICE_START_CMD`/`VOICE_HOME_CMD`（下記・共通）。

## CLI 版（voice_control.py, 参考）

## なぜこの設計か

ゼロショット実験（[smolvla-vs-act.md](experiments/smolvla-vs-act.md)）で
**「言語（What）は SmolVLA に通じるが、行動（How）は fine-tune が要る」**と分かった。
音声操作は VLA の「すでに動く部分（言語チャンネル）」をそのまま使う話。発話は
`TASK_OVERRIDE` で子スクリプトへ渡すので、

- 今（1 タスク ACT/SmolVLA）: 声は「開始／停止／ホーム」の**司令**として働く
- 次（マルチタスク SmolVLA）: 発話内容がそのまま**挙動を選ぶ**（Phase B）

と地続きになる。

## セットアップ（Mac のみ）

```bash
uv sync --extra voice     # faster-whisper + sounddevice を追加
```

初回はマイク権限が要る。**Terminal（や iTerm）にマイク権限を付与**しておくこと
（システム設定 > プライバシーとセキュリティ > マイク）。Claude Code 経由では権限が
取れないので、必ずユーザーの手元 Terminal で起動する。

## 使い方

```bash
cd ~/2026/personal/so101-lab
source scripts/_env.sh
uv run --extra voice python scripts/voice_control.py
```

起動すると 1 秒ほど周囲音を較正し、待受に入る。話しかけると：

| 発話に含める語 | 動作 |
|---|---|
| 「入れて」「スタート」「開始」「掴んで」等 | `eval.sh` を 1 エピソード起動（発話全文を task に注入）|
| 「ホーム」「戻して」「初期姿勢」 | `go_home.py` で開始姿勢へ（アイドル時のみ）|
| 「ストップ」「止まって」「やめて」 | 実行中の子に SIGINT＝**Ctrl-C 相当の安全停止** |
| 「終了」「シャットダウン」 or Ctrl-C | 待受を終了 |

判定の優先順は STOP > HOME > START。実行中は新しい START/HOME を無視するので、
まず「ストップ」で止めてから次の指示を出す。

## 安全

- **「ストップ」は常時聞いている**。タスク実行中もマイクループは別プロセスで走り続け、
  子プロセスにシグナルを送れる。ただし**物理の非常停止（Ctrl-C・電源）を最優先**に。
- SIGINT で止まらなければ SIGTERM→SIGKILL と段階的に確実に落とす。
- 5V 運用のブラウンアウトは音声とは無関係に起きうる。急な動きが出たら電源を切る。

## 調整（環境変数、すべて任意）

| 変数 | 既定 | 用途 |
|---|---|---|
| `VOICE_MODEL` | `small` | Whisper サイズ。誤認識が多ければ `medium`、遅ければ `base` |
| `VOICE_RMS_THRESHOLD` | 自動較正 | 発話検出の音量しきい値。ノイズ環境で誤爆するなら手動で上げる |
| `VOICE_WAKEWORD` | なし | 設定するとその語を含む発話だけ受付（例 `ロボット`）。誤爆を強力に防ぐ |
| `VOICE_START_CMD` | `./scripts/eval.sh` | 「開始」で呼ぶコマンド。async にするなら `./scripts/eval_async.sh` |
| `VOICE_HOME_CMD` | `uv run python scripts/go_home.py` | 「ホーム」で呼ぶコマンド |

## 既知の限界（＝Phase B への宿題）

- **今の ACT は言語を無視**する。声で挙動は変わらず「1 タスクを起動/停止」するだけ。
  発話で本当に挙動を変えるにはマルチタスクの言語条件付き fine-tune（SmolVLA）が要る。
- Whisper は短い日本語の命令語（「掴んで」等）を取りこぼすことがある。ウェイクワードや
  はっきりした発話で回避。medium にすると精度は上がるが Mac CPU では遅くなる。
- 誤認識対策としてキーワードは substring マッチ。厳密な意図解釈（LLM で正規化）は次段。

## Phase B への発展

1. 2〜3 タスクを**別々の言語ラベル**で収録（「カップに入れて」「左に置いて」「積んで」）
2. その和集合で SmolVLA を再 fine-tune（言語条件付き）
3. `voice_control.py` はそのまま。発話が `TASK_OVERRIDE` として効き、**声で挙動が変わる**

このとき右ゾーンのデータも一緒に録れば、カバレッジの穴埋めも同時に進む。
