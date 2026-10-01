//+------------------------------------------------------------------+
//|                                                 RegimeEngine.mqh |
//|                             XAU-MEGA-SCALPER Formal Spec v0.2    |
//|                             DEBUG & CONTINUOUS RESEARCH EDITION  |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"
#include "DataModel.mqh"

class CRegimeEngine
{
private:
   // Budgeted Parameters (§1)
   int      m_adx_period;
   double   m_adx_trend_min;
   int      m_atr_period_m15;
   int      m_atr_period_m5;
   double   m_atr_expansion_ratio;
   int      m_atr_pct_lookback_bars;
   double   m_atr_pct_chaos_pctl;
   int      m_spread_avg_lookback_ticks;
   double   m_spread_chaos_mult;
   double   m_spread_chaos_abs_pts;
   int      m_vwap_slope_bars;
   int      m_dwell_bars;

   // State tracking
   ENUM_REGIME m_active_regime;
   ENUM_REGIME m_candidate_regime;
   int         m_persist_counter;
   int         m_dwell_counter;
   bool        m_initialized;

   // Calculate Component-Based Trend Score (0-100) (§1)
   void CalculateTrendScore(const MqlRates &m5_rates[],
                            double ema9, double ema21, double ema50,
                            double adx, double vwap, double vwap_slope,
                            ENUM_REGIME raw,
                            SRegimeState &state)
   {
      state.score_ema_alignment = 0;
      state.score_adx           = 0;
      state.score_vwap_pos      = 0;
      state.score_vwap_slope    = 0;
      state.score_structure     = 0;
      state.score_momentum      = 0;

      bool is_bull = (ema9 >= ema21);

      // 1. M15 EMA Alignment (max 20)
      if(is_bull)
      {
         if(ema9 > ema21 && ema21 > ema50) state.score_ema_alignment = 20;
         else if(ema9 > ema21) state.score_ema_alignment = 10;
      }
      else
      {
         if(ema9 < ema21 && ema21 < ema50) state.score_ema_alignment = 20;
         else if(ema9 < ema21) state.score_ema_alignment = 10;
      }

      // 2. M15 ADX Strength (max 20)
      if(adx >= m_adx_trend_min)
      {
         double frac = (adx - m_adx_trend_min) / MathMax(25.0, 50.0 - m_adx_trend_min);
         state.score_adx = 10 + (int)MathMin(10, MathRound(frac * 10.0));
      }
      else
      {
         state.score_adx = (int)MathRound((adx / MathMax(1.0, m_adx_trend_min)) * 10.0);
      }

      // 3. VWAP Position (max 15)
      double close_m5 = m5_rates[0].close;
      if(is_bull && close_m5 > vwap) state.score_vwap_pos = 15;
      else if(!is_bull && close_m5 < vwap) state.score_vwap_pos = 15;

      // 4. VWAP Slope (max 15)
      if(is_bull && vwap_slope > 0.0)
      {
         state.score_vwap_slope = (int)MathMin(15, MathRound((vwap_slope / 0.05) * 15.0));
      }
      else if(!is_bull && vwap_slope < 0.0)
      {
         state.score_vwap_slope = (int)MathMin(15, MathRound((MathAbs(vwap_slope) / 0.05) * 15.0));
      }

      // 5. M5 Structure (max 15)
      if(is_bull)
      {
         if(m5_rates[0].high > m5_rates[1].high && m5_rates[0].low > m5_rates[1].low)
            state.score_structure = 15;
         else if(m5_rates[0].close > m5_rates[1].close)
            state.score_structure = 8;
      }
      else
      {
         if(m5_rates[0].high < m5_rates[1].high && m5_rates[0].low < m5_rates[1].low)
            state.score_structure = 15;
         else if(m5_rates[0].close < m5_rates[1].close)
            state.score_structure = 8;
      }

      // 6. Momentum (max 15)
      if(is_bull)
      {
         if(m5_rates[0].close > m5_rates[0].open && m5_rates[0].close > m5_rates[1].high)
            state.score_momentum = 15;
         else if(m5_rates[0].close > m5_rates[0].open)
            state.score_momentum = 8;
      }
      else
      {
         if(m5_rates[0].close < m5_rates[0].open && m5_rates[0].close < m5_rates[1].low)
            state.score_momentum = 15;
         else if(m5_rates[0].close < m5_rates[0].open)
            state.score_momentum = 8;
      }

      state.total_trend_score = state.score_ema_alignment + state.score_adx +
                                state.score_vwap_pos + state.score_vwap_slope +
                                state.score_structure + state.score_momentum;
   }

public:
   CRegimeEngine(void) : m_adx_period(14),
                         m_adx_trend_min(25.0),
                         m_atr_period_m15(14),
                         m_atr_period_m5(14),
                         m_atr_expansion_ratio(1.8),
                         m_atr_pct_lookback_bars(100),
                         m_atr_pct_chaos_pctl(99.0),
                         m_spread_avg_lookback_ticks(100),
                         m_spread_chaos_mult(3.0),
                         m_spread_chaos_abs_pts(450.0),
                         m_vwap_slope_bars(5),
                         m_dwell_bars(3),
                         m_active_regime(REGIME_NONE),
                         m_candidate_regime(REGIME_NONE),
                         m_persist_counter(0),
                         m_dwell_counter(0),
                         m_initialized(false)
   {
   }

