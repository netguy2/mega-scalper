//+------------------------------------------------------------------+
//|                                                  ScalpEngine.mqh |
//|                             XAU-MEGA-SCALPER  M1 TRIGGER LAYER   |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"
#include "DataModel.mqh"

//+------------------------------------------------------------------+
//| Three-layer scalp pipeline, evaluated on every closed M1 bar:    |
//|                                                                  |
//|   M15  REGIME    -> direction only ("I only want LONGs").        |
//|   M5   LOCATION  -> price pulled back into the M5 EMA9 zone,     |
//|                     trend support held, price not over-extended. |
//|   M1   TRIGGER   -> momentum candle AND (micro-structure break   |
//|                     OR reclaim of the M5 EMA9).                  |
//|                                                                  |
//| The trend score is NOT consulted here - it is diagnostic only.   |
//| All distances are expressed in ATR(M5) so the engine adapts to   |
//| quiet / fast gold without retuning.                              |
//+------------------------------------------------------------------+
class CScalpEngine
{
private:
   string   m_symbol;
   bool     m_enabled;
   int      m_lookback;        // M1 bars scanned for the pullback extreme
   int      m_swing_bars;      // M1 bars defining the micro swing high/low
   double   m_zone_atr;        // pullback must reach EMA9 + zone * ATR
   double   m_hold_atr;        // ...but not break EMA21 by more than this * ATR
   double   m_max_ext_atr;     // do not chase beyond EMA9 + this * ATR
   double   m_min_body_frac;   // trigger body >= frac * average M1 range
   double   m_sl_buffer_atr;   // stop buffer beyond the micro swing
   double   m_min_sl_atr;      // stop distance floor (keeps position size sane)
   double   m_atr_sl_mult;     // stop distance cap (shared with the other engines)

public:
   CScalpEngine(void) : m_symbol(SYMBOL_XAUUSD),
                        m_enabled(true),
                        m_lookback(8),
                        m_swing_bars(4),
                        m_zone_atr(0.30),
                        m_hold_atr(0.50),
                        m_max_ext_atr(1.20),
                        m_min_body_frac(0.60),
                        m_sl_buffer_atr(0.10),
                        m_min_sl_atr(0.60),
                        m_atr_sl_mult(1.5)
   {
   }

   void Init(string symbol,
             bool enabled,
             int lookback_bars,
             int swing_bars,
             double zone_atr,
             double hold_atr,
             double max_ext_atr,
             double min_body_frac,
             double sl_buffer_atr,
             double min_sl_atr,
             double atr_sl_mult)
   {
      m_symbol        = symbol;
      m_enabled       = enabled;
      m_lookback      = MathMax(3, lookback_bars);
      m_swing_bars    = MathMax(2, swing_bars);
      m_zone_atr      = zone_atr;
      m_hold_atr      = hold_atr;
      m_max_ext_atr   = max_ext_atr;
      m_min_body_frac = MathMax(0.05, min_body_frac);
      m_sl_buffer_atr = sl_buffer_atr;
      m_min_sl_atr    = min_sl_atr;
      m_atr_sl_mult   = atr_sl_mult;
   }

   bool IsEnabled(void) const { return m_enabled; }

