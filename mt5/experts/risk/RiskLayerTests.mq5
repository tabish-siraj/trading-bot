//+------------------------------------------------------------------+
//| RiskLayerTests.mq5                                               |
//| Unit tests for RiskLayer.mqh. No trading. Prints PASS/FAIL and   |
//| unloads itself. Run it on any chart; it does not place orders.   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include "RiskLayer.mqh"

int  g_pass = 0;
int  g_fail = 0;
bool g_ran  = false;

void Check(const string name, const bool ok)
{
   if(ok) { g_pass++; Print("PASS  ", name); }
   else   { g_fail++; Print("FAIL  ", name); }
}

void ExpectDecision(const string name, const RiskDecision &d,
                    const ENUM_RISK_ACTION action, const ENUM_RISK_CODE code)
{
   bool ok = (d.action == action && d.code == code);
   if(!ok)
      PrintFormat("      got action=%s code=%s lots=%.4f reason=%s",
                  RiskActionToString(d.action), RiskCodeToString(d.code), d.lots, d.reason);
   Check(name, ok);
}

void ExpectLots(const string name, const RiskDecision &d, const double expected)
{
   bool ok = (MathAbs(d.lots - expected) < 1e-6);
   if(!ok)
      PrintFormat("      got lots=%.6f expected=%.6f", d.lots, expected);
   Check(name, ok);
}

void ExpectEval(const string name, const RiskLimits &l, const RiskContext &c, const RiskOrder &o,
                const ENUM_RISK_ACTION action, const ENUM_RISK_CODE code)
{
   RiskDecision d;
   RiskEvaluate(l, c, o, d);
   ExpectDecision(name, d, action, code);
}

void ExpectEvalLots(const string name, const RiskLimits &l, const RiskContext &c, const RiskOrder &o,
                    const ENUM_RISK_ACTION action, const ENUM_RISK_CODE code, const double expectedLots)
{
   RiskDecision d;
   RiskEvaluate(l, c, o, d);
   ExpectDecision(name, d, action, code);
   ExpectLots(name + "_lots", d, expectedLots);
}

void BaseLimits(RiskLimits &l)
{
   RiskLimitsInit(l);
   l.demoOnly             = true;
   l.useEquity            = true;
   l.riskPctPerTrade      = 0.5;
   l.maxLots              = 1.0;
   l.maxDailyLossPct      = 2.0;
   l.maxConsecutiveLosses = 3;
   l.maxTradesPerDay      = 5;
   l.maxSpreadPrice       = 0.40;
   l.onePositionAtATime   = true;
   l.maxMarginUsagePct    = 80.0;
}

void BaseContext(RiskContext &c)
{
   RiskContextInit(c);
   c.accountTradeMode   = ACCOUNT_TRADE_MODE_DEMO;
   c.balance            = 10000.0;
   c.equity             = 10000.0;
   c.freeMargin         = 9000.0;
   c.realizedPnLToday   = 0.0;
   c.floatingPnL        = 0.0;
   c.dayStartEquity     = 10000.0;
   c.entriesToday       = 0;
   c.consecutiveLosses  = 0;
   c.ask                = 2000.10;
   c.bid                = 2000.00;
   c.tickSize           = 0.01;
   c.tickValue          = 1.0;
   c.volumeStep         = 0.01;
   c.minLot             = 0.01;
   c.maxLot             = 100.0;
   c.marginPerLot       = 200.0;
   c.stopsLevelPrice    = 0.10;
   c.hasOpenPosition    = false;
}

void BaseOrder(RiskOrder &o)
{
   RiskOrderInit(o);
   o.direction         = 1;
   o.entryPrice        = 2000.10;
   o.stopDistancePrice = 6.0;
}

