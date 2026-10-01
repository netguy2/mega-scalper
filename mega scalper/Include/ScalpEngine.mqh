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
#include "MarketContext.mqh"

//--- One candidate (level, direction) of the liquidity-sweep search
struct SSweepProbe
{
   bool     valid;
   double   s;
   string   name;
   double   price;
   double   depth;      // penetration in ATR(M5); negative = level not reached
   double   extreme;    // sweep wick extreme
   bool     swept;
   bool     in_range;   // not a breakdown
   bool     reclaim;
   bool     reject;
   double   close_pos;  // 0..1 position of the close in the favourable part of the bar
   bool     disp;
   double   disp_x;
   int      score;
};

//+------------------------------------------------------------------+
//| Evaluated on every closed M1 bar. Three entry modes share one    |
//| pipeline and one set of context filters. Direction comes from    |
//| the FAST M5 micro-trend (EMA9 vs EMA21 + price side), NOT from   |
//| the slow M15 regime - that lags by hours and, during a sharp     |
//| move, points the wrong way. The regime only vetoes CHAOS.        |
//|                                                                  |
//|  MODE 1  PULLBACK    price retraces into the M5 EMA9 zone,       |
//|                      support held, not extended; M1 momentum     |
//|                      candle + (structure break OR EMA9 reclaim). |
//|  MODE 2  SWEEP       a key level (PDH/PDL, Asian H/L, day H/L,   |
//|                      round number) is taken by a wick, the M1    |
//|                      closes back inside with rejection and       |
//|                      displacement. Both directions, any regime.  |
//|  MODE 3  MOMENTUM    impulse continuation: a big-body M1 candle  |
//|                      closing near its extreme, breaking the      |
//|                      micro swing in the micro-trend direction.   |
//|                                                                  |
//|  CONTEXT FILTERS (all modes): H1 bias not opposed | room to the  |
//|  next level | RSI(M1) not exhausted | ATR floor.                 |
//|  GRADE A/B/C counts confluence and scales position size; it      |
//|  never replaces the entry rules. The trend score is NOT used.    |
//+------------------------------------------------------------------+
class CScalpEngine
{
private:
   string          m_symbol;
   SScalpConfig    m_cfg;
   CMarketContext  m_ctx;

   // Same sweep level is not re-entered inside this window
   string          m_last_sweep_level;
   datetime        m_last_sweep_time;

   int CountPass(const SSweepProbe &p)
   {
      return (p.swept ? 1 : 0) + (p.in_range ? 1 : 0) + (p.reclaim ? 1 : 0) + (p.reject ? 1 : 0) + (p.disp ? 1 : 0);
   }

   bool Fail(SScalpState &out, SSignalResult &signal, const string code)
   {
      signal.fail_code    = code;
      signal.fail_details = out.reason;
      return false;
   }

public:
   CScalpEngine(void) : m_symbol(SYMBOL_XAUUSD),
                        m_last_sweep_level(""),
                        m_last_sweep_time(0)
   {
   }

   bool Init(const string symbol, const SScalpConfig &cfg)
   {
      m_symbol = symbol;
      m_cfg    = cfg;
      m_cfg.lookback_bars = MathMax(3, cfg.lookback_bars);
      m_cfg.swing_bars    = MathMax(2, cfg.swing_bars);
      m_cfg.min_body_frac = MathMax(0.05, cfg.min_body_frac);
      m_last_sweep_level  = "";
      m_last_sweep_time   = 0;
      return m_ctx.Init(symbol, cfg);
   }

   void Release(void) { m_ctx.Release(); }

   bool IsEnabled(void) const { return m_cfg.enabled; }

   //+------------------------------------------------------------------+
   //| Evaluate on the last closed M1 bar. Always fills `out` (panel);  |
   //| fills `signal` and returns true only when entry-ready.           |
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
      signal.risk_mult        = 1.0;

      out.eval_time = TimeCurrent();

      if(!m_cfg.enabled)
      {
         out.reason = "Scalp engine disabled (InpScalpEnabled = false)";
         return Fail(out, signal, "S0");
      }

