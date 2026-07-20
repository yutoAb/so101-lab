"""ロボット司令の共通部品（CLI 版 voice_control.py と Web 版 voice_web.py で共有）。

ここはロボットを直接動かさない。既存スクリプト（eval.sh / go_home.py）を「子プロセス」
として起動・停止し、発話/ボタンをコマンドに分類するだけ。制御ロジックには触れない。
"""
import os
import re
import signal
import subprocess
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

VOICE_START_CMD = os.environ.get("VOICE_START_CMD", "./scripts/eval.sh")
VOICE_HOME_CMD = os.environ.get("VOICE_HOME_CMD", "uv run python scripts/go_home.py")

# コマンド判定キーワード（部分一致。判定優先順: QUIT > STOP > HOME > START）
STOP_WORDS = ("ストップ", "すとっぷ", "止ま", "止め", "やめ", "停止", "stop")
HOME_WORDS = ("ホーム", "戻し", "戻っ", "初期", "home")
START_WORDS = ("スタート", "開始", "始め", "入れて", "いれて", "掴", "つかん",
               "取って", "とって", "やって", "start", "go")
QUIT_WORDS = ("終了", "しゅうりょう", "シャットダウン", "shutdown", "quit", "exit")


class Child:
    """ロボットを動かす子プロセス。プロセスグループごと確実に停止できる。"""

    def __init__(self, kind: str, popen: subprocess.Popen):
        self.kind = kind          # "eval" | "home"
        self.popen = popen

    def alive(self) -> bool:
        return self.popen.poll() is None

    def stop(self) -> None:
        """SIGINT（Ctrl-C 相当）→ 効かなければ SIGTERM/SIGKILL で確実に止める。"""
        if not self.alive():
            return
        try:
            pgid = os.getpgid(self.popen.pid)
        except ProcessLookupError:
            return
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(pgid, sig)
            except ProcessLookupError:
                return
            for _ in range(30):                     # 最大 3 秒待つ
                if self.popen.poll() is not None:
                    return
                time.sleep(0.1)


def spawn(kind: str, cmd: str, task: str) -> Child:
    """cmd を子プロセスとして起動。発話文を TASK_OVERRIDE で子に渡す。"""
    env = dict(os.environ)
    env["TASK_OVERRIDE"] = task
    env.setdefault("NUM_EVAL_EPISODES", "1")        # 「開始」1 回で 1 エピソード
    popen = subprocess.Popen(
        cmd, shell=True, cwd=REPO_ROOT, env=env,
        start_new_session=True,                     # 独立プロセスグループ→まとめて停止できる
    )
    return Child(kind, popen)


def classify(text: str) -> str:
    """発話/入力テキストをコマンドに分類。優先順: quit > stop > home > start。"""
    t = text.lower()
    if any(w.lower() in t for w in QUIT_WORDS):
        return "quit"
    if any(w.lower() in t for w in STOP_WORDS):
        return "stop"
    if any(w.lower() in t for w in HOME_WORDS):
        return "home"
    if any(w.lower() in t for w in START_WORDS):
        return "start"
    return "none"


def task_from_utterance(text: str, default: str = "") -> str:
    """発話をポリシーに渡すタスク文に変換する。

    「スタート」のような**内容の無い起動語だけ**の発話なら default（既定タスク）を返す。
    「ブロックを掴んで入れて」のように内容がある発話は、そのまま全文を返す
    （言語条件付き VLA には自然文をそのまま渡すのが望ましい）。
    """
    remainder = re.sub("|".join(map(re.escape, START_WORDS)), "", text)
    remainder = re.sub(r"[\s　、。，．,.!?！？]", "", remainder)
    return text.strip() if remainder else default
