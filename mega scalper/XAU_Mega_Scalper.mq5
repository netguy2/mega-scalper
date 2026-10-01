//+------------------------------------------------------------------+
//|                                           XAU_Mega_Scalper.mq5   |
//|                             XAU-MEGA-SCALPER Formal Spec v0.2    |
//|                             DEBUG & CONTINUOUS RESEARCH EDITION  |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, Advanced Algo"
#property link        "https://github.com"
#property version     "1.20"
#property description "XAU-MEGA-SCALPER v0.2 Debug & Continuous Research Edition"
#property strict

//--- Core System Includes
#include "Include/Defines.mqh"
#include "Include/Logger.mqh"
#include "Include/DecisionLogger.mqh"
#include "Include/DataModel.mqh"
#include "Include/Gates.mqh"
#include "Include/RegimeEngine.mqh"
#include "Include/EngineA_TrendPullback.mqh"
#include "Include/EngineB_Breakout.mqh"
#include "Include/EngineC_MeanReversion.mqh"
#include "Include/ScalpEngine.mqh"
#include "Include/RiskEngine.mqh"
#include "Include/TradeManager.mqh"
#include "Include/ExecutionStateMachine.mqh"
#include "Include/PanelGUI.mqh"

//+------------------------------------------------------------------+
//| RESEARCH / CONTINUOUS TEST CONFIGURATION                         |
//+------------------------------------------------------------------+
input group "=== RESEARCH / TEST MODE ==="
input bool     InpContinuousResearchMode  = true;   // Continuous Mode (No daily loss/DD brakes)
input bool     InpEnableOnChartPanel      = true;   // Show Interactive Control Panel
input bool     InpEnableDecisionLog       = true;   // Write Full Decision Audit to File

//+------------------------------------------------------------------+
//| 1. PARAMETER BUDGET: MODULE 1 - REGIME ENGINE (12)               |
//+------------------------------------------------------------------+
input group "=== REGIME ENGINE (12 Seed Params) ==="
input int      InpADXPeriod               = 14;     // 1. adx_period
input double   InpADXTrendMin             = 25.0;   // 2. adx_trend_min
input int      InpATRPeriodM15            = 14;     // 3. atr_period_m15
input int      InpATRPeriodM5             = 14;     // 4. atr_period_m5
input double   InpATRExpansionRatio       = 1.8;    // 5. atr_expansion_ratio
input int      InpATRPctLookbackBars      = 100;    // 6. atr_pct_lookback_bars
input double   InpATRPctChaosPctl         = 99.0;   // 7. atr_pct_chaos_pctl
input int      InpSpreadAvgLookbackTicks  = 100;    // 8. spread_avg_lookback_ticks
input double   InpSpreadChaosMult         = 3.0;    // 9. spread_chaos_mult
input double   InpSpreadChaosAbsPts       = 450.0;  // 10. spread_chaos_abs_pts
input int      InpVWAPSlopeBars           = 5;      // 11. vwap_slope_bars
input int      InpDwellBars               = 3;      // 12. dwell_bars

//+------------------------------------------------------------------+
//| 2. PARAMETER BUDGET: MODULE 2 - TREND-PULLBACK (6)               |
//+------------------------------------------------------------------+
input group "=== ENGINE A: TREND-PULLBACK (6 Seed Params) ==="
input int      InpEMAFast                 = 9;      // 13. ema_fast
input int      InpEMAMid                  = 21;     // 14. ema_mid
input int      InpEMASlow                 = 50;     // 15. ema_slow
input double   InpPullbackATRFrac         = 0.35;   // 16. pullback_atr_frac
input double   InpRejectionWickRatio      = 1.5;    // 17. rejection_wick_ratio
input int      InpMomentumLookbackBars    = 1;      // 18. momentum_lookback_bars

//+------------------------------------------------------------------+
//| 3. PARAMETER BUDGET: MODULE 3 - BREAKOUT (6)                     |
//+------------------------------------------------------------------+
input group "=== ENGINE B: BREAKOUT (6 Seed Params) ==="
input int      InpORWindowMin             = 30;     // 19. or_window_min
input int      InpDonchianPeriod          = 20;     // 20. donchian_period
input double   InpBreakoutBufferATR       = 0.10;   // 21. breakout_buffer_atr
input double   InpRangeMinATR             = 0.8;    // 22. range_min_atr
input double   InpRangeMaxATR             = 3.0;    // 23. range_max_atr
input int      InpMomentumConfirmBars     = 2;      // 24. momentum_confirm_bars