      // ---- 1. Regime: only CHAOS (and warm-up) veto the scalp layer ------------
      ENUM_REGIME ar = regime.active_regime;
      if(ar != REGIME_TREND_UP && ar != REGIME_TREND_DN && ar != REGIME_RANGE && ar != REGIME_EXPANSION)
      {
         out.reason = StringFormat("Regime is %s - scalping paused", RegimeToString(ar));
         return Fail(out, signal, "S1");
      }
      out.regime_ok  = true;
      out.regime_dir = (ar == REGIME_TREND_UP) ? 1 : ((ar == REGIME_TREND_DN) ? -1 : 0);

      // ---- 2. Inputs ------------------------------------------------------------
      double atr = regime.atr_m5;
      if(atr <= 0.0)
      {
         out.reason = "ATR(M5) not ready";
         return Fail(out, signal, "S2");
      }

      double ema9 = 0.0, ema21 = 0.0;
      if(!data.GetEMA_M5(ema9, ema21))
      {
         out.reason = "M5 EMA buffers not ready";
         return Fail(out, signal, "S2");
      }

      int need = MathMax(MathMax(m_cfg.lookback_bars, m_cfg.swing_bars + 1), 12);
      MqlRates m1[];                       // series order: m1[0] = last CLOSED M1 bar
      if(!data.GetClosedBars(PERIOD_M1, need, m1))
      {
         out.reason = "M1 history not ready";
         return Fail(out, signal, "S2");
      }
      double close0 = m1[0].close;

      m_ctx.Refresh(close0);

      double avg_range = 0.0;
      for(int r = 1; r <= 10; r++) avg_range += (m1[r].high - m1[r].low);
      avg_range /= 10.0;
      double rng0 = m1[0].high - m1[0].low;

      // ---- 3. Fast M5 micro-trend (direction for modes 1 and 3) ---------------------
      int m5dir = 0;
      if(ema9 > ema21 && close0 > ema21)      m5dir = 1;
      else if(ema9 < ema21 && close0 < ema21) m5dir = -1;
      out.m5_dir = m5dir;

      // ---- 4. MODES 1 + 3 (share the micro-structure maths) ---------------------------
      bool   t_touch = false, t_hold = false, t_noext = false;
      bool   t_struct = false, t_reclaim = false, t_mom = false;
      double t_touch_v = 0.0, t_hold_v = 0.0, t_noext_v = 0.0, t_struct_v = 0.0, t_mom_v = 0.0;
      bool   mm_beyond = false, mm_ext = false, mm_body = false, mm_close = false;
      double mm_beyond_v = 0.0, mm_ext_v = 0.0, mm_body_v = 0.0, mm_cpos = 0.0;
      if(m5dir != 0)
      {
         double s = (double)m5dir;

         double dip = (s > 0.0) ? m1[0].low : m1[0].high;
         for(int i = 1; i < m_cfg.lookback_bars; i++)
         {
            if(s > 0.0) dip = MathMin(dip, m1[i].low);
            else        dip = MathMax(dip, m1[i].high);
         }
         t_touch_v = s * (dip - ema9) / atr;
         t_touch   = (t_touch_v <= m_cfg.zone_atr);

         t_hold_v  = s * (close0 - ema21) / atr;
         t_hold    = (t_hold_v >= -m_cfg.hold_atr);

         t_noext_v = s * (close0 - ema9) / atr;
         t_noext   = (t_noext_v <= m_cfg.max_ext_atr);

         double swing = (s > 0.0) ? m1[1].high : m1[1].low;
         for(int j = 2; j <= m_cfg.swing_bars; j++)
         {
            if(s > 0.0) swing = MathMax(swing, m1[j].high);
            else        swing = MathMin(swing, m1[j].low);
         }
         t_struct_v = s * (close0 - swing) / atr;
         t_struct   = (t_struct_v > 0.0);

         bool crossed = false;
         for(int k = 1; k <= 3; k++)
         {
            if(s * (m1[k].close - ema9) <= 0.0) crossed = true;
         }
         t_reclaim = (s * (close0 - ema9) > 0.0 && crossed);

         double body = s * (close0 - m1[0].open);
         t_mom_v = (avg_range > 0.0) ? (body / avg_range) : 0.0;
         t_mom   = (body > 0.0 && t_mom_v >= m_cfg.min_body_frac);

         // Momentum burst
         mm_body_v   = t_mom_v;
         mm_body     = (body > 0.0 && mm_body_v >= m_cfg.mom_body_mult);
         mm_beyond_v = s * (close0 - ema9) / atr;
         mm_beyond   = (mm_beyond_v > 0.0);
         mm_ext_v    = mm_beyond_v;
         mm_ext      = (mm_ext_v <= m_cfg.mom_max_ext);
         mm_cpos     = (rng0 > 0.0) ? ((s > 0.0) ? (close0 - m1[0].low) / rng0 : (m1[0].high - close0) / rng0) : 0.0;
         mm_close    = (mm_cpos >= m_cfg.mom_close_pos);
      }
      bool pb_ready  = (m5dir != 0) && t_touch && t_hold && t_noext && t_mom && (t_struct || t_reclaim);
      bool mom_ready = m_cfg.mom_enabled && (m5dir != 0) && mm_beyond && mm_ext && mm_body && t_struct && mm_close;

