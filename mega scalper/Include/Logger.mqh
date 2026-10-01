//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|                             XAU-MEGA-SCALPER Formal Spec v1.0    |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"

class CLogger
{
private:
   int      m_file_handle;
   string   m_current_day_str;
   bool     m_enabled;

   string GetDateString(datetime dt)
   {
      MqlDateTime mdt;
      TimeToStruct(dt, mdt);
      return StringFormat("%04d%02d%02d", mdt.year, mdt.mon, mdt.day);
   }

   void EnsureDayFile(datetime server_time)
   {
      string day_str = GetDateString(server_time);
      if(day_str != m_current_day_str || m_file_handle == INVALID_HANDLE)
      {
         if(m_file_handle != INVALID_HANDLE)
         {
            FileClose(m_file_handle);
            m_file_handle = INVALID_HANDLE;
         }
         
         m_current_day_str = day_str;
         string filename = StringFormat("XAU_MEGA_%s.csv", m_current_day_str);
         
         // Check if file exists to write header
         bool file_exists = FileIsExist(filename, FILE_COMMON | FILE_READ);
         
         m_file_handle = FileOpen(filename, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
         if(m_file_handle != INVALID_HANDLE)
         {
            FileSeek(m_file_handle, 0, SEEK_END);
            if(FileSize(m_file_handle) == 0)
            {
               // Write standard CSV header
               FileWrite(m_file_handle,
                  "Timestamp",
                  "Regime_Active",
                  "Regime_Raw",
                  "Persist",
                  "Dwell_OK",
                  "G1_Warmup",
                  "G2_Session",
                  "G3_Spread",
                  "Spread_ATR_Ratio",
                  "G4_News",
                  "G5_Regime",
                  "G6_Risk",
                  "Daily_DD_Pct",
                  "Consec_Loss",
                  "Open_Positions",
                  "G7_Exec",
                  "Engine_Evaluated",
                  "Signal_Direction",
                  "Sub_Type",
                  "Pass_Details",
                  "Rejection_Code",
                  "Rejection_Details",
                  "Final_Decision"
               );
               FileFlush(m_file_handle);
            }
         }
         else
         {
            PrintFormat("[LOGGER ERROR] Unable to open CSV file %s! Error: %d", filename, GetLastError());
         }
      }
   }

public:
   CLogger(void) : m_file_handle(INVALID_HANDLE), m_current_day_str(""), m_enabled(true) {}
   
   ~CLogger(void)
   {
      Close();
   }

   void Close(void)
   {
      if(m_file_handle != INVALID_HANDLE)
      {
         FileClose(m_file_handle);
         m_file_handle = INVALID_HANDLE;
      }
   }

   void SetEnabled(bool enabled) { m_enabled = enabled; }

   //+------------------------------------------------------------------+
   //| Write one row per M5 close matching Section 12 Specification     |
   //+------------------------------------------------------------------+
   void LogBarEvaluation(datetime bar_time,
                         const SRegimeState &regime,
                         const SGateResults &gates,
                         const SSignalResult &signal,
                         string final_decision)
   {
      if(!m_enabled) return;

      EnsureDayFile(bar_time);

      string t_str = TimeToString(bar_time, TIME_DATE | TIME_MINUTES);
      
      // 1. Write structured row to CSV
      if(m_file_handle != INVALID_HANDLE)
      {
         FileWrite(m_file_handle,
            t_str,
            RegimeToString(regime.active_regime),
            RegimeToString(regime.raw_regime),
            IntegerToString(regime.persist_count),
            regime.dwell_ok ? "1" : "0",
            gates.g1_warmup ? "PASS" : "FAIL",
            gates.g2_session ? "PASS" : "FAIL",
            gates.g3_spread ? "PASS" : "FAIL",
            DoubleToString(gates.spread_atr_ratio, 4),
            gates.g4_news ? "PASS" : "FAIL",
            gates.g5_regime ? "PASS" : "FAIL",
            gates.g6_risk ? "PASS" : "FAIL",
            DoubleToString(gates.daily_dd_pct, 4),
            IntegerToString(gates.consec_losses),
            IntegerToString(gates.open_positions),
            gates.g7_execution ? "PASS" : "FAIL",
            EngineToString(signal.engine),
            DirectionToString(signal.direction),
            signal.sub_type,
            signal.pass_details,
            signal.fail_code,
            signal.fail_details,
            final_decision
         );
         FileFlush(m_file_handle);
      }

      // 2. Also format exact log string for MT5 Experts console as requested in §12
      string log_msg = StringFormat(
         "T=%s  REGIME=%s  PERSIST=%d  DWELL_OK=%d\n"
         "  G1 WARMUP    %s\n"
         "  G2 SESSION   %s\n"
         "  G3 SPREAD    %s  %.2f ATR\n"
         "  G4 NEWS      %s\n"
         "  G5 REGIME    %s\n"
         "  G6 RISK      %s  dd=%.2f%%  consec=%d\n"
         "  G7 EXEC      %s\n"
         "  %s  %s  %s\n"
         "    Details: %s\n"
         "  -> %s  reason=%s (%s)",
         t_str,
         RegimeToString(regime.active_regime),
         regime.persist_count,
         regime.dwell_ok ? 1 : 0,
         gates.g1_warmup ? "PASS" : "FAIL",
         gates.g2_session ? "PASS" : "FAIL",
         gates.g3_spread ? "PASS" : "FAIL", gates.spread_atr_ratio,
         gates.g4_news ? "PASS" : "FAIL",
         gates.g5_regime ? "PASS" : "FAIL",
         gates.g6_risk ? "PASS" : "FAIL", gates.daily_dd_pct * 100.0, gates.consec_losses,
         gates.g7_execution ? "PASS" : "FAIL",
         EngineToString(signal.engine),
         signal.valid ? "SIGNAL" : "EVAL",
         DirectionToString(signal.direction),
         signal.valid ? signal.pass_details : (signal.fail_details != "" ? signal.fail_details : "none"),
         final_decision,
         signal.valid ? "VALID_SETUP" : (signal.fail_code != "" ? signal.fail_code : gates.fail_reason),
         gates.fail_reason != "" ? gates.fail_reason : signal.fail_details
      );

      Print(log_msg);
   }

   //+------------------------------------------------------------------+
   //| Log Execution & Order Events                                     |
   //+------------------------------------------------------------------+
   void LogEvent(string category, string message)
   {
      string t_str = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
      PrintFormat("[%s] [%s] %s", t_str, category, message);
   }
};
