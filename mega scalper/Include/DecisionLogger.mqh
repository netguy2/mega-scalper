//+------------------------------------------------------------------+
//|                                               DecisionLogger.mqh |
//|                             XAU-MEGA-SCALPER Formal Spec v0.2    |
//|                             DEBUG & CONTINUOUS RESEARCH EDITION  |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"

class CDecisionLogger
{
private:
   int      m_file_handle;
   string   m_filename;
   string   m_recent_log_lines[12];
   int      m_recent_count;

   void OpenLogFile(void)
   {
      m_filename = "XAU_MEGA_DECISIONS.log";
      m_file_handle = FileOpen(m_filename, FILE_READ | FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(m_file_handle != INVALID_HANDLE)
      {
         FileSeek(m_file_handle, 0, SEEK_END);
         if(FileSize(m_file_handle) == 0)
         {
            string banner = "========================================================================================\n"
                            "       XAU-MEGA-SCALPER v0.2 DEBUG — COMPREHENSIVE STRATEGY & DECISION AUDIT LOG       \n"
                            "       Records Every Candle: Raw Metrics, Regime Dwell, 3-Engine Dry Scans, Gates      \n"
                            "========================================================================================\n\n";
            FileWriteString(m_file_handle, banner);
            FileFlush(m_file_handle);
         }
      }
   }

public:
   CDecisionLogger(void) : m_file_handle(INVALID_HANDLE), m_filename(""), m_recent_count(0)
   {
      for(int i = 0; i < 12; i++) m_recent_log_lines[i] = "";
   }

   ~CDecisionLogger(void)
   {
      Close();
   }

   void Init(void)
   {
      OpenLogFile();
      AddRecentLine("SYSTEM INITIALIZED - AUDIT LOG ACTIVE");
   }

   void Close(void)
   {
      if(m_file_handle != INVALID_HANDLE)
      {
         FileClose(m_file_handle);
         m_file_handle = INVALID_HANDLE;
      }
   }

   void AddRecentLine(string line)
   {
      string t = TimeToString(TimeCurrent(), TIME_SECONDS);
      string entry = StringFormat("[%s] %s", t, line);

      for(int i = 11; i > 0; i--)
         m_recent_log_lines[i] = m_recent_log_lines[i - 1];

      m_recent_log_lines[0] = entry;
      if(m_recent_count < 12) m_recent_count++;
   }

   string GetRecentLine(int index) const
   {
      if(index >= 0 && index < 12)
         return m_recent_log_lines[index];
      return "";
   }

   int GetRecentCount(void) const { return m_recent_count; }

   //+------------------------------------------------------------------+
   //| Write Exhaustive Diagnostic M5 Evaluation Block (§13)            |
   //+------------------------------------------------------------------+
   void LogCandleEvaluation(datetime bar_time,
                            double current_price,
                            const SRegimeState &regime,
                            const SGateResults &gates,
                            const SDrySignal &dry_a,
                            const SDrySignal &dry_b,
                            const SDrySignal &dry_c,
                            const SSignalResult &signal,
                            string final_outcome,
                            string detailed_reason)
   {
      if(m_file_handle == INVALID_HANDLE)
         OpenLogFile();

      string t_str = TimeToString(bar_time, TIME_DATE | TIME_MINUTES);
      string block = "";

      // 1. Raw Market
      StringConcatenate(block,
         "========================================================================================\n",
         "CANDLE EVALUATION: ", t_str, "  |  Server Time: ", TimeToString(TimeCurrent(), TIME_SECONDS), "\n",
         "RAW MARKET\n",
         "----------------------------------------------------------------------------------------\n",
         "  Price:        ", DoubleToString(current_price, 2), "\n",
         "  Spread:       ", DoubleToString(gates.spread_pts, 1), " pts (", DoubleToString(gates.spread_atr_ratio, 3), " ATR) [Limit: ", DoubleToString(gates.spread_limit_ratio, 3), " ATR]\n",
         "  ATR M5:       ", DoubleToString(regime.atr_m5, 2), "  |  ATR Ratio: ", DoubleToString(regime.atr_ratio, 2), " (Expansion thresh: 1.80)\n",
         "  ATR M15 Pct:  ", DoubleToString(regime.atr_pct, 4), "  |  P99: ", DoubleToString(regime.atr_pct_p99, 4), "\n",
         "  ADX M15:      ", DoubleToString(regime.adx_m15, 1), " (Trend min: 25.0)\n",
         "  Session VWAP: ", DoubleToString(regime.session_vwap, 2), "  |  VWAP Slope: ", DoubleToString(regime.vwap_slope, 4), "\n",
         "  M15 EMAs:     EMA9: ", DoubleToString(regime.ema9_m15, 2), "  EMA21: ", DoubleToString(regime.ema21_m15, 2), "  EMA50: ", DoubleToString(regime.ema50_m15, 2), "\n\n"
      );

      // 2. Regime Engine
      StringConcatenate(block, block,
         "REGIME STATE MACHINE\n",
         "----------------------------------------------------------------------------------------\n",
         "  Raw Regime:       ", RegimeToString(regime.raw_regime), "\n",
         "  Candidate Regime: ", RegimeToString(regime.candidate_regime), "\n",
         "  Active Regime:    ", RegimeToString(regime.active_regime), "\n",
         "  Persistence:      ", IntegerToString(regime.persist_count), " / ", IntegerToString(regime.persist_required), " bars\n",
         "  Dwell:            ", IntegerToString(regime.dwell_count), " / ", IntegerToString(regime.dwell_required), " bars (Dwell OK: ", regime.dwell_ok ? "YES" : "NO", ")\n",
         "  Chaos Check:      ", regime.primary_chaos_reason == "NONE" ? "NO (CLEAN)" : "TRIGGERED (" + regime.primary_chaos_reason + ")\n",
         "    - Spread Mult:  ", regime.chaos_spread_mult_fail ? "FAIL" : "PASS", " (", DoubleToString(regime.chaos_spread_mult_val, 2), "x / limit ", DoubleToString(regime.chaos_spread_mult_limit, 2), "x)\n",
         "    - Abs Spread:   ", regime.chaos_spread_abs_fail ? "FAIL" : "PASS", " (", DoubleToString(regime.chaos_spread_abs_val, 1), " pts / limit ", DoubleToString(regime.chaos_spread_abs_limit, 1), " pts)\n",
         "    - ATR Pct P99:  ", regime.chaos_atr_p99_fail ? "FAIL" : "PASS", " (", DoubleToString(regime.chaos_atr_p99_val, 4), " / limit ", DoubleToString(regime.chaos_atr_p99_limit, 4), ")\n",
         "  Trend Score:      ", IntegerToString(regime.total_trend_score), " / 100\n",
         "    - EMA Align:    ", IntegerToString(regime.score_ema_alignment), " / 20\n",
         "    - ADX Strength: ", IntegerToString(regime.score_adx), " / 20\n",
         "    - VWAP Pos:     ", IntegerToString(regime.score_vwap_pos), " / 15\n",
         "    - VWAP Slope:   ", IntegerToString(regime.score_vwap_slope), " / 15\n",
         "    - Structure:    ", IntegerToString(regime.score_structure), " / 15\n",
         "    - Momentum:     ", IntegerToString(regime.score_momentum), " / 15\n\n"
      );

      // 3. Dry Strategy Candidates (§12)
      StringConcatenate(block, block,
         "STRATEGY CANDIDATE SCANS (ALL 3 ENGINES)\n",
         "----------------------------------------------------------------------------------------\n",
         "  [Engine A - Trend-Pullback]:  ", dry_a.status_desc, "\n",
         "    - Condition 1: ", dry_a.condition1_desc, " -> ", dry_a.condition1_pass ? "PASS" : "FAIL", "\n",
         "    - Condition 2: ", dry_a.condition2_desc, " -> ", dry_a.condition2_pass ? "PASS" : "FAIL", "\n",
         "    - Condition 3: ", dry_a.condition3_desc, " -> ", dry_a.condition3_pass ? "PASS" : "FAIL", "\n",
         "    - Rejection:   ", dry_a.primary_rejection_reason != "" ? dry_a.primary_rejection_reason : "None (Valid)", "\n",
         "  [Engine B - Breakout]:        ", dry_b.status_desc, "\n",
         "    - Condition 1: ", dry_b.condition1_desc, " -> ", dry_b.condition1_pass ? "PASS" : "FAIL", "\n",
         "    - Condition 2: ", dry_b.condition2_desc, " -> ", dry_b.condition2_pass ? "PASS" : "FAIL", "\n",
         "    - Condition 3: ", dry_b.condition3_desc, " -> ", dry_b.condition3_pass ? "PASS" : "FAIL", "\n",
         "    - Rejection:   ", dry_b.primary_rejection_reason != "" ? dry_b.primary_rejection_reason : "None (Valid)", "\n",
         "  [Engine C - Mean Reversion]:  ", dry_c.status_desc, "\n",
         "    - Condition 1: ", dry_c.condition1_desc, " -> ", dry_c.condition1_pass ? "PASS" : "FAIL", "\n",
         "    - Condition 2: ", dry_c.condition2_desc, " -> ", dry_c.condition2_pass ? "PASS" : "FAIL", "\n",
         "    - Condition 3: ", dry_c.condition3_desc, " -> ", dry_c.condition3_pass ? "PASS" : "FAIL", "\n",
         "    - Rejection:   ", dry_c.primary_rejection_reason != "" ? dry_c.primary_rejection_reason : "None (Valid)", "\n\n"
      );

      // 4. Execution Gates
      StringConcatenate(block, block,
         "EXECUTION GATES CHECKLIST (G1-G7)\n",
         "----------------------------------------------------------------------------------------\n",
         "  G1 Warmup:    ", gates.g1_warmup ? "PASS" : "FAIL", " (M15:", IntegerToString(gates.m15_bars_have), "/", IntegerToString(gates.m15_bars_req),
         ", M5:", IntegerToString(gates.m5_bars_have), "/", IntegerToString(gates.m5_bars_req),
         ", M1:", IntegerToString(gates.m1_bars_have), "/", IntegerToString(gates.m1_bars_req),
         ", VWAP:", IntegerToString(gates.vwap_bars_have), "/", IntegerToString(gates.vwap_bars_req), ")\n",
         "  G2 Session:   ", gates.g2_session ? "PASS" : "FAIL", " (London+NY 07:00-20:00)\n",
         "  G3 Spread:    ", gates.g3_spread ? "PASS" : "FAIL", " (", DoubleToString(gates.spread_atr_ratio, 3), " <= ", DoubleToString(gates.spread_limit_ratio, 3), " ATR)\n",
         "  G4 News:      ", gates.g4_news ? "PASS" : "FAIL", "\n",
         "  G5 Regime:    ", gates.g5_regime ? "PASS" : "FAIL", " (Dwell:", regime.dwell_ok ? "OK" : "WAIT", ", Chaos:", regime.primary_chaos_reason, ")\n",
         "  G6 Risk:      ", gates.g6_risk ? "PASS" : "FAIL", " (Open Pos: ", IntegerToString(gates.open_positions), "/", IntegerToString(gates.max_positions), ", Daily DD: ", DoubleToString(gates.daily_dd_pct*100.0, 2), "%)\n",
         "  G7 Execution: ", gates.g7_execution ? "PASS" : "FAIL", " (Terminal connected & algo trading enabled)\n\n"
      );

      // 5. Final Decision
      if(signal.valid)
      {
         StringConcatenate(block, block,
            ">>> FINAL OUTCOME: [TRADE DISPATCHED] <<<\n",
            "    Dispatched Engine: ", EngineToString(signal.engine), " ", DirectionToString(signal.direction), "\n",
            "    Entry Type:        ", signal.is_stop_order ? "STOP ORDER" : "MARKET ORDER", "\n",
            "    Stop/Market Level: ", DoubleToString(signal.stop_entry_price > 0 ? signal.stop_entry_price : current_price, 2), "\n",
            "    Calculated SL:     ", DoubleToString(signal.sl_price, 2), "\n",
            "    Why it traded:     ", signal.pass_details, "\n"
         );
         AddRecentLine(StringFormat("TRADE: %s %s @ %.2f | SL: %.2f",
                                    EngineToString(signal.engine), DirectionToString(signal.direction), current_price, signal.sl_price));
      }
      else
      {
         StringConcatenate(block, block,
            ">>> FINAL OUTCOME: [NO TRADE] <<<\n",
            "    Primary Reason:    ", detailed_reason, "\n",
            "    Rejection Source:  ", signal.fail_code != "" ? signal.fail_code : gates.fail_gate, "\n"
         );
         AddRecentLine(StringFormat("NO TRADE: %s", detailed_reason));
      }

      StringConcatenate(block, block, "========================================================================================\n\n");

      if(m_file_handle != INVALID_HANDLE)
      {
         FileWriteString(m_file_handle, block);
         FileFlush(m_file_handle);
      }
   }

   void LogTradeLifecycleEvent(string event_type, string description)
   {
      if(m_file_handle == INVALID_HANDLE)
         OpenLogFile();

      string t_str = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
      string line = StringFormat("[%s] [LIFECYCLE] [%s] %s\n", t_str, event_type, description);

      if(m_file_handle != INVALID_HANDLE)
      {
         FileWriteString(m_file_handle, line);
         FileFlush(m_file_handle);
      }

      AddRecentLine(StringFormat("%s: %s", event_type, description));
   }
};