   //+------------------------------------------------------------------+
   //| Evaluate on the last closed M1 bar. Always fills `out` (for the  |
   //| panel); fills `signal` and returns true only when entry-ready.   |
   //+------------------------------------------------------------------+
   bool Evaluate(CDataModel &data,
                 const SRegimeState &regime,
                 SScalpState &out,
                 SSignalResult &signal)
   {
      out.Reset();

      signal.valid            = false;
      signal.engine           = ENGINE_A_TREND_PULLBACK;
      signal.direction        = DIR_NONE;
      signal.is_stop_order    = false;
      signal.stop_entry_price = 0.0;
      signal.sl_price         = 0.0;
      signal.atr_m5_at_signal = regime.atr_m5;
      signal.stop_expire_bars = 0;
      signal.sub_type         = "M1SCALP";
      signal.pass_details     = "";
      signal.fail_code        = "";
      signal.fail_details     = "";
      signal.signal_time      = TimeCurrent();
      signal.score            = 0;

      out.eval_time = TimeCurrent();

      if(!m_enabled)
      {
         out.reason          = "Scalp engine disabled (InpScalpEnabled = false)";
         signal.fail_code    = "S0";
         signal.fail_details = out.reason;
         return false;
      }

      // ---- 1. M15 regime -> direction only -------------------------
      double s = 0.0;   // +1 long, -1 short
      if(regime.active_regime == REGIME_TREND_UP)
      {
         out.direction = DIR_LONG;
         s = 1.0;
      }
      else if(regime.active_regime == REGIME_TREND_DN)
      {
         out.direction = DIR_SHORT;
         s = -1.0;
      }
      else
      {
         out.reason          = StringFormat("Regime is %s - M1 scalps need TREND_UP / TREND_DN",
                                            RegimeToString(regime.active_regime));
         signal.fail_code    = "S1";
         signal.fail_details = out.reason;
         return false;
      }
      out.regime_ok = true;

      // ---- 2. Inputs ------------------------------------------------
      double atr = regime.atr_m5;
      if(atr <= 0.0)
      {
         out.reason          = "ATR(M5) not ready";
         signal.fail_code    = "S2";
         signal.fail_details = out.reason;
         return false;
      }

      double ema9 = 0.0, ema21 = 0.0;
      if(!data.GetEMA_M5(ema9, ema21))
      {
         out.reason          = "M5 EMA buffers not ready";
         signal.fail_code    = "S2";
         signal.fail_details = out.reason;
         return false;
      }

      int need = MathMax(MathMax(m_lookback, m_swing_bars + 1), 12);
      MqlRates m1[];                       // series order: m1[0] = last CLOSED M1 bar
      if(!data.GetClosedBars(PERIOD_M1, need, m1))
      {
         out.reason          = "M1 history not ready";
         signal.fail_code    = "S2";
         signal.fail_details = out.reason;
         return false;
      }

      double close0 = m1[0].close;

      // ---- 3. M5 LOCATION -------------------------------------------
      // Deepest point of the recent pullback (lowest low for longs, highest high for shorts)
      double dip = (s > 0.0) ? m1[0].low : m1[0].high;
      for(int i = 1; i < m_lookback; i++)
      {
         if(s > 0.0) dip = MathMin(dip, m1[i].low);
         else        dip = MathMax(dip, m1[i].high);
      }

      out.loc_touch_val = s * (dip - ema9) / atr;
      out.loc_touch_lim = m_zone_atr;
      out.loc_touch     = (out.loc_touch_val <= m_zone_atr);

      out.loc_hold_val  = s * (close0 - ema21) / atr;
      out.loc_hold_lim  = -m_hold_atr;
      out.loc_hold      = (out.loc_hold_val >= -m_hold_atr);

      out.loc_noext_val = s * (close0 - ema9) / atr;
      out.loc_noext_lim = m_max_ext_atr;
      out.loc_noext     = (out.loc_noext_val <= m_max_ext_atr);

      out.location_ok   = (out.loc_touch && out.loc_hold && out.loc_noext);

      // ---- 4. M1 TRIGGER --------------------------------------------
      // Micro swing = extreme of the bars BEFORE the trigger bar
      double swing = m1[1].high;
      if(s < 0.0) swing = m1[1].low;
      for(int j = 2; j <= m_swing_bars; j++)
      {
         if(s > 0.0) swing = MathMax(swing, m1[j].high);
         else        swing = MathMin(swing, m1[j].low);
      }
      out.trg_struct_val = s * (close0 - swing) / atr;
      out.trg_structure  = (out.trg_struct_val > 0.0);

      // Reclaim: closes back through M5 EMA9 after at least one close on the wrong side (last 3 bars)
      bool crossed = false;
      for(int k = 1; k <= 3; k++)
      {
         if(s * (m1[k].close - ema9) <= 0.0) crossed = true;
      }
      out.trg_reclaim = (s * (close0 - ema9) > 0.0 && crossed);

      // Momentum: decisive body in trade direction relative to recent M1 range
      double avg_range = 0.0;
      for(int r = 1; r <= 10; r++) avg_range += (m1[r].high - m1[r].low);
      avg_range /= 10.0;

      double body = s * (close0 - m1[0].open);
      out.trg_mom_val  = (avg_range > 0.0) ? (body / avg_range) : 0.0;
      out.trg_mom_lim  = m_min_body_frac;
      out.trg_momentum = (body > 0.0 && out.trg_mom_val >= m_min_body_frac);

      out.trigger_ok   = (out.trg_momentum && (out.trg_structure || out.trg_reclaim));
      out.entry_ready  = (out.location_ok && out.trigger_ok);

      // ---- 5. Protective stop (micro swing +/- buffer, clamped in ATR) ----
      double sl_ref = (s > 0.0) ? m1[0].low : m1[0].high;
      for(int q = 1; q <= m_swing_bars; q++)
      {
         if(s > 0.0) sl_ref = MathMin(sl_ref, m1[q].low);
         else        sl_ref = MathMax(sl_ref, m1[q].high);
      }
      double entry = (s > 0.0) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double sl_dist = s * (entry - (sl_ref - s * m_sl_buffer_atr * atr));
      double min_d   = m_min_sl_atr * atr;
      double max_d   = MathMax(min_d, m_atr_sl_mult * atr);
      if(sl_dist < min_d) sl_dist = min_d;
      if(sl_dist > max_d) sl_dist = max_d;
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      out.sl_price = NormalizeDouble(entry - s * sl_dist, digits);

      // ---- 6. Human-readable reason (first missing ingredient) -----------
      if(!out.loc_touch)
         out.reason = StringFormat("No pullback into M5 EMA9 zone (%.2f > %.2f ATR)", out.loc_touch_val, out.loc_touch_lim);
      else if(!out.loc_hold)
         out.reason = StringFormat("Trend support lost: %.2f ATR vs M5 EMA21 (min %.2f)", out.loc_hold_val, out.loc_hold_lim);
      else if(!out.loc_noext)
         out.reason = StringFormat("Price extended %.2f ATR from M5 EMA9 - not chasing (max %.2f)", out.loc_noext_val, out.loc_noext_lim);
      else if(!out.trg_momentum)
         out.reason = StringFormat("M1 momentum candle missing (body %.2f of avg range, need %.2f)", out.trg_mom_val, out.trg_mom_lim);
      else if(!(out.trg_structure || out.trg_reclaim))
         out.reason = "M1 structure break / EMA9 reclaim missing";
      else
         out.reason = "All scalp conditions met";

      if(!out.entry_ready)
      {
         signal.fail_code    = "S_SETUP";
         signal.fail_details = out.reason;
         return false;
      }

      // ---- 7. Signal ---------------------------------------------------
      signal.valid        = true;
      signal.direction    = out.direction;
      signal.sl_price     = out.sl_price;
      signal.pass_details = StringFormat("M1SCALP %s | pullback %.2f/%.2f | hold %.2f | ext %.2f | brk %+.2f %s | mom %.2f/%.2f",
                                         DirectionToString(out.direction),
                                         out.loc_touch_val, out.loc_touch_lim,
                                         out.loc_hold_val, out.loc_noext_val,
                                         out.trg_struct_val, out.trg_reclaim ? "RECLAIM" : "",
                                         out.trg_mom_val, out.trg_mom_lim);
      return true;
   }
};
