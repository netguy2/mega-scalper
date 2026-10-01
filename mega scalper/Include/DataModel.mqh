//+------------------------------------------------------------------+
//|                                                    DataModel.mqh |
//|                             XAU-MEGA-SCALPER Formal Spec v1.0    |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"

class CDataModel
{
private:
   string         m_symbol;
   
   // Indicator Handles
   int            m_h_ema9_m15;
   int            m_h_ema21_m15;
   int            m_h_ema50_m15;
   int            m_h_ema9_m5;
   int            m_h_ema21_m5;
   int            m_h_adx_m15;
   int            m_h_atr_m15;
   int            m_h_atr_m5;
   int            m_h_bands_m5;

   // Indicator parameters
   int            m_adx_period;
   int            m_atr_period_m15;
   int            m_atr_period_m5;
   int            m_ema_fast;
   int            m_ema_mid;
   int            m_ema_slow;
   int            m_bb_period;
   double         m_bb_sigma;
   int            m_donchian_period;
   int            m_vwap_slope_bars;
   int            m_atr_pct_lookback_bars;
   double         m_atr_pct_chaos_pctl;
   int            m_spread_avg_lookback_ticks;

   // Rolling tick spread tracker
   double         m_spread_history[];
   int            m_spread_count;
   int            m_spread_idx;

public:
   CDataModel(void) : m_symbol(SYMBOL_XAUUSD),
                      m_h_ema9_m15(INVALID_HANDLE),
                      m_h_ema21_m15(INVALID_HANDLE),
                      m_h_ema50_m15(INVALID_HANDLE),
                      m_h_ema9_m5(INVALID_HANDLE),
                      m_h_ema21_m5(INVALID_HANDLE),
                      m_h_adx_m15(INVALID_HANDLE),
                      m_h_atr_m15(INVALID_HANDLE),
                      m_h_atr_m5(INVALID_HANDLE),
                      m_h_bands_m5(INVALID_HANDLE),
                      m_adx_period(14),
                      m_atr_period_m15(14),
                      m_atr_period_m5(14),
                      m_ema_fast(9),
                      m_ema_mid(21),
                      m_ema_slow(50),
                      m_bb_period(20),
                      m_bb_sigma(2.0),
                      m_donchian_period(20),
                      m_vwap_slope_bars(5),
                      m_atr_pct_lookback_bars(100),
                      m_atr_pct_chaos_pctl(99.0),
                      m_spread_avg_lookback_ticks(100),
                      m_spread_count(0),
                      m_spread_idx(0)
   {
   }

   ~CDataModel(void)
   {
      ReleaseIndicators();
   }

   void ReleaseIndicators(void)
   {
      if(m_h_ema9_m15 != INVALID_HANDLE)   IndicatorRelease(m_h_ema9_m15);
      if(m_h_ema21_m15 != INVALID_HANDLE)  IndicatorRelease(m_h_ema21_m15);
      if(m_h_ema50_m15 != INVALID_HANDLE)  IndicatorRelease(m_h_ema50_m15);
      if(m_h_ema9_m5 != INVALID_HANDLE)    IndicatorRelease(m_h_ema9_m5);
      if(m_h_ema21_m5 != INVALID_HANDLE)   IndicatorRelease(m_h_ema21_m5);
      if(m_h_adx_m15 != INVALID_HANDLE)    IndicatorRelease(m_h_adx_m15);
      if(m_h_atr_m15 != INVALID_HANDLE)    IndicatorRelease(m_h_atr_m15);
      if(m_h_atr_m5 != INVALID_HANDLE)     IndicatorRelease(m_h_atr_m5);
      if(m_h_bands_m5 != INVALID_HANDLE)   IndicatorRelease(m_h_bands_m5);

      m_h_ema9_m15 = m_h_ema21_m15 = m_h_ema50_m15 = INVALID_HANDLE;
      m_h_ema9_m5  = m_h_ema21_m5  = INVALID_HANDLE;
      m_h_adx_m15  = m_h_atr_m15   = m_h_atr_m5     = INVALID_HANDLE;
      m_h_bands_m5 = INVALID_HANDLE;
   }

