//+------------------------------------------------------------------+
//|                                     ExecutionStateMachine.mqh    |
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
#include "Gates.mqh"
#include "RiskEngine.mqh"
#include "TradeManager.mqh"

class CExecutionStateMachine
{
private:
   string               m_symbol;
   ulong                m_magic;
   CTrade               m_trade;
   CLogger             *m_logger;
   CRiskEngine         *m_risk;
   CGates              *m_gates;
   CTradeManager       *m_trade_mgr;

   ENUM_EXEC_STATE      m_state;
   ENUM_EA_RUN_STATE    m_run_state; // STOPPED, STARTING, RUNNING (§3 & §4)
   SSignalResult        m_pending_signal;
   int                  m_rejection_count_session;
   bool                 m_session_disabled;

   // Latency measurement
   ulong                m_order_send_time_us;

   // Stop order tracking
   ulong                m_active_stop_ticket;
   datetime             m_stop_placed_time;
   int                  m_stop_bars_alive;

public:
   CExecutionStateMachine(void) : m_symbol(SYMBOL_XAUUSD),
                                  m_magic(202601),
                                  m_logger(NULL),
                                  m_risk(NULL),
                                  m_gates(NULL),
                                  m_trade_mgr(NULL),
                                  m_state(STATE_IDLE),
                                  m_run_state(EA_STATE_RUNNING), // Default running for tests
                                  m_rejection_count_session(0),
                                  m_session_disabled(false),
                                  m_order_send_time_us(0),
                                  m_active_stop_ticket(0),
                                  m_stop_placed_time(0),
                                  m_stop_bars_alive(0)
   {
   }

