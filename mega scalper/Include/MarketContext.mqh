//+------------------------------------------------------------------+
//|                                                MarketContext.mqh |
//|                             XAU-MEGA-SCALPER  CONTEXT LAYER      |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"

//+------------------------------------------------------------------+
//| Everything a gold scalp should know BEFORE it pulls the trigger: |
//|                                                                  |
//|   * H1 bias        EMA50 vs EMA200 + H1 close position           |
//|   * Key liquidity  previous-day high/low, Asian-session range,   |
//|                    intraday high/low, nearest round numbers      |
//|   * Session        Asia / London / London+NY overlap / NY        |
//|   * RSI(M1)        exhaustion filter (do not buy the top)        |
//|                                                                  |
//| Refresh() is called once per closed M1 bar (cheap).              |
//| Session hours are BROKER SERVER hours - shift them to match your |
//| broker's GMT offset.                                             |
//+------------------------------------------------------------------+
class CMarketContext
{
private:
   string   m_symbol;
   int      m_h_h1_ema50;
   int      m_h_h1_ema200;
   int      m_h_rsi_m1;

   int      m_asian_start;
   int      m_asian_end;
   int      m_london_start;
   int      m_overlap_start;
   int      m_overlap_end;
   int      m_ny_end;
   double   m_round_step;

   void AddLevel(const string name, double price)
   {
      if(price <= 0.0 || lv_n >= 12) return;
      lv_name[lv_n]  = name;
      lv_price[lv_n] = price;
      lv_n++;
   }

public:
   // ---- outputs (valid after Refresh) ----
   int      h1_bias;          // +1 / -1 / 0
   double   rsi_m1;
   int      session_id;       // 0 off, 1 asia, 2 london, 3 overlap, 4 ny
   string   session_name;
   bool     session_prime;    // overlap or first 90 minutes of London
   string   lv_name[12];
   double   lv_price[12];
   int      lv_n;

   CMarketContext(void) : m_symbol(SYMBOL_XAUUSD),
                          m_h_h1_ema50(INVALID_HANDLE),
                          m_h_h1_ema200(INVALID_HANDLE),
                          m_h_rsi_m1(INVALID_HANDLE),
                          m_asian_start(0),
                          m_asian_end(7),
                          m_london_start(7),
                          m_overlap_start(12),
                          m_overlap_end(16),
                          m_ny_end(20),
                          m_round_step(50.0),
                          h1_bias(0),
                          rsi_m1(50.0),
                          session_id(0),
                          session_name("OFF"),
                          session_prime(false),
                          lv_n(0)
   {
   }

   ~CMarketContext(void)
   {
      Release();
   }

   void Release(void)
   {
      if(m_h_h1_ema50 != INVALID_HANDLE)  { IndicatorRelease(m_h_h1_ema50);  m_h_h1_ema50  = INVALID_HANDLE; }
      if(m_h_h1_ema200 != INVALID_HANDLE) { IndicatorRelease(m_h_h1_ema200); m_h_h1_ema200 = INVALID_HANDLE; }
      if(m_h_rsi_m1 != INVALID_HANDLE)    { IndicatorRelease(m_h_rsi_m1);    m_h_rsi_m1    = INVALID_HANDLE; }
   }

