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

   // 12. Initialize On-Chart Control Panel
   if(InpEnableOnChartPanel)
   {
      ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
      ChartSetInteger(0, CHART_FOREGROUND, false);
      g_panel.Init(&g_trade_manager, &g_exec_sm, &g_dec_logger);
      g_panel.Update(g_regime_state, g_gate_results, g_last_signal, g_diagnostic, g_dry_a, g_dry_b, g_dry_c);
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
}

//+------------------------------------------------------------------+
//| High-Frequency UI & Diagnostic Timer                             |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(InpEnableOnChartPanel)
   {
      UpdateStrategyDiagnostic();
      g_panel.Update(g_regime_state, g_gate_results, g_last_signal, g_diagnostic, g_dry_a, g_dry_b, g_dry_c);
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
         g_panel.Update(g_regime_state, g_gate_results, g_last_signal, g_diagnostic, g_dry_a, g_dry_b, g_dry_c);
      }
   }
}