   void Init(string symbol,
             ulong magic,
             CLogger *logger,
             CRiskEngine *risk,
             CGates *gates,
             CTradeManager *trade_mgr)
   {
      m_symbol                 = symbol;
      m_magic                  = magic;
      m_logger                 = logger;
      m_risk                   = risk;
      m_gates                  = gates;
      m_trade_mgr              = trade_mgr;
      m_state                  = STATE_IDLE;
      m_run_state              = EA_STATE_RUNNING;
      m_active_stop_ticket     = 0;
      m_rejection_count_session = 0;
      m_session_disabled       = false;

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(30);
      uint filling = (uint)SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_FOK) != 0)
         m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((filling & SYMBOL_FILLING_IOC) != 0)
         m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else
         m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }

   ENUM_EXEC_STATE   GetState(void) const { return m_state; }
   ENUM_EA_RUN_STATE GetRunState(void) const { return m_run_state; }

   void SetRunState(ENUM_EA_RUN_STATE state)
   {
      m_run_state = state;
      if(m_logger != NULL)
      {
         string s = (state == EA_STATE_RUNNING) ? "RUNNING" :
                    ((state == EA_STATE_STARTING) ? "STARTING" : "STOPPED");
         m_logger.LogEvent("UI_COMMAND", StringFormat("EA Run State changed to: %s", s));
      }
   }

   void ResetSessionRejections(void)
   {
      m_rejection_count_session = 0;
      m_session_disabled = false;
   }

   void OnM5BarClose(void)
   {
      if(m_active_stop_ticket > 0)
      {
         m_stop_bars_alive++;
         if(m_stop_bars_alive >= 2)
         {
            if(m_logger != NULL)
               m_logger.LogEvent("STOP_EXPIRED", StringFormat("Pending Stop order #%I64u cancelled after 2 M5 bars.", m_active_stop_ticket));
            m_trade.OrderDelete(m_active_stop_ticket);
            m_active_stop_ticket = 0;
            m_state = STATE_IDLE;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Submit Signal into State Machine                                 |
   //+------------------------------------------------------------------+
   bool DispatchSignal(const SSignalResult &signal)
   {
      // Check manual STOP state (§4): Stop opening new trades, keep managing active
      if(m_run_state != EA_STATE_RUNNING)
      {
         if(m_logger != NULL)
            m_logger.LogEvent("DISPATCH_SKIPPED", "EA is currently STOPPED by user. No new entries allowed.");
         return false;
      }

      if(m_session_disabled)
      {
         if(m_logger != NULL)
            m_logger.LogEvent("DISPATCH_FAIL", "Trading disabled for session (rejections >= 3)");
         return false;
      }

      if(m_trade_mgr.HasActivePosition() || m_active_stop_ticket > 0)
      {
         if(m_logger != NULL)
            m_logger.LogEvent("DISPATCH_FAIL", "Global max positions (1) already open");
         return false;
      }

      m_pending_signal = signal;
      m_state          = STATE_PRE_TRADE_CHECK;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Process Execution on tick                                        |
   //+------------------------------------------------------------------+
   void ProcessTickExecution(const SRegimeState &regime, double spread_pts, double point_val)
   {
      if(m_active_stop_ticket > 0)
      {
         if(!OrderSelect(m_active_stop_ticket))
         {
            m_trade_mgr.SyncOpenPosition();
            if(m_trade_mgr.HasActivePosition())
            {
               if(m_logger != NULL)
                  m_logger.LogEvent("STOP_FILLED", StringFormat("Stop order #%I64u filled!", m_active_stop_ticket));
               m_active_stop_ticket = 0;
               m_state = STATE_MANAGED;
            }
            else
            {
               m_active_stop_ticket = 0;
               m_state = STATE_IDLE;
            }
         }
         return;
      }

      if(m_state == STATE_PRE_TRADE_CHECK)
      {
         // In STOPPED state, abort new entries
         if(m_run_state != EA_STATE_RUNNING)
         {
            m_state = STATE_IDLE;
            return;
         }

         SGateResults tick_gate;
         if(!m_gates.EvaluateG3(spread_pts, regime.atr_m5, point_val, tick_gate))
         {
            if(m_logger != NULL)
               m_logger.LogEvent("PRE_CHECK_FAIL", StringFormat("G3 spread failed: %s", tick_gate.fail_reason));
            m_state = STATE_IDLE;
            return;
         }

         if(!m_gates.EvaluateG6(tick_gate))
         {
            if(m_logger != NULL)
               m_logger.LogEvent("PRE_CHECK_FAIL", StringFormat("G6 risk failed: %s", tick_gate.fail_reason));
            m_state = STATE_IDLE;
            return;
         }

         string fail_reason = "";

         if(!m_gates.EvaluateG7(fail_reason))
         {
            if(m_logger != NULL)
               m_logger.LogEvent("PRE_CHECK_FAIL", StringFormat("G7 execution failed: %s", fail_reason));
            m_state = STATE_IDLE;
            return;
         }

         double lots = 0.0;
         bool is_indivisible = false;
         string size_log = "";
         double entry_ref = (m_pending_signal.direction == DIR_LONG) ?
                            SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                            SymbolInfoDouble(m_symbol, SYMBOL_BID);

         if(m_pending_signal.is_stop_order)
            entry_ref = m_pending_signal.stop_entry_price;

         if(!m_risk.CalculatePositionSize(m_pending_signal.engine,
                                          m_pending_signal.direction,
                                          entry_ref,
                                          m_pending_signal.sl_price,
                                          spread_pts,
                                          regime.atr_m5,
                                          lots,
                                          is_indivisible,
                                          size_log))
         {
            if(m_logger != NULL)
               m_logger.LogEvent("SIZING_FAIL", size_log);
            m_state = STATE_IDLE;
            return;
         }

         m_state = STATE_ORDER_SENT;
         m_order_send_time_us = GetMicrosecondCount();

         string comment = StringFormat("ENG_%c_%s",
                                       (m_pending_signal.engine == ENGINE_A_TREND_PULLBACK) ? 'A' :
                                       ((m_pending_signal.engine == ENGINE_B_BREAKOUT) ? 'B' : 'C'),
                                       m_pending_signal.sub_type);

         if(m_pending_signal.is_stop_order)
         {
            ENUM_ORDER_TYPE order_type = (m_pending_signal.direction == DIR_LONG) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
            double stop_price = m_pending_signal.stop_entry_price;
            double sl_price   = m_pending_signal.sl_price;

            ResetLastError();
            bool sent = m_trade.OrderOpen(m_symbol, order_type, lots, 0.0, stop_price, sl_price, 0.0,
                                          ORDER_TIME_GTC, 0, comment);

            if(sent)
            {
               m_active_stop_ticket = m_trade.ResultOrder();
               m_stop_placed_time   = TimeCurrent();
               m_stop_bars_alive    = 0;
               if(m_logger != NULL)
                  m_logger.LogEvent("STOP_PLACED", StringFormat("Stop #%I64u placed @ %.2f, SL=%.2f, Lots=%.2f",
                                    m_active_stop_ticket, stop_price, sl_price, lots));
            }
            else
            {
               HandleRejection(m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
            }
         }
         else
         {
            bool sent = false;
            ResetLastError();

            if(m_pending_signal.direction == DIR_LONG)
            {
               double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
               sent = m_trade.Buy(lots, m_symbol, ask, m_pending_signal.sl_price, 0.0, comment);
            }
            else
            {
               double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
               sent = m_trade.Sell(lots, m_symbol, bid, m_pending_signal.sl_price, 0.0, comment);
            }

            if(sent)
            {
               ulong ticket = m_trade.ResultOrder();
               m_state = STATE_FILLED;

               // Compute execution latency (§10)
               ulong elapsed_us = GetMicrosecondCount() - m_order_send_time_us;
               long latency_ms = (long)(elapsed_us / 1000);
               m_trade_mgr.RegisterExecutionLatency(latency_ms);

               if(!VerifyProtected(ticket, m_pending_signal.sl_price))
               {
                  if(m_logger != NULL)
                     m_logger.LogEvent("PROTECT_FAIL", "SL unattached! Flattening.");
                  m_trade.PositionClose(ticket);
                  m_state = STATE_IDLE;
                  return;
               }

               m_state = STATE_PROTECTED;
               m_trade_mgr.RegisterNewPosition(ticket,
                                               m_pending_signal.engine,
                                               m_pending_signal.direction,
                                               m_trade.ResultPrice(),
                                               m_pending_signal.sl_price,
                                               lots,
                                               is_indivisible);
               m_state = STATE_MANAGED;
            }
            else
            {
               HandleRejection(m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
            }
         }
      }
   }

   bool VerifyProtected(ulong ticket, double intended_sl)
   {
      for(int i = 0; i < 20; i++)
      {
         if(PositionSelectByTicket(ticket))
         {
            double pos_sl = PositionGetDouble(POSITION_SL);
            if(pos_sl > 0.0) return true;
         }
         Sleep(100);
      }
      return false;
   }

   void HandleRejection(uint retcode, string desc)
   {
      m_rejection_count_session++;
      m_trade_mgr.RegisterRejection();
      if(m_logger != NULL)
         m_logger.LogEvent("ORDER_REJECTED", StringFormat("Order rejected: %d (%s). Session rejections: %d",
                           retcode, desc, m_rejection_count_session));

      if(m_rejection_count_session >= 3)
      {
         m_session_disabled = true;
         if(m_logger != NULL)
            m_logger.LogEvent("SESSION_DISABLED", ">=3 rejections reached. Disabling session.");
      }

      m_state = STATE_IDLE;
   }
};
