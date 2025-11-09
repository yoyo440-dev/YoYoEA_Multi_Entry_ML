# Repository Guidelines (YoYoEA_Multi_Entry_ML)

## CODEX
- 会話は日本語でお願いします。
- StateLogger / ML 周りの作業ログは `Codex_memo/` 配下にある Markdown（例: `Codex_memo/state_logger_tasks.md`）へ記載し、概要を `YoYoEA_Multi_Entry/Memo/memo.txt` にも転記して全体履歴を同期してください。
- コード/データ処理のアクションは時刻・内容・結果・次アクションを明記してください。

## 構成
- EA: `MQL4/Experts/MarketStateLogger.mq4`
- 追加モジュール: `MQL4/Include/`（必要に応じて `MarketStateLogger/*.mqh` を配置）。
- ドキュメント: `docs/`（`market_state_logger_design.md`, `ml_config_pipeline.md` ほか）。
- Python/ETL 等の自動化スクリプトは `scripts/`、生成データは `data/`（`raw_logs/`, `features/`, `models/`, `recommendations/` 等サブフォルダ）へ配置。
- 共有成果物は `../shared/analysis`・`../shared/Compile_log` を利用。

## ビルド・デプロイ
- StateLogger のコンパイルは `pwsh ./Scripts/compile_StateLogger.ps1` を使用。`metaeditor.exe` やログディレクトリは必要に応じて書き換え。
- 生成された `MarketStateLogger.ex4` を MT4 の `MQL4/Experts` に配置し、M5 チャート専用で動作確認。
- CSV は `MQL4/Files/StateLog_<Symbol>_<TF>_<YYYYMMDD>.csv` 命名、`shared/analysis/raw_logs` に日次で退避。

## コーディング規約
- MQL4 部分は YoYoEA_Multi_Entry と同様に 3 スペースインデント、接頭辞規約 (`Inp*`, `g_*`, `k*`) を踏襲。
- Python/ETL は PEP8 を参考にしつつ、モジュール化と型ヒントを推奨。
- ログは UTF-8 / ISO8601 で統一し、`run_id` をキーに YoYoEA_Multi_Entry の Signal/Trade ログと結合できる形式を守る。

## テスト
- Strategy Tester / 実チャート双方で `OnTick` と `OnTimer` フォールバックが動作するか確認。
- CSV ヘッダーや列数変更時は `docs/market_state_logger_design.md` を更新し、ETL スクリプトの互換性を担保。
- ML モデル更新時は `data/models/` にバージョン別サブフォルダを作成し、評価メトリクスを `docs/` に整理。

## コミット/PR
- 変更粒度は小さく、件名に対象 (`StateLogger`, `ETL`, `ML`) を含める（例: `StateLogger: add volatility flag columns`）。
- データ/ログ類は原則コミットしない（必要なサンプルは `data/samples/` に最小限）。`.gitignore` を活用。
- PR には実行コマンド、出力サンプル、必要ならバックテスト条件を添付し、`Memo/memo.txt` を更新してから提出。