      // ---- 5. MODE 2: liquidity sweep reversal (both directions, any tradable regime) ----
      SSweepProbe best;
      best.valid = false; best.score = -1; best.s = 0.0; best.name = ""; best.price = 0.0;
      best.depth = -99.0; best.extreme = 0.0; best.swept = false; best.in_range = false;
      best.reclaim = false; best.reject = false; best.close_pos = 0.0; best.disp = false; best.disp_x = 0.0;
      bool sweep_ready = false;

      if(m_cfg.sweep_enabled)
      {
         double dispx = (avg_range > 0.0) ? rng0 / avg_range : 0.0;
         for(int d = 0; d < 2; d++)
         {
            double s = (d == 0) ? 1.0 : -1.0;

            double ext  = (s > 0.0) ? MathMin(m1[0].low, m1[1].low) : MathMax(m1[0].high, m1[1].high);
            double cpos = (rng0 > 0.0) ? ((s > 0.0) ? (close0 - m1[0].low) / rng0 : (m1[0].high - close0) / rng0) : 0.0;
            bool   dir_candle = (s * (close0 - m1[0].open) > 0.0);

            for(int li = 0; li < m_ctx.lv_n; li++)
            {
               SSweepProbe p;
               p.valid    = true;
               p.s        = s;
               p.name     = m_ctx.lv_name[li];
               p.price    = m_ctx.lv_price[li];
               p.extreme  = ext;
               p.depth    = s * (p.price - ext) / atr;
               p.swept    = (p.depth >= m_cfg.sweep_min_depth);
               p.in_range = (p.swept && p.depth <= m_cfg.sweep_max_depth);
               p.reclaim  = (s * (close0 - p.price) > 0.0);
               p.close_pos = cpos;
               p.reject   = (cpos >= m_cfg.sweep_close_pos && dir_candle);
               p.disp_x   = dispx;
               p.disp     = (dispx >= m_cfg.sweep_disp_mult);
               p.score    = CountPass(p);

               bool full = (p.swept && p.in_range && p.reclaim && p.reject && p.disp);
               bool better = false;
               if(!best.valid || best.score < 0) better = true;
               else if(full && !sweep_ready)     better = true;
               else if(full == sweep_ready)
               {
                  if(p.score > best.score) better = true;
                  else if(p.score == best.score && p.depth > best.depth) better = true;
               }
               if(better)
               {
                  best = p;
                  sweep_ready = full;
               }
            }
         }
      }

