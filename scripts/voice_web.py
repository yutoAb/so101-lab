"""音声操作 Web UI: ブラウザのマイクで SO-101 を動かす（Phase A オーケストレーション）。

ブラウザで録音 → ローカル FastAPI に送信 → faster-whisper で文字起こし → コマンド判定
→ 既存スクリプト（eval.sh / go_home.py）を子プロセスで起動・停止する。CLI 版
（voice_control.py）と同じ司令ロジック（_orchestrate.py）を共有し、入力を「Terminal の
マイク」から「ブラウザのマイク」に替えただけ。ブラウザは getUserMedia でサイトごとに
明示的にマイク許可を出すので、Terminal のマイク権限問題（無音=ゼロ）を回避できる。

安全のため 127.0.0.1 のみで待受（ロボット制御を LAN に晒さない）。

使い方（Mac、Chrome/Safari 等で）:
    cd ~/2026/personal/so101-lab && source scripts/_env.sh
    uv run --extra voice python scripts/voice_web.py
    # → ブラウザで http://127.0.0.1:8600 を開く

環境変数: VOICE_MODEL（Whisper サイズ, 既定 small）, VOICE_WEB_PORT（既定 8600）,
          VOICE_START_CMD / VOICE_HOME_CMD（_orchestrate.py と共通）。
"""
import os
import tempfile
import threading

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse

from _orchestrate import (
    VOICE_HOME_CMD, VOICE_START_CMD, Child, classify, spawn, task_from_utterance,
)

VOICE_MODEL = os.environ.get("VOICE_MODEL", "small")
VOICE_WEB_PORT = int(os.environ.get("VOICE_WEB_PORT", "8600"))
HTML_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "voice_web.html")

app = FastAPI()

_model = None                 # faster-whisper（起動時ロード）
_lock = threading.Lock()      # 子プロセス状態を触る時の排他
_child: Child | None = None   # 現在動いている子（eval / home）


def get_model():
    global _model
    if _model is None:
        from faster_whisper import WhisperModel
        print(f"==> Whisper 読み込み中: {VOICE_MODEL} (CPU/int8)…", flush=True)
        _model = WhisperModel(VOICE_MODEL, device="cpu", compute_type="int8")
        print("    読み込み完了", flush=True)
    return _model


def _running() -> bool:
    return _child is not None and _child.alive()


def dispatch(command: str, task: str) -> dict:
    """判定済みコマンドを実行。状態変更は _lock 下で行う。返り値は UI 表示用。"""
    global _child
    with _lock:
        running = _running()
        if command == "stop":
            if running:
                _child.stop()
                _child = None
                return {"ok": True, "message": "安全停止しました"}
            return {"ok": True, "message": "実行中のタスクはありません"}
        if command == "home":
            if running:
                return {"ok": False, "message": "実行中です。先に『ストップ』で止めてください"}
            _child = spawn("home", VOICE_HOME_CMD, "")
            return {"ok": True, "message": f"ホームへ移動中: {VOICE_HOME_CMD}"}
        if command == "start":
            if running:
                return {"ok": False, "message": "すでに実行中です。『ストップ』で止めてから"}
            task = task or os.environ.get("TASK_DESCRIPTION", "")
            _child = spawn("eval", VOICE_START_CMD, task)
            return {"ok": True, "message": f"タスク開始: 「{task}」"}
        return {"ok": False, "message": "コマンドを認識できませんでした"}


@app.get("/")
def index():
    with open(HTML_PATH, encoding="utf-8") as f:
        return HTMLResponse(f.read())


@app.get("/status")
def status():
    with _lock:
        if _child is None:
            return {"running": False, "kind": None}
        return {
            "running": _child.alive(),
            "kind": _child.kind,
            "returncode": _child.popen.returncode,
        }


@app.post("/command")
async def command(request: Request):
    """ブラウザ録音（webm/opus 生バイト）を受け取り、文字起こし→判定→実行。"""
    audio = await request.body()
    if not audio:
        return JSONResponse({"ok": False, "message": "音声が空です"}, status_code=400)

    with tempfile.NamedTemporaryFile(suffix=".webm", delete=True) as tmp:
        tmp.write(audio)
        tmp.flush()
        model = get_model()
        segments, _ = model.transcribe(tmp.name, language="ja", beam_size=1)
        text = "".join(s.text for s in segments).strip()

    if not text:
        return {"ok": False, "text": "", "command": "none",
                "message": "聞き取れませんでした", "running": _running()}

    cmd = classify(text)
    task = task_from_utterance(text, os.environ.get("TASK_DESCRIPTION", "")) if cmd == "start" else ""
    result = dispatch(cmd, task)
    result.update({"text": text, "command": cmd, "running": _running()})
    return result


# ボタン用の明示エンドポイント（音声が滑った時のフォールバック）
@app.post("/start")
async def start_btn(request: Request):
    body = await request.json()
    task = (body or {}).get("task", "").strip() or os.environ.get("TASK_DESCRIPTION", "")
    result = dispatch("start", task)
    result.update({"running": _running()})
    return result


@app.post("/home")
def home_btn():
    result = dispatch("home", "")
    result.update({"running": _running()})
    return result


@app.post("/stop")
def stop_btn():
    result = dispatch("stop", "")
    result.update({"running": _running()})
    return result


def main():
    for var in ("FOLLOWER_PORT", "FOLLOWER_ID"):
        if var not in os.environ:
            print(f"[!] 環境変数 {var} が未設定です。先に `source scripts/_env.sh` を。", flush=True)
            raise SystemExit(1)
    get_model()   # 起動時にロードしておく（初回発話の待ちを無くす）
    print(f"\n==> 音声操作 Web UI: http://127.0.0.1:{VOICE_WEB_PORT}  を開いてください\n", flush=True)
    uvicorn.run(app, host="127.0.0.1", port=VOICE_WEB_PORT, log_level="warning")


if __name__ == "__main__":
    main()
