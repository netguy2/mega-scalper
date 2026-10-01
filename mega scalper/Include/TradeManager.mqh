//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh |
//|                             XAU-MEGA-SCALPER Formal Spec v1.0    |
//|                             CONTINUOUS RESEARCH / TEST EDITION   |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include <Trade\Trade.mqh>
#include "Defines.mqh"
#include "Logger.mqh"

class CTradeManager
{
private:
   string         m_symbol;
   ulong          m_magic;
   CTrade         m_trade;
   CLogger       *m_logger;

   // Emergency parameters (§11)
   double         m_spread_chaos_abs_pts;
   double         m_daily_dd_pct;
   bool           m_research_mode;

   // Active position tracking state
   SPositionTrack m_pos;

   // Performance Tracking & Strategy Attribution (§10 & §11)
   STradeStats    m_stats;
   SEngineStats   m_stats_engine_a;
   SEngineStats   m_stats_engine_b;
   SEngineStats   m_stats_engine_c;

public:
   CTradeManager(void) : m_symbol(SYMBOL_XAUUSD),
                         m_magic(202601),
                         m_logger(NULL),
                         m_spread_chaos_abs_pts(450.0),
                         m_daily_dd_pct(0.03),
                         m_research_mode(true)
   {
      ResetPositionTrack();
      ResetStatistics();
   }

   void Init(string symbol, ulong magic, CLogger *logger, double spread_chaos_abs_pts, double daily_dd_pct, bool research_mode)
   {
      m_symbol               = symbol;
      m_magic                = magic;
      m_logger               = logger;
      m_spread_chaos_abs_pts = spread_chaos_abs_pts;
      m_daily_dd_pct         = daily_dd_pct;
      m_research_mode        = research_mode;

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(30);
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);