      // ---- 6. Choose the mode that drives the panel and the trade -------------------------
      //        priority when several are ready: sweep > pullback > momentum
      if(sweep_ready)        out.mode = 2;
      else if(pb_ready)      out.mode = 1;
      else if(mom_ready)     out.mode = 3;
      else if(m5dir != 0)    out.mode = 1;      // show the pullback checklist while hunting
      else                   out.mode = 2;      // mixed micro-trend: show the sweep hunt

      double dir_s = 0.0;
      if(out.mode == 1 || out.mode == 3) dir_s = (double)m5dir;
      else if(best.valid) dir_s = best.s;
      out.direction = (dir_s > 0.0) ? DIR_LONG : ((dir_s < 0.0) ? DIR_SHORT : DIR_NONE);

      bool bias_fit = (!m_cfg.use_h1_bias || m_ctx.h1_bias != -(int)dir_s);

      if(out.mode == 1)
      {
         out.mode_name = "PULLBACK";
         out.loc_title = "M5 LOCATION";
         out.trg_title = "M1 TRIGGER";
         out.rule      = "Trigger = Momentum AND (Structure OR Reclaim).  Values in ATR(M5).";

         out.ck_label[0] = "Pullback zone";   out.ck_value[0] = StringFormat("%.2f / %.2f", t_touch_v, m_cfg.zone_atr);          out.ck_pass[0] = t_touch;
         out.ck_label[1] = "Trend held";      out.ck_value[1] = StringFormat("%+.2f / %+.2f", t_hold_v, -m_cfg.hold_atr);       out.ck_pass[1] = t_hold;
         out.ck_label[2] = "Not extended";    out.ck_value[2] = StringFormat("%.2f / %.2f", t_noext_v, m_cfg.max_ext_atr);      out.ck_pass[2] = t_noext;
         out.ck_label[3] = "Structure break"; out.ck_value[3] = StringFormat("%+.2f ATR", t_struct_v);                          out.ck_pass[3] = t_struct;
         out.ck_label[4] = "EMA9 reclaim";    out.ck_value[4] = t_reclaim ? "YES" : "NO";                                       out.ck_pass[4] = t_reclaim;
         out.ck_label[5] = "Momentum";        out.ck_value[5] = StringFormat("%.2f / %.2f", t_mom_v, m_cfg.min_body_frac);      out.ck_pass[5] = t_mom;

         out.location_ok = (t_touch && t_hold && t_noext);
         out.trigger_ok  = (t_mom && (t_struct || t_reclaim));
         out.trg_n       = (t_mom ? 1 : 0) + ((t_struct || t_reclaim) ? 1 : 0);
      }
      else if(out.mode == 3)
      {
         out.mode_name = "MOMENTUM";
         out.loc_title = "M5 TREND";
         out.trg_title = "M1 IMPULSE";
         out.rule      = "Impulse = big body + closes near its extreme + breaks the micro swing.";

         out.ck_label[0] = "Micro-trend";      out.ck_value[0] = (m5dir > 0) ? "UP" : "DOWN";                                      out.ck_pass[0] = (m5dir != 0);
         out.ck_label[1] = "Beyond M5 EMA9";   out.ck_value[1] = StringFormat("%+.2f ATR", mm_beyond_v);                            out.ck_pass[1] = mm_beyond;
         out.ck_label[2] = "Not overextended"; out.ck_value[2] = StringFormat("%.2f / %.2f", mm_ext_v, m_cfg.mom_max_ext);          out.ck_pass[2] = mm_ext;
         out.ck_label[3] = "Impulse body";     out.ck_value[3] = StringFormat("%.1fx / %.1fx", mm_body_v, m_cfg.mom_body_mult);     out.ck_pass[3] = mm_body;
         out.ck_label[4] = "Structure break";  out.ck_value[4] = StringFormat("%+.2f ATR", t_struct_v);                             out.ck_pass[4] = t_struct;
         out.ck_label[5] = "Closes near high"; out.ck_value[5] = StringFormat("%.0f%% / %.0f%%", mm_cpos * 100.0, m_cfg.mom_close_pos * 100.0); out.ck_pass[5] = mm_close;

         out.location_ok = (m5dir != 0 && mm_beyond && mm_ext);
         out.trigger_ok  = (mm_body && t_struct && mm_close);
         out.trg_n       = (mm_body ? 1 : 0) + ((t_struct && mm_close) ? 1 : 0);
      }
      else
      {
         out.mode_name = "LIQUIDITY SWEEP";
         out.loc_title = "LIQUIDITY LEVEL";
         out.trg_title = "SWEEP CONFIRM";
         out.rule      = "Sweep = level taken by a wick, close back inside, rejection + displacement.";

         if(best.valid)
         {
            out.ck_label[0] = "Level swept";     out.ck_value[0] = StringFormat("%s %+.2f", best.name, best.depth);              out.ck_pass[0] = best.swept;
            out.ck_label[1] = "Not a breakdown"; out.ck_value[1] = StringFormat("%.2f / %.2f", best.depth, m_cfg.sweep_max_depth); out.ck_pass[1] = best.in_range;
            out.ck_label[2] = "Closed back in";  out.ck_value[2] = best.reclaim ? "YES" : "NO";                                   out.ck_pass[2] = best.reclaim;
            out.ck_label[3] = "Rejection";       out.ck_value[3] = StringFormat("%.0f%% / %.0f%%", best.close_pos * 100.0, m_cfg.sweep_close_pos * 100.0); out.ck_pass[3] = best.reject;
            out.ck_label[4] = "Displacement";    out.ck_value[4] = StringFormat("%.1fx / %.1fx", best.disp_x, m_cfg.sweep_disp_mult); out.ck_pass[4] = best.disp;
            out.ck_label[5] = "H1 bias fit";     out.ck_value[5] = bias_fit ? "OK" : "OPPOSED";                                   out.ck_pass[5] = bias_fit;
            out.location_ok = (best.swept && best.in_range && best.reclaim);
            out.trigger_ok  = (best.reject && best.disp && bias_fit);
            out.trg_n       = (best.reject ? 1 : 0) + (best.disp ? 1 : 0);
         }
         else
         {
            out.ck_label[0] = "Level swept";    out.ck_value[0] = "no levels";
            out.reason      = "No key liquidity levels available yet";
         }
      }

