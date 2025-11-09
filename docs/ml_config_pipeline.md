# 機械学習ベースのConfig最適化仕様

## 目的
- YoYoEA_Multi_EntryのConfig（ATRバンドON/OFF、SL/TP/BE/Trail設定など）を市場状態に応じて自動・半自動で切り替える。
- 既存バックテスト/運用ログと新規に収集する市場状態ログを活用して、最適パラメータをXGBoostで推薦する。

## 全体アーキテクチャ
1. **Market State Logger EA**
   - M5チャートごとに稼働させ、各M5バー終値（OnTick/OnTimer）で ATR/ADX/MA傾き/BB幅/Spread/セッション等をCSV出力。
   - 出力先: `MQL4/Files/StateLog_<symbol>_<tf>.csv`
   - 主要列：`timestamp, symbol, timeframe, atr14, atr50, adx14, ma_fast, ma_slow, ma_slope, ma_long200, bb_width, fibo_ratio_20, spread, session, weekday`
2. **YoYoEA_Multi_Entry ログ拡張**
   - `ProcessStrategy` と `ExecuteEntry` 内でシグナル評価時の市場状態・Config情報を `SignalLog_<profile>.csv` に追記。
   - `TradeLog` と共通の `run_id`, `ticket`, `strategy` を保持し、ENTRY/EXIT結果と結合できる形にする。
3. **ETLスクリプト（Python）**
   - `StateLog`, `SignalLog`, `TradeLog`, `TradeParams` を読み込み、シグナル単位や時間帯単位で特徴量テーブルを生成。
   - 時系列分割で Train/Validation セットを作成。
4. **XGBoost 学習**
   - 目的1: 最適Config/ATRバンドIDを分類。
   - 目的2: SL/TP/BE/Trail 倍率を回帰。
   - 目的3: 期待損益/ドローダウンを回帰させ、閾値で採用／停止判断。
5. **推論とデプロイ**
   - 学習済みモデルを Python スクリプト化し、最新StateLog/SignalLogから特徴量を生成。
   - 推薦結果を `recommendations/config_<profile>.csv` 等に吐き出し、EAが参照するAtrBandConfig/TradeParamsを更新。
   - 手動レビュー→反映→MetaEditorコンパイルのフローを整備。

## 特徴量カテゴリ
- **市場状態系**: ATR複数期間（例:14/50）、標準偏差、ADX、MA差分（短期・長期）、長期MA値（200期間を基準とする）、BB幅、Donchian幅、直近20本の高安から算出したフィボナッチリトレースメント比率、価格レンジ、時間帯/曜日、スプレッド。
- **トレンド／レンジ指標**: MA傾き、価格チャネル比率、RSI/CCIの長期値、ADX閾値でのトレンド強度、レンジ滞在時間。
- **EA状態系**: 戦略別の直近PF/勝率/連敗数、保有ポジション数、含み損益、トレーリング状態。
- **Configメタデータ**: 現在のAtrBand行ID、SL/TP/BE/Trailの設定、MagicPrefix、Profile名。
- **外部要因**（任意）: カレンダー/祝日フラグ、Newsボラティリティ指標など。

## ラベル設計
- **分類**: 「今回の市場状態で採用すべきConfig ID」。過去実績から最もPFや損益が良かったConfigを教師ラベルにする。
- **回帰**: SL/TP/BE/Trail 倍率、期待損益、リスク指標（最大DD、Sharpe）を数値として学習。
- **閾値判定**: XGBoost出力をもとに `Enable/Disable` を決める二値分類も並行して実装可。

- `SignalLog` 仕様例:
  - 出力先: `MQL4/Files/SignalLog_<profile>.csv`
  - 列: `timestamp, run_id, profile, strategy, band_id, signal_direction, atr_value, adx14, ma_fast, ma_slow, ma_long200, fibo_ratio_20, spread, session, reason (placed/skipped_<cause>), param_snapshot_id`
  - ENTRY不成立でもシグナル毎に1行を記録し、`TradeLog` の `ticket`（発注済みのみ）と紐付くよう `pending_ticket` カラムを保持。

## データパイプライン
1. **収集**: Market State Logger + YoYoEA_Multi_Entry から日次CSVを収集し、`/analysis/raw_logs/YYYYMMDD/` に保存。
2. **前処理**: Python (`pandas`, `numpy`) で結合、欠損補完、ラベル生成。
3. **特徴量保存**: `analysis/features/<profile>_<yyyymm>.parquet` などで高速に保持。
4. **学習**: `xgboost` + `scikit-learn` で GridSearch/Optuna を利用したハイパーパラ最適化。
5. **評価**: 時系列分割で walk-forward 検証し、PF/勝率/最大DD/サンプル効率を指標に採用可否を判断。
6. **推論/デプロイ**: `scripts/recommend_configs.py`（仮）で最新特徴量に対し推論→`recommendations/` にConfig案を出力→レビュー後 `AtrBandConfig_*.csv` を更新。

### ディレクトリ例
- `analysis/raw_logs/YYYYMMDD/StateLog_*.csv`
- `analysis/raw_logs/YYYYMMDD/SignalLog_*.csv`
- `analysis/features/feature_table_<profile>_<yyyymm>.parquet`
- `analysis/models/xgboost_<profile>_<yyyymmdd>.json`
- `recommendations/config_<profile>_<timestamp>.csv`

## 実装メモ
- ログファイルはUTF-8、ISO日時で統一。run_id/ticket/profileをキーにする。
- 既存 `TradeLog` 書式は維持しつつ、SignalLogでシグナル採用/スキップ理由と市場指標を記録。
- Market State LoggerはMT4ヒストリー再生（バックテスト）でも動作するよう `OnTick` ベースで記録。
- Python環境: `python3.10+`, `pandas`, `numpy`, `xgboost`, `scikit-learn`, `optuna(任意)`。
- 推薦結果のレビュー手順をREADMEまたはMemoに追記し、誤適用を防止。
- 評価は walk-forward で各期間のPF/勝率/最大DDを比較し、閾値（例: PF>=1.1, 最大DD<=基準×1.2）を満たすモデルのみ採用。