   bool Init(const string symbol, const SScalpConfig &cfg)
   {
      Release();
      m_symbol        = symbol;
      m_asian_start   = cfg.asian_start;
      m_asian_end     = cfg.asian_end;
      m_london_start  = cfg.london_start;
      m_overlap_start = cfg.overlap_start;
      m_overlap_end   = cfg.overlap_end;
      m_ny_end        = cfg.ny_end;
      m_round_step    = (cfg.round_step > 1.0) ? cfg.round_step : 50.0;

      m_h_h1_ema50  = iMA(m_symbol, PERIOD_H1, 50,  0, MODE_EMA, PRICE_CLOSE);
      m_h_h1_ema200 = iMA(m_symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
      m_h_rsi_m1    = iRSI(m_symbol, PERIOD_M1, 14, PRICE_CLOSE);

      if(m_h_h1_ema50 == INVALID_HANDLE || m_h_h1_ema200 == INVALID_HANDLE || m_h_rsi_m1 == INVALID_HANDLE)
      {
         PrintFormat("[CONTEXT ERROR] Indicator creation failed for %s. Error: %d", m_symbol, GetLastError());
         return false;
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| Recompute bias, session and the key-level list for `price`.      |
   //+------------------------------------------------------------------+
   void Refresh(double price)
   {
      datetime now = TimeCurrent();
      MqlDateTime mdt;
      TimeToStruct(now, mdt);
      int hour = mdt.hour;
      int minu = mdt.min;
      mdt.hour = 0; mdt.min = 0; mdt.sec = 0;
      datetime day0 = StructToTime(mdt);

      // ---- H1 bias --------------------------------------------------
      h1_bias = 0;
      double e50[1], e200[1];
      double h1_close = iClose(m_symbol, PERIOD_H1, 1);
      if(h1_close > 0.0 &&
         CopyBuffer(m_h_h1_ema50, 0, 1, 1, e50) == 1 &&
         CopyBuffer(m_h_h1_ema200, 0, 1, 1, e200) == 1)
      {
         if(e50[0] > e200[0] && h1_close > e50[0])      h1_bias = 1;
         else if(e50[0] < e200[0] && h1_close < e50[0]) h1_bias = -1;
      }

      // ---- RSI(M1) --------------------------------------------------
      double rs[1];
      rsi_m1 = (CopyBuffer(m_h_rsi_m1, 0, 1, 1, rs) == 1) ? rs[0] : 50.0;

      // ---- Session --------------------------------------------------
      session_id    = 0;
      session_name  = "OFF";
      session_prime = false;
      if(hour >= m_overlap_start && hour < m_overlap_end)           { session_id = 3; session_name = "LDN+NY"; }
      else if(hour >= m_london_start && hour < m_overlap_start)     { session_id = 2; session_name = "LONDON"; }
      else if(hour >= m_overlap_end && hour < m_ny_end)             { session_id = 4; session_name = "NEW YORK"; }
      else if(hour >= m_asian_start && hour < m_asian_end)          { session_id = 1; session_name = "ASIA"; }

      int mins_since_london = (hour - m_london_start) * 60 + minu;
      session_prime = (session_id == 3) || (mins_since_london >= 0 && mins_since_london < 90);

      // ---- Key liquidity levels --------------------------------------
      lv_n = 0;

      double pdh = iHigh(m_symbol, PERIOD_D1, 1);
      double pdl = iLow(m_symbol, PERIOD_D1, 1);
      AddLevel("PDH", pdh);
      AddLevel("PDL", pdl);

      // Asian range (only once it has completed today)
      datetime a_start = day0 + m_asian_start * 3600;
      datetime a_end   = day0 + m_asian_end * 3600;
      if(m_asian_end > m_asian_start && now >= a_end)
      {
         MqlRates a_rates[];
         int n = CopyRates(m_symbol, PERIOD_M15, a_start, a_end - 1, a_rates);
         if(n > 0)
         {
            double ah = a_rates[0].high;
            double al = a_rates[0].low;
            for(int i = 1; i < n; i++)
            {
               if(a_rates[i].high > ah) ah = a_rates[i].high;
               if(a_rates[i].low  < al) al = a_rates[i].low;
            }
            AddLevel("ASIA HI", ah);
            AddLevel("ASIA LO", al);
         }
      }

      // Today's extremes, excluding the three most recent M1 bars so a fresh sweep
      // of them is detectable instead of the extreme simply being "now".
      int bars_today = iBarShift(m_symbol, PERIOD_M1, day0, false);
      if(bars_today > 8)
      {
         int ih = iHighest(m_symbol, PERIOD_M1, MODE_HIGH, bars_today - 3, 3);
         int il = iLowest(m_symbol, PERIOD_M1, MODE_LOW,  bars_today - 3, 3);
         if(ih >= 0) AddLevel("DAY HI", iHigh(m_symbol, PERIOD_M1, ih));
         if(il >= 0) AddLevel("DAY LO", iLow(m_symbol, PERIOD_M1, il));
      }

      // Round numbers either side of price (psychological levels)
      double base = MathFloor(price / m_round_step) * m_round_step;
      AddLevel(StringFormat("%.0f", base), base);
      AddLevel(StringFormat("%.0f", base + m_round_step), base + m_round_step);
   }

   //+------------------------------------------------------------------+
   //| Free space (in ATR) to the nearest level in trade direction.     |
   //+------------------------------------------------------------------+
   double RoomATR(double price, int dir, double atr, string &level_name)
   {
      level_name = "none";
      if(atr <= 0.0 || dir == 0) return 99.0;

      double best = 99.0;
      for(int i = 0; i < lv_n; i++)
      {
         double d = (double)dir * (lv_price[i] - price);
         if(d <= 0.05 * atr) continue;                // behind us or touching
         double d_atr = d / atr;
         if(d_atr < best)
         {
            best = d_atr;
            level_name = lv_name[i];
         }
      }
      return best;
   }
};