   void Init(int adx_period,
             double adx_trend_min,
             int atr_period_m15,
             int atr_period_m5,
             double atr_expansion_ratio,
             int atr_pct_lookback_bars,
             double atr_pct_chaos_pctl,
             int spread_avg_lookback_ticks,
             double spread_chaos_mult,
             double spread_chaos_abs_pts,
             int vwap_slope_bars,
             int dwell_bars)
   {
      m_adx_period                = adx_period;
      m_adx_trend_min             = adx_trend_min;
      m_atr_period_m15            = atr_period_m15;
      m_atr_period_m5             = atr_period_m5;
      m_atr_expansion_ratio       = atr_expansion_ratio;
      m_atr_pct_lookback_bars     = atr_pct_lookback_bars;
      m_atr_pct_chaos_pctl        = atr_pct_chaos_pctl;
      m_spread_avg_lookback_ticks = spread_avg_lookback_ticks;
      m_spread_chaos_mult         = spread_chaos_mult;
      m_spread_chaos_abs_pts      = spread_chaos_abs_pts;
      m_vwap_slope_bars           = vwap_slope_bars;
      m_dwell_bars                = dwell_bars;

      m_active_regime    = REGIME_NONE;
      m_candidate_regime = REGIME_NONE;
      m_persist_counter  = 0;
      m_dwell_counter    = 0;
      m_initialized      = false;
   }

