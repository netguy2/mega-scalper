//+------------------------------------------------------------------+
//|                                            EngineB_Breakout.mqh |
//|                             XAU-MEGA-SCALPER Formal Spec v0.2    |
//|                             DEBUG & CONTINUOUS RESEARCH EDITION  |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"
#include "DataModel.mqh"

class CEngineB_Breakout
{
private:
   int      m_or_window_min;
   int      m_donchian_period;
   double   m_breakout_buffer_atr;
   double   m_range_min_atr;
   double   m_range_max_atr;
   int      m_momentum_confirm_bars;
   double   m_atr_sl_mult;

   datetime m_cached_or_day;
   double   m_cached_or_high;
   double   m_cached_or_low;
   bool     m_or_formed;

   bool CalculateLondonOR(string symbol, datetime bar_time, double &or_high, double &or_low)
   {
      MqlDateTime mdt;
      TimeToStruct(bar_time, mdt);
      mdt.hour = 7; mdt.min = 0; mdt.sec = 0;
      datetime london_open = StructToTime(mdt);
      datetime london_or_end = london_open + (m_or_window_min * 60);

      if(bar_time < london_or_end) return false;

      if(m_cached_or_day == london_open && m_or_formed)
      {
         or_high = m_cached_or_high;
         or_low  = m_cached_or_low;
         return true;
      }

      MqlRates or_rates[];
      ArraySetAsSeries(or_rates, true);
      int copied = CopyRates(symbol, PERIOD_M1, london_open, london_or_end, or_rates);
      if(copied <= 0) return false;

      or_high = or_rates[0].high;
      or_low  = or_rates[0].low;
      for(int i = 1; i < copied; i++)
      {
         if(or_rates[i].high > or_high) or_high = or_rates[i].high;
         if(or_rates[i].low  < or_low)  or_low  = or_rates[i].low;
      }

      m_cached_or_day  = london_open;
      m_cached_or_high = or_high;
      m_cached_or_low  = or_low;
      m_or_formed      = true;
      return true;
   }

public:
   CEngineB_Breakout(void) : m_or_window_min(30),
                             m_donchian_period(20),
                             m_breakout_buffer_atr(0.10),
                             m_range_min_atr(0.8),
                             m_range_max_atr(3.0),
                             m_momentum_confirm_bars(2),
                             m_atr_sl_mult(1.5),
                             m_cached_or_day(0),
                             m_cached_or_high(0.0),
                             m_cached_or_low(0.0),
                             m_or_formed(false)
   {
   }

   void Init(int or_window_min,
             int donchian_period,
             double breakout_buffer_atr,
             double range_min_atr,
             double range_max_atr,
             int momentum_confirm_bars,
             double atr_sl_mult)
   {
      m_or_window_min         = or_window_min;
      m_donchian_period       = donchian_period;
      m_breakout_buffer_atr   = breakout_buffer_atr;
      m_range_min_atr         = range_min_atr;
      m_range_max_atr         = range_max_atr;
      m_momentum_confirm_bars = momentum_confirm_bars;
      m_atr_sl_mult           = atr_sl_mult;
      m_cached_or_day         = 0;
      m_or_formed             = false;
   }