void RunTests()
{
   RiskLimits  lim;
   RiskContext ctx;
   RiskOrder   ord;

   // 1. Normal approval: 10000 * 0.5% = 50; loss/lot = 600 -> 0.08 lots.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ExpectEvalLots("approve_normal", lim, ctx, ord,
                  RISK_ACTION_APPROVE, RISK_CODE_OK, 0.08);

   // 2. Demo lock.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.accountTradeMode = ACCOUNT_TRADE_MODE_REAL;
   ExpectEval("reject_live_account", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_NOT_DEMO);

   // 3. Spread cap.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.ask = 2000.60;
   ExpectEval("reject_spread", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_SPREAD);

   // 4. Daily loss cap (-2% of 10000 = -200).
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.realizedPnLToday = -250.0;
   ExpectEval("reject_daily_loss", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_DAILY_LOSS);

   // 5. Consecutive losses.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.consecutiveLosses = 3;
   ExpectEval("reject_consecutive_losses", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_CONSECUTIVE_LOSSES);

   // 6. Max entries per day.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.entriesToday = 5;
   ExpectEval("reject_max_trades", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_MAX_TRADES);

   // 7. One position at a time.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.hasOpenPosition = true;
   ExpectEval("reject_position_open", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_POSITION_OPEN);

   // 8. Broker minimum stop distance.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ord.stopDistancePrice = 0.05;
   ExpectEval("reject_stop_too_tight", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_STOP_TOO_TIGHT);

   // 9. Below broker minimum lot.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.equity = 100.0; ctx.balance = 100.0; ctx.dayStartEquity = 100.0;
   ExpectEval("reject_below_min_lot", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_BELOW_MIN_LOT);

   // 10. Resize down to the hard lot cap.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   lim.riskPctPerTrade = 100.0;
   ExpectEvalLots("resize_to_lot_cap", lim, ctx, ord,
                  RISK_ACTION_RESIZE, RISK_CODE_RESIZED_CAP, 1.00);

   // 11. Resize down to the margin cap.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.freeMargin = 10.0;   // 80% = 8; /200 = 0.04 lots
   ExpectEvalLots("resize_to_margin", lim, ctx, ord,
                  RISK_ACTION_RESIZE, RISK_CODE_RESIZED_MARGIN, 0.04);

   // 12. Margin below minimum lot.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.freeMargin = 1.0;    // 80% = 0.8; /200 = 0.004 -> below min
   ExpectEval("reject_margin", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_MARGIN);

   // 13. Equity vs balance sizing.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.equity = 5000.0;     // 25 / 600 = 0.0416 -> 0.04
   ExpectEvalLots("use_equity", lim, ctx, ord,
                  RISK_ACTION_APPROVE, RISK_CODE_OK, 0.04);

   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.equity = 5000.0; lim.useEquity = false;   // 10000 * 0.5% = 50 -> 0.08
   ExpectEvalLots("use_balance", lim, ctx, ord,
                  RISK_ACTION_APPROVE, RISK_CODE_OK, 0.08);

   // 14. Bad input and missing quote/margin fail closed.
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ord.stopDistancePrice = 0.0;
   ExpectEval("reject_bad_input", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_BAD_INPUT);

   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.ask = 0.0;
   ExpectEval("reject_no_quote", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_NO_QUOTE);

   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   ctx.marginPerLot = 0.0;
   ExpectEval("reject_margin_unavailable", lim, ctx, ord,
              RISK_ACTION_REJECT, RISK_CODE_MARGIN);

   // 15. Zero caps disable their filters (documented behaviour).
   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   lim.maxSpreadPrice = 0.0; ctx.ask = 2000.60;
   ExpectEval("zero_max_spread_disables", lim, ctx, ord,
              RISK_ACTION_APPROVE, RISK_CODE_OK);

   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   lim.maxDailyLossPct = 0.0; ctx.realizedPnLToday = -500.0;
   ExpectEval("zero_daily_cap_disables", lim, ctx, ord,
              RISK_ACTION_APPROVE, RISK_CODE_OK);

   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   lim.maxConsecutiveLosses = 0; ctx.consecutiveLosses = 10;
   ExpectEval("zero_consec_disables", lim, ctx, ord,
              RISK_ACTION_APPROVE, RISK_CODE_OK);

   BaseLimits(lim); BaseContext(ctx); BaseOrder(ord);
   lim.maxTradesPerDay = 0; ctx.entriesToday = 99;
   ExpectEval("zero_max_trades_disables", lim, ctx, ord,
              RISK_ACTION_APPROVE, RISK_CODE_OK);

   PrintFormat("RISK TEST SUMMARY: %d passed, %d failed", g_pass, g_fail);
   if(g_fail == 0) Print("RISK TESTS PASSED");
   else            Print("RISK TESTS FAILED");
}

int OnInit()
{
   Print("RiskLayerTests: starting (no trading will occur)");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(g_ran) return;
   g_ran = true;
   RunTests();
   ExpertRemove();
}