//+------------------------------------------------------------------+
//| 4. PARAMETER BUDGET: MODULE 4 - MEAN REVERSION (6)               |
//+------------------------------------------------------------------+
input group "=== ENGINE C: MEAN REVERSION (6 Seed Params) ==="
input int      InpBBPeriod                = 20;     // 25. bb_period
input double   InpBBSigma                 = 2.0;    // 26. bb_sigma
input double   InpVWAPDevATRMin           = 1.2;    // 27. vwap_dev_atr_min
input int      InpBandTouchLookback       = 3;      // 28. band_touch_lookback
input double   InpRejectionWickRatioMR    = 1.2;    // 29. rejection_wick_ratio_mr
input double   InpMaxFadeExtensionATR     = 2.5;    // 30. max_fade_extension_atr

//+------------------------------------------------------------------+
//| 5. PARAMETER BUDGET: MODULE 5 - RISK / EXECUTION (8)             |
//+------------------------------------------------------------------+
input group "=== RISK & EXECUTION (8 Seed Params) ==="
input double   InpRiskPerTradePct         = 0.01;   // 31. risk_per_trade_pct (1.0%)
input double   InpATRSLMult               = 1.5;    // 32. atr_sl_mult
input double   InpMaxSpreadATRRatio       = 0.15;   // 33. max_spread_atr_ratio
input double   InpDailyDDPct              = 0.03;   // 34. daily_dd_pct (Production only)
input int      InpConsecLossLimit         = 3;      // 35. consec_loss_limit (Production only)
input int      InpCooldownBars            = 0;      // 36. cooldown_bars (0 for instant re-scan)
input int      InpMaxPositions            = 1;      // 37. max_positions (Global 1 hard cap)
input int      InpNewsBlackoutMin         = 30;     // 38. news_blackout_min

//+------------------------------------------------------------------+
//| SCALP ENGINE: M15 bias -> M5 location -> M1 micro-trigger        |
//+------------------------------------------------------------------+
input group "=== SCALP ENGINE: ENTRY (M1 TRIGGER LAYER) ==="
input bool     InpScalpEnabled            = true;   // Enable the M1 scalp layer (both modes below)
input int      InpScalpLookbackM1         = 8;      // [Trend] M1 bars scanned for the pullback extreme
input int      InpScalpSwingBarsM1        = 4;      // [Trend] M1 bars defining the micro swing high/low
input double   InpScalpZoneATR            = 0.30;   // [Trend] Pullback must reach M5 EMA9 + zone*ATR(M5)
input double   InpScalpHoldATR            = 0.50;   // [Trend] Max break of M5 EMA21 tolerated (ATR) before trend is "lost"
input double   InpScalpMaxExtATR          = 1.20;   // [Trend] Do not chase beyond M5 EMA9 + this*ATR(M5)
input double   InpScalpMinBodyFrac        = 0.60;   // [Trend] Trigger candle body >= frac * avg M1 range
input double   InpScalpSLBufferATR        = 0.10;   // Stop buffer beyond the micro swing / sweep wick (ATR M5)
input double   InpScalpMinSLATR           = 0.60;   // Minimum stop distance (ATR M5)

input group "=== SCALP ENGINE: LIQUIDITY SWEEP MODE ==="
input bool     InpSweepEnabled            = true;   // Trade stop-hunt reversals at key levels (also active in RANGE)
input double   InpSweepMinDepthATR        = 0.05;   // Wick must take the level out by at least this (ATR M5)
input double   InpSweepMaxDepthATR        = 1.00;   // ...but not by more than this (that is a breakdown, not a sweep)
input double   InpSweepClosePos           = 0.60;   // Rejection: close in the favourable 40% of the M1 bar
input double   InpSweepDispMult           = 1.20;   // Displacement: bar range >= mult * average M1 range
input double   InpRoundStep               = 50.0;   // Round-number level spacing ($)

input group "=== SCALP ENGINE: CONTEXT FILTERS ==="
input bool     InpUseH1Bias               = true;   // Block trades against the H1 EMA50/EMA200 bias
input double   InpScalpMinRoomATR         = 0.80;   // Require this much free space (ATR M5) to the next key level
input double   InpScalpRSIMax             = 78.0;   // No buys above / sells below (100-x) RSI(M1): exhaustion
input double   InpScalpMinATRUsd          = 0.80;   // Dead-market floor: ATR(M5) in $ must exceed this
input int      InpScalpMinGradePts        = 0;      // Minimum confluence points (0=any, 2=B+, 3=A only)
input int      InpScalpLossCooldownMin    = 3;      // After a loss wait N min x consecutive losses (max x3), 0=off
input int      InpMaxEntriesPerDay        = 30;     // Hard cap on scalp entries per server day, 0=off

input group "=== SESSIONS (BROKER SERVER HOURS - adjust to your broker's GMT offset) ==="
input int      InpAsianStartHour          = 0;      // Asian range start
input int      InpAsianEndHour            = 7;      // Asian range end / London open
input int      InpLondonStartHour         = 7;      // London session start
input int      InpOverlapStartHour        = 12;     // London + New York overlap start
input int      InpOverlapEndHour          = 16;     // Overlap end
input int      InpNYEndHour               = 20;     // New York session end

