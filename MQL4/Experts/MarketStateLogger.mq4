#property strict
#property copyright "YoYoEA_Multi_Entry"
#property link      "https://example.com"
#property description "Market state logging EA for YoYoEA_Multi_Entry ML pipeline"

input string           InpProfileName            = "Default";
input string           InpRunId                  = "";
input ENUM_TIMEFRAMES  InpTargetTimeframe        = PERIOD_M5;
input int              InpAtrFastPeriod          = 14;
input int              InpAtrSlowPeriod          = 50;
input int              InpAdxPeriod              = 14;
input int              InpMaFastPeriod           = 20;
input int              InpMaSlowPeriod           = 50;
input int              InpMaLongPeriod           = 200;
input int              InpBollPeriod             = 20;
input double           InpBollDeviation          = 2.0;
input int              InpDonchianPeriod         = 20;
input int              InpFiboLookback           = 20;
input int              InpSlopeLookback          = 5;
input int              InpSessionOffsetMinutes   = 540;
input int              InpTimerSeconds           = 2;
input bool             InpFlushEveryWrite        = false;
input bool             InpWriteHeader            = true;
input bool             InpVerboseLog             = false;
input double           InpAtrLowThreshold        = 0.2;
input double           InpAtrHighThreshold       = 0.8;
input double           InpSpreadHighThreshold    = 2.5;

enum ENUM_VOLATILITY
  {
   VOL_LOW = 0,
   VOL_NORMAL,
   VOL_HIGH
  };

struct StateMetrics
  {
   bool              valid;
   datetime          bar_time;
   datetime          timestamp;
   string            session;
   string            notes;
   ENUM_VOLATILITY   volatility_flag;
   int               weekday;
   double            open_price;
   double            high_price;
   double            low_price;
   double            close_price;
   double            atr_fast;
   double            atr_slow;
   double            adx_main;
   double            ma_fast;
   double            ma_slow;
   double            ma_long;
   double            ma_slope;
   double            bb_width;
   double            donchian_width;
   double            fibo_ratio;
   double            spread_pips;
  };

int                 g_fileHandle      = INVALID_HANDLE;
datetime            g_lastBarTime     = 0;
datetime            g_currentLogDate  = 0;
string              g_logFilePath     = "";
string              g_runId           = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(Period() != InpTargetTimeframe)
     {
      PrintFormat("[StateLogger] Attach to %s timeframe chart. Current: %s", EnumToTfString(InpTargetTimeframe), EnumToTfString((ENUM_TIMEFRAMES)Period()));
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_runId = (StringLen(InpRunId) > 0) ? InpRunId : BuildAutoRunId();
   g_lastBarTime = iTime(_Symbol, InpTargetTimeframe, 0);
   if(g_lastBarTime == 0)
     {
      Print("[StateLogger] Unable to fetch initial bar time");
      return(INIT_FAILED);
     }

   if(InpTimerSeconds > 0)
      EventSetTimer(InpTimerSeconds);

   datetime now = TimeCurrent();
   g_logFilePath = BuildLogFileName(now);
   g_currentLogDate = DateOf(now);

   if(!OpenLogFile(g_logFilePath))
      return(INIT_FAILED);

   PrintFormat("[StateLogger] Init complete. Log %s run_id=%s", g_logFilePath, g_runId);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpTimerSeconds > 0)
      EventKillTimer();

   CloseLogFile();
   PrintFormat("[StateLogger] Deinit reason=%d", reason);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ProcessBar();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   ProcessBar();
  }

//+------------------------------------------------------------------+
void ProcessBar()
  {
   datetime currentBar = iTime(_Symbol, InpTargetTimeframe, 0);
   if(currentBar == 0)
      return;

   if(g_lastBarTime == 0)
      g_lastBarTime = currentBar;

   if(currentBar == g_lastBarTime)
      return;

   if(InpVerboseLog)
      PrintFormat("[StateLogger] New bar detected %s", TimeToString(currentBar, TIME_DATE|TIME_MINUTES));

   datetime completedBar = iTime(_Symbol, InpTargetTimeframe, 1);
   if(completedBar == 0)
      return;

   g_lastBarTime = currentBar;
   if(!RotateLogIfNeeded(completedBar))
      return;

   StateMetrics metrics;
   if(!CaptureState(1, completedBar, metrics))
      return;

   AppendRow(metrics);
  }

