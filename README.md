# YoYoEA_Multi_Entry_ML
YoYoEA_Multi_Entry_ML は YoYoEA_Multi_Entry の機械学習パイプラインを構成するリポジトリです。MetaTrader4 用の Market State Logger EA と、収集したログから特徴量生成・モデル学習・推論を行うスクリプト郡を同梱します。

## ディレクトリ構成
- `MQL4/Experts/MarketStateLogger.mq4` : M5 バーごとに市場状態を CSV へ記録する EA
- `MQL4/Include/` : StateLogger 向けの補助ライブラリ（必要に応じて追加）
- `docs/` : `market_state_logger_design.md`, `ml_config_pipeline.md` など仕様書
- `scripts/` : Python/PowerShell 等の ETL・学習・デプロイスクリプト
- `data/` : `raw_logs/`, `features/`, `models/`, `recommendations/` など成果物を保存（`.gitignore` で大型ファイル除外予定）

## ビルド手順
1. Windows 側に MetaEditor (MT4) を用意し、`Scripts/compile_StateLogger.ps1` 内の `$metaEditor`/`$targetMq4` を環境に合わせて調整します。
2. WSL/PowerShell から `pwsh ./Scripts/compile_StateLogger.ps1` を実行すると EX4 が `D:\Rakuten_MT4\MQL4\Experts\MarketStateLogger.ex4` へ配置され、ログは `../shared/Compile_log/StateLogger_<timestamp>.log` に保存されます。
3. MT4 の Strategy Tester で M5 チャートにアタッチし、`StateLog_<Symbol>_<TF>_<YYYYMMDD>.csv` が `MQL4/Files` に出力されることを確認してください。

## データパイプライン
1. **収集**: StateLogger (M5) + YoYoEA_Multi_Entry の `TradeLog`/`SignalLog` を `shared/analysis/raw_logs/YYYYMMDD` に集約。
2. **前処理**: `scripts/etl/*.py` で CSV を結合し、特徴量テーブルを `data/features/<profile>_<yyyymm>.parquet` へ保存。
3. **学習/評価**: `scripts/train_xgboost.py` 等で walk-forward 検証、指標 (PF, 勝率, 最大DD) を `docs/` に記録。
4. **推論**: 最新特徴量から `recommendations/config_<profile>_<timestamp>.csv` を生成し、YoYoEA_Multi_Entry の Config 更新に利用。

## ログ仕様
- CSV は UTF-8 / ISO8601。`run_id` をキーに EA 側ログと連携。
- 主要列は設計書 `docs/market_state_logger_design.md` を参照。列追加時は必ず同書と ETL スクリプトを更新してください。

## 依存ライブラリ（想定）
- Python 3.10+
- pandas / numpy / xgboost / scikit-learn / optuna (任意)

## 次のステップ
- `scripts/` と `data/` の初期テンプレートを追加し、ETL スケルトンを実装。
- YoYoEA_Multi_Entry 側で `SignalLog` 拡張を行い、StateLog と結合できる形を整備。