      out.loc_n = (out.ck_pass[0] ? 1 : 0) + (out.ck_pass[1] ? 1 : 0) + (out.ck_pass[2] ? 1 : 0);
      if(out.mode == 2 && best.valid && best.name == m_last_sweep_level &&
         (TimeCurrent() - m_last_sweep_time) < 600 && out.location_ok && out.trigger_ok)
      {
         out.trigger_ok = false;
         out.reason = StringFormat("Sweep of %s already traded in the last 10 minutes", best.name);
      }

      // ---- 7. Context filters ------------------------------------------------------------
      int dir_i = (int)dir_s;
      out.h1_bias      = m_ctx.h1_bias;
      out.ctx_bias_ok  = bias_fit;
      out.rsi_m1       = m_ctx.rsi_m1;
      out.ctx_rsi_ok   = (dir_i > 0) ? (m_ctx.rsi_m1 < m_cfg.rsi_max) : ((dir_i < 0) ? (m_ctx.rsi_m1 > 100.0 - m_cfg.rsi_max) : true);
      out.atr_usd      = atr;
      out.ctx_vol_ok   = (atr >= m_cfg.min_atr_usd);
      out.session_id   = m_ctx.session_id;
      out.session_name = m_ctx.session_name;
      out.room_atr     = m_ctx.RoomATR(close0, dir_i, atr, out.room_level);
      out.ctx_room_ok  = (out.room_atr >= m_cfg.min_room_atr);