//+------------------------------------------------------------------+
bool CaptureState(const int shift, const datetime barTime, StateMetrics &out)
  {
   InitMetrics(out);
   out.bar_time = barTime;
   out.timestamp = TimeCurrent();
   out.weekday = TimeDayOfWeek(barTime);
   out.session = DetermineSessionLabel(barTime);

   out.open_price = iOpen(_Symbol, InpTargetTimeframe, shift);
   out.high_price = iHigh(_Symbol, InpTargetTimeframe, shift);
   out.low_price = iLow(_Symbol, InpTargetTimeframe, shift);
   out.close_price = iClose(_Symbol, InpTargetTimeframe, shift);

   if(!IsValidPrice(out.open_price) || !IsValidPrice(out.close_price))
     {
      out.notes = "price_na";
      return(false);
     }

   out.atr_fast = iATR(_Symbol, InpTargetTimeframe, InpAtrFastPeriod, shift);
   out.atr_slow = iATR(_Symbol, InpTargetTimeframe, InpAtrSlowPeriod, shift);
   out.adx_main = iADX(_Symbol, InpTargetTimeframe, InpAdxPeriod, PRICE_CLOSE, MODE_MAIN, shift);

   out.ma_fast = iMA(_Symbol, InpTargetTimeframe, InpMaFastPeriod, 0, MODE_SMA, PRICE_CLOSE, shift);
   out.ma_slow = iMA(_Symbol, InpTargetTimeframe, InpMaSlowPeriod, 0, MODE_SMA, PRICE_CLOSE, shift);
   out.ma_long = iMA(_Symbol, InpTargetTimeframe, InpMaLongPeriod, 0, MODE_SMA, PRICE_CLOSE, shift);
   out.ma_slope = CalcSlope(InpMaFastPeriod, InpSlopeLookback, shift);

   out.bb_width = CalcBollingerWidth(shift);
   out.donchian_width = CalcDonchianWidth(InpDonchianPeriod, shift);
   out.fibo_ratio = CalcFiboRatio(InpFiboLookback, shift, out.close_price);
   out.spread_pips = CalcSpreadPips();
   out.volatility_flag = DeriveVolatility(out);

   out.valid = true;
   return(true);
  }

//+------------------------------------------------------------------+
void AppendRow(StateMetrics &metrics)
  {
   if(g_fileHandle == INVALID_HANDLE)
      return;

   string csvLine = BuildCsvLine(metrics);
   FileSeek(g_fileHandle, 0, SEEK_END);
   FileWriteString(g_fileHandle, csvLine);
   FileWriteString(g_fileHandle, "\n");
   if(InpFlushEveryWrite)
      FileFlush(g_fileHandle);
  }

//+------------------------------------------------------------------+
bool OpenLogFile(const string filePath)
  {
   CloseLogFile();
   int flags = FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE;
   g_fileHandle = FileOpen(filePath, flags, ';');
   if(g_fileHandle == INVALID_HANDLE)
     {
      PrintFormat("[StateLogger] Failed to open %s. Error %d", filePath, GetLastError());
      return(false);
     }

   if(FileSize(g_fileHandle) == 0 && InpWriteHeader)
      WriteHeader();

   FileSeek(g_fileHandle, 0, SEEK_END);
   return(true);
  }

//+------------------------------------------------------------------+
void WriteHeader()
  {
   if(g_fileHandle == INVALID_HANDLE)
      return;

   string header = "timestamp;bar_time;run_id;profile;symbol;timeframe;open;high;low;close;"+
                   "atr_fast;atr_slow;adx14;ma_fast;ma_slow;ma_long;ma_slope;bb_width;donchian_width;"+
                   "fibo_ratio;spread;session;weekday;volatility;notes";
   FileWriteString(g_fileHandle, header);
   FileWriteString(g_fileHandle, "\n");
  }