      uint filling = (uint)SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_FOK) != 0)
         m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((filling & SYMBOL_FILLING_IOC) != 0)
         m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else
         m_trade.SetTypeFilling(ORDER_FILLING_RETURN);

      ResetPositionTrack();
      SyncOpenPosition();
      UpdateHistoryStatistics();
   }

   void ResetPositionTrack(void)
   {
      m_pos.ticket       = 0;
      m_pos.magic        = m_magic;
      m_pos.engine       = ENGINE_NONE;
      m_pos.direction    = DIR_NONE;
      m_pos.entry_price  = 0.0;
      m_pos.initial_sl   = 0.0;
      m_pos.current_sl   = 0.0;
      m_pos.initial_lots = 0.0;
      m_pos.current_lots = 0.0;
      m_pos.r_points     = 0.0;
      m_pos.stage        = STAGE_INITIAL;
      m_pos.open_time    = 0;
      m_pos.bars_held_m5 = 0;
      m_pos.indivisible  = false;
      m_pos.active       = false;
   }

   void ResetStatistics(void)
   {
      ZeroMemory(m_stats);
      ZeroMemory(m_stats_engine_a);
      ZeroMemory(m_stats_engine_b);
      ZeroMemory(m_stats_engine_c);
   }

   STradeStats GetGlobalStats(void) const { return m_stats; }
   SEngineStats GetEngineAStats(void) const { return m_stats_engine_a; }
   SEngineStats GetEngineBStats(void) const { return m_stats_engine_b; }
   SEngineStats GetEngineCStats(void) const { return m_stats_engine_c; }

   bool HasActivePosition(void) const { return m_pos.active; }
   SPositionTrack GetCurrentPosition(void) const { return m_pos; }

   void RegisterExecutionLatency(long latency_ms)
   {
      m_stats.total_latency_ms += latency_ms;
      m_stats.latency_samples++;
      m_stats.avg_latency_ms = (double)m_stats.total_latency_ms / (double)m_stats.latency_samples;
   }

   void RegisterRejection(void) { m_stats.rejected_orders++; }
   void RegisterPartialFill(void) { m_stats.partial_fills++; }

   void RegisterNewPosition(ulong ticket,
                            ENUM_ENGINE_TYPE engine,
                            ENUM_TRADE_DIRECTION dir,
                            double entry_price,
                            double sl_price,
                            double lots,
                            bool is_indivisible)
   {
      m_pos.ticket       = ticket;
      m_pos.magic        = m_magic;
      m_pos.engine       = engine;
      m_pos.direction    = dir;
      m_pos.entry_price  = entry_price;
      m_pos.initial_sl   = sl_price;
      m_pos.current_sl   = sl_price;
      m_pos.initial_lots = lots;
      m_pos.current_lots = lots;
      m_pos.r_points     = MathAbs(entry_price - sl_price);
      m_pos.stage        = STAGE_INITIAL;
      m_pos.open_time    = TimeCurrent();
      m_pos.bars_held_m5 = 0;
      m_pos.indivisible  = is_indivisible;
      m_pos.active       = true;

      if(m_logger != NULL)
      {
         m_logger.LogEvent("TRADE_OPEN",
            StringFormat("Ticket #%I64u | Engine: %s | Dir: %s | Lots: %.2f | Entry: %.2f | SL: %.2f | R_dist: %.2f pts",
                         m_pos.ticket, EngineToString(m_pos.engine), DirectionToString(m_pos.direction),
                         m_pos.current_lots, m_pos.entry_price, m_pos.initial_sl, m_pos.r_points / _Point));
      }
   }

   // Sync existing position on startup or reload
   void SyncOpenPosition(void)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
               PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
            {
               m_pos.ticket       = ticket;
               m_pos.entry_price  = PositionGetDouble(POSITION_PRICE_OPEN);
               m_pos.current_sl   = PositionGetDouble(POSITION_SL);
               m_pos.initial_sl   = m_pos.current_sl;
               m_pos.current_lots = PositionGetDouble(POSITION_VOLUME);
               m_pos.initial_lots = m_pos.current_lots;
               m_pos.direction    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? DIR_LONG : DIR_SHORT;
               m_pos.r_points     = MathAbs(m_pos.entry_price - m_pos.current_sl);
               m_pos.open_time    = (datetime)PositionGetInteger(POSITION_TIME);
               m_pos.stage        = STAGE_INITIAL;
               m_pos.active       = true;

               double lot_step    = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
               m_pos.indivisible  = (m_pos.current_lots < (2.0 * lot_step));

               string comment = PositionGetString(POSITION_COMMENT);
               if(StringFind(comment, "ENG_A") >= 0) m_pos.engine = ENGINE_A_TREND_PULLBACK;
               else if(StringFind(comment, "ENG_B") >= 0) m_pos.engine = ENGINE_B_BREAKOUT;
               else if(StringFind(comment, "ENG_C") >= 0) m_pos.engine = ENGINE_C_MEAN_REVERSION;
               else m_pos.engine = ENGINE_A_TREND_PULLBACK;

               return;
            }
         }
      }
      ResetPositionTrack();
   }

   void OnM5BarClose(void)
   {
      if(m_pos.active)
      {
         m_pos.bars_held_m5++;
      }
   }

   // Refresh closed trades stats & attribution from MT5 history (§10 & §11)
   void UpdateHistoryStatistics(void)
   {
      HistorySelect(0, TimeCurrent());
      int total_deals = HistoryDealsTotal();

      ResetStatistics();

      for(int i = 0; i < total_deals; i++)
      {
         ulong deal_ticket = HistoryDealGetTicket(i);
         if(deal_ticket == 0) continue;

         long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
         if(magic != (long)m_magic) continue;

         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
         {
            double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) +
                            HistoryDealGetDouble(deal_ticket, DEAL_SWAP) +
                            HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);

            string comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);
            ENUM_ENGINE_TYPE engine = ENGINE_A_TREND_PULLBACK;
            if(StringFind(comment, "ENG_B") >= 0) engine = ENGINE_B_BREAKOUT;
            else if(StringFind(comment, "ENG_C") >= 0) engine = ENGINE_C_MEAN_REVERSION;

            // Global stats
            m_stats.total_trades++;
            m_stats.net_profit += profit;

            if(profit > 0.0)
            {
               m_stats.wins++;
               m_stats.gross_profit += profit;
            }
            else
            {
               m_stats.losses++;
               m_stats.gross_loss += MathAbs(profit);
            }

            // Engine attribution
            if(engine == ENGINE_A_TREND_PULLBACK)
            {
               m_stats_engine_a.total_trades++;
               m_stats_engine_a.net_profit += profit;
               if(profit > 0.0) { m_stats_engine_a.wins++; m_stats_engine_a.gross_profit += profit; }
               else { m_stats_engine_a.losses++; m_stats_engine_a.gross_loss += MathAbs(profit); }
            }
            else if(engine == ENGINE_B_BREAKOUT)
            {
               m_stats_engine_b.total_trades++;
               m_stats_engine_b.net_profit += profit;
               if(profit > 0.0) { m_stats_engine_b.wins++; m_stats_engine_b.gross_profit += profit; }
               else { m_stats_engine_b.losses++; m_stats_engine_b.gross_loss += MathAbs(profit); }
            }
            else if(engine == ENGINE_C_MEAN_REVERSION)
            {
               m_stats_engine_c.total_trades++;
               m_stats_engine_c.net_profit += profit;
               if(profit > 0.0) { m_stats_engine_c.wins++; m_stats_engine_c.gross_profit += profit; }
               else { m_stats_engine_c.losses++; m_stats_engine_c.gross_loss += MathAbs(profit); }
            }
         }
      }

      // Compute derived metrics
      if(m_stats.total_trades > 0)
         m_stats.win_rate = ((double)m_stats.wins / (double)m_stats.total_trades) * 100.0;
      if(m_stats.gross_loss > 0.0)
         m_stats.profit_factor = m_stats.gross_profit / m_stats.gross_loss;
      else
         m_stats.profit_factor = (m_stats.gross_profit > 0.0) ? 99.9 : 0.0;

      m_stats.avg_win  = (m_stats.wins > 0) ? (m_stats.gross_profit / m_stats.wins) : 0.0;
      m_stats.avg_loss = (m_stats.losses > 0) ? (m_stats.gross_loss / m_stats.losses) : 0.0;

      if(m_stats_engine_a.total_trades > 0)
         m_stats_engine_a.win_rate = ((double)m_stats_engine_a.wins / (double)m_stats_engine_a.total_trades) * 100.0;
      if(m_stats_engine_b.total_trades > 0)
         m_stats_engine_b.win_rate = ((double)m_stats_engine_b.wins / (double)m_stats_engine_b.total_trades) * 100.0;
      if(m_stats_engine_c.total_trades > 0)
         m_stats_engine_c.win_rate = ((double)m_stats_engine_c.wins / (double)m_stats_engine_c.total_trades) * 100.0;
   }

   //+------------------------------------------------------------------+
   //| Close All Positions & Cancel Pending Orders (Button Action §5)   |
   //+------------------------------------------------------------------+
   bool CloseAllNow(string &status_report)
   {
      int closed_buy = 0;
      int closed_sell = 0;
      int cancelled_pending = 0;

      // Close positions
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0)
         {
            if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
               PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
            {
               ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               if(m_trade.PositionClose(ticket))
               {
                  if(type == POSITION_TYPE_BUY) closed_buy++;
                  else closed_sell++;
               }
            }
         }
      }

      // Cancel pending orders
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket > 0)
         {
            if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
               OrderGetInteger(ORDER_MAGIC) == (long)m_magic)
            {
               if(m_trade.OrderDelete(ticket))
                  cancelled_pending++;
            }
         }
      }

      ResetPositionTrack();
      UpdateHistoryStatistics();

      status_report = StringFormat("BUY closed: %d  |  SELL closed: %d  |  Pending cancelled: %d  |  POSITIONS: 0",
                                   closed_buy, closed_sell, cancelled_pending);
      if(m_logger != NULL)
         m_logger.LogEvent("CLOSE_ALL", status_report);

      return true;
   }

   //+------------------------------------------------------------------+
   //| Dynamic Tick Management (§11)                                    |
   //+------------------------------------------------------------------+
   void OnTickManage(const SRegimeState &regime, double spread_pts, double current_dd_pct)
   {
      if(!m_pos.active) return;

      // Verify position still exists
      if(!PositionSelectByTicket(m_pos.ticket))
      {
         UpdateHistoryStatistics();
         if(m_logger != NULL)
            m_logger.LogEvent("POSITION_CLOSED", StringFormat("Ticket #%I64u closed. Total trades: %d, Net PnL: $%.2f",
                              m_pos.ticket, m_stats.total_trades, m_stats.net_profit));
         ResetPositionTrack();
         return;
      }

      // 1. Emergency Exits
      if(regime.active_regime == REGIME_CHAOS)
      {
         if(m_logger != NULL)
            m_logger.LogEvent("EMERGENCY_EXIT", "Regime flipped to CHAOS! Emergency flattening.");
         m_trade.PositionClose(m_pos.ticket);
         ResetPositionTrack();
         UpdateHistoryStatistics();
         return;
      }

      if(spread_pts > (2.0 * m_spread_chaos_abs_pts))
      {
         if(m_logger != NULL)
            m_logger.LogEvent("EMERGENCY_EXIT", StringFormat("Spread %.1f pts > 2*chaos threshold! Flattening.", spread_pts));
         m_trade.PositionClose(m_pos.ticket);
         ResetPositionTrack();
         UpdateHistoryStatistics();
         return;
      }

      // In production mode only, daily DD breaches force close
      if(!m_research_mode && current_dd_pct >= m_daily_dd_pct)
      {
         if(m_logger != NULL)
            m_logger.LogEvent("EMERGENCY_EXIT", "Daily DD limit breached in production mode! Flattening.");
         m_trade.PositionClose(m_pos.ticket);
         ResetPositionTrack();
         UpdateHistoryStatistics();
         return;
      }

      // 2. Engine C Time Stop Check (§7)
      double current_bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double current_ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double point       = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      double current_profit_price = 0.0;
      if(m_pos.direction == DIR_LONG)
         current_profit_price = current_bid - m_pos.entry_price;
      else
         current_profit_price = m_pos.entry_price - current_ask;

      double r_mult = (m_pos.r_points > 0.0) ? (current_profit_price / m_pos.r_points) : 0.0;

      if(m_pos.engine == ENGINE_C_MEAN_REVERSION && m_pos.bars_held_m5 >= 10 && r_mult < 1.0)
      {
         if(m_logger != NULL)
            m_logger.LogEvent("TIME_STOP", StringFormat("Engine C time stop: 10 bars elapsed (%.2fR). Closing at market.", r_mult));
         m_trade.PositionClose(m_pos.ticket);
         ResetPositionTrack();
         UpdateHistoryStatistics();
         return;
      }

      // 3. Stage 1: +0.5R Breakeven
      if(m_pos.engine != ENGINE_B_BREAKOUT && m_pos.stage < STAGE_1_BREAKEVEN)
      {
         if(r_mult >= 0.5)
         {
            double spread_offset = spread_pts * point;
            double be_sl = (m_pos.direction == DIR_LONG) ?
                           (m_pos.entry_price + spread_offset) :
                           (m_pos.entry_price - spread_offset);

            if(m_trade.PositionModify(m_pos.ticket, be_sl, 0.0))
            {
               m_pos.current_sl = be_sl;
               m_pos.stage      = STAGE_1_BREAKEVEN;
               if(m_logger != NULL)
                  m_logger.LogEvent("STAGE_1_BE", StringFormat("Ticket #%I64u reached +0.5R -> SL to BE (%.2f)", m_pos.ticket, be_sl));
            }
         }
      }

      // 4. Stage 2: +1.0R Partial Close (50%) or Lock-in
      if(m_pos.stage < STAGE_2_PARTIAL_CLOSE)
      {
         if(r_mult >= 1.0)
         {
            if(m_pos.indivisible)
            {
               if(m_pos.engine == ENGINE_C_MEAN_REVERSION)
               {
                  if(m_logger != NULL)
                     m_logger.LogEvent("STAGE_2_EXIT", "Engine C reached +1.0R. Closing 100% at market.");
                  m_trade.PositionClose(m_pos.ticket);
                  ResetPositionTrack();
                  UpdateHistoryStatistics();
                  return;
               }
               else
               {
                  double lock_sl = (m_pos.direction == DIR_LONG) ?
                                   (m_pos.entry_price + 0.75 * m_pos.r_points) :
                                   (m_pos.entry_price - 0.75 * m_pos.r_points);
                  if(m_trade.PositionModify(m_pos.ticket, lock_sl, 0.0))
                  {
                     m_pos.current_sl = lock_sl;
                     m_pos.stage      = STAGE_2_PARTIAL_CLOSE;
                     if(m_logger != NULL)
                        m_logger.LogEvent("STAGE_2_LOCK", StringFormat("Ticket #%I64u indivisible: SL locked +0.75R (%.2f)", m_pos.ticket, lock_sl));
                  }
               }
            }
            else
            {
               double lot_step  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
               double close_vol = MathFloor((m_pos.current_lots * 0.5) / lot_step) * lot_step;
               close_vol        = NormalizeDouble(close_vol, 2);

               if(close_vol > 0.0 && m_trade.PositionClosePartial(m_pos.ticket, close_vol))
               {
                  m_pos.current_lots -= close_vol;
                  m_pos.stage         = STAGE_2_PARTIAL_CLOSE;
                  if(m_logger != NULL)
                     m_logger.LogEvent("STAGE_2_PARTIAL", StringFormat("Ticket #%I64u closed 50%% (%.2f lots) at +1.0R", m_pos.ticket, close_vol));
               }

               if(m_pos.engine == ENGINE_C_MEAN_REVERSION)
               {
                  m_trade.PositionClose(m_pos.ticket);
                  ResetPositionTrack();
                  UpdateHistoryStatistics();
                  return;
               }
            }
         }
      }

      // 5. Stage 3: +1.5R ATR Trailing Stop (Ratcheting)
      if(m_pos.engine != ENGINE_C_MEAN_REVERSION && r_mult >= 1.5)
      {
         m_pos.stage = STAGE_3_ATR_TRAIL;
         double atr_m5 = regime.atr_m5;
         if(atr_m5 > 0.0)
         {
            if(m_pos.direction == DIR_LONG)
            {
               double ratcheted_sl = current_bid - 1.2 * atr_m5;
               if(ratcheted_sl > (m_pos.current_sl + point * 10))
               {
                  if(m_trade.PositionModify(m_pos.ticket, ratcheted_sl, 0.0))
                  {
                     m_pos.current_sl = ratcheted_sl;
                     if(m_logger != NULL)
                        m_logger.LogEvent("STAGE_3_TRAIL", StringFormat("Ticket #%I64u Trailing SL -> %.2f (%.2fR)", m_pos.ticket, ratcheted_sl, r_mult));
                  }
               }
            }
            else
            {
               double ratcheted_sl = current_ask + 1.2 * atr_m5;
               if(ratcheted_sl < (m_pos.current_sl - point * 10))
               {
                  if(m_trade.PositionModify(m_pos.ticket, ratcheted_sl, 0.0))
                  {
                     m_pos.current_sl = ratcheted_sl;
                     if(m_logger != NULL)
                        m_logger.LogEvent("STAGE_3_TRAIL", StringFormat("Ticket #%I64u Trailing SL -> %.2f (%.2fR)", m_pos.ticket, ratcheted_sl, r_mult));
                  }
               }
            }
         }
      }
   }
};