      out.ctx_ok = (out.ctx_bias_ok && out.ctx_rsi_ok && out.ctx_vol_ok && out.ctx_room_ok);
      if(!out.ctx_bias_ok)
         out.ctx_reason = StringFormat("H1 bias is %s - against the trade", (m_ctx.h1_bias > 0) ? "UP" : "DOWN");
      else if(!out.ctx_vol_ok)
         out.ctx_reason = StringFormat("Dead market: ATR(M5) %.2f below floor %.2f", atr, m_cfg.min_atr_usd);
      else if(!out.ctx_rsi_ok)
         out.ctx_reason = StringFormat("RSI(M1) %.0f exhausted for a %s", m_ctx.rsi_m1, (dir_i > 0) ? "buy" : "sell");
      else if(!out.ctx_room_ok)
         out.ctx_reason = StringFormat("Only %.2f ATR of room before %s (need %.2f)", out.room_atr, out.room_level, m_cfg.min_room_atr);

      // ---- 8. Confluence grade --------------------------------------------------------------
      int pts = 0;
      if(dir_i != 0 && m_ctx.h1_bias == dir_i)                pts++;   // H1 trend agrees
      if(m_ctx.session_prime)                                 pts++;   // London open / overlap liquidity
      if(out.room_atr >= 2.0 * m_cfg.min_room_atr)            pts++;   // clear runway
      if(dir_i != 0 && out.regime_dir == dir_i)               pts++;   // slow M15 regime agrees too
      if(pts > 4) pts = 4;
      out.grade_pts = pts;
      out.grade     = (pts >= 3) ? "A" : ((pts == 2) ? "B" : "C");
      out.risk_mult = (pts >= 3) ? 1.0 : ((pts == 2) ? 0.75 : 0.5);
      bool grade_ok = (pts >= m_cfg.min_grade_pts);

      // ---- 9. Protective stop ------------------------------------------------------------------
      if(dir_i != 0)
      {
         double s = (double)dir_i;
         double sl_ref;
         if(out.mode == 2 && best.valid)
         {
            sl_ref = best.extreme;                              // just beyond the sweep wick
         }
         else
         {
            sl_ref = (s > 0.0) ? m1[0].low : m1[0].high;        // beyond the micro swing
            for(int q = 1; q <= m_cfg.swing_bars; q++)
            {
               if(s > 0.0) sl_ref = MathMin(sl_ref, m1[q].low);
               else        sl_ref = MathMax(sl_ref, m1[q].high);
            }
         }
         double entry   = (s > 0.0) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double sl_dist = s * (entry - (sl_ref - s * m_cfg.sl_buffer_atr * atr));
         double min_d   = m_cfg.min_sl_atr * atr;
         double max_d   = MathMax(min_d, m_cfg.atr_sl_mult * atr);
         if(sl_dist < min_d) sl_dist = min_d;
         if(sl_dist > max_d) sl_dist = max_d;
         int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
         out.sl_price = NormalizeDouble(entry - s * sl_dist, digits);
      }

