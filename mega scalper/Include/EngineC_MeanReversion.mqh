//+------------------------------------------------------------------+
//|                                       EngineC_MeanReversion.mqh |
//|                             XAU-MEGA-SCALPER Formal Spec v0.2    |
//|                             DEBUG & CONTINUOUS RESEARCH EDITION  |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"
#include "DataModel.mqh"

class CEngineC_MeanReversion
{
private:
   int      m_bb_period;
   double   m_bb_sigma;
   double   m_vwap_dev_atr_min;
   int      m_band_touch_lookback;
   double   m_rejection_wick_ratio_mr;
   double   m_max_fade_extension_atr;

public:
   CEngineC_MeanReversion(void) : m_bb_period(20),
                                  m_bb_sigma(2.0),
                                  m_vwap_dev_atr_min(1.2),
                                  m_band_touch_lookback(3),
                                  m_rejection_wick_ratio_mr(1.2),
                                  m_max_fade_extension_atr(2.5)
   {
   }

   void Init(int bb_period,
             double bb_sigma,
             double vwap_dev_atr_min,
             int band_touch_lookback,
             double rejection_wick_ratio_mr,
             double max_fade_extension_atr)
   {
      m_bb_period               = bb_period;
      m_bb_sigma                = bb_sigma;
      m_vwap_dev_atr_min        = vwap_dev_atr_min;
      m_band_touch_lookback     = band_touch_lookback;
      m_rejection_wick_ratio_mr = rejection_wick_ratio_mr;
      m_max_fade_extension_atr  = max_fade_extension_atr;
   }

   //+------------------------------------------------------------------+
   //| Dry Candidate Evaluation (§12)                                   |
   //+------------------------------------------------------------------+
   void EvaluateDryCandidate(CDataModel &data, const SRegimeState &regime, SDrySignal &dry)
   {
      dry.engine           = ENGINE_C_MEAN_REVERSION;
      dry.candidate_dir    = DIR_NONE;
      dry.setup_found      = false;
      dry.condition1_desc  = "VWAP Dev (C1)";
      dry.condition1_pass  = false;
      dry.condition2_desc  = "BB Band Touch (C2)";
      dry.condition2_pass  = false;
      dry.condition3_desc  = "Rejection Wick (C3)";
      dry.condition3_pass  = false;
      dry.status_desc      = "NO SETUP";
      dry.primary_rejection_reason = "";

      double atr_m5 = regime.atr_m5;
      if(atr_m5 <= 0.0)
      {
         dry.primary_rejection_reason = "ATR M5 non-positive";
         return;
      }

      MqlRates m5_rates[];
      int req = MathMax(m_band_touch_lookback, 4);
      if(!data.GetClosedBars(PERIOD_M5, req, m5_rates))
      {
         dry.primary_rejection_reason = "Failed to copy M5 bars";
         return;
      }

      double bb_mid, bb_upper, bb_lower;
      if(!data.GetBands_M5(bb_mid, bb_upper, bb_lower))
      {
         dry.primary_rejection_reason = "Failed to read Bollinger Bands";
         return;
      }

      double trig_close = m5_rates[0].close;
      double trig_open  = m5_rates[0].open;
      double trig_high  = m5_rates[0].high;
      double trig_low   = m5_rates[0].low;

      double vwap_dist     = MathAbs(trig_close - regime.session_vwap);
      double vwap_dist_atr = vwap_dist / atr_m5;
      double max_cap       = MathMin(m_max_fade_extension_atr, 1.5);

      bool c1_pass = (vwap_dist_atr >= m_vwap_dev_atr_min && vwap_dist_atr <= max_cap);
      dry.condition1_pass = c1_pass;
      dry.condition1_desc = StringFormat("VWAP Dev: %.2f ATR (min %.2f, cap %.2f)", vwap_dist_atr, m_vwap_dev_atr_min, max_cap);

      bool is_fade_long = (trig_close < regime.session_vwap);
      dry.candidate_dir = is_fade_long ? DIR_LONG : DIR_SHORT;

      if(is_fade_long)
      {
         bool touched = false;
         for(int i = 0; i < m_band_touch_lookback; i++)
         {
            if(m5_rates[i].low <= bb_lower) { touched = true; break; }
         }
         dry.condition2_pass = touched;
         dry.condition2_desc = touched ? "Lower Band Touched ✓" : "Band Not Touched ✗";

         double body = MathAbs(trig_close - trig_open);
         if(body < _Point) body = _Point;
         double lower_wick = trig_open - trig_low;
         double wick_ratio = lower_wick / body;
         bool c3_pass = (trig_close > trig_open && wick_ratio >= m_rejection_wick_ratio_mr);
         dry.condition3_pass = c3_pass;
         dry.condition3_desc = StringFormat("Wick: %.2f (req %.2f)", wick_ratio, m_rejection_wick_ratio_mr);

         if(c1_pass && touched && c3_pass)
         {
            dry.setup_found = true;
            dry.status_desc = "CANDIDATE BUY FADE";
            if(regime.active_regime != REGIME_RANGE)
               dry.primary_rejection_reason = StringFormat("Regime is %s (needs RANGE)", RegimeToString(regime.active_regime));
         }
         else
         {
            if(!c1_pass) dry.primary_rejection_reason = StringFormat("VWAP dev %.2f ATR outside [%.2f, %.2f]", vwap_dist_atr, m_vwap_dev_atr_min, max_cap);
            else if(!touched) dry.primary_rejection_reason = "Lower Bollinger band not touched in lookback";
            else dry.primary_rejection_reason = StringFormat("Rejection wick ratio %.2f < req %.2f", wick_ratio, m_rejection_wick_ratio_mr);
         }
      }
      else
      {
         bool touched = false;
         for(int i = 0; i < m_band_touch_lookback; i++)
         {
            if(m5_rates[i].high >= bb_upper) { touched = true; break; }
         }
         dry.condition2_pass = touched;
         dry.condition2_desc = touched ? "Upper Band Touched ✓" : "Band Not Touched ✗";

         double body = MathAbs(trig_open - trig_close);
         if(body < _Point) body = _Point;
         double upper_wick = trig_high - trig_open;
         double wick_ratio = upper_wick / body;
         bool c3_pass = (trig_close < trig_open && wick_ratio >= m_rejection_wick_ratio_mr);
         dry.condition3_pass = c3_pass;
         dry.condition3_desc = StringFormat("Wick: %.2f (req %.2f)", wick_ratio, m_rejection_wick_ratio_mr);

         if(c1_pass && touched && c3_pass)
         {
            dry.setup_found = true;
            dry.status_desc = "CANDIDATE SELL FADE";
            if(regime.active_regime != REGIME_RANGE)
               dry.primary_rejection_reason = StringFormat("Regime is %s (needs RANGE)", RegimeToString(regime.active_regime));
         }
         else
         {
            if(!c1_pass) dry.primary_rejection_reason = StringFormat("VWAP dev %.2f ATR outside [%.2f, %.2f]", vwap_dist_atr, m_vwap_dev_atr_min, max_cap);
            else if(!touched) dry.primary_rejection_reason = "Upper Bollinger band not touched in lookback";
            else dry.primary_rejection_reason = StringFormat("Rejection wick ratio %.2f < req %.2f", wick_ratio, m_rejection_wick_ratio_mr);
         }
      }
   }