   bool Init(string symbol,
             int adx_period,
             int atr_period_m15,
             int atr_period_m5,
             int ema_fast,
             int ema_mid,
             int ema_slow,
             int bb_period,
             double bb_sigma,
             int donchian_period,
             int vwap_slope_bars,
             int atr_pct_lookback_bars,
             double atr_pct_chaos_pctl,
             int spread_avg_lookback_ticks)
   {
      m_symbol = symbol;
      m_adx_period = adx_period;
      m_atr_period_m15 = atr_period_m15;
      m_atr_period_m5 = atr_period_m5;
      m_ema_fast = ema_fast;
      m_ema_mid = ema_mid;
      m_ema_slow = ema_slow;
      m_bb_period = bb_period;
      m_bb_sigma = bb_sigma;
      m_donchian_period = donchian_period;
      m_vwap_slope_bars = vwap_slope_bars;
      m_atr_pct_lookback_bars = atr_pct_lookback_bars;
      m_atr_pct_chaos_pctl = atr_pct_chaos_pctl;
      m_spread_avg_lookback_ticks = spread_avg_lookback_ticks;

      ArrayResize(m_spread_history, m_spread_avg_lookback_ticks);
      ArrayInitialize(m_spread_history, 0.0);
      m_spread_count = 0;
      m_spread_idx = 0;

      ReleaseIndicators();

      // M15 Indicators
      m_h_ema9_m15  = iMA(m_symbol, PERIOD_M15, m_ema_fast, 0, MODE_EMA, PRICE_CLOSE);
      m_h_ema21_m15 = iMA(m_symbol, PERIOD_M15, m_ema_mid, 0, MODE_EMA, PRICE_CLOSE);
      m_h_ema50_m15 = iMA(m_symbol, PERIOD_M15, m_ema_slow, 0, MODE_EMA, PRICE_CLOSE);
      m_h_adx_m15   = iADX(m_symbol, PERIOD_M15, m_adx_period);
      m_h_atr_m15   = iATR(m_symbol, PERIOD_M15, m_atr_period_m15);

      // M5 Indicators
      m_h_atr_m5    = iATR(m_symbol, PERIOD_M5, m_atr_period_m5);
      m_h_ema9_m5   = iMA(m_symbol, PERIOD_M5, m_ema_fast, 0, MODE_EMA, PRICE_CLOSE);
      m_h_ema21_m5  = iMA(m_symbol, PERIOD_M5, m_ema_mid, 0, MODE_EMA, PRICE_CLOSE);
      m_h_bands_m5  = iBands(m_symbol, PERIOD_M5, m_bb_period, 0, m_bb_sigma, PRICE_CLOSE);

      if(m_h_ema9_m15 == INVALID_HANDLE || m_h_ema21_m15 == INVALID_HANDLE || m_h_ema50_m15 == INVALID_HANDLE ||
         m_h_adx_m15 == INVALID_HANDLE || m_h_atr_m15 == INVALID_HANDLE || m_h_atr_m5 == INVALID_HANDLE ||
         m_h_bands_m5 == INVALID_HANDLE || m_h_ema9_m5 == INVALID_HANDLE || m_h_ema21_m5 == INVALID_HANDLE)
      {
         PrintFormat("[DATA_MODEL ERROR] Indicator creation failed for symbol %s. Error: %d", m_symbol, GetLastError());
         return false;
      }

      return true;
   }

   // Update rolling tick spread on every incoming tick
   void UpdateTickSpread(double spread_pts)
   {
      m_spread_history[m_spread_idx] = spread_pts;
      m_spread_idx = (m_spread_idx + 1) % m_spread_avg_lookback_ticks;
      if(m_spread_count < m_spread_avg_lookback_ticks) m_spread_count++;
   }

