//+------------------------------------------------------------------+
//|                                     EngineA_TrendPullback.mqh    |
//|                             XAU-MEGA-SCALPER Formal Spec v0.2    |
//|                             DEBUG & CONTINUOUS RESEARCH EDITION  |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"
#include "DataModel.mqh"

class CEngineA_TrendPullback
{
private:
   int      m_ema_fast;
   int      m_ema_mid;
   int      m_ema_slow;
   double   m_pullback_atr_frac;
   double   m_rejection_wick_ratio;
   int      m_momentum_lookback_bars;
   double   m_atr_sl_mult;

public:
   CEngineA_TrendPullback(void) : m_ema_fast(9),
                                  m_ema_mid(21),
                                  m_ema_slow(50),
                                  m_pullback_atr_frac(0.35),
                                  m_rejection_wick_ratio(1.5),
                                  m_momentum_lookback_bars(1),
                                  m_atr_sl_mult(1.5)
   {
   }

   void Init(int ema_fast,
             int ema_mid,
             int ema_slow,
             double pullback_atr_frac,
             double rejection_wick_ratio,
             int momentum_lookback_bars,
             double atr_sl_mult)
   {
      m_ema_fast               = ema_fast;
      m_ema_mid                = ema_mid;
      m_ema_slow               = ema_slow;
      m_pullback_atr_frac      = pullback_atr_frac;
      m_rejection_wick_ratio   = rejection_wick_ratio;
      m_momentum_lookback_bars = momentum_lookback_bars;
      m_atr_sl_mult            = atr_sl_mult;
   }

   //+------------------------------------------------------------------+
   //| Dry Candidate Evaluation (§12)                                   |
   //+------------------------------------------------------------------+
   void EvaluateDryCandidate(CDataModel &data, const SRegimeState &regime, SDrySignal &dry)
   {
      dry.engine           = ENGINE_A_TREND_PULLBACK;
      dry.candidate_dir    = DIR_NONE;
      dry.setup_found      = false;
      dry.condition1_desc  = "EMA21 Pullback (A2)";
      dry.condition1_pass  = false;
      dry.condition2_desc  = "Rejection Wick (A3)";
      dry.condition2_pass  = false;
      dry.condition3_desc  = "Momentum Conf (A4)";
      dry.condition3_pass  = false;
      dry.status_desc      = "NO SETUP";
      dry.primary_rejection_reason = "";

      double ema9, ema21, ema50;
      if(!data.GetEMA_M15(ema9, ema21, ema50))
      {
         dry.primary_rejection_reason = "Indicator handle read fail (EMA)";
         return;
      }

      MqlRates m5_rates[];
      if(!data.GetClosedBars(PERIOD_M5, 4, m5_rates))
      {
         dry.primary_rejection_reason = "Failed to copy M5 closed bars";
         return;
      }

      double atr_m5 = regime.atr_m5;
      if(atr_m5 <= 0.0)
      {
         dry.primary_rejection_reason = "ATR M5 non-positive";
         return;
      }

      double limit = m_pullback_atr_frac * atr_m5;
      double trig_close = m5_rates[0].close;
      double trig_open  = m5_rates[0].open;
      double trig_high  = m5_rates[0].high;
      double trig_low   = m5_rates[0].low;

      bool is_bull = (ema9 >= ema21);
      dry.candidate_dir = is_bull ? DIR_LONG : DIR_SHORT;

      if(is_bull)
      {
         // A2 Pullback
         bool a2_pass = false;
         double min_dist = 999999.0;
         for(int i = 0; i < 3; i++)
         {
            double d = MathAbs(m5_rates[i].low - ema21);
            if(d < min_dist) min_dist = d;
            if(m5_rates[i].low <= (ema21 + limit) && m5_rates[i].high >= (ema21 - limit)) a2_pass = true;
            if(MathAbs(m5_rates[i].close - ema21) <= limit) a2_pass = true;
         }
         dry.condition1_pass = a2_pass;
         dry.condition1_desc = StringFormat("A2 Dist: %.2f (lim %.2f)", min_dist, limit);

         // A3 Rejection Wick
         double body = MathAbs(trig_close - trig_open);
         if(body < _Point) body = _Point;
         double lower_wick = trig_open - trig_low;
         double wick_ratio = lower_wick / body;
         bool a3_pass = (trig_close > trig_open && wick_ratio >= m_rejection_wick_ratio);
         dry.condition2_pass = a3_pass;
         dry.condition2_desc = StringFormat("A3 Wick: %.2f (req %.2f)", wick_ratio, m_rejection_wick_ratio);

         // A4 Momentum
         bool mom_high = (trig_close > m5_rates[1].high);
         bool mom_ema  = (trig_close > ema9 && ema9 > ema21);
         bool a4_pass = (mom_high || mom_ema);
         dry.condition3_pass = a4_pass;
         dry.condition3_desc = StringFormat("A4 Mom: %s", mom_high ? "High" : (mom_ema ? "EMA" : "None"));

         if(a2_pass && a3_pass && a4_pass)
         {
            dry.setup_found = true;
            dry.status_desc = "CANDIDATE BUY (All conditions met)";
            if(regime.active_regime != REGIME_TREND_UP)
               dry.primary_rejection_reason = StringFormat("Regime is %s (not TREND_UP)", RegimeToString(regime.active_regime));
         }
         else
         {
            if(!a2_pass) dry.primary_rejection_reason = StringFormat("A2 Pullback dist %.2f > limit %.2f", min_dist, limit);
            else if(!a3_pass) dry.primary_rejection_reason = StringFormat("A3 Wick ratio %.2f < req %.2f", wick_ratio, m_rejection_wick_ratio);
            else dry.primary_rejection_reason = "A4 Momentum unconfirmed";
         }
      }
      else
      {
         // Symmetric Bearish
         bool a2_pass = false;
         double min_dist = 999999.0;
         for(int i = 0; i < 3; i++)
         {
            double d = MathAbs(m5_rates[i].high - ema21);
            if(d < min_dist) min_dist = d;
            if(m5_rates[i].high >= (ema21 - limit) && m5_rates[i].low <= (ema21 + limit)) a2_pass = true;
            if(MathAbs(m5_rates[i].close - ema21) <= limit) a2_pass = true;
         }
         dry.condition1_pass = a2_pass;
         dry.condition1_desc = StringFormat("A2 Dist: %.2f (lim %.2f)", min_dist, limit);

         double body = MathAbs(trig_open - trig_close);
         if(body < _Point) body = _Point;
         double upper_wick = trig_high - trig_open;
         double wick_ratio = upper_wick / body;
         bool a3_pass = (trig_close < trig_open && wick_ratio >= m_rejection_wick_ratio);
         dry.condition2_pass = a3_pass;
         dry.condition2_desc = StringFormat("A3 Wick: %.2f (req %.2f)", wick_ratio, m_rejection_wick_ratio);

         bool mom_low = (trig_close < m5_rates[1].low);
         bool mom_ema = (trig_close < ema9 && ema9 < ema21);
         bool a4_pass = (mom_low || mom_ema);
         dry.condition3_pass = a4_pass;
         dry.condition3_desc = StringFormat("A4 Mom: %s", mom_low ? "Low" : (mom_ema ? "EMA" : "None"));

         if(a2_pass && a3_pass && a4_pass)
         {
            dry.setup_found = true;
            dry.status_desc = "CANDIDATE SELL (All conditions met)";
            if(regime.active_regime != REGIME_TREND_DN)
               dry.primary_rejection_reason = StringFormat("Regime is %s (not TREND_DN)", RegimeToString(regime.active_regime));
         }
         else
         {
            if(!a2_pass) dry.primary_rejection_reason = StringFormat("A2 Pullback dist %.2f > limit %.2f", min_dist, limit);
            else if(!a3_pass) dry.primary_rejection_reason = StringFormat("A3 Wick ratio %.2f < req %.2f", wick_ratio, m_rejection_wick_ratio);
            else dry.primary_rejection_reason = "A4 Momentum unconfirmed";
         }
      }
   }

