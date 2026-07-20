"""音声オーケストレーション: マイクの発話で eval / go_home を起動・停止する。

このスクリプト自体はロボットを直接動かさない。マイク→Whisper で文字起こしし、
キーワードで既存スクリプト（eval.sh / go_home.py）を「子プロセス」として起動・停止
するだけの司令塔。ロボット制御ロジックには一切触れないので安全に足せる。

    [マイク] → faster-whisper(Mac,CPU) → 発話テキスト
            → コマンド判定 → 子プロセス（eval.sh 等）を spawn / kill

発話は TASK_OVERRIDE として子に渡す。ACT は言語を無視するが、SmolVLA は言語条件に
効くので、将来のマルチタスク化（発話で挙動が変わる）にそのまま繋がる。

コマンド（発話に以下が含まれれば発火。判定は STOP > HOME > START の優先順）:
  - 停止 : 「ストップ」「止まって」「やめて」「停止」  → 実行中の子に SIGINT（＝Ctrl-C 相当の安全停止）
  - ホーム: 「ホーム」「戻して」「初期姿勢」          → go_home.py（アイドル時のみ）
  - 開始 : 「スタート」「開始」「入れて」「掴んで」等 → eval.sh を起動（発話全文を task に注入）
  - 終了 : 「終了」「シャットダウン」                → スーパーバイザ自体を終了（Ctrl-C でも可）

使い方（Mac、マイク権限のある Terminal で）:
    cd ~/2026/personal/so101-lab && source scripts/_env.sh
    uv run --extra voice python scripts/voice_control.py

依存: pyproject の [voice] extra（faster-whisper, sounddevice）。`uv sync --extra voice`。

環境変数での調整（すべて任意）:
  VOICE_MODEL        faster-whisper のモデル名（tiny/base/small/medium。既定 small）
  VOICE_RMS_THRESHOLD 発話検出の音量しきい値。未指定なら起動時に周囲音から自動較正
  VOICE_WAKEWORD     設定すると、この語を含む発話だけを受け付ける（誤爆防止。既定 なし）
  VOICE_START_CMD    「開始」で起動するコマンド（既定 "./scripts/eval.sh"）
                     async にしたい時: VOICE_START_CMD="./scripts/eval_async.sh"
  VOICE_HOME_CMD     「ホーム」で起動するコマンド（既定 "uv run python scripts/go_home.py"）
"""
import os
import sys
import time

import numpy as np
import sounddevice as sd

from _orchestrate import (
    VOICE_HOME_CMD, VOICE_START_CMD, classify, spawn, task_from_utterance,
)

SAMPLE_RATE = 16000
BLOCK_SEC = 0.03                     # 1 ブロック 30ms
BLOCK_LEN = int(SAMPLE_RATE * BLOCK_SEC)
SILENCE_HANG_SEC = 0.7               # この長さ無音が続いたら発話終了とみなす
MIN_UTTER_SEC = 0.3                  # これより短い音は雑音として捨てる
PREROLL_SEC = 0.2                    # 発話冒頭の欠けを防ぐ先読みバッファ

VOICE_MODEL = os.environ.get("VOICE_MODEL", "small")
VOICE_WAKEWORD = os.environ.get("VOICE_WAKEWORD", "").strip()


def log(msg: str) -> None:
    print(msg, flush=True)


def load_model():
    from faster_whisper import WhisperModel   # 重いので遅延 import
    log(f"==> Whisper モデル読み込み中: {VOICE_MODEL} (CPU/int8)…")
    model = WhisperModel(VOICE_MODEL, device="cpu", compute_type="int8")
    log("    読み込み完了")
    return model


def transcribe(model, audio: np.ndarray) -> str:
    segments, _ = model.transcribe(audio, language="ja", beam_size=1)
    return "".join(s.text for s in segments).strip()


def calibrate_threshold(stream: sd.InputStream) -> float:
    """起動時に周囲音を ~1 秒サンプルして発話しきい値を決める。"""
    override = os.environ.get("VOICE_RMS_THRESHOLD")
    if override:
        thr = float(override)
        log(f"==> 音量しきい値（指定）: {thr:.4f}")
        return thr
    log("==> 周囲音を較正中（1 秒、静かにしてください）…")
    floor = []
    for _ in range(int(1.0 / BLOCK_SEC)):
        block, _ = stream.read(BLOCK_LEN)
        floor.append(float(np.sqrt(np.mean(block[:, 0] ** 2))))
    thr = max(np.mean(floor) * 4.0, 0.008)
    log(f"    しきい値 = {thr:.4f}（環境ノイズ {np.mean(floor):.4f}）")
    return thr


