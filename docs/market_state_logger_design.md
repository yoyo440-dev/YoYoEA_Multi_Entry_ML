# Market State Logger EA 設計メモ

## 1. 目的とスコープ
- YoYoEA_Multi_Entry の機械学習パイプライン向けに、市場状態特徴量を低遅延で記録する MT4 EA（以下 StateLogger）を新規に作成する。
- M5 チャート単位で稼働し、各バー確定時のテクニカル指標・セッション情報・スプレッドを CSV (`MQL4/Files/StateLog_<Symbol>_<TF>.csv`) へ蓄積する。
- Strategy Tester（ヒストリカル再生）でも同じコードで動かし、バックテストログを再利用できることを必須要件とする。

## 2. 実行環境と前提条件
- 対象: MetaTrader 4 build 1380 以降を想定。3 スペースインデントを含む既存 CoDEX 規約に従う。
- チャート時間足: デフォルト PERIOD_M5。`input ENUM_TIMEFRAMES InpTargetTimeframe` で変更可。
- 取引サーバ時間は JST ではないため、`input int InpSessionOffsetMinutes` で東京時間への換算を行う。
- 複数チャートで同一ファイルに書き込む競合を避けるため、ファイルロックは行わずチャート別ファイル（シンボル×時間足×日付）方式を採用する。

## 3. データ取得タイミング
1. `OnInit`
   - バリデーション: 対象チャートの時間足が `InpTargetTimeframe` と一致しているか確認。
   - ログファイル名を確定 (`StateLog_<symbol>_<tf>_<YYYYMMDD>.csv`) し、ヘッダー有無を判定。
2. `OnTick`
   - `iTime(_Symbol, InpTargetTimeframe, 0)` を監視し、新しいバーに遷移した瞬間に計測。
   - テスターでティックが無い場合に備え `EventSetTimer(InpTimerSeconds)` を使い、`OnTimer` で同じロジックをフォールバックする。
3. `OnDeinit`
   - ファイルハンドルとタイマーを解放。

## 4. ログ列仕様
|列名|型|説明|
|---|---|---|
|`timestamp`|datetime|サーバ時刻（ISO8601 文字列で出力）。|
|`bar_time`|datetime|対象バーの開始時刻。|
|`run_id`|string|`InpRunId` または初期化時に生成する UUID 風文字列。|
|`symbol`|string|チャートシンボル。|
|`timeframe`|int|`PeriodSeconds(InpTargetTimeframe)` を記録。|
|`open,high,low,close`|double|対象バーの OHLC。|
|`atr14, atr50`|double|`iATR` による 14/50 期間 ATR。|
|`adx14`|double|`iADX` の 14 期間メインライン。|
|`ma_fast, ma_slow`|double|短期/中期単純移動平均。パラメータは extern 指定。|
|`ma_slope`|double|直近 `InpSlopeLookback` 本での MA ファースト差分（pips/バー）。|
|`ma_long200`|double|長期 200 SMA。|
|`bb_width`|double|ボリンジャーバンド上限−下限。期間/偏差は extern。|
|`donchian_width`|double|`iHigh/iLow` 20 本レンジ幅。|
|`fibo_ratio_20`|double|直近 20 本の (Close−Low)/(High−Low)。0〜1。|
|`spread`|double|`MarketInfo(_Symbol, MODE_SPREAD)`（pips 換算）。|
|`session`|string|`ASIA/EUROPE/US/OTHER`。`InpSessionOffsetMinutes` で補正。|
|`weekday`|int|`TimeDayOfWeek(bar_time)`。|
|`volatility_flag`|string|ATR・スプレッドなどの閾値による `LOW/NORMAL/HIGH`。|
|`notes`|string|異常時の警告メッセージ。通常は空。|

## 5. モジュール構成

### 5.1 ファイル・ロギング
- `bool OpenLogFile()`
  - `FileOpen(log_path, FILE_CSV|FILE_WRITE|FILE_READ|FILE_SHARE_WRITE|FILE_SHARE_READ, ';')` で開く。
  - 日付が変わったら `RotateLogIfNeeded()` を実行し、新ファイルに切り替え。
- `void WriteHeader()`
  - ファイル新規作成時に 1 度だけ列名を書き込む。`InpWriteHeader` で ON/OFF。
- `void AppendRow(const StateMetrics &metrics)`
  - `FileSeek(0, SEEK_END)` 済みで 1 行出力。`InpFlushEveryWrite` が true の場合 `FileFlush()`。

### 5.2 状態検出
- `bool IsNewBar()`
  - `datetime barTime = iTime(...);` と `g_lastBarTime` を比較して新バー判定。