   //+------------------------------------------------------------------+
   //| Evaluate raw regime and apply persistence + dwell hysteresis     |
   //+------------------------------------------------------------------+
   bool UpdateOnBarClose(CDataModel &data,
                         double spread_now_pts,
                         datetime bar_time,
                         SRegimeState &state)
   {
      // 1. Gather all required metrics
      double atr_m15_buf[];
      if(!data.GetATR_M15(1, atr_m15_buf)) return false;
      state.atr_m15 = atr_m15_buf[0];

      if(!data.GetATR_M5_Ratio(state.atr_m5, state.atr_ratio)) return false;
      if(!data.GetATRPctPercentile(state.atr_pct, state.atr_pct_p99)) return false;

      state.spread_avg   = data.GetSpreadAvg();
      state.session_vwap = data.CalculateSessionVWAP(bar_time);
      if(!data.GetVWAPSlope(state.session_vwap, state.atr_m5, state.vwap_slope)) return false;

      if(!data.GetEMA_M15(state.ema9_m15, state.ema21_m15, state.ema50_m15)) return false;
      if(!data.GetADX_M15(state.adx_m15)) return false;

      MqlRates m5_rates[];
      if(!data.GetClosedBars(PERIOD_M5, 4, m5_rates)) return false;
      double close_m5        = m5_rates[0].close;
      double open_m5_minus_3 = m5_rates[3].open;

      // 2. Explicit Chaos Sub-checks (§3)
      // Only evaluate spread multiplier if we have at least 10 baseline ticks to avoid cold-start spike
      state.chaos_spread_mult_val   = (state.spread_avg > 0.0) ? (spread_now_pts / state.spread_avg) : 1.0;
      state.chaos_spread_mult_limit = m_spread_chaos_mult;
      state.chaos_spread_mult_fail  = (state.spread_avg > 0.0 && state.chaos_spread_mult_val > m_spread_chaos_mult);

      state.chaos_spread_abs_val    = spread_now_pts;
      state.chaos_spread_abs_limit  = m_spread_chaos_abs_pts;
      state.chaos_spread_abs_fail   = (spread_now_pts > m_spread_chaos_abs_pts);

      state.chaos_atr_p99_val       = state.atr_pct;
      state.chaos_atr_p99_limit     = state.atr_pct_p99;
      state.chaos_atr_p99_fail      = (state.atr_pct > state.atr_pct_p99);

      state.primary_chaos_reason = "NONE";
      if(state.chaos_spread_mult_fail) state.primary_chaos_reason = "SPREAD_MULTIPLIER";
      else if(state.chaos_spread_abs_fail) state.primary_chaos_reason = "ABSOLUTE_SPREAD";
      else if(state.chaos_atr_p99_fail) state.primary_chaos_reason = "ATR_PERCENTILE";

      // 3. Classify Raw Regime (§4)
      ENUM_REGIME raw = REGIME_RANGE;

      if(state.primary_chaos_reason != "NONE")
      {
         raw = REGIME_CHAOS;
      }
      else
      {
         // EXPANSION check
         double price_disp = MathAbs(close_m5 - open_m5_minus_3);
         if(state.atr_ratio > m_atr_expansion_ratio && price_disp > (1.5 * state.atr_m5))
         {
            raw = REGIME_EXPANSION;
         }
         else
         {
            // TREND_UP check
            bool ema_up  = (state.ema9_m15 > state.ema21_m15 && state.ema21_m15 > state.ema50_m15);
            bool adx_ok  = (state.adx_m15 > m_adx_trend_min);
            bool vwap_up = (close_m5 > state.session_vwap && state.vwap_slope > 0.0);

            if(ema_up && adx_ok && vwap_up)
            {
               raw = REGIME_TREND_UP;
            }
            else
            {
               // TREND_DN check (symmetric)
               bool ema_dn  = (state.ema9_m15 < state.ema21_m15 && state.ema21_m15 < state.ema50_m15);
               bool vwap_dn = (close_m5 < state.session_vwap && state.vwap_slope < 0.0);

               if(ema_dn && adx_ok && vwap_dn)
               {
                  raw = REGIME_TREND_DN;
               }
               else
               {
                  raw = REGIME_RANGE;
               }
            }
         }
      }

      state.raw_regime = raw;

      // 4. Calculate Diagnostic Trend Score (0-100) (§1)
      CalculateTrendScore(m5_rates, state.ema9_m15, state.ema21_m15, state.ema50_m15,
                          state.adx_m15, state.session_vwap, state.vwap_slope, raw, state);

      // 5. Apply Hysteresis & Dwell State Machine (Fixing the REGIME=NONE bug §2)
      // Cold-start / Warmup bootstrap: Initial active regime cannot be NONE
      if(!m_initialized || m_active_regime == REGIME_NONE)
      {
         m_active_regime    = (raw != REGIME_CHAOS) ? raw : REGIME_RANGE;
         m_candidate_regime = raw;
         m_persist_counter  = 2;
         m_dwell_counter    = m_dwell_bars;
         m_initialized      = true;
      }
      else if(raw == REGIME_CHAOS)
      {
         // Instant downgrade rule for safety
         m_active_regime    = REGIME_CHAOS;
         m_candidate_regime = REGIME_CHAOS;
         m_persist_counter  = 2;
         m_dwell_counter    = 0;
      }
      else if(m_active_regime == REGIME_CHAOS)
      {
         // Coming out of CHAOS: re-evaluate immediately to raw
         m_active_regime    = raw;
         m_candidate_regime = raw;
         m_persist_counter  = 1;
         m_dwell_counter    = 0;
      }
      else
      {
         m_dwell_counter++;

         if(raw == m_active_regime)
         {
            m_candidate_regime = raw;
            m_persist_counter  = 2;
         }
         else
         {
            if(raw == m_candidate_regime)
            {
               m_persist_counter++;
            }
            else
            {
               m_candidate_regime = raw;
               m_persist_counter  = 1;
            }

            // Flip rule: candidate raw for 2 consecutive M5 closes AND dwell bars elapsed
            if(m_persist_counter >= 2 && m_dwell_counter >= m_dwell_bars)
            {
               m_active_regime = m_candidate_regime;
               m_dwell_counter = 0;
            }
         }
      }

      state.active_regime    = m_active_regime;
      state.candidate_regime = m_candidate_regime;
      state.persist_count    = m_persist_counter;
      state.persist_required = 2;
      state.dwell_count      = m_dwell_counter;
      state.dwell_required   = m_dwell_bars;
      state.dwell_ok         = (m_dwell_counter >= m_dwell_bars || m_active_regime == REGIME_CHAOS);

      return true;
   }

   ENUM_REGIME GetActiveRegime(void) const { return m_active_regime; }
};
