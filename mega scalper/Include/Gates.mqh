//+------------------------------------------------------------------+
//|                                                        Gates.mqh |
//|                             XAU-MEGA-SCALPER Formal Spec v0.2    |
//|                             DEBUG & CONTINUOUS RESEARCH EDITION  |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"
#include "DataModel.mqh"

class CGates
{
private:
   string         m_symbol;
   ulong          m_magic;
   bool           m_research_mode;

   // Budgeted Parameters (§1)
   double         m_max_spread_atr_ratio;
   double         m_daily_dd_pct;
   int            m_consec_loss_limit;
   int            m_cooldown_bars;
   int            m_max_positions;
   int            m_news_blackout_min;

   // Telemetry
   datetime       m_current_day_start;
   double         m_day_starting_equity;
   int            m_daily_consec_losses;
   datetime       m_last_trade_close_time;

public:
   CGates(void) : m_symbol(SYMBOL_XAUUSD),
                  m_magic(202601),
                  m_research_mode(true),
                  m_max_spread_atr_ratio(0.15),
                  m_daily_dd_pct(0.03),
                  m_consec_loss_limit(3),
                  m_cooldown_bars(0),
                  m_max_positions(1),
                  m_news_blackout_min(30),
                  m_current_day_start(0),
                  m_day_starting_equity(0.0),
                  m_daily_consec_losses(0),
                  m_last_trade_close_time(0)
   {
   }

   void Init(string symbol,
             ulong magic,
             bool research_mode,
             double max_spread_atr_ratio,
             double daily_dd_pct,
             int consec_loss_limit,
             int cooldown_bars,
             int max_positions,
             int news_blackout_min)
   {
      m_symbol               = symbol;
      m_magic                = magic;
      m_research_mode        = research_mode;
      m_max_spread_atr_ratio = max_spread_atr_ratio;
      m_daily_dd_pct         = daily_dd_pct;
      m_consec_loss_limit    = consec_loss_limit;
      m_cooldown_bars        = cooldown_bars;
      m_max_positions        = max_positions;
      m_news_blackout_min    = news_blackout_min;

      ResetDailyTracking();
   }

   void SetResearchMode(bool active) { m_research_mode = active; }
   bool IsResearchMode(void) const { return m_research_mode; }

   void ResetDailyTracking(void)
   {
      datetime now = TimeCurrent();
      MqlDateTime mdt;
      TimeToStruct(now, mdt);
      mdt.hour = 0; mdt.min = 0; mdt.sec = 0;
      m_current_day_start = StructToTime(mdt);
      m_day_starting_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      UpdateTradeHistoryStats();
   }

   void OnNewDay(datetime server_time)
   {
      MqlDateTime mdt;
      TimeToStruct(server_time, mdt);
      mdt.hour = 0; mdt.min = 0; mdt.sec = 0;
      datetime day_start = StructToTime(mdt);

      if(day_start > m_current_day_start)
      {
         m_current_day_start = day_start;
         m_day_starting_equity = AccountInfoDouble(ACCOUNT_EQUITY);
         m_daily_consec_losses = 0;
      }
   }

