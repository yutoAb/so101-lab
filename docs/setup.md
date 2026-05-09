# Setup: 開封からキャリブレーションまで（Phase 0–5）

## Phase 0: 開封チェック

| 確認項目 | 期待 |
|---|---|
| Feetech STS3215 サーボ | 12 個（1:345 ×7 / 1:191 ×2 / 1:147 ×3） |
| XIAO 用シリアルバスサーボドライバ基板 | 2 枚（リーダー用・フォロワー用） |
| AC アダプタ 5V 4A | 2 個（PSE 認証 / 日本仕様） |
| USB Type-C ケーブル | 2 本 |
| DC ジャック付ケーブル | 2 本 |
| スタッド ×8 / ネジ ×8 / クランプ ×4 | あり |
| 3D プリントパーツ（131222 側） | リーダー＋フォロワー両方分 |

足りないものはここで気付く方が後より楽。

## Phase 1: ソフト環境構築

```bash
bash scripts/install.sh
```

中身（`scripts/install.sh` 参照）:
- `pip install lerobot`
- `pip install -e ".[feetech]"` — Feetech サーボ用 SDK
- HF アカウント連携（`hf auth login --token <YOUR_TOKEN>`）
- USB Web カメラ動作確認

HF トークンは [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) で write 権限のものを発行。

## Phase 2: USB ポート特定

```bash
bash scripts/find-port.sh
```

リーダー用基板とフォロワー用基板を**別々の USB ポート**に挿し、CLI の指示に従って片方ずつ抜き差し。出てきた `/dev/tty.usbmodem...`（Mac）または `/dev/ttyACM...`（Linux）を `_env.sh` の `FOLLOWER_PORT` / `LEADER_PORT` にメモ。

> **Linux の場合**: `sudo chmod 666 /dev/ttyACM0 /dev/ttyACM1` でアクセス権を付与。

## Phase 3: モーター ID & ボーレート設定 ⚠️ 組立前

**最重要・最も間違えやすい工程**。組み立てた後だとケーブルを通し直すハメになる。

「コントローラ基板に 1 個だけ」サーボを繋いで、CLI が「次は X モーターを繋いで」と順に指示してくる流れ。フォロワー → リーダーの順で実行：

```bash
bash scripts/setup-motors-follower.sh
bash scripts/setup-motors-leader.sh
```

### リーダー側の注意点

リーダー腕は 6 軸でギア比が異なるサーボを混在させる：

| 軸 | ギア比 | 役割 |
|---|---|---|
| Shoulder Pan | 1:191 | 自重を支えながら旋回 |
| Shoulder Lift | 1:345 | 最も重い荷重 |
| Elbow Flex | 1:191 | 中ほどの荷重 |
| Wrist Flex / Roll / Gripper | 1:147 | 軽くて素早く動く |

CLI が「次は wrist_roll を繋いで」と指示してきたら、**1:147 のサーボを選んで繋ぐ**。間違えるとリーダーが自重を支えられない or 重すぎて動かなくなる。

## Phase 4: 双腕の組立

ここで初めて 3D プリントパーツを使う。Joint 1〜6 + グリッパーの順で組む。組立は **2〜3 時間**見ておく（双腕分）。

公式の SO-101 ドキュメントの組立図に加え、日本語の組立記事を横に開きながらが圧倒的に楽：

- [ABEJA Tech Blog: SO-101 組み立てレポート](https://tech-blog.abeja.asia/entry/so101-assembly-report-202505)
- [Seeed K.K. ブログ: SO-101 を組み立てて動かしてみた](https://lab.seeed.co.jp/entry/2025/09/19/120000)
- [SO-101 公式組立ガイド](https://huggingface.co/docs/lerobot/so101)

### 必要な工具
- 2.0mm / 2.5mm の六角レンチ（M2 / M3 ネジ用）
- 細いプラスドライバー（モーターホーン用）

## Phase 5: キャリブレーション

組立が終わってから：

```bash
bash scripts/calibrate.sh
```

CLI が「全関節をホームポジションに動かして Enter」「最大角まで動かして Enter」と指示する流れ。**個体差を吸収する重要工程**で、ここをサボると後の学習で再現性が崩れる。

キャリブレーション結果は LeRobot のデフォルト保存先（通常 `~/.cache/huggingface/lerobot/calibration/...`）に保存される。本リポジトリでは `.gitignore` でローカル管理にとどめる（個体に紐づくため）。

---

完了したら → [docs/workflow.md](workflow.md)（Phase 6〜9: テレオペ → データ収集 → 学習 → 推論）へ。