   bool Evaluate(CDataModel &data, const SRegimeState &regime, SSignalResult &signal)
   {
      signal.valid            = false;
      signal.engine           = ENGINE_C_MEAN_REVERSION;
      signal.direction        = DIR_NONE;
      signal.is_stop_order    = false;
      signal.stop_entry_price = 0.0;
      signal.sl_price         = 0.0;
      signal.atr_m5_at_signal = regime.atr_m5;
      signal.stop_expire_bars = 0;
      signal.sub_type         = "MEAN_REV";
      signal.pass_details     = "";
      signal.fail_code        = "";
      signal.fail_details     = "";

      if(regime.active_regime != REGIME_RANGE)
      {
         signal.fail_code    = "C_REGIME";
         signal.fail_details = StringFormat("Regime %s is not RANGE", RegimeToString(regime.active_regime));
         return false;
      }

      SDrySignal dry;
      EvaluateDryCandidate(data, regime, dry);

      if(!dry.setup_found)
      {
         signal.fail_code    = "C_SETUP";
         signal.fail_details = dry.primary_rejection_reason;
         return false;
      }

      MqlRates m5_rates[];
      data.GetClosedBars(PERIOD_M5, 1, m5_rates);
      double trig_close = m5_rates[0].close;

      double bb_mid, bb_upper, bb_lower;
      data.GetBands_M5(bb_mid, bb_upper, bb_lower);

      if(dry.candidate_dir == DIR_LONG)
      {
         signal.valid        = true;
         signal.direction    = DIR_LONG;
         signal.sl_price     = MathMax(trig_close - 1.2 * regime.atr_m5, bb_lower - 0.3 * regime.atr_m5);
         signal.pass_details = StringFormat("%s | %s | %s", dry.condition1_desc, dry.condition2_desc, dry.condition3_desc);
         return true;
      }
      else
      {
         signal.valid        = true;
         signal.direction    = DIR_SHORT;
         signal.sl_price     = MathMin(trig_close + 1.2 * regime.atr_m5, bb_upper + 0.3 * regime.atr_m5);
         signal.pass_details = StringFormat("%s | %s | %s", dry.condition1_desc, dry.condition2_desc, dry.condition3_desc);
         return true;
      }
   }
};
