# so101-lab

HuggingFace [LeRobot](https://github.com/huggingface/lerobot) × SO-101 双腕ロボットアームで、模倣学習・VLA・強化学習を手元で回すための作業ノート＆スクリプト集。

## このリポジトリの目的

SO-101（オープンソースの双腕ロボットアーム）を題材に、**実機で模倣学習のパイプラインを一周させる**ための個人的な作業記録です。

「データ収集 → 学習 → 軽量化 → リアルタイム推論ループ」という MLOps 的な一連の流れを、シミュレーションではなく手元の実機で最小構成から回し、どこに落とし穴があるのかを一次情報として残すことを目的にしています。アプリケーションではなく、`lerobot-*` CLI を薄く包む bash スクリプト群と、フェーズごとの作業ノート（`docs/`）で構成されています。

## ハードウェア構成

| 部品 | 入手元 | 価格 |
|---|---|---|
| SO-101 オープンソースロボットアームキット | [秋月電子通商 131169](https://akizukidenshi.com/catalog/g/g131169/) | ¥39,980 |
| 3D プリントパーツ | [秋月電子通商 131222](https://akizukidenshi.com/catalog/g/g131222/) | （別売） |
| USB Web カメラ（Logicool C270n 等） | Amazon | ¥2,500 |

サーボは Feetech STS3215 ×12（フォロワー 6 + リーダー 6）。リーダーはギア比違い（1:191×2, 1:147×3, 1:345×1）。

## ロードマップ

| Phase | やること | ドキュメント |
|---|---|---|
| 0 | 開封チェック | [docs/setup.md](docs/setup.md) |
| 1 | LeRobot 環境構築 + HF 連携 | [docs/setup.md](docs/setup.md) |
| 2 | USB ポート特定 | [docs/setup.md](docs/setup.md) |
| 3 | モーター ID & ボーレート設定（組立前） | [docs/setup.md](docs/setup.md) |
| 4 | 双腕の組立 | [docs/setup.md](docs/setup.md) |
| 5 | キャリブレーション | [docs/setup.md](docs/setup.md) |
| 6 | テレオペ動作確認 | [docs/workflow.md](docs/workflow.md) |
| 7 | データセット収集（HF Hub に push） | [docs/workflow.md](docs/workflow.md) |
| 8 | ポリシー学習（ACT / Diffusion / SmolVLA） | [docs/workflow.md](docs/workflow.md) |
| 9 | 学習済みポリシーで推論 | [docs/workflow.md](docs/workflow.md) |

## ディレクトリ構成

```
so101-lab/
├── README.md            # このファイル
├── docs/
│   ├── setup.md         # Phase 0-5（開封〜キャリブレーション）
│   └── workflow.md      # Phase 6-9（テレオペ → 収集 → 学習 → 推論）
└── scripts/
    ├── _env.sh.example  # 環境変数テンプレート（コピーして _env.sh を作る）
    ├── install.sh       # LeRobot + Feetech SDK
    ├── find-port.sh     # USB ポート特定
    ├── setup-motors-follower.sh
    ├── setup-motors-leader.sh
    ├── calibrate.sh     # 双腕キャリブレーション
    ├── teleoperate.sh   # テレオペ確認
    ├── record.sh        # データセット収集
    ├── train.sh         # ポリシー学習
    └── eval.sh          # 学習済みポリシーで推論
```

## 使い方

```bash
# 1. 環境変数を設定
cp scripts/_env.sh.example scripts/_env.sh
$EDITOR scripts/_env.sh   # FOLLOWER_PORT, LEADER_PORT, HF_USER などを埋める

# 2. 各 Phase を順に実行
bash scripts/install.sh
bash scripts/find-port.sh
bash scripts/setup-motors-follower.sh
bash scripts/setup-motors-leader.sh
# 組立 → bash scripts/calibrate.sh → bash scripts/teleoperate.sh
```

## 関連リソース

- [LeRobot 公式ドキュメント](https://huggingface.co/docs/lerobot)
- [SO-101 セットアップ手順 (公式)](https://huggingface.co/docs/lerobot/so101)
- [Imitation Learning on Real-World Robots (公式)](https://huggingface.co/docs/lerobot/il_robots)
- [TheRobotStudio/SO-ARM100 (BOM)](https://github.com/TheRobotStudio/SO-ARM100)
- [ABEJA Tech Blog: SO-101 組み立てレポート](https://tech-blog.abeja.asia/entry/so101-assembly-report-202505)
- [Seeed K.K. ブログ: SO-101 を組み立てて動かしてみた](https://lab.seeed.co.jp/entry/2025/09/19/120000)

## ログ

- 2026-05-09: キット到着、リポジトリ初期化
- 2026-06-21: uv 化。モーター設定 → 組立 → キャリブレーションまで完了
- 2026-06-22: テレオペ動作確認。双腕の追従デモを記録
- 2026-07-05: 学習なしで LLM に直接操縦させる実験（模倣学習の必要性を確認）→ [記事](https://qiita.com/yuAbe/items/b498be1d93103d587a7a)
- 2026-07-08: 手首カメラ追加、30Hz 安定化。lerobot 0.5.1 / Python 3.12 にピン留め
- 2026-07-09〜10: 「ブロックを掴んでカップに入れる」タスクを 50 エピソード収集 → ACT を学習（RTX A6000, 100k step）→ 実機評価。学習データへの操作者の写り込みで一度 0/10 に沈んだのを、原因を切り分けて成功率 60% まで復帰 → [デバッグ記録の記事](https://qiita.com/yuAbe/items/9611280b08f5114f8816)
- 2026-07-13: データを 50 → 102 エピソードに拡張して再学習。机を 3×3 に区切って成功率を可視化（学習分布内は 100%、分布外は 0%）→ [続きの記事](https://qiita.com/yuAbe/items/3e01faa4ad66ef6a6371)