   // Standard Strategy Dispatch
   bool Evaluate(CDataModel &data, const SRegimeState &regime, SSignalResult &signal)
   {
      signal.valid            = false;
      signal.engine           = ENGINE_A_TREND_PULLBACK;
      signal.direction        = DIR_NONE;
      signal.is_stop_order    = false;
      signal.stop_entry_price = 0.0;
      signal.sl_price         = 0.0;
      signal.atr_m5_at_signal = regime.atr_m5;
      signal.stop_expire_bars = 0;
      signal.sub_type         = "PULLBACK";
      signal.pass_details     = "";
      signal.fail_code        = "";
      signal.fail_details     = "";

      if(regime.active_regime != REGIME_TREND_UP && regime.active_regime != REGIME_TREND_DN)
      {
         signal.fail_code    = "A1";
         signal.fail_details = StringFormat("Active regime is %s (not TREND)", RegimeToString(regime.active_regime));
         return false;
      }

      SDrySignal dry;
      EvaluateDryCandidate(data, regime, dry);

      if(!dry.setup_found)
      {
         signal.fail_code    = "A_SETUP";
         signal.fail_details = dry.primary_rejection_reason;
         return false;
      }

      MqlRates m5_rates[];
      data.GetClosedBars(PERIOD_M5, 1, m5_rates);
      double trig_close = m5_rates[0].close;

      signal.valid        = true;
      signal.direction    = dry.candidate_dir;
      signal.sl_price     = (signal.direction == DIR_LONG) ?
                            (trig_close - m_atr_sl_mult * regime.atr_m5) :
                            (trig_close + m_atr_sl_mult * regime.atr_m5);
      signal.pass_details = StringFormat("%s | %s | %s", dry.condition1_desc, dry.condition2_desc, dry.condition3_desc);
      return true;
   }
};