input group "=== SCALP ENGINE: EXIT MANAGEMENT ==="
input int      InpScalpTimeStopMin        = 15;     // Close scalps that have not worked after N minutes (0=off)
input double   InpScalpTimeStopR          = 0.20;   // ...unless they are at least this many R in profit
input double   InpScalpTPR                = 2.20;   // Bank the remainder at this R multiple (0=off)
input double   InpScalpTrailStartR        = 1.20;   // ATR trail starts at this R (scalps)
input double   InpScalpTrailATR           = 0.70;   // Trail distance in ATR(M5) (scalps)
input bool     InpScalpAdverseExit        = true;   // Exit early on a decisive opposite M1 impulse before break-even
input int      InpFlattenMinOfDay         = 1320;   // Flatten scalps at this server minute-of-day (1320=22:00; Friday -60), 0=off

//--- Operational Settings
input group "=== OPERATIONAL CONSTANTS ==="
input ulong    InpMagicNumber             = 202601; // Magic Number
input bool     InpEnableCSVLogging        = true;   // Enable Section 12 CSV Logs

//--- Global Engine Singletons
CLogger                 g_logger;
CDecisionLogger         g_dec_logger;
CDataModel              g_data;
CGates                  g_gates;
CRegimeEngine           g_regime_engine;
CEngineA_TrendPullback  g_engine_a;
CEngineB_Breakout       g_engine_b;
CEngineC_MeanReversion  g_engine_c;
CRiskEngine             g_risk_engine;
CTradeManager           g_trade_manager;
CExecutionStateMachine  g_exec_sm;
CScalpEngine           g_scalp_engine;
CPanelGUI               g_panel;

//--- State & Telemetry Tracking
datetime                g_last_m5_bar_time = 0;
SRegimeState            g_regime_state;
SGateResults            g_gate_results;
SSignalResult           g_last_signal;
SStrategyDiagnostic     g_diagnostic;
SDrySignal              g_dry_a;
SDrySignal              g_dry_b;
SDrySignal              g_dry_c;
SScalpState             g_scalp;
SFunnel                 g_funnel;
datetime                g_last_m1_bar_time = 0;
datetime                g_funnel_day       = 0;