def main() -> None:
    for var in ("FOLLOWER_PORT", "FOLLOWER_ID"):
        if var not in os.environ:
            log(f"[!] 環境変数 {var} が未設定です。先に `source scripts/_env.sh` してください。")
            sys.exit(1)

    model = load_model()
    child: Child | None = None

    log("")
    log("==================== 音声操作 待受開始 ====================")
    log("  「入れて」「スタート」 → タスク実行")
    log("  「ホーム」「戻して」   → 開始姿勢へ")
    log("  「ストップ」「止まって」→ 実行中を安全停止")
    log("  「終了」 または Ctrl-C → 待受終了")
    if VOICE_WAKEWORD:
        log(f"  ウェイクワード: 「{VOICE_WAKEWORD}」を含む発話のみ受付")
    log("==========================================================")

    stream = sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="float32",
                            blocksize=BLOCK_LEN)
    stream.start()
    try:
        threshold = calibrate_threshold(stream)
        preroll_blocks = int(PREROLL_SEC / BLOCK_SEC)
        hang_blocks = int(SILENCE_HANG_SEC / BLOCK_SEC)

        pre: list[np.ndarray] = []       # 発話前の先読みリングバッファ
        buf: list[np.ndarray] = []       # 発話中のバッファ
        speaking = False
        silence = 0
        log("\n[待受中] 話しかけてください…")

        while True:
            # 子プロセスが自然終了したら掃除
            if child is not None and not child.alive():
                log(f"[i] {child.kind} 終了（コード {child.popen.returncode}）\n[待受中]…")
                child = None

            block, _ = stream.read(BLOCK_LEN)
            mono = block[:, 0]
            rms = float(np.sqrt(np.mean(mono ** 2)))

            if not speaking:
                pre.append(mono.copy())
                if len(pre) > preroll_blocks:
                    pre.pop(0)
                if rms > threshold:
                    speaking = True
                    silence = 0
                    buf = list(pre)          # 冒頭欠け防止に先読み分を含める
                    pre = []
                continue

            # 発話中
            buf.append(mono.copy())
            if rms > threshold:
                silence = 0
            else:
                silence += 1
                if silence < hang_blocks:
                    continue
                # 発話終了 → 判定
                speaking = False
                audio = np.concatenate(buf)
                buf = []
                if len(audio) / SAMPLE_RATE < MIN_UTTER_SEC:
                    continue

                text = transcribe(model, audio)
                if not text:
                    continue
                log(f'\n[聞取] 「{text}」')

                if VOICE_WAKEWORD and VOICE_WAKEWORD.lower() not in text.lower():
                    log(f"  (ウェイクワード「{VOICE_WAKEWORD}」無し→無視)")
                    continue

                cmd = classify(text)
                running = child is not None and child.alive()

                if cmd == "quit":
                    log("==> 終了します")
                    break
                elif cmd == "stop":
                    if running:
                        log("  ■ 安全停止中…")
                        child.stop()
                        child = None
                        log("  停止しました")
                    else:
                        log("  (実行中のタスクはありません)")
                elif cmd == "home":
                    if running:
                        log("  (実行中。先に『ストップ』で止めてください)")
                    else:
                        log(f"  ▶ home 起動: {VOICE_HOME_CMD}")
                        child = spawn("home", VOICE_HOME_CMD, "")
                elif cmd == "start":
                    if running:
                        log("  (すでに実行中。『ストップ』で止めてから)")
                    else:
                        task = task_from_utterance(text, os.environ.get("TASK_DESCRIPTION", ""))
                        log(f"  ▶ eval 起動: {VOICE_START_CMD}  task=「{task}」")
                        child = spawn("eval", VOICE_START_CMD, task)
                else:
                    log("  (コマンドとして認識できませんでした)")
    except KeyboardInterrupt:
        log("\n==> Ctrl-C 終了")
    finally:
        if child is not None and child.alive():
            log("==> 実行中の子プロセスを停止します")
            child.stop()
        stream.stop()
        stream.close()
        log("待受を終了しました。")


if __name__ == "__main__":
    main()