      // ---- 10. Reason (first missing ingredient) -----------------------------------------------
      if(out.reason == "")
      {
         if(out.mode == 1)
         {
            if(!t_touch)        out.reason = StringFormat("No pullback into M5 EMA9 zone (%.2f > %.2f ATR) - watching for a sweep or impulse", t_touch_v, m_cfg.zone_atr);
            else if(!t_hold)    out.reason = StringFormat("Trend support lost: %.2f ATR vs M5 EMA21 (min %.2f)", t_hold_v, -m_cfg.hold_atr);
            else if(!t_noext)   out.reason = StringFormat("Price extended %.2f ATR from M5 EMA9 - not chasing (max %.2f)", t_noext_v, m_cfg.max_ext_atr);
            else if(!t_mom)     out.reason = StringFormat("M1 momentum candle missing (body %.2f of avg range, need %.2f)", t_mom_v, m_cfg.min_body_frac);
            else if(!(t_struct || t_reclaim)) out.reason = "M1 structure break / EMA9 reclaim missing";
         }
         else if(out.mode == 3)
         {
            if(!mm_beyond)      out.reason = "Price not beyond M5 EMA9 in the micro-trend direction";
            else if(!mm_ext)    out.reason = StringFormat("Impulse already overextended (%.2f ATR from EMA9, max %.2f)", mm_ext_v, m_cfg.mom_max_ext);
            else if(!mm_body)   out.reason = StringFormat("Impulse body too small (%.1fx avg range, need %.1fx)", mm_body_v, m_cfg.mom_body_mult);
            else if(!t_struct)  out.reason = "Impulse did not break the micro swing";
            else if(!mm_close)  out.reason = StringFormat("Impulse closed weak (%.0f%% of range, need %.0f%%)", mm_cpos * 100.0, m_cfg.mom_close_pos * 100.0);
         }
         else if(best.valid)
         {
            string idle = (m5dir == 0) ? "M5 micro-trend is mixed. " : "";
            if(!best.swept)         out.reason = StringFormat("%sWaiting for a liquidity sweep - nearest %s (%+.2f ATR)", idle, best.name, best.depth);
            else if(!best.in_range) out.reason = StringFormat("%s broke by %.2f ATR - a breakdown, not a sweep", best.name, best.depth);
            else if(!best.reclaim)  out.reason = StringFormat("%s swept but price has not closed back inside", best.name);
            else if(!best.reject)   out.reason = StringFormat("%s swept - rejection weak (close %.0f%%, need %.0f%%)", best.name, best.close_pos * 100.0, m_cfg.sweep_close_pos * 100.0);
            else if(!best.disp)     out.reason = StringFormat("%s swept - no displacement (%.1fx, need %.1fx)", best.name, best.disp_x, m_cfg.sweep_disp_mult);
            else if(!bias_fit)      out.reason = "Sweep fights the H1 bias";
         }

         if(out.reason == "")
         {
            if(!out.ctx_ok)       out.reason = out.ctx_reason;
            else if(!grade_ok)    out.reason = StringFormat("Grade %s (%d pts) below the minimum of %d", out.grade, pts, m_cfg.min_grade_pts);
            else                  out.reason = "All scalp conditions met";
         }
      }

      out.entry_ready = (out.location_ok && out.trigger_ok && out.ctx_ok && grade_ok);

      if(!out.entry_ready)
      {
         signal.fail_code    = "S_SETUP";
         signal.fail_details = out.reason;
         return false;
      }

      // ---- 11. Signal ---------------------------------------------------------------------------
      signal.valid        = true;
      signal.direction    = out.direction;
      signal.sl_price     = out.sl_price;
      signal.sub_type     = (out.mode == 2) ? "SWEEP" : ((out.mode == 3) ? "MOMENTUM" : "M1SCALP");
      signal.risk_mult    = out.risk_mult;
      signal.score        = pts;
      if(out.mode == 2)
      {
         m_last_sweep_level = best.name;
         m_last_sweep_time  = TimeCurrent();
         signal.pass_details = StringFormat("SWEEP %s %s | depth %.2f | close %.0f%% | disp %.1fx | H1 %+d | room %.1f ATR | grade %s",
                                            DirectionToString(out.direction), best.name, best.depth,
                                            best.close_pos * 100.0, best.disp_x, m_ctx.h1_bias, out.room_atr, out.grade);
      }
      else if(out.mode == 3)
      {
         signal.pass_details = StringFormat("MOMENTUM %s | body %.1fx | close %.0f%% | beyond EMA9 %.2f ATR | brk %+.2f | H1 %+d | room %.1f ATR | grade %s",
                                            DirectionToString(out.direction), mm_body_v, mm_cpos * 100.0, mm_beyond_v,
                                            t_struct_v, m_ctx.h1_bias, out.room_atr, out.grade);
      }
      else
      {
         signal.pass_details = StringFormat("PULLBACK %s | pullback %.2f/%.2f | hold %.2f | ext %.2f | brk %+.2f %s | mom %.2f/%.2f | H1 %+d | room %.1f ATR | grade %s",
                                            DirectionToString(out.direction), t_touch_v, m_cfg.zone_atr, t_hold_v, t_noext_v,
                                            t_struct_v, t_reclaim ? "RECLAIM" : "", t_mom_v, m_cfg.min_body_frac,
                                            m_ctx.h1_bias, out.room_atr, out.grade);
      }
      return true;
   }
};
