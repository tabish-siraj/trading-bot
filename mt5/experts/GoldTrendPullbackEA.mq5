//+------------------------------------------------------------------+
//|                                        GoldTrendPullbackEA.mq5   |
//|  v0.1 - Base EA for XAUUSD. Demo-locked by default.              |
//|                                                                  |
//|  Strategy: trend-pullback                                        |
//|   - Trend filter : EMA(fast) vs EMA(slow) + price vs slow EMA    |
//|   - Entry        : RSI crosses back through a level (pullback    |
//|                    ended), evaluated on the CLOSED bar only     |
//|   - Filters      : ATR minimum, max spread, session, Friday      |
//|   - Exits        : ATR-based SL/TP, optional time stop           |
//|   - Risk         : % of balance per trade, daily loss cap,       |
//|                    consecutive-loss stop, max trades per day     |
//|                                                                  |
//|  NOT financial advice. No profitability is claimed or implied.   |
//+------------------------------------------------------------------+
#property copyright "Gold bot project"
#property version   "0.10"
#property strict

#include <Trade/Trade.mqh>

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
input double           InpRiskPct         = 0.5;    // Risk per trade, % of balance
input double           InpMaxLots         = 1.0;    // Hard cap on lot size
input double           InpMaxDailyLossPct = 2.0;    // Stop for the day at this % loss
input int              InpMaxConsecLosses = 3;      // Stop for the day after N losses in a row
input int              InpMaxTradesPerDay = 5;      // Max new entries per server day
input int              InpDeviationPts    = 30;     // Max slippage in points

//--- globals -------------------------------------------------------
CTrade   trade;
int      hFast = INVALID_HANDLE;
int      hSlow = INVALID_HANDLE;
int      hRsi  = INVALID_HANDLE;
int      hAtr  = INVALID_HANDLE;
datetime g_lastBar = 0;
string   g_status  = "";

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

   PrintFormat("GoldTPB v0.1 started on %s %s | digits=%d point=%g | risk=%.2f%%",
               _Symbol, EnumToString(InpTF), _Digits, _Point, InpRiskPct);
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

   // 1) Manage any open position (time stop)
   ulong    ticket;
   long     ptype;
   datetime popen;
   if(GetOwnPosition(ticket, ptype, popen))
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

   // 2) Daily risk gates
   double realized; int entries; int consecLosses;
   GetDayStats(realized, entries, consecLosses);

   double dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE) - realized;
   double dayPnL      = realized + OwnFloatingPnL();
   if(dayStartBal > 0 && dayPnL <= -(InpMaxDailyLossPct / 100.0) * dayStartBal)
   { SetStatus(StringFormat("HALT: daily loss cap hit (%.2f)", dayPnL)); return; }

   if(consecLosses >= InpMaxConsecLosses)
   { SetStatus(StringFormat("HALT: %d consecutive losses today", consecLosses)); return; }

   if(entries >= InpMaxTradesPerDay)
   { SetStatus("HALT: max trades per day reached"); return; }

   // 3) Time / session filters (server time)
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour)
   { SetStatus("Outside session"); return; }
   if(dt.day_of_week == 5 && dt.hour >= InpFridayCutoffHour)
   { SetStatus("Friday cutoff"); return; }
   if(dt.day_of_week == 0 || dt.day_of_week == 6)
   { SetStatus("Weekend"); return; }

   // 4) Spread filter (price units)
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) { SetStatus("No quote"); return; }
   if((ask - bid) > InpMaxSpread)
   { SetStatus(StringFormat("Spread too wide (%.2f)", ask - bid)); return; }

   // 5) Signal
   double atr;
   int dir = GetSignal(atr);
   if(dir == 0) { SetStatus("No signal"); return; }

   // 6) Execute
   OpenTrade(dir, atr);
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
void OpenTrade(int dir, double atr)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (dir > 0) ? ask : bid;

   double slDist = InpSlAtrMult * atr;
   double tpDist = InpTpAtrMult * atr;

   // Respect broker minimum stop distance
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(slDist <= minDist || tpDist <= minDist)
   { SetStatus("SL/TP inside broker stop level - skipped"); return; }

   double sl = (dir > 0) ? price - slDist : price + slDist;
   double tp = (dir > 0) ? price + tpDist : price - tpDist;
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double lots = CalcLots(slDist);
   if(lots <= 0) { SetStatus("Lot size invalid / below minimum - skipped"); return; }

   // Margin check
   double margin = 0.0;
   ENUM_ORDER_TYPE otype = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(otype, _Symbol, lots, price, margin) ||
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.8)
   { SetStatus("Not enough free margin - skipped"); return; }

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
//| Lot size so that hitting the stop loses InpRiskPct of balance.   |
//+------------------------------------------------------------------+
double CalcLots(double slDist)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0 || slDist <= 0) return 0.0;

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
   double lossPerLot = (slDist / tickSize) * tickValue;
   if(lossPerLot <= 0) return 0.0;

   double lots   = riskMoney / lossPerLot;
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) return 0.0;

   lots = MathFloor(lots / step + 1e-9) * step;

   if(lots < minLot)
   {
      PrintFormat("GoldTPB: computed lots %.4f below broker minimum %.2f - trade skipped "
                  "(risk too small for this balance/stop).", lots, minLot);
      return 0.0;
   }

   lots = MathMin(lots, MathMin(maxLot, InpMaxLots));
   int d = (int)MathMax(0.0, MathRound(-MathLog10(step)));
   return NormalizeDouble(lots, d);
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
bool GetOwnPosition(ulong &ticket, long &type, datetime &openTime)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ticket   = t;
      type     = PositionGetInteger(POSITION_TYPE);
      openTime = (datetime)PositionGetInteger(POSITION_TIME);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
double OwnFloatingPnL()
{
   double sum = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      sum += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return sum;
}

//+------------------------------------------------------------------+
//| Today's (server day) realized P&L, entries, and loss streak.    |
//+------------------------------------------------------------------+
void GetDayStats(double &realized, int &entries, int &consecLosses)
{
   realized = 0.0; entries = 0; consecLosses = 0;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayStart = StructToTime(dt);

   if(!HistorySelect(dayStart, TimeCurrent() + 60)) return;

   int  total = HistoryDealsTotal();
   bool streakBroken = false;

   for(int i = total - 1; i >= 0; i--)   // newest first so the streak is "most recent"
   {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic) continue;

      long   entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      double comm  = HistoryDealGetDouble(tk, DEAL_COMMISSION) + HistoryDealGetDouble(tk, DEAL_FEE);

      if(entry == DEAL_ENTRY_IN)
      {
         entries++;
         realized += comm;
      }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         double p = HistoryDealGetDouble(tk, DEAL_PROFIT)
                  + HistoryDealGetDouble(tk, DEAL_SWAP) + comm;
         realized += p;
         if(!streakBroken)
         {
            if(p < 0) consecLosses++;
            else      streakBroken = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
void SetStatus(const string s)
{
   g_status = s;
   Comment("GoldTrendPullbackEA v0.1\n",
           "Symbol: ", _Symbol, "  TF: ", EnumToString(InpTF), "\n",
           "Status: ", g_status, "\n",
           "Server time: ", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
}
//+------------------------------------------------------------------+