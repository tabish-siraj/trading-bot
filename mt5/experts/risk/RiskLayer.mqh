//+------------------------------------------------------------------+
//| RiskLayer.mqh                                                    |
//| Pure, strategy-agnostic risk decisions.                          |
//|                                                                  |
//| No MT5 account reads, no order execution, no strategy logic.     |
//| The caller builds a RiskContext and receives a RiskDecision.     |
//|                                                                  |
//| Contract:                                                        |
//|   RiskEvaluate(limits, context, order, decision)                 |
//|     RISK_ACTION_REJECT  -> lots = 0                              |
//|     RISK_ACTION_APPROVE -> lots = computed size                  |
//|     RISK_ACTION_RESIZE  -> lots = smaller, still inside caps     |
//|                                                                  |
//| A component that cannot compute a cap must fail closed.          |
//| Do not add timezone, strategy, or execution logic here.          |
//+------------------------------------------------------------------+
#property strict

#ifndef __RISK_LAYER_MQH__
#define __RISK_LAYER_MQH__

enum ENUM_RISK_ACTION
{
   RISK_ACTION_APPROVE = 0,
   RISK_ACTION_RESIZE  = 1,
   RISK_ACTION_REJECT  = 2
};

enum ENUM_RISK_CODE
{
   RISK_CODE_OK = 0,
   RISK_CODE_BAD_INPUT,
   RISK_CODE_NOT_DEMO,
   RISK_CODE_NO_QUOTE,
   RISK_CODE_SPREAD,
   RISK_CODE_POSITION_OPEN,
   RISK_CODE_DAILY_LOSS,
   RISK_CODE_CONSECUTIVE_LOSSES,
   RISK_CODE_MAX_TRADES,
   RISK_CODE_STOP_TOO_TIGHT,
   RISK_CODE_BELOW_MIN_LOT,
   RISK_CODE_MARGIN,
   RISK_CODE_RESIZED_CAP,
   RISK_CODE_RESIZED_MARGIN
};

struct RiskLimits
{
   bool   demoOnly;
   bool   useEquity;            // true: size/cap on equity, false: balance
   double riskPctPerTrade;      // % of base per trade
   double maxLots;              // hard lot cap
   double maxDailyLossPct;      // 0 disables
   int    maxConsecutiveLosses; // 0 disables
   int    maxTradesPerDay;      // 0 disables
   double maxSpreadPrice;       // 0 disables
   bool   onePositionAtATime;
   double maxMarginUsagePct;    // % of free margin; 0 disables
};

struct RiskContext
{
   long   accountTradeMode;     // ACCOUNT_TRADE_MODE_*
   double balance;
   double equity;
   double freeMargin;
   double realizedPnLToday;
   double floatingPnL;
   double dayStartEquity;
   int    entriesToday;
   int    consecutiveLosses;
   double ask;
   double bid;
   double tickSize;
   double tickValue;
   double volumeStep;
   double minLot;
   double maxLot;
   double marginPerLot;         // precomputed by the caller for one lot
   double stopsLevelPrice;      // broker minimum stop distance in price
   bool   hasOpenPosition;
};

struct RiskOrder
{
   int    direction;            // +1 buy, -1 sell
   double entryPrice;           // informational; 0 means "use quote"
   double stopDistancePrice;    // > 0
};

struct RiskDecision
{
   ENUM_RISK_ACTION action;
   ENUM_RISK_CODE   code;
   double           lots;
   string           reason;
};

//--- initialisers ---------------------------------------------------
void RiskLimitsInit(RiskLimits &l)
{
   // Fail-closed defaults: the caller must set real values.
   l.demoOnly             = true;
   l.useEquity            = true;
   l.riskPctPerTrade      = 0.0;
   l.maxLots              = 0.0;
   l.maxDailyLossPct      = 0.0;
   l.maxConsecutiveLosses = 0;
   l.maxTradesPerDay      = 0;
   l.maxSpreadPrice       = 0.0;
   l.onePositionAtATime   = true;
   l.maxMarginUsagePct    = 0.0;
}

void RiskContextInit(RiskContext &c)
{
   c.accountTradeMode   = -1;
   c.balance            = 0.0;
   c.equity             = 0.0;
   c.freeMargin         = 0.0;
   c.realizedPnLToday   = 0.0;
   c.floatingPnL        = 0.0;
   c.dayStartEquity     = 0.0;
   c.entriesToday       = 0;
   c.consecutiveLosses  = 0;
   c.ask                = 0.0;
   c.bid                = 0.0;
   c.tickSize           = 0.0;
   c.tickValue          = 0.0;
   c.volumeStep         = 0.0;
   c.minLot             = 0.0;
   c.maxLot             = 0.0;
   c.marginPerLot       = 0.0;
   c.stopsLevelPrice    = 0.0;
   c.hasOpenPosition    = false;
}