//+------------------------------------------------------------------+
//| Update Strategy Diagnostics & Dry Candidate Scans (§9 & §12)     |
//+------------------------------------------------------------------+
void UpdateStrategyDiagnostic(void)
{
   ZeroMemory(g_diagnostic);

   // 1. Run Candidate Dry-Scans on all 3 engines
   g_engine_a.EvaluateDryCandidate(g_data, g_regime_state, g_dry_a);
   g_engine_b.EvaluateDryCandidate(_Symbol, g_data, g_regime_state, g_dry_b);
   g_engine_c.EvaluateDryCandidate(g_data, g_regime_state, g_dry_c);

   // 2. Populate Diagnostic Callout based on Active Regime
   switch(g_regime_state.active_regime)
   {
      case REGIME_TREND_UP:
      case REGIME_TREND_DN:
      {
         g_diagnostic.active_engine_name = "Trend-Pullback (Engine A)";
         g_diagnostic.condition1_name    = g_dry_a.condition1_desc;
         g_diagnostic.condition1_pass    = g_dry_a.condition1_pass;
         g_diagnostic.condition2_name    = g_dry_a.condition2_desc;
         g_diagnostic.condition2_pass    = g_dry_a.condition2_pass;
         g_diagnostic.condition3_name    = g_dry_a.condition3_desc;
         g_diagnostic.condition3_pass    = g_dry_a.condition3_pass;

         if(!g_dry_a.condition1_pass)      g_diagnostic.next_action = "WAITING FOR EMA21 PULLBACK";
         else if(!g_dry_a.condition2_pass) g_diagnostic.next_action = "WAITING FOR REJECTION WICK RATIO >= 1.50";
         else if(!g_dry_a.condition3_pass) g_diagnostic.next_action = "WAITING FOR MOMENTUM CONFIRMATION";
         else                              g_diagnostic.next_action = "VALID SETUP -> EXECUTING PULLBACK";
         break;
      }

      case REGIME_EXPANSION:
      {
         g_diagnostic.active_engine_name = "Breakout (Engine B)";
         g_diagnostic.condition1_name    = g_dry_b.condition1_desc;
         g_diagnostic.condition1_pass    = g_dry_b.condition1_pass;
         g_diagnostic.condition2_name    = g_dry_b.condition2_desc;
         g_diagnostic.condition2_pass    = g_dry_b.condition2_pass;
         g_diagnostic.condition3_name    = g_dry_b.condition3_desc;
         g_diagnostic.condition3_pass    = g_dry_b.condition3_pass;

         if(!g_dry_b.condition1_pass)      g_diagnostic.next_action = "WAITING FOR RANGE WIDTH IN [0.8, 3.0] ATR";
         else if(!g_dry_b.condition2_pass) g_diagnostic.next_action = "WAITING FOR BREAKOUT BREACH";
         else if(!g_dry_b.condition3_pass) g_diagnostic.next_action = "WAITING FOR 2 MOMENTUM CLOSES";
         else                              g_diagnostic.next_action = "BREAKOUT CONFIRMED -> STOP ORDER ACTIVE";
         break;
      }

      case REGIME_RANGE:
      {
         if(g_regime_state.atr_ratio > 1.3)
         {
            g_diagnostic.active_engine_name = "Breakout (Expansion in Range)";
            g_diagnostic.condition1_name    = g_dry_b.condition1_desc;
            g_diagnostic.condition1_pass    = g_dry_b.condition1_pass;
            g_diagnostic.condition2_name    = g_dry_b.condition2_desc;
            g_diagnostic.condition2_pass    = g_dry_b.condition2_pass;
            g_diagnostic.condition3_name    = g_dry_b.condition3_desc;
            g_diagnostic.condition3_pass    = g_dry_b.condition3_pass;
            g_diagnostic.next_action        = "WAITING FOR BREAKOUT BREACH";
         }
         else
         {
            g_diagnostic.active_engine_name = "Mean Reversion (Engine C)";
            g_diagnostic.condition1_name    = g_dry_c.condition1_desc;
            g_diagnostic.condition1_pass    = g_dry_c.condition1_pass;
            g_diagnostic.condition2_name    = g_dry_c.condition2_desc;
            g_diagnostic.condition2_pass    = g_dry_c.condition2_pass;
            g_diagnostic.condition3_name    = g_dry_c.condition3_desc;
            g_diagnostic.condition3_pass    = g_dry_c.condition3_pass;

            if(!g_dry_c.condition1_pass)      g_diagnostic.next_action = "WAITING FOR VWAP EXTENSION >= 1.2 ATR";
            else if(!g_dry_c.condition2_pass) g_diagnostic.next_action = "WAITING FOR BOLLINGER BAND TOUCH";
            else if(!g_dry_c.condition3_pass) g_diagnostic.next_action = "WAITING FOR REJECTION WICK RATIO >= 1.20";
            else                              g_diagnostic.next_action = "VALID FADE -> ENTERING MARKET";
         }
         break;
      }

      case REGIME_CHAOS:
      default:
      {
         g_diagnostic.active_engine_name = "None (Safety Standby)";
         g_diagnostic.condition1_name    = StringFormat("Spread Mult (%.2fx / %.2fx)", g_regime_state.chaos_spread_mult_val, g_regime_state.chaos_spread_mult_limit);
         g_diagnostic.condition1_pass    = !g_regime_state.chaos_spread_mult_fail;
         g_diagnostic.condition2_name    = StringFormat("Abs Spread (%.1f / %.1f pt)", g_regime_state.chaos_spread_abs_val, g_regime_state.chaos_spread_abs_limit);
         g_diagnostic.condition2_pass    = !g_regime_state.chaos_spread_abs_fail;
         g_diagnostic.condition3_name    = StringFormat("ATR Pctl (%.4f / %.4f)", g_regime_state.chaos_atr_p99_val, g_regime_state.chaos_atr_p99_limit);
         g_diagnostic.condition3_pass    = !g_regime_state.chaos_atr_p99_fail;
         g_diagnostic.next_action        = StringFormat("CHAOS DETECTED (%s) -> SAFETY STANDBY", g_regime_state.primary_chaos_reason);
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Daily funnel reset (server day)                                  |
//+------------------------------------------------------------------+
void ResetFunnelIfNewDay(void)
{
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);
   mdt.hour = 0;
   mdt.min  = 0;
   mdt.sec  = 0;
   datetime day_start = StructToTime(mdt);
   if(day_start != g_funnel_day)
   {
      g_funnel_day = day_start;
      g_funnel.Reset();
   }
}

//+------------------------------------------------------------------+
//| M1 scalp pipeline - runs once per closed M1 bar                  |
//|   gates -> M15 regime bias -> M5 location -> M1 trigger -> send  |
//| Every exit increments exactly one funnel bucket so the panel can |
//| show where each bar died.                                        |
//+------------------------------------------------------------------+
void RunScalpPipeline(double spread_pts, double point)
{
   ResetFunnelIfNewDay();
   g_funnel.scanned++;

   bool gates_ok = g_gates.EvaluateAllGates(g_data, g_regime_state, spread_pts, point, g_gate_results);

   // Always evaluate: the panel shows the live checklist even while a gate blocks entry
   SSignalResult sig;
   g_scalp_engine.Evaluate(g_data, g_regime_state, g_scalp, sig);

   if(!gates_ok)
   {
      string fg = g_gate_results.fail_gate;
      if(fg == "G1_WARMUP")       g_funnel.warmup_blocked++;
      else if(fg == "G2_SESSION") g_funnel.session_blocked++;
      else if(fg == "G3_SPREAD")  g_funnel.spread_blocked++;
      else if(fg == "G4_NEWS")    g_funnel.news_blocked++;
      else if(fg == "G5_REGIME")  g_funnel.regime_blocked++;
      else if(fg == "G6_RISK")
      {
         // The 1-position cap trips G6 for every bar of an open trade: that is not a "risk block"
         if(g_trade_manager.HasActivePosition()) g_funnel.in_trade++;
         else                                    g_funnel.risk_blocked++;
      }
      else                        g_funnel.exec_blocked++;
      return;
   }
   g_funnel.gates_passed++;

   if(!g_scalp.regime_ok)    return;
   g_funnel.regime_ok++;

   if(!g_scalp.location_ok)  return;
   g_funnel.location_ok++;

   if(!g_scalp.trigger_ok)   return;
   g_funnel.trigger_ok++;

   if(!sig.valid)
   {
      // Setup is complete but a context filter (H1 bias / room / RSI / ATR floor) or the grade refused it
      g_funnel.ctx_blocked++;
      return;
   }

   // Post-loss cooldown (scaled by consecutive losses) and daily entry cap
   int streak = g_gates.GetConsecLosses();
   if(InpScalpLossCooldownMin > 0 && streak > 0 && g_gates.GetLastCloseTime() > 0)
   {
      long wait_sec = (long)InpScalpLossCooldownMin * 60 * (long)MathMin(streak, 3);
      if((long)(TimeCurrent() - g_gates.GetLastCloseTime()) < wait_sec)
      {
         g_funnel.cooldown_blocked++;
         return;
      }
   }
   if(InpMaxEntriesPerDay > 0 && g_funnel.dispatched >= InpMaxEntriesPerDay)
   {
      g_funnel.cooldown_blocked++;
      return;
   }

   // Do not stack on a signal the M5-close path already queued this tick
   if(g_exec_sm.GetState() == STATE_PRE_TRADE_CHECK)
      return;

   if(g_exec_sm.DispatchSignal(sig))
   {
      g_funnel.dispatched++;
      if(sig.sub_type == "SWEEP") g_funnel.sweep_entries++;
      g_last_signal = sig;
      if(InpEnableDecisionLog)
      {
         g_dec_logger.LogTradeLifecycleEvent("SCALP_TRIGGER", sig.pass_details);
      }
   }
   else
   {
      g_funnel.exec_blocked++;
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   string symbol = _Symbol;

   // 1. Initialize Loggers
   g_logger.SetEnabled(InpEnableCSVLogging);
   g_logger.LogEvent("INIT", "Starting XAU-MEGA-SCALPER v0.2 Debug & Research Edition...");

   if(InpEnableDecisionLog)
   {
      g_dec_logger.Init();
      g_dec_logger.LogTradeLifecycleEvent("SYSTEM_INIT", "EA initialized on " + symbol + " in Continuous Research Mode.");
   }

   // 2. Initialize Data Model
   if(!g_data.Init(symbol,
                   InpADXPeriod,
                   InpATRPeriodM15,
                   InpATRPeriodM5,
                   InpEMAFast,
                   InpEMAMid,
                   InpEMASlow,
                   InpBBPeriod,
                   InpBBSigma,
                   InpDonchianPeriod,
                   InpVWAPSlopeBars,
                   InpATRPctLookbackBars,
                   InpATRPctChaosPctl,
                   InpSpreadAvgLookbackTicks))
   {
      Print("[INIT FATAL] DataModel failed to initialize indicators!");
      return INIT_FAILED;
   }

   // 3. Initialize Gates with Explicit Research Mode Toggle
   g_gates.Init(symbol,
                InpMagicNumber,
                InpContinuousResearchMode,
                InpMaxSpreadATRRatio,
                InpDailyDDPct,
                InpConsecLossLimit,
                InpCooldownBars,
                InpMaxPositions,
                InpNewsBlackoutMin);

   // 4. Initialize Regime Engine
   g_regime_engine.Init(InpADXPeriod,
                        InpADXTrendMin,
                        InpATRPeriodM15,
                        InpATRPeriodM5,
                        InpATRExpansionRatio,
                        InpATRPctLookbackBars,
                        InpATRPctChaosPctl,
                        InpSpreadAvgLookbackTicks,
                        InpSpreadChaosMult,
                        InpSpreadChaosAbsPts,
                        InpVWAPSlopeBars,
                        InpDwellBars);

   // 5. Initialize Engine A (Trend-Pullback)
   g_engine_a.Init(InpEMAFast,
                   InpEMAMid,
                   InpEMASlow,
                   InpPullbackATRFrac,
                   InpRejectionWickRatio,
                   InpMomentumLookbackBars,
                   InpATRSLMult);

   // 6. Initialize Engine B (Breakout)
   g_engine_b.Init(InpORWindowMin,
                   InpDonchianPeriod,
                   InpBreakoutBufferATR,
                   InpRangeMinATR,
                   InpRangeMaxATR,
                   InpMomentumConfirmBars,
                   InpATRSLMult);

   // 7. Initialize Engine C (Mean Reversion)
   g_engine_c.Init(InpBBPeriod,
                   InpBBSigma,
                   InpVWAPDevATRMin,
                   InpBandTouchLookback,
                   InpRejectionWickRatioMR,
                   InpMaxFadeExtensionATR);

   // 7b. Initialize Scalp Engine (M1 trigger layer + market context)
   SScalpConfig scfg;
   scfg.enabled         = InpScalpEnabled;
   scfg.sweep_enabled   = InpSweepEnabled;
   scfg.use_h1_bias     = InpUseH1Bias;
   scfg.lookback_bars   = InpScalpLookbackM1;
   scfg.swing_bars      = InpScalpSwingBarsM1;
   scfg.zone_atr        = InpScalpZoneATR;
   scfg.hold_atr        = InpScalpHoldATR;
   scfg.max_ext_atr     = InpScalpMaxExtATR;
   scfg.min_body_frac   = InpScalpMinBodyFrac;
   scfg.sl_buffer_atr   = InpScalpSLBufferATR;
   scfg.min_sl_atr      = InpScalpMinSLATR;
   scfg.atr_sl_mult     = InpATRSLMult;
   scfg.min_room_atr    = InpScalpMinRoomATR;
   scfg.rsi_max         = InpScalpRSIMax;
   scfg.min_atr_usd     = InpScalpMinATRUsd;
   scfg.min_grade_pts   = InpScalpMinGradePts;
   scfg.sweep_min_depth = InpSweepMinDepthATR;
   scfg.sweep_max_depth = InpSweepMaxDepthATR;
   scfg.sweep_close_pos = InpSweepClosePos;
   scfg.sweep_disp_mult = InpSweepDispMult;
   scfg.round_step      = InpRoundStep;
   scfg.asian_start     = InpAsianStartHour;
   scfg.asian_end       = InpAsianEndHour;
   scfg.london_start    = InpLondonStartHour;
   scfg.overlap_start   = InpOverlapStartHour;
   scfg.overlap_end     = InpOverlapEndHour;
   scfg.ny_end          = InpNYEndHour;
   if(!g_scalp_engine.Init(symbol, scfg))
   {
      Print("[INIT FATAL] Scalp market-context indicators failed to initialize!");
      return INIT_FAILED;
   }
   g_scalp.Reset();
   g_funnel.Reset();

   // 8. Initialize Risk Engine
   g_risk_engine.Init(symbol,
                      InpRiskPerTradePct,
                      InpATRSLMult,
                      InpDailyDDPct,
                      InpConsecLossLimit,
                      InpCooldownBars,
                      InpMaxPositions);

   // 9. Initialize Trade Manager
   g_trade_manager.Init(symbol,
                        InpMagicNumber,
                        &g_logger,
                        InpSpreadChaosAbsPts,
                        InpDailyDDPct,
                        InpContinuousResearchMode);
   g_trade_manager.ConfigureScalpExits(InpScalpTimeStopMin,
                                       InpScalpTimeStopR,
                                       InpScalpTPR,
                                       InpScalpTrailStartR,
                                       InpScalpTrailATR,
                                       InpFlattenMinOfDay,
                                       InpScalpAdverseExit);

   // 10. Initialize Execution State Machine
   g_exec_sm.Init(symbol,
                  InpMagicNumber,
                  &g_logger,
                  &g_risk_engine,
                  &g_gates,
                  &g_trade_manager);

   // 11. Execute Instant Baseline Calculation (Zero Cold-Start Delay)
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double spread_pts = (point > 0.0) ? (ask - bid) / point : 0.0;
   g_data.UpdateTickSpread(spread_pts);

   datetime last_closed_bar = iTime(symbol, PERIOD_M5, 1);
   g_regime_engine.UpdateOnBarClose(g_data, spread_pts, last_closed_bar, g_regime_state);
   g_gates.EvaluateAllGates(g_data, g_regime_state, spread_pts, point, g_gate_results);
   UpdateStrategyDiagnostic();

   {
      SSignalResult init_sig;
      g_scalp_engine.Evaluate(g_data, g_regime_state, g_scalp, init_sig);
   }
   g_last_m1_bar_time = iTime(symbol, PERIOD_M1, 0);
   ResetFunnelIfNewDay();

   // 12. Initialize On-Chart Control Panel
   if(InpEnableOnChartPanel)
   {
      ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
      ChartSetInteger(0, CHART_FOREGROUND, false);
      g_panel.Init(&g_trade_manager, &g_exec_sm, &g_dec_logger);
      g_panel.Update(g_regime_state, g_gate_results, g_last_signal, g_diagnostic, g_dry_a, g_dry_b, g_dry_c, g_scalp, g_funnel);
   }

   // 250ms Timer for UI Refresh
   EventSetMillisecondTimer(250);

   g_last_m5_bar_time = iTime(symbol, PERIOD_M5, 0);
   g_logger.LogEvent("INIT_SUCCESS", "XAU-MEGA-SCALPER v0.2 DEBUG initialized successfully.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(InpEnableOnChartPanel)
   {
      ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
      g_panel.Destroy();
   }
   g_dec_logger.LogTradeLifecycleEvent("SYSTEM_DEINIT", StringFormat("Deinit reason: %d", reason));
   g_dec_logger.Close();
   g_logger.Close();
   g_data.ReleaseIndicators();
   g_scalp_engine.Release();
}

//+------------------------------------------------------------------+
//| High-Frequency UI & Diagnostic Timer                             |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(InpEnableOnChartPanel)
   {
      UpdateStrategyDiagnostic();
      g_panel.Update(g_regime_state, g_gate_results, g_last_signal, g_diagnostic, g_dry_a, g_dry_b, g_dry_c, g_scalp, g_funnel);
   }
}

//+------------------------------------------------------------------+
//| Interactive Chart Events (Tabs & Button Clicks)                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(InpEnableOnChartPanel)
   {
      g_panel.OnChartEvent(id, lparam, dparam, sparam);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   string symbol = _Symbol;
   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double ask    = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(symbol, SYMBOL_BID);
   double spread_pts = (point > 0.0) ? ((ask - bid) / point) : 0.0;

   // 1. Tick spread tracking
   g_data.UpdateTickSpread(spread_pts);

   // 2. Keep spread & session live on every tick
   g_gate_results.spread_pts = spread_pts;
   g_gate_results.spread_price = spread_pts * point;
   if(g_regime_state.atr_m5 > 0.0)
      g_gate_results.spread_atr_ratio = g_gate_results.spread_price / g_regime_state.atr_m5;
   g_gate_results.spread_limit_ratio = InpMaxSpreadATRRatio;
   g_gate_results.g3_spread = (g_gate_results.spread_atr_ratio <= InpMaxSpreadATRRatio);
   string dummy_sess = "";
   g_gate_results.g2_session = g_gates.EvaluateG2(TimeCurrent(), dummy_sess);

   // 3. Continuous tick management of open positions (§11)
   double current_dd = 0.0;
   int open_pos = 0;
   string dummy_reason = "";
   g_gates.EvaluateG6(g_gate_results);
   g_trade_manager.OnTickManage(g_regime_state, spread_pts, g_gate_results.daily_dd_pct);

   // 4. Execution state machine tick processing (§10)
   g_exec_sm.ProcessTickExecution(g_regime_state, spread_pts, point);

   // ----------------------------------------------------------------
   // 5. Closed-Bar Rule (§2): Evaluate on M5 Bar Close
   // ----------------------------------------------------------------
   datetime current_m5_bar_time = iTime(symbol, PERIOD_M5, 0);
   if(current_m5_bar_time != g_last_m5_bar_time)
   {
      datetime closed_bar_time = g_last_m5_bar_time;
      g_last_m5_bar_time = current_m5_bar_time;

      g_trade_manager.OnM5BarClose();
      g_exec_sm.OnM5BarClose();

      // Step A: Update Regime Engine on closed bar (§4)
      if(!g_regime_engine.UpdateOnBarClose(g_data, spread_pts, closed_bar_time, g_regime_state))
      {
         Print("[EVAL ERROR] Regime Engine update failed on bar close!");
         return;
      }

      // Step B: Evaluate Gates G1..G7 in strict order (§3)
      bool gates_passed = g_gates.EvaluateAllGates(g_data, g_regime_state, spread_pts, point, g_gate_results);

      // Step C: Run Dry Candidate Scans for all 3 engines (§12)
      g_engine_a.EvaluateDryCandidate(g_data, g_regime_state, g_dry_a);
      g_engine_b.EvaluateDryCandidate(symbol, g_data, g_regime_state, g_dry_b);
      g_engine_c.EvaluateDryCandidate(g_data, g_regime_state, g_dry_c);

      // Step D: Dispatch Strategy Signal matching active regime (§8)
      SSignalResult signal;
      signal.valid            = false;
      signal.engine           = ENGINE_NONE;
      signal.direction        = DIR_NONE;
      signal.is_stop_order    = false;
      signal.stop_entry_price = 0.0;
      signal.sl_price         = 0.0;
      signal.atr_m5_at_signal = g_regime_state.atr_m5;
      signal.sub_type         = "NONE";
      signal.pass_details     = "";
      signal.fail_code        = "";
      signal.fail_details     = "";
      signal.signal_time      = TimeCurrent();
      signal.score            = 0;
      signal.risk_mult        = 1.0;

      string final_decision  = "NO_TRADE";
      string detailed_reason = "";

      if(!gates_passed)
      {
         final_decision  = "NO_TRADE";
         detailed_reason = StringFormat("Blocked by Gate %s: %s", g_gate_results.fail_gate, g_gate_results.fail_reason);
         signal.fail_code    = g_gate_results.fail_gate;
         signal.fail_details = g_gate_results.fail_reason;
      }
      else
      {
         switch(g_regime_state.active_regime)
         {
            case REGIME_TREND_UP:
            case REGIME_TREND_DN:
               signal.engine = ENGINE_A_TREND_PULLBACK;
               g_engine_a.Evaluate(g_data, g_regime_state, signal);
               break;

            case REGIME_EXPANSION:
               signal.engine = ENGINE_B_BREAKOUT;
               g_engine_b.Evaluate(symbol, g_data, g_regime_state, signal);
               break;

            case REGIME_RANGE:
               if(g_regime_state.atr_ratio > 1.3)
               {
                  signal.engine = ENGINE_B_BREAKOUT;
                  g_engine_b.Evaluate(symbol, g_data, g_regime_state, signal);
               }
               else
               {
                  signal.engine = ENGINE_C_MEAN_REVERSION;
                  g_engine_c.Evaluate(g_data, g_regime_state, signal);
               }
               break;

            case REGIME_CHAOS:
            default:
               final_decision = "NO_TRADE";
               detailed_reason = StringFormat("Trading forbidden in CHAOS (%s)", g_regime_state.primary_chaos_reason);
               signal.fail_code = "REGIME_CHAOS";
               signal.fail_details = detailed_reason;
               break;
         }

         if(signal.valid)
         {
            final_decision  = "TRADE_DISPATCHED";
            detailed_reason = signal.pass_details;
            g_last_signal   = signal;
            g_exec_sm.DispatchSignal(signal);
         }
         else
         {
            final_decision  = "NO_TRADE";
            detailed_reason = StringFormat("%s condition failed: %s (%s)",
                                           EngineToString(signal.engine), signal.fail_code, signal.fail_details);
         }
      }

      // Step E: Write Structured CSV Log (§12)
      g_logger.LogBarEvaluation(closed_bar_time,
                                g_regime_state,
                                g_gate_results,
                                signal,
                                final_decision);

      // Step F: Write Exhaustive Diagnostic M5 Candle Decision Block (§13)
      if(InpEnableDecisionLog)
      {
         double cur_price = (bid + ask) * 0.5;
         g_dec_logger.LogCandleEvaluation(closed_bar_time,
                                          cur_price,
                                          g_regime_state,
                                          g_gate_results,
                                          g_dry_a,
                                          g_dry_b,
                                          g_dry_c,
                                          signal,
                                          final_decision,
                                          detailed_reason);
      }

      // Step G: Refresh Diagnostic View
      if(InpEnableOnChartPanel)
      {
         UpdateStrategyDiagnostic();
         g_panel.Update(g_regime_state, g_gate_results, g_last_signal, g_diagnostic, g_dry_a, g_dry_b, g_dry_c, g_scalp, g_funnel);
      }
   }

   // ----------------------------------------------------------------
   // 6. M1 Scalp Pipeline (M15 bias -> M5 location -> M1 trigger)
   //    Evaluated on every closed M1 bar, independent of the M5 close.
   // ----------------------------------------------------------------
   datetime current_m1_bar_time = iTime(symbol, PERIOD_M1, 0);
   if(current_m1_bar_time != g_last_m1_bar_time)
   {
      g_last_m1_bar_time = current_m1_bar_time;
      g_trade_manager.OnM1BarClose();        // adverse-impulse exit for unprotected scalps
      RunScalpPipeline(spread_pts, point);

      if(InpEnableOnChartPanel)
      {
         g_panel.Update(g_regime_state, g_gate_results, g_last_signal, g_diagnostic, g_dry_a, g_dry_b, g_dry_c, g_scalp, g_funnel);
      }
   }
}