   //+------------------------------------------------------------------+
   //| Dry Candidate Evaluation (§12)                                   |
   //+------------------------------------------------------------------+
   void EvaluateDryCandidate(string symbol, CDataModel &data, const SRegimeState &regime, SDrySignal &dry)
   {
      dry.engine           = ENGINE_B_BREAKOUT;
      dry.candidate_dir    = DIR_NONE;
      dry.setup_found      = false;
      dry.condition1_desc  = "Range Width (B1)";
      dry.condition1_pass  = false;
      dry.condition2_desc  = "Breakout Breach";
      dry.condition2_pass  = false;
      dry.condition3_desc  = "Momentum Closes (B2)";
      dry.condition3_pass  = false;
      dry.status_desc      = "NO SETUP";
      dry.primary_rejection_reason = "";

      double atr_m5 = regime.atr_m5;
      if(atr_m5 <= 0.0)
      {
         dry.primary_rejection_reason = "ATR M5 non-positive";
         return;
      }

      double don_h = 0.0, don_l = 0.0;
      if(!data.GetDonchian_M5(m_donchian_period, don_h, don_l))
      {
         dry.primary_rejection_reason = "Failed to calculate Donchian channel";
         return;
      }

      double don_width_atr = (don_h - don_l) / atr_m5;
      dry.condition1_pass = (don_width_atr >= m_range_min_atr && don_width_atr <= m_range_max_atr);
      dry.condition1_desc = StringFormat("Width: %.2f ATR [%.1f, %.1f]", don_width_atr, m_range_min_atr, m_range_max_atr);

      MqlRates m5_rates[];
      int req = MathMax(m_momentum_confirm_bars + 1, 3);
      if(!data.GetClosedBars(PERIOD_M5, req, m5_rates))
      {
         dry.primary_rejection_reason = "Failed to copy M5 rates";
         return;
      }

      double buffer = m_breakout_buffer_atr * atr_m5;
      double trig_close = m5_rates[0].close;

      bool breach_high = (trig_close > (don_h + buffer));
      bool breach_low  = (trig_close < (don_l - buffer));
      dry.condition2_pass = (breach_high || breach_low);
      dry.condition2_desc = StringFormat("Close %.2f vs H:%.2f L:%.2f", trig_close, don_h + buffer, don_l - buffer);

      if(breach_high)
      {
         dry.candidate_dir = DIR_LONG;
         bool mom = true;
         for(int i = 0; i < m_momentum_confirm_bars; i++)
         {
            if(m5_rates[i].close <= m5_rates[i].open) { mom = false; break; }
         }
         dry.condition3_pass = mom;
         dry.condition3_desc = mom ? "2 Bull Closes ✓" : "Momentum Fail ✗";

         if(dry.condition1_pass && dry.condition2_pass && mom)
         {
            dry.setup_found = true;
            dry.status_desc = "CANDIDATE BUY STOP";
            if(regime.active_regime != REGIME_EXPANSION && !(regime.active_regime == REGIME_RANGE && regime.atr_ratio > 1.3))
               dry.primary_rejection_reason = StringFormat("Regime is %s (needs EXPANSION or RANGE+ATR>1.3)", RegimeToString(regime.active_regime));
         }
         else
         {
            if(!dry.condition1_pass) dry.primary_rejection_reason = StringFormat("Donchian width %.2f ATR outside [%.1f, %.1f]", don_width_atr, m_range_min_atr, m_range_max_atr);
            else if(!mom) dry.primary_rejection_reason = "Momentum closes unconfirmed";
         }
      }
      else if(breach_low)
      {
         dry.candidate_dir = DIR_SHORT;
         bool mom = true;
         for(int i = 0; i < m_momentum_confirm_bars; i++)
         {
            if(m5_rates[i].close >= m5_rates[i].open) { mom = false; break; }
         }
         dry.condition3_pass = mom;
         dry.condition3_desc = mom ? "2 Bear Closes ✓" : "Momentum Fail ✗";

         if(dry.condition1_pass && dry.condition2_pass && mom)
         {
            dry.setup_found = true;
            dry.status_desc = "CANDIDATE SELL STOP";
            if(regime.active_regime != REGIME_EXPANSION && !(regime.active_regime == REGIME_RANGE && regime.atr_ratio > 1.3))
               dry.primary_rejection_reason = StringFormat("Regime is %s (needs EXPANSION or RANGE+ATR>1.3)", RegimeToString(regime.active_regime));
         }
         else
         {
            if(!dry.condition1_pass) dry.primary_rejection_reason = StringFormat("Donchian width %.2f ATR outside [%.1f, %.1f]", don_width_atr, m_range_min_atr, m_range_max_atr);
            else if(!mom) dry.primary_rejection_reason = "Momentum closes unconfirmed";
         }
      }
      else
      {
         dry.primary_rejection_reason = "Price within range, no breakout breach";
      }
   }

   bool Evaluate(string symbol, CDataModel &data, const SRegimeState &regime, SSignalResult &signal)
   {
      signal.valid            = false;
      signal.engine           = ENGINE_B_BREAKOUT;
      signal.direction        = DIR_NONE;
      signal.is_stop_order    = true;
      signal.stop_entry_price = 0.0;
      signal.sl_price         = 0.0;
      signal.atr_m5_at_signal = regime.atr_m5;
      signal.stop_expire_bars = 2;
      signal.sub_type         = "NONE";
      signal.pass_details     = "";
      signal.fail_code        = "";
      signal.fail_details     = "";

      bool active = (regime.active_regime == REGIME_EXPANSION) ||
                    (regime.active_regime == REGIME_RANGE && regime.atr_ratio > 1.3);

      if(!active)
      {
         signal.fail_code    = "B_REGIME";
         signal.fail_details = StringFormat("Regime %s not active for breakout", RegimeToString(regime.active_regime));
         return false;
      }

      SDrySignal dry;
      EvaluateDryCandidate(symbol, data, regime, dry);

      if(!dry.setup_found)
      {
         signal.fail_code    = "B_SETUP";
         signal.fail_details = dry.primary_rejection_reason;
         return false;
      }

      MqlRates m5_rates[];
      data.GetClosedBars(PERIOD_M5, 1, m5_rates);

      signal.valid            = true;
      signal.direction        = dry.candidate_dir;
      signal.sub_type         = "B-DON";
      signal.stop_entry_price = (signal.direction == DIR_LONG) ? (m5_rates[0].high + _Point) : (m5_rates[0].low - _Point);
      signal.sl_price         = (signal.direction == DIR_LONG) ?
                                (signal.stop_entry_price - m_atr_sl_mult * regime.atr_m5) :
                                (signal.stop_entry_price + m_atr_sl_mult * regime.atr_m5);
      signal.pass_details     = StringFormat("%s | %s | %s", dry.condition1_desc, dry.condition2_desc, dry.condition3_desc);
      return true;
   }
};