void RiskOrderInit(RiskOrder &o)
{
   o.direction         = 0;
   o.entryPrice        = 0.0;
   o.stopDistancePrice = 0.0;
}

void RiskDecisionInit(RiskDecision &d)
{
   d.action = RISK_ACTION_REJECT;
   d.code   = RISK_CODE_BAD_INPUT;
   d.lots   = 0.0;
   d.reason = "";
}

//--- helpers --------------------------------------------------------
double RiskFloorToStep(const double value, const double step)
{
   if(step <= 0.0) return 0.0;
   return MathFloor(value / step + 1e-9) * step;
}

int RiskStepDecimals(const double step)
{
   if(step <= 0.0) return 0;
   int d = 0;
   double s = step;
   while(d < 8 && MathAbs(s - MathRound(s)) > 1e-6)
   {
      s *= 10.0;
      d++;
   }
   return d;
}

string RiskActionToString(const ENUM_RISK_ACTION a)
{
   switch(a)
   {
      case RISK_ACTION_APPROVE: return "APPROVE";
      case RISK_ACTION_RESIZE:  return "RESIZE";
      case RISK_ACTION_REJECT:  return "REJECT";
   }
   return "UNKNOWN";
}

string RiskCodeToString(const ENUM_RISK_CODE code)
{
   switch(code)
   {
      case RISK_CODE_OK:                  return "OK";
      case RISK_CODE_BAD_INPUT:           return "BAD_INPUT";
      case RISK_CODE_NOT_DEMO:            return "NOT_DEMO";
      case RISK_CODE_NO_QUOTE:            return "NO_QUOTE";
      case RISK_CODE_SPREAD:              return "SPREAD";
      case RISK_CODE_POSITION_OPEN:       return "POSITION_OPEN";
      case RISK_CODE_DAILY_LOSS:          return "DAILY_LOSS";
      case RISK_CODE_CONSECUTIVE_LOSSES:  return "CONSECUTIVE_LOSSES";
      case RISK_CODE_MAX_TRADES:          return "MAX_TRADES";
      case RISK_CODE_STOP_TOO_TIGHT:      return "STOP_TOO_TIGHT";
      case RISK_CODE_BELOW_MIN_LOT:       return "BELOW_MIN_LOT";
      case RISK_CODE_MARGIN:              return "MARGIN";
      case RISK_CODE_RESIZED_CAP:         return "RESIZED_CAP";
      case RISK_CODE_RESIZED_MARGIN:      return "RESIZED_MARGIN";
   }
   return "UNKNOWN";
}

void RiskReject(const ENUM_RISK_CODE code, const string reason, RiskDecision &d)
{
   d.action = RISK_ACTION_REJECT;
   d.code   = code;
   d.lots   = 0.0;
   d.reason = reason;
}

//--- validation -----------------------------------------------------
ENUM_RISK_CODE RiskValidate(const RiskLimits &l, const RiskContext &c, const RiskOrder &o)
{
   if(o.direction != 1 && o.direction != -1)        return RISK_CODE_BAD_INPUT;
   if(o.stopDistancePrice <= 0.0)                   return RISK_CODE_BAD_INPUT;
   if(l.riskPctPerTrade <= 0.0)                     return RISK_CODE_BAD_INPUT;
   if(l.maxLots <= 0.0)                             return RISK_CODE_BAD_INPUT;
   if(c.tickSize <= 0.0 || c.tickValue <= 0.0)      return RISK_CODE_BAD_INPUT;
   if(c.volumeStep <= 0.0 || c.minLot <= 0.0)       return RISK_CODE_BAD_INPUT;
   if(c.maxLot < c.minLot)                          return RISK_CODE_BAD_INPUT;
   if(c.ask <= 0.0 || c.bid <= 0.0)                 return RISK_CODE_NO_QUOTE;
   if(c.marginPerLot <= 0.0)                        return RISK_CODE_MARGIN;
   return RISK_CODE_OK;
}