   double GetSpreadAvg(void) const
   {
      if(m_spread_count == 0) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < m_spread_count; i++)
         sum += m_spread_history[i];
      return sum / m_spread_count;
   }

   // Warmup validation (§2, G1)
   bool CheckWarmup(string &reason, int &m15_count, int &m5_count, int &m1_count, int &session_m1_count)
   {
      m15_count = iBars(m_symbol, PERIOD_M15);
      m5_count  = iBars(m_symbol, PERIOD_M5);
      m1_count  = iBars(m_symbol, PERIOD_M1);

      if(m15_count < 250)
      {
         reason = StringFormat("M15 bars %d < 250", m15_count);
         return false;
      }
      if(m5_count < 250)
      {
         reason = StringFormat("M5 bars %d < 250", m5_count);
         return false;
      }
      if(m1_count < 500)
      {
         reason = StringFormat("M1 bars %d < 500", m1_count);
         return false;
      }

      // Check Session VWAP bars (>= 30 M1 bars since rollover)
      datetime now = TimeCurrent();
      MqlDateTime mdt;
      TimeToStruct(now, mdt);
      mdt.hour = 0;
      mdt.min  = 0;
      mdt.sec  = 0;
      datetime day_start = StructToTime(mdt);

      session_m1_count = iBarShift(m_symbol, PERIOD_M1, day_start, false);
      // iBarShift gives shift relative to now (0 is current bar)
      if(session_m1_count < 30)
      {
         reason = StringFormat("Session M1 bars %d < 30", session_m1_count);
         return false;
      }

      return true;
   }

   // Calculate Session VWAP from broker rollover up to reference bar time
   double CalculateSessionVWAP(datetime target_time)
   {
      MqlDateTime mdt;
      TimeToStruct(target_time, mdt);
      mdt.hour = 0;
      mdt.min  = 0;
      mdt.sec  = 0;
      datetime day_start = StructToTime(mdt);

      MqlRates m1_rates[];
      ArraySetAsSeries(m1_rates, true);
      int copied = CopyRates(m_symbol, PERIOD_M1, day_start, target_time, m1_rates);
      if(copied <= 0) return 0.0;

      double sum_typical_vol = 0.0;
      double sum_vol = 0.0;

      for(int i = 0; i < copied; i++)
      {
         double typical = (m1_rates[i].high + m1_rates[i].low + m1_rates[i].close) / 3.0;
         double vol = (double)m1_rates[i].tick_volume;
         sum_typical_vol += typical * vol;
         sum_vol += vol;
      }

      if(sum_vol > 0.0)
         return sum_typical_vol / sum_vol;
      
      return (m1_rates[0].high + m1_rates[0].low + m1_rates[0].close) / 3.0;
   }

   // Copy closed bar rates for a given timeframe (index 1 is latest closed bar)
   bool GetClosedBars(ENUM_TIMEFRAMES tf, int count, MqlRates &rates[])
   {
      ArraySetAsSeries(rates, true);
      // Index 1 is the last completed bar, count bars
      int copied = CopyRates(m_symbol, tf, 1, count, rates);
      return (copied == count);
   }

   // Indicator Value Accessors (Series array indexing: 0 = bar[1], latest closed bar)
   bool GetATR_M15(int count, double &buf[])
   {
      ArraySetAsSeries(buf, true);
      return (CopyBuffer(m_h_atr_m15, 0, 1, count, buf) == count);
   }

   bool GetATR_M5(int count, double &buf[])
   {
      ArraySetAsSeries(buf, true);
      return (CopyBuffer(m_h_atr_m5, 0, 1, count, buf) == count);
   }

   bool GetEMA_M15(double &ema9, double &ema21, double &ema50)
   {
      double b9[1], b21[1], b50[1];
      if(CopyBuffer(m_h_ema9_m15, 0, 1, 1, b9) < 1) return false;
      if(CopyBuffer(m_h_ema21_m15, 0, 1, 1, b21) < 1) return false;
      if(CopyBuffer(m_h_ema50_m15, 0, 1, 1, b50) < 1) return false;
      ema9  = b9[0];
      ema21 = b21[0];
      ema50 = b50[0];
      return true;
   }

   // M5 EMAs on the last closed M5 bar (location reference for the M1 scalp layer)
   bool GetEMA_M5(double &ema9, double &ema21)
   {
      double b9[1], b21[1];
      if(CopyBuffer(m_h_ema9_m5, 0, 1, 1, b9) < 1) return false;
      if(CopyBuffer(m_h_ema21_m5, 0, 1, 1, b21) < 1) return false;
      ema9  = b9[0];
      ema21 = b21[0];
      return true;
   }

   bool GetADX_M15(double &adx_val)
   {
      double b[1];
      if(CopyBuffer(m_h_adx_m15, 0, 1, 1, b) < 1) return false;
      adx_val = b[0];
      return true;
   }

   bool GetBands_M5(double &mid, double &upper, double &lower)
   {
      double b_mid[1], b_up[1], b_dn[1];
      if(CopyBuffer(m_h_bands_m5, 0, 1, 1, b_mid) < 1) return false;
      if(CopyBuffer(m_h_bands_m5, 1, 1, 1, b_up) < 1)  return false;
      if(CopyBuffer(m_h_bands_m5, 2, 1, 1, b_dn) < 1)  return false;
      mid   = b_mid[0];
      upper = b_up[0];
      lower = b_dn[0];
      return true;
   }

   // Donchian High and Low over closed M5 bars (excluding current forming bar)
   bool GetDonchian_M5(int period, double &donchian_high, double &donchian_low)
   {
      MqlRates rates[];
      if(!GetClosedBars(PERIOD_M5, period, rates)) return false;

      donchian_high = rates[0].high;
      donchian_low  = rates[0].low;

      for(int i = 1; i < period; i++)
      {
         if(rates[i].high > donchian_high) donchian_high = rates[i].high;
         if(rates[i].low  < donchian_low)  donchian_low  = rates[i].low;
      }
      return true;
   }

   // Calculate SMA of ATR_M5 over 96 bars for atr_ratio calculation
   bool GetATR_M5_Ratio(double &atr_m5_current, double &atr_ratio)
   {
      double atr_buf[];
      ArraySetAsSeries(atr_buf, true);
      int copied = CopyBuffer(m_h_atr_m5, 0, 1, 96, atr_buf);
      if(copied < 96) return false;

      atr_m5_current = atr_buf[0];
      double sum = 0.0;
      for(int i = 0; i < 96; i++) sum += atr_buf[i];
      double sma_96 = sum / 96.0;

      atr_ratio = (sma_96 > 0.0) ? (atr_m5_current / sma_96) : 1.0;
      return true;
   }

   // Calculate 99th percentile of atr_pct = ATR_M15 / close over last atr_pct_lookback_bars M15 bars
   bool GetATRPctPercentile(double &atr_pct_current, double &atr_pct_pctl)
   {
      double atr_buf[];
      ArraySetAsSeries(atr_buf, true);
      MqlRates m15_rates[];
      ArraySetAsSeries(m15_rates, true);

      int copied_atr = CopyBuffer(m_h_atr_m15, 0, 1, m_atr_pct_lookback_bars, atr_buf);
      int copied_rates = CopyRates(m_symbol, PERIOD_M15, 1, m_atr_pct_lookback_bars, m15_rates);
      if(copied_atr < m_atr_pct_lookback_bars || copied_rates < m_atr_pct_lookback_bars) return false;

      double ratios[];
      ArrayResize(ratios, m_atr_pct_lookback_bars);

      for(int i = 0; i < m_atr_pct_lookback_bars; i++)
      {
         if(m15_rates[i].close > 0.0)
            ratios[i] = atr_buf[i] / m15_rates[i].close;
         else
            ratios[i] = 0.0;
      }

      atr_pct_current = ratios[0];

      // Sort ascending to get percentile
      ArraySort(ratios);
      int rank = (int)MathRound((m_atr_pct_chaos_pctl / 100.0) * (m_atr_pct_lookback_bars - 1));
      if(rank >= m_atr_pct_lookback_bars) rank = m_atr_pct_lookback_bars - 1;
      if(rank < 0) rank = 0;

      atr_pct_pctl = ratios[rank];
      return true;
   }

   // Calculate VWAP slope over vwap_slope_bars M5 closes:
   // (vwap[t] - vwap[t-N]) / (N * ATR_M5)
   bool GetVWAPSlope(double vwap_current, double atr_m5, double &vwap_slope)
   {
      MqlRates m5_rates[];
      // We need closed bar from N bars ago
      int copied = CopyRates(m_symbol, PERIOD_M5, m_vwap_slope_bars + 1, 1, m5_rates);
      if(copied < 1) return false;

      datetime time_n = m5_rates[0].time;
      double vwap_n = CalculateSessionVWAP(time_n);

      if(atr_m5 <= 0.0 || m_vwap_slope_bars <= 0)
      {
         vwap_slope = 0.0;
         return false;
      }

      vwap_slope = (vwap_current - vwap_n) / ((double)m_vwap_slope_bars * atr_m5);
      return true;
   }
};