- `void CaptureState(StateMetrics &out)`
  - すべてのインジケータ値を計算して `out` にセット。計算失敗時は `out.valid=false`。
- 指標計算
  - ATR/ADX/SMA/BB は組込み関数で取得。
  - Donchian 幅は `iHigh/iLow` で `ArrayMaximum/ArrayMinimum`。
  - フィボ比率は `HighMax-LowMin` が 0 の場合は `0.5` を返す。
  - スプレッドは `MarketInfo` または `SymbolInfoInteger` (build 1320+)。

### 5.3 セッション判定
- `ENUM_SESSION DetermineSession(datetime ts)`
  - サーバ時間に `InpSessionOffsetMinutes` を加算後、東京 08:00-15:00 → `ASIA`、ロンドン 15:00-22:00 → `EUROPE`、ニューヨーク 22:00-05:00 → `US`。
  - どれにも当てはまらない場合 `OTHER`。

### 5.4 アラート/エラー
- 主要エラーは `PrintFormat` でターミナルへ通知し、`notes` 列に簡易メッセージを挿入。
- ファイルが開けない、インジ計算が失敗した場合は `ExpertRemove()` で強制停止し、人為的な気付きやすさを確保。

## 6. extern 入力とグローバル変数

### 6.1 extern 入力（案）
|名称|型|初期値|用途|
|---|---|---|---|
|`InpProfileName`|string|"Default"|ログと run_id に刻印し、分析側と紐付ける。|
|`InpRunId`|string|""|未設定なら `Symbol()+TimeCurrent()` で自動生成。|
|`InpTargetTimeframe`|ENUM_TIMEFRAMES|PERIOD_M5|ロギング対象の時間足。|
|`InpAtrFastPeriod`|int|14|ATR(1) の期間。|
|`InpAtrSlowPeriod`|int|50|ATR(2) の期間。|
|`InpAdxPeriod`|int|14|ADX の期間。|
|`InpMaFastPeriod`|int|20|短期 MA。|
|`InpMaSlowPeriod`|int|50|中期 MA。|
|`InpMaLongPeriod`|int|200|長期 MA。|
|`InpBollPeriod`|int|20|BB の期間。|
|`InpBollDeviation`|double|2.0|BB 偏差。|
|`InpDonchianPeriod`|int|20|Donchian 幅計算本数。|
|`InpFiboLookback`|int|20|フィボ比率算出本数。|
|`InpSlopeLookback`|int|5|MA 傾き計算に使う過去本数。|
|`InpSessionOffsetMinutes`|int|540|サーバ→JST 変換 (例: 9 時間)。|
|`InpTimerSeconds`|int|2|フォールバックタイマー間隔。0 で無効。|
|`InpFlushEveryWrite`|bool|false|1 行ごとに `FileFlush` 実行。|
|`InpWriteHeader`|bool|true|ヘッダー出力 ON/OFF。|
|`InpVerboseLog`|bool|false|デバッグログ出力レベル。|

### 6.2 グローバル状態
- `int g_fileHandle = INVALID_HANDLE;`
- `datetime g_lastBarTime = 0;`
- `string g_logFilePath;`
- `string g_runId;`
- `datetime g_currentLogDate;`

## 7. ファイル配置と成果物
- EA 本体: `YoYoEA_Multi_Entry_ML/MQL4/Experts/MarketStateLogger.mq4`
- 共通関数（必要なら）: `YoYoEA_Multi_Entry_ML/MQL4/Include/MarketStateLogger/utils.mqh`
- ドキュメント: 本ファイル `docs/market_state_logger_design.md`
- バックテスト用セット: 今後 `presets/StateLogger/*.set` を作成予定。

## 8. 運用フロー
1. 収集対象シンボルの M5 チャートへ StateLogger をアタッチ。
2. 日次で `analysis/raw_logs/<date>/StateLog_<symbol>_<tf>.csv` にコピー。
3. ETL スクリプトが `run_id` で YoYoEA_Multi_Entry の Signal/Trade ログと結合。
4. 学習済みモデルが Config 推薦を出力し、レビュー後に本番 Config へ反映。

## 9. 今後の ToDo
1. `MarketStateLogger.mq4` の骨組み生成（#property, extern 入力, OnInit/OnTick/OnTimer）。
2. 各インジケータ取得と `StateMetrics` 構造体の実装。
3. CSV ローテーションと例外処理のユニットテスト（Strategy Tester での単体検証）。
4. README へ StateLogger ワークフローの追記。