   void UpdateTradeHistoryStats(void)
   {
      datetime now = TimeCurrent();
      HistorySelect(m_current_day_start, now);
      int total_deals = HistoryDealsTotal();

      m_daily_consec_losses = 0;
      m_last_trade_close_time = 0;

      for(int i = total_deals - 1; i >= 0; i--)
      {
         ulong deal_ticket = HistoryDealGetTicket(i);
         if(deal_ticket == 0) continue;

         long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
         if(magic != (long)m_magic) continue;

         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
         {
            datetime deal_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
            if(deal_time > m_last_trade_close_time)
               m_last_trade_close_time = deal_time;

            double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) +
                            HistoryDealGetDouble(deal_ticket, DEAL_SWAP) +
                            HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);

            if(profit < 0.0)
               m_daily_consec_losses++;
            else if(profit > 0.0)
               break;
         }
      }
   }

   // Check G1 Warmup
   bool EvaluateG1(CDataModel &data, SGateResults &res)
   {
      string reason = "";
      res.m15_bars_req  = 250;
      res.m5_bars_req   = 250;
      res.m1_bars_req   = 500;
      res.vwap_bars_req = 30;

      if(!data.CheckWarmup(reason, res.m15_bars_have, res.m5_bars_have, res.m1_bars_have, res.vwap_bars_have))
      {
         res.fail_reason = reason;
         return false;
      }
      return true;
   }

   // Check G2 Session Rules (§3.1)
   bool EvaluateG2(datetime server_time, string &fail_reason)
   {
      MqlDateTime mdt;
      TimeToStruct(server_time, mdt);

      if(mdt.day_of_week == 5 && mdt.hour >= 19)
      {
         fail_reason = "Friday after 19:00 blackout";
         return false;
      }

      int min_of_day = mdt.hour * 60 + mdt.min;
      if(min_of_day >= 1350 || min_of_day < 90)
      {
         fail_reason = "Rollover blackout (22:30-01:30)";
         return false;
      }

      // London 07:00-16:00, NY 12:30-20:00 (Union: 07:00 - 20:00)
      if(min_of_day < 420 || min_of_day >= 1200)
      {
         fail_reason = StringFormat("Outside session (Server %02d:%02d not in 07:00-20:00)", mdt.hour, mdt.min);
         return false;
      }

      return true;
   }

   // Check G3 Spread Gate: spread_price <= max_spread_atr_ratio * ATR_M5
   bool EvaluateG3(double spread_pts, double atr_m5, double point_val, SGateResults &res)
   {
      res.spread_pts         = spread_pts;
      res.spread_price       = spread_pts * point_val;
      res.spread_limit_ratio = m_max_spread_atr_ratio;

      if(atr_m5 <= 0.0)
      {
         res.spread_atr_ratio = 0.0;
         res.fail_reason = "ATR_M5 is non-positive (0)";
         return false;
      }

      res.spread_atr_ratio = res.spread_price / atr_m5;

      if(res.spread_atr_ratio > m_max_spread_atr_ratio)
      {
         res.fail_reason = StringFormat("Spread ratio %.3f ATR > limit %.3f ATR (%.1f pts)",
                                        res.spread_atr_ratio, m_max_spread_atr_ratio, spread_pts);
         return false;
      }

      return true;
   }

   // Check G4 News Blackout
   bool EvaluateG4(datetime server_time, string &fail_reason)
   {
#ifdef __MQL5__
      MqlCalendarValue values[];
      datetime from = server_time - m_news_blackout_min * 60;
      datetime to   = server_time + m_news_blackout_min * 60;

      ResetLastError();
      int count = CalendarValueHistory(values, from, to, "US");
      if(count > 0)
      {
         for(int i = 0; i < count; i++)
         {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
            {
               if(event.importance == CALENDAR_IMPORTANCE_HIGH)
               {
                  fail_reason = StringFormat("News blackout: %s within %d min", event.name, m_news_blackout_min);
                  return false;
               }
            }
         }
      }
#endif
      return true;
   }

   // Check G5 Regime Gate
   bool EvaluateG5(const SRegimeState &regime, string &fail_reason)
   {
      if(regime.active_regime == REGIME_CHAOS)
      {
         fail_reason = StringFormat("Regime is CHAOS (%s)", regime.primary_chaos_reason);
         return false;
      }

      if(!regime.dwell_ok)
      {
         fail_reason = StringFormat("Regime dwell not met (%d/%d bars)", regime.dwell_count, regime.dwell_required);
         return false;
      }

      return true;
   }

   // Check G6 Risk Gate (§7 & §8)
   bool EvaluateG6(SGateResults &res)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_day_starting_equity > 0.0)
      {
         double dd = (m_day_starting_equity - equity) / m_day_starting_equity;
         res.daily_dd_pct = (dd > 0.0) ? dd : 0.0;
      }
      else
      {
         res.daily_dd_pct = 0.0;
      }

      UpdateTradeHistoryStats();
      res.consec_losses  = m_daily_consec_losses;
      res.open_positions = CountActivePositions();
      res.max_positions  = m_max_positions;

      // In Production mode, DD & consecutive losses halt the EA
      if(!m_research_mode)
      {
         if(res.daily_dd_pct >= m_daily_dd_pct)
         {
            res.fail_reason = StringFormat("Daily DD breach: %.2f%% >= limit %.2f%%", res.daily_dd_pct * 100.0, m_daily_dd_pct * 100.0);
            return false;
         }

         if(res.consec_losses >= m_consec_loss_limit)
         {
            res.fail_reason = StringFormat("Consecutive losses %d >= limit %d", res.consec_losses, m_consec_loss_limit);
            return false;
         }
      }

      // Hard Cap: Global 1 open position (§8)
      if(res.open_positions >= m_max_positions)
      {
         res.fail_reason = StringFormat("Open positions %d >= max %d", res.open_positions, m_max_positions);
         return false;
      }

      if(m_cooldown_bars > 0 && m_last_trade_close_time > 0)
      {
         int bars_since_close = iBarShift(m_symbol, PERIOD_M5, m_last_trade_close_time, false);
         if(bars_since_close < m_cooldown_bars)
         {
            res.fail_reason = StringFormat("Cooldown active: %d M5 bars < %d required", bars_since_close, m_cooldown_bars);
            return false;
         }
      }

      return true;
   }

   // Check G7 Execution Gate
   bool EvaluateG7(string &fail_reason)
   {
      if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      {
         fail_reason = "Terminal disconnected";
         return false;
      }

      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      {
         fail_reason = "Algo trading disabled in terminal/EA";
         return false;
      }

      if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      {
         fail_reason = "Trading not allowed for account";
         return false;
      }

      return true;
   }

   // Master Gate Evaluation
   bool EvaluateAllGates(CDataModel &data,
                         const SRegimeState &regime,
                         double spread_pts,
                         double point_val,
                         SGateResults &results)
   {
      datetime now = TimeCurrent();
      OnNewDay(now);

      results.all_passed   = false;
      results.g1_warmup    = false;
      results.g2_session   = false;
      results.g3_spread    = false;
      results.g4_news      = false;
      results.g5_regime    = false;
      results.g6_risk      = false;
      results.g7_execution = false;
      results.fail_gate    = "";
      results.fail_reason  = "";

      // G1: WARMUP
      if(!EvaluateG1(data, results))
      {
         results.fail_gate = "G1_WARMUP";
         return false;
      }
      results.g1_warmup = true;

      // G2: SESSION
      if(!EvaluateG2(now, results.fail_reason))
      {
         results.fail_gate = "G2_SESSION";
         return false;
      }
      results.g2_session = true;

      // G3: SPREAD
      if(!EvaluateG3(spread_pts, regime.atr_m5, point_val, results))
      {
         results.fail_gate = "G3_SPREAD";
         return false;
      }
      results.g3_spread = true;

      // G4: NEWS
      if(!EvaluateG4(now, results.fail_reason))
      {
         results.fail_gate = "G4_NEWS";
         return false;
      }
      results.g4_news = true;

      // G5: REGIME
      if(!EvaluateG5(regime, results.fail_reason))
      {
         results.fail_gate = "G5_REGIME";
         return false;
      }
      results.g5_regime = true;

      // G6: RISK
      if(!EvaluateG6(results))
      {
         results.fail_gate = "G6_RISK";
         return false;
      }
      results.g6_risk = true;

      // G7: EXECUTION
      if(!EvaluateG7(results.fail_reason))
      {
         results.fail_gate = "G7_EXECUTION";
         return false;
      }
      results.g7_execution = true;

      results.all_passed = true;
      return true;
   }

   int CountActivePositions(void)
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
               PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
            {
               count++;
            }
         }
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket > 0)
         {
            if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
               OrderGetInteger(ORDER_MAGIC) == (long)m_magic)
            {
               count++;
            }
         }
      }
      return count;
   }
};
