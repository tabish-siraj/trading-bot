//+------------------------------------------------------------------+
//| RiskAdapter.mqh                                                  |
//| Reads MT5 account/symbol/history state into a RiskContext.       |
//|                                                                  |
//| This file is the only place where the risk layer touches MT5     |
//| state. It contains no decision rules.                            |
//|                                                                  |
//| NOTE: day boundaries use SERVER time for now. Moving them to UTC |
//| is part of the Phase 2 session work; do not build session logic  |
//| on top of this before that is fixed.                             |
//+------------------------------------------------------------------+
#property strict

#ifndef __RISK_ADAPTER_MQH__
#define __RISK_ADAPTER_MQH__

#include "RiskLayer.mqh"

//--- server-day stats: realized PnL, entries, loss streak ----------
void RiskAdapterDayStats(const string symbol, const long magic,
                         double &realized, int &entries, int &consecLosses)
{
   realized     = 0.0;
   entries      = 0;
   consecLosses = 0;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayStart = StructToTime(dt);

   if(!HistorySelect(dayStart, TimeCurrent() + 60)) return;

   int  total        = HistoryDealsTotal();
   bool streakBroken = false;

   for(int i = total - 1; i >= 0; i--)   // newest first: streak is "most recent"
   {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != symbol) continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != magic) continue;

      long   entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      double comm  = HistoryDealGetDouble(tk, DEAL_COMMISSION)
                   + HistoryDealGetDouble(tk, DEAL_FEE);

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

//--- position helpers -----------------------------------------------
bool RiskAdapterHasPosition(const string symbol, const long magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      return true;
   }
   return false;
}

bool RiskAdapterOwnPosition(ulong &ticket, long &type, datetime &openTime,
                            const string symbol, const long magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      ticket   = t;
      type     = PositionGetInteger(POSITION_TYPE);
      openTime = (datetime)PositionGetInteger(POSITION_TIME);
      return true;
   }
   return false;
}

double RiskAdapterFloatingPnL(const string symbol, const long magic)
{
   double sum = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      sum += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return sum;
}

//--- context builder ------------------------------------------------
// direction/entryPrice are used only to compute margin for one lot.
void RiskAdapterBuildContext(RiskContext &ctx, const long magic, const string symbol,
                             const int direction, const double entryPrice)
{
   RiskContextInit(ctx);

   ctx.accountTradeMode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   ctx.balance          = AccountInfoDouble(ACCOUNT_BALANCE);
   ctx.equity           = AccountInfoDouble(ACCOUNT_EQUITY);
   ctx.freeMargin       = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   double realized; int entries; int consec;
   RiskAdapterDayStats(symbol, magic, realized, entries, consec);
   ctx.realizedPnLToday  = realized;
   ctx.floatingPnL       = RiskAdapterFloatingPnL(symbol, magic);
   ctx.entriesToday      = entries;
   ctx.consecutiveLosses = consec;
   // equity = day-start equity + realized + floating (ignores deposits).
   ctx.dayStartEquity    = ctx.equity - ctx.realizedPnLToday - ctx.floatingPnL;

   ctx.ask      = SymbolInfoDouble(symbol, SYMBOL_ASK);
   ctx.bid      = SymbolInfoDouble(symbol, SYMBOL_BID);
   ctx.tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   ctx.tickValue= SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   ctx.volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   ctx.minLot     = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   ctx.maxLot     = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   ctx.stopsLevelPrice = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL)
                       * SymbolInfoDouble(symbol, SYMBOL_POINT);
   ctx.hasOpenPosition = RiskAdapterHasPosition(symbol, magic);

   ctx.marginPerLot = 0.0;
   double price = (entryPrice > 0.0) ? entryPrice
                   : ((direction > 0) ? ctx.ask : ctx.bid);
   ENUM_ORDER_TYPE ot = (direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double margin = 0.0;
   if(OrderCalcMargin(ot, symbol, 1.0, price, margin))
      ctx.marginPerLot = margin;
}

#endif // __RISK_ADAPTER_MQH__