//--- main entry point -----------------------------------------------
void RiskEvaluate(const RiskLimits &limits, const RiskContext &ctx, const RiskOrder &order,
                  RiskDecision &d)
{
   RiskDecisionInit(d);

   ENUM_RISK_CODE invalid = RiskValidate(limits, ctx, order);
   if(invalid != RISK_CODE_OK)
   {
      RiskReject(invalid, RiskCodeToString(invalid), d);
      return;
   }

   // 1) Demo lock.
   if(limits.demoOnly && ctx.accountTradeMode != ACCOUNT_TRADE_MODE_DEMO)
   {
      RiskReject(RISK_CODE_NOT_DEMO, "account is not demo", d);
      return;
   }

   // 2) Spread.
   double spread = ctx.ask - ctx.bid;
   if(limits.maxSpreadPrice > 0.0 && spread > limits.maxSpreadPrice)
   {
      RiskReject(RISK_CODE_SPREAD,
                 StringFormat("spread %.5f > cap %.5f", spread, limits.maxSpreadPrice), d);
      return;
   }

   // 3) One position at a time.
   if(limits.onePositionAtATime && ctx.hasOpenPosition)
   {
      RiskReject(RISK_CODE_POSITION_OPEN, "position already open", d);
      return;
   }

   // 4) Daily loss cap.
   if(limits.maxDailyLossPct > 0.0 && ctx.dayStartEquity > 0.0)
   {
      double dayPnL = ctx.realizedPnLToday + ctx.floatingPnL;
      double cap    = -(limits.maxDailyLossPct / 100.0) * ctx.dayStartEquity;
      if(dayPnL <= cap)
      {
         RiskReject(RISK_CODE_DAILY_LOSS,
                    StringFormat("day PnL %.2f <= cap %.2f", dayPnL, cap), d);
         return;
      }
   }

   // 5) Consecutive-loss stop.
   if(limits.maxConsecutiveLosses > 0 && ctx.consecutiveLosses >= limits.maxConsecutiveLosses)
   {
      RiskReject(RISK_CODE_CONSECUTIVE_LOSSES,
                 StringFormat("%d consecutive losses", ctx.consecutiveLosses), d);
      return;
   }

   // 6) Max entries per day.
   if(limits.maxTradesPerDay > 0 && ctx.entriesToday >= limits.maxTradesPerDay)
   {
      RiskReject(RISK_CODE_MAX_TRADES,
                 StringFormat("%d entries today", ctx.entriesToday), d);
      return;
   }

   // 7) Broker minimum stop distance.
   if(ctx.stopsLevelPrice > 0.0 && order.stopDistancePrice < ctx.stopsLevelPrice)
   {
      RiskReject(RISK_CODE_STOP_TOO_TIGHT,
                 StringFormat("stop %.5f < broker min %.5f", order.stopDistancePrice, ctx.stopsLevelPrice), d);
      return;
   }

   // 8) Position size from risk.
   double base       = limits.useEquity ? ctx.equity : ctx.balance;
   double riskMoney  = base * limits.riskPctPerTrade / 100.0;
   double lossPerLot = (order.stopDistancePrice / ctx.tickSize) * ctx.tickValue;
   if(lossPerLot <= 0.0)
   {
      RiskReject(RISK_CODE_BAD_INPUT, "loss per lot <= 0", d);
      return;
   }

   double lots = RiskFloorToStep(riskMoney / lossPerLot, ctx.volumeStep);
   bool   resized = false;
   ENUM_RISK_CODE resizeCode = RISK_CODE_OK;

   // 9) Hard lot cap.
   double hardCap = MathMin(limits.maxLots, ctx.maxLot);
   if(lots > hardCap)
   {
      lots       = RiskFloorToStep(hardCap, ctx.volumeStep);
      resized    = true;
      resizeCode = RISK_CODE_RESIZED_CAP;
   }

   if(lots < ctx.minLot)
   {
      RiskReject(RISK_CODE_BELOW_MIN_LOT,
                 StringFormat("lots %.4f < min %.4f", lots, ctx.minLot), d);
      return;
   }

   // 10) Margin cap (resize down, never up).
   if(limits.maxMarginUsagePct > 0.0 && ctx.freeMargin > 0.0)
   {
      double maxByMargin = RiskFloorToStep((ctx.freeMargin * limits.maxMarginUsagePct / 100.0) / ctx.marginPerLot,
                                           ctx.volumeStep);
      if(maxByMargin < ctx.minLot)
      {
         RiskReject(RISK_CODE_MARGIN, "free margin below minimum lot", d);
         return;
      }
      if(lots > maxByMargin)
      {
         lots       = maxByMargin;
         resized    = true;
         resizeCode = RISK_CODE_RESIZED_MARGIN;
      }
   }

   lots = NormalizeDouble(lots, RiskStepDecimals(ctx.volumeStep));
   if(lots < ctx.minLot)
   {
      RiskReject(RISK_CODE_BELOW_MIN_LOT, "lots below minimum after rounding", d);
      return;
   }

   d.lots = lots;
   if(resized)
   {
      d.action = RISK_ACTION_RESIZE;
      d.code   = resizeCode;
      d.reason = StringFormat("resized to %.2f lots", lots);
   }
   else
   {
      d.action = RISK_ACTION_APPROVE;
      d.code   = RISK_CODE_OK;
      d.reason = StringFormat("%.2f lots", lots);
   }
}

#endif // __RISK_LAYER_MQH__
