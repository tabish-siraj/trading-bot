//+------------------------------------------------------------------+
//|                                        GoldTrendPullbackEA.mq5   |
//|  v0.2 - Base EA for XAUUSD. Demo-locked by default.              |
//|                                                                  |
//|  Strategy: trend-pullback (PLACEHOLDER; replaced in Phase 2)     |
//|   - Trend filter : EMA(fast) vs EMA(slow) + price vs slow EMA    |
//|   - Entry        : RSI crosses back through a level (pullback    |
//|                    ended), evaluated on the CLOSED bar only      |
//|   - Filters      : ATR minimum, session, Friday                  |
//|   - Exits        : ATR-based SL/TP, optional time stop           |
//|                                                                  |
//|  Risk: delegated to risk/RiskLayer.mqh. This EA no longer        |
//|  contains sizing or cap rules. It only supplies context and      |
//|  executes the approved decision.                                 |
//|                                                                  |
//|  NOT financial advice. No profitability is claimed or implied.   |
//+------------------------------------------------------------------+
#property copyright "Gold bot project"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include "risk/RiskAdapter.mqh"

//--- inputs --------------------------------------------------------
input group "=== Safety ==="
input bool             InpDemoOnly        = true;     // Refuse to run on a live/real account
input long             InpMagic           = 26112401; // Magic number (unique per EA/symbol)
input string           InpComment         = "GoldTPB";// Order comment

input group "=== Strategy ==="
input ENUM_TIMEFRAMES  InpTF              = PERIOD_M15; // Signal timeframe
input int              InpEmaFast         = 50;
input int              InpEmaSlow         = 200;
input int              InpRsiPeriod       = 14;
input double           InpRsiLongLevel    = 40.0;   // Long: RSI crosses UP through this
input double           InpRsiShortLevel   = 60.0;   // Short: RSI crosses DOWN through this
input int              InpAtrPeriod       = 14;
input double           InpMinAtr          = 1.50;   // Min ATR in PRICE units (USD) to trade
input double           InpSlAtrMult       = 1.5;    // Stop-loss = ATR * this
input double           InpTpAtrMult       = 3.0;    // Take-profit = ATR * this
input int              InpMaxBarsInTrade  = 48;     // Time stop in bars (0 = off)

input group "=== Filters ==="
input double           InpMaxSpread       = 0.40;   // Max spread in PRICE units (USD)
input int              InpStartHour       = 7;      // Session start (SERVER time)
input int              InpEndHour         = 20;     // Session end   (SERVER time, exclusive)
input int              InpFridayCutoffHour= 18;     // No new trades on Friday from this hour

input group "=== Risk ==="
input bool             InpRiskOnEquity    = true;   // Size and cap from equity (recommended)
input double           InpRiskPct         = 0.5;    // Risk per trade, % of base
input double           InpMaxLots         = 1.0;    // Hard cap on lot size
input double           InpMaxDailyLossPct = 2.0;    // Stop for the day at this % loss
input int              InpMaxConsecLosses = 3;      // Stop for the day after N losses in a row
input int              InpMaxTradesPerDay = 5;      // Max new entries per server day
input double           InpMaxMarginUsagePct = 80.0; // Max % of free margin used by one order
input int              InpDeviationPts    = 30;     // Max slippage in points

//--- globals -------------------------------------------------------
CTrade     trade;
RiskLimits g_risk;
int        hFast = INVALID_HANDLE;
int        hSlow = INVALID_HANDLE;
int        hRsi  = INVALID_HANDLE;
int        hAtr  = INVALID_HANDLE;
datetime   g_lastBar = 0;
string     g_status  = "";