//+------------------------------------------------------------------+
void CloseLogFile()
  {
   if(g_fileHandle != INVALID_HANDLE)
     {
      FileClose(g_fileHandle);
      g_fileHandle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
bool RotateLogIfNeeded(const datetime barTime)
  {
   datetime day = DateOf(barTime);
   if(day == g_currentLogDate && g_fileHandle != INVALID_HANDLE)
      return(true);

   g_currentLogDate = day;
   g_logFilePath = BuildLogFileName(barTime);
   return(OpenLogFile(g_logFilePath));
  }

//+------------------------------------------------------------------+
void InitMetrics(StateMetrics &s)
  {
   s.valid = false;
   s.session = "";
   s.notes = "";
   s.volatility_flag = VOL_NORMAL;
  }

//+------------------------------------------------------------------+
double CalcSlope(const int maPeriod, const int lookback, const int shift)
  {
   if(lookback <= 0)
      return(0.0);

   double current = iMA(_Symbol, InpTargetTimeframe, maPeriod, 0, MODE_SMA, PRICE_CLOSE, shift);
   double past = iMA(_Symbol, InpTargetTimeframe, maPeriod, 0, MODE_SMA, PRICE_CLOSE, shift + lookback);
   double pip = PipSize();
   if(pip == 0.0)
      pip = _Point;
   return((current - past) / (lookback * pip));
  }

//+------------------------------------------------------------------+
double CalcBollingerWidth(const int shift)
  {
   double upper = iBands(_Symbol, InpTargetTimeframe, InpBollPeriod, 0, InpBollDeviation, PRICE_CLOSE, MODE_UPPER, shift);
   double lower = iBands(_Symbol, InpTargetTimeframe, InpBollPeriod, 0, InpBollDeviation, PRICE_CLOSE, MODE_LOWER, shift);
   return(MathMax(upper - lower, 0.0));
  }

//+------------------------------------------------------------------+
double CalcDonchianWidth(const int period, const int shift)
  {
   if(period <= 0)
      return(0.0);

   double highest = -DBL_MAX;
   double lowest = DBL_MAX;
   for(int i=0; i<period; i++)
     {
      double h = iHigh(_Symbol, InpTargetTimeframe, shift + i);
      double l = iLow(_Symbol, InpTargetTimeframe, shift + i);
      if(h > highest)
         highest = h;
      if(l < lowest)
         lowest = l;
     }

   if(highest <= -DBL_MAX || lowest >= DBL_MAX)
      return(0.0);

   return(highest - lowest);
  }

//+------------------------------------------------------------------+
double CalcFiboRatio(const int period, const int shift, const double closePrice)
  {
   if(period <= 0)
      return(0.5);

   double highest = -DBL_MAX;
   double lowest = DBL_MAX;
   for(int i=0; i<period; i++)
     {
      double h = iHigh(_Symbol, InpTargetTimeframe, shift + i);
      double l = iLow(_Symbol, InpTargetTimeframe, shift + i);
      if(h > highest)
         highest = h;
      if(l < lowest)
         lowest = l;
     }

   if(highest <= lowest)
      return(0.5);

   return(MathMin(MathMax((closePrice - lowest) / (highest - lowest), 0.0), 1.0));
  }

//+------------------------------------------------------------------+
double CalcSpreadPips()
  {
   double spreadPoints = MarketInfo(_Symbol, MODE_SPREAD);
   double pip = PipSize();
   if(pip == 0.0)
      return(spreadPoints);
   return(spreadPoints * _Point / pip);
  }

//+------------------------------------------------------------------+
ENUM_VOLATILITY DeriveVolatility(const StateMetrics &metrics)
  {
   if(metrics.atr_fast >= InpAtrHighThreshold || metrics.spread_pips >= InpSpreadHighThreshold)
      return(VOL_HIGH);
   if(metrics.atr_fast <= InpAtrLowThreshold)
      return(VOL_LOW);
   return(VOL_NORMAL);
  }

//+------------------------------------------------------------------+
string BuildCsvLine(const StateMetrics &m)
  {
   string volatility = VolatilityToString(m.volatility_flag);
   string line = StringFormat("%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s",
                              FormatDateTime(m.timestamp),
                              FormatDateTime(m.bar_time),
                              g_runId,
                              InpProfileName,
                              _Symbol,
                              EnumToTfString(InpTargetTimeframe),
                              DoubleToString(m.open_price, _Digits),
                              DoubleToString(m.high_price, _Digits),
                              DoubleToString(m.low_price, _Digits),
                              DoubleToString(m.close_price, _Digits),
                              DoubleToString(m.atr_fast, 6),
                              DoubleToString(m.atr_slow, 6),
                              DoubleToString(m.adx_main, 6),
                              DoubleToString(m.ma_fast, 6),
                              DoubleToString(m.ma_slow, 6),
                              DoubleToString(m.ma_long, 6),
                              DoubleToString(m.ma_slope, 6),
                              DoubleToString(m.bb_width, 6),
                              DoubleToString(m.donchian_width, 6),
                              DoubleToString(m.fibo_ratio, 6),
                              DoubleToString(m.spread_pips, 4),
                              m.session,
                              IntegerToString(m.weekday),
                              volatility,
                              m.notes);
   return(line);
  }

//+------------------------------------------------------------------+
string VolatilityToString(const ENUM_VOLATILITY v)
  {
   if(v == VOL_HIGH)
      return("HIGH");
   if(v == VOL_LOW)
      return("LOW");
   return("NORMAL");
  }

//+------------------------------------------------------------------+
string DetermineSessionLabel(const datetime barTime)
  {
   datetime adjusted = barTime + InpSessionOffsetMinutes * 60;
   int hour = TimeHour(adjusted);

   if(hour >= 8 && hour < 15)
      return("ASIA");
   if(hour >= 15 && hour < 22)
      return("EUROPE");
   if(hour >= 22 || hour < 5)
      return("US");
   return("OTHER");
  }

//+------------------------------------------------------------------+
string BuildLogFileName(const datetime dt)
  {
   string dateStr = TimeToString(dt, TIME_DATE);
   StringReplace(dateStr, ".", "");
   return(StringFormat("StateLog_%s_%s_%s.csv", _Symbol, EnumToTfString(InpTargetTimeframe), dateStr));
  }

//+------------------------------------------------------------------+
string EnumToTfString(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:   return("M1");
      case PERIOD_M5:   return("M5");
      case PERIOD_M15:  return("M15");
      case PERIOD_M30:  return("M30");
      case PERIOD_H1:   return("H1");
      case PERIOD_H4:   return("H4");
      case PERIOD_D1:   return("D1");
      case PERIOD_W1:   return("W1");
      case PERIOD_MN1:  return("MN1");
     }
   return(IntegerToString(tf));
  }

//+------------------------------------------------------------------+
string BuildAutoRunId()
  {
   string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   StringReplace(ts, ":", "");
   StringReplace(ts, ".", "");
   StringReplace(ts, " ", "");
   return(StringFormat("%s_%s", _Symbol, ts));
  }

//+------------------------------------------------------------------+
double PipSize()
  {
   if(_Digits == 3 || _Digits == 5)
      return(10 * _Point);
   return(_Point);
  }

//+------------------------------------------------------------------+
bool IsValidPrice(const double price)
  {
   return(price > 0 && price < DBL_MAX);
  }

//+------------------------------------------------------------------+
datetime DateOf(const datetime t)
  {
   MqlDateTime mt;
   TimeToStruct(t, mt);
   mt.hour = 0;
   mt.min = 0;
   mt.sec = 0;
   return(StructToTime(mt));
  }

//+------------------------------------------------------------------+
string FormatDateTime(const datetime dt)
  {
   return(TimeToString(dt, TIME_DATE|TIME_SECONDS));
  }