//+------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(_Symbol, "XAU") < 0)
   {
      Print("GoldTPB: this EA is for gold only. Attach it to an XAUUSD chart. Symbol=", _Symbol);
      return INIT_FAILED;
   }

   if(InpDemoOnly && AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("GoldTPB: InpDemoOnly is true but this is not a demo account. Refusing to start.");
      return INIT_FAILED;
   }

   if(InpEmaFast >= InpEmaSlow)
   {
      Print("GoldTPB: EmaFast must be smaller than EmaSlow.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpStartHour < 0 || InpStartHour > 23 ||
      InpEndHour < 1 || InpEndHour > 24 || InpStartHour >= InpEndHour)
   {
      Print("GoldTPB: invalid session hours.");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Copy inputs into the fixed risk config.
   RiskLimitsInit(g_risk);
   g_risk.demoOnly             = InpDemoOnly;
   g_risk.useEquity            = InpRiskOnEquity;
   g_risk.riskPctPerTrade      = InpRiskPct;
   g_risk.maxLots              = InpMaxLots;
   g_risk.maxDailyLossPct      = InpMaxDailyLossPct;
   g_risk.maxConsecutiveLosses = InpMaxConsecLosses;
   g_risk.maxTradesPerDay      = InpMaxTradesPerDay;
   g_risk.maxSpreadPrice       = InpMaxSpread;
   g_risk.onePositionAtATime   = true;
   g_risk.maxMarginUsagePct    = InpMaxMarginUsagePct;

   hFast = iMA(_Symbol, InpTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, InpTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hRsi  = iRSI(_Symbol, InpTF, InpRsiPeriod, PRICE_CLOSE);
   hAtr  = iATR(_Symbol, InpTF, InpAtrPeriod);

   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE ||
      hRsi  == INVALID_HANDLE || hAtr  == INVALID_HANDLE)
   {
      Print("GoldTPB: failed to create indicator handles. Error=", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   PrintFormat("GoldTPB v0.2 started on %s %s | digits=%d point=%g | risk=%.2f%% on %s",
               _Symbol, EnumToString(InpTF), _Digits, _Point, InpRiskPct,
               (InpRiskOnEquity ? "equity" : "balance"));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hFast != INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hRsi  != INVALID_HANDLE) IndicatorRelease(hRsi);
   if(hAtr  != INVALID_HANDLE) IndicatorRelease(hAtr);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Everything runs once per new bar; signals use the last CLOSED bar.
   if(!IsNewBar()) return;

   // 1) Manage any open position (time stop). Execution, not risk.
   ulong    ticket;
   long     ptype;
   datetime popen;
   if(RiskAdapterOwnPosition(ticket, ptype, popen, _Symbol, InpMagic))
   {
      if(InpMaxBarsInTrade > 0)
      {
         long barsHeld = (long)((TimeCurrent() - popen) / PeriodSeconds(InpTF));
         if(barsHeld >= InpMaxBarsInTrade)
         {
            if(trade.PositionClose(ticket))
               PrintFormat("GoldTPB: time stop, closed #%I64u after %d bars", ticket, (int)barsHeld);
            else
               PrintFormat("GoldTPB: time-stop close FAILED #%I64u ret=%d (%s)",
                           ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         }
      }
      SetStatus("Position open - waiting");
      return;
   }

   // 2) Time / session filters (strategy; TODO Phase 2: move to UTC).
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour)
   { SetStatus("Outside session"); return; }
   if(dt.day_of_week == 5 && dt.hour >= InpFridayCutoffHour)
   { SetStatus("Friday cutoff"); return; }
   if(dt.day_of_week == 0 || dt.day_of_week == 6)
   { SetStatus("Weekend"); return; }

   // 3) Signal.
   double atr;
   int dir = GetSignal(atr);
   if(dir == 0) { SetStatus("No signal"); return; }

   // 4) Risk decision.
   double stopDist = InpSlAtrMult * atr;
   RiskContext ctx;
   RiskAdapterBuildContext(ctx, InpMagic, _Symbol, dir, 0.0);

   RiskOrder order;
   RiskOrderInit(order);
   order.direction         = dir;
   order.stopDistancePrice = stopDist;
   order.entryPrice        = (dir > 0) ? ctx.ask : ctx.bid;

   RiskDecision decision;
   RiskEvaluate(g_risk, ctx, order, decision);
   if(decision.action == RISK_ACTION_REJECT)
   {
      SetStatus(StringFormat("RISK %s: %s", RiskCodeToString(decision.code), decision.reason));
      return;
   }

   // 5) Execute.
   OpenTrade(dir, atr, decision.lots, stopDist);
}

//+------------------------------------------------------------------+
//| Returns +1 long, -1 short, 0 none. atr = ATR of last closed bar. |
//+------------------------------------------------------------------+
int GetSignal(double &atr)
{
   double f[], s[], r[], a[];
   ArraySetAsSeries(f, true);
   ArraySetAsSeries(s, true);
   ArraySetAsSeries(r, true);
   ArraySetAsSeries(a, true);

   // start_pos=1 -> index 0 = last closed bar (shift 1), index 1 = shift 2
   if(CopyBuffer(hFast, 0, 1, 2, f) < 2) return 0;
   if(CopyBuffer(hSlow, 0, 1, 2, s) < 2) return 0;
   if(CopyBuffer(hRsi,  0, 1, 2, r) < 2) return 0;
   if(CopyBuffer(hAtr,  0, 1, 1, a) < 1) return 0;

   atr = a[0];
   if(atr < InpMinAtr) return 0;

   double close1 = iClose(_Symbol, InpTF, 1);
   if(close1 <= 0) return 0;

   // Uptrend + RSI crosses back UP through the long level
   if(f[0] > s[0] && close1 > s[0] && r[1] < InpRsiLongLevel && r[0] >= InpRsiLongLevel)
      return 1;

   // Downtrend + RSI crosses back DOWN through the short level
   if(f[0] < s[0] && close1 < s[0] && r[1] > InpRsiShortLevel && r[0] <= InpRsiShortLevel)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
void OpenTrade(int dir, double atr, double lots, double slDist)
{
   if(lots <= 0.0) { SetStatus("Invalid lots - skipped"); return; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (dir > 0) ? ask : bid;
   double tpDist = InpTpAtrMult * atr;

   // TP is strategy, so the risk layer has not checked its broker distance.
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(tpDist <= minDist)
   { SetStatus("TP inside broker stop level - skipped"); return; }

   double sl = (dir > 0) ? price - slDist : price + slDist;
   double tp = (dir > 0) ? price + tpDist : price - tpDist;
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   bool ok = (dir > 0) ? trade.Buy(lots, _Symbol, price, sl, tp, InpComment)
                       : trade.Sell(lots, _Symbol, price, sl, tp, InpComment);

   PrintFormat("GoldTPB: %s %.2f lots @ %.*f SL=%.*f TP=%.*f ATR=%.2f | ok=%s ret=%d (%s)",
               (dir > 0 ? "BUY" : "SELL"), lots,
               _Digits, price, _Digits, sl, _Digits, tp, atr,
               (ok ? "true" : "false"),
               trade.ResultRetcode(), trade.ResultRetcodeDescription());

   SetStatus(ok ? "Order sent" : "Order FAILED - see Experts log");
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, InpTF, 0);
   if(t == 0) return false;
   if(t != g_lastBar)
   {
      g_lastBar = t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void SetStatus(const string s)
{
   g_status = s;
   Comment("GoldTrendPullbackEA v0.2\n",
           "Symbol: ", _Symbol, "  TF: ", EnumToString(InpTF), "\n",
           "Status: ", g_status, "\n",
           "Server time: ", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
}
