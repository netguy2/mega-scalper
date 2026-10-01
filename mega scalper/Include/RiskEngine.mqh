//+------------------------------------------------------------------+
//|                                                   RiskEngine.mqh |
//|                             XAU-MEGA-SCALPER Formal Spec v1.0    |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"

class CRiskEngine
{
private:
   string   m_symbol;
   
   // Budgeted Parameters (§1)
   double   m_risk_per_trade_pct;
   double   m_atr_sl_mult;
   double   m_daily_dd_pct;
   int      m_consec_loss_limit;
   int      m_cooldown_bars;
   int      m_max_positions;

public:
   CRiskEngine(void) : m_symbol(SYMBOL_XAUUSD),
                       m_risk_per_trade_pct(0.01),
                       m_atr_sl_mult(1.5),
                       m_daily_dd_pct(0.03),
                       m_consec_loss_limit(3),
                       m_cooldown_bars(6),
                       m_max_positions(1)
   {
   }

   void Init(string symbol,
             double risk_per_trade_pct,
             double atr_sl_mult,
             double daily_dd_pct,
             int consec_loss_limit,
             int cooldown_bars,
             int max_positions)
   {
      m_symbol             = symbol;
      m_risk_per_trade_pct = risk_per_trade_pct;
      m_atr_sl_mult        = atr_sl_mult;
      m_daily_dd_pct       = daily_dd_pct;
      m_consec_loss_limit  = consec_loss_limit;
      m_cooldown_bars      = cooldown_bars;
      m_max_positions      = max_positions;
   }

   //+------------------------------------------------------------------+
   //| Calculate Lot Size and Spread-Adjusted SL (§9, Trap B)           |
   //+------------------------------------------------------------------+
   bool CalculatePositionSize(ENUM_ENGINE_TYPE engine,
                              ENUM_TRADE_DIRECTION dir,
                              double entry_price,
                              double &sl_price,
                              double spread_pts,
                              double atr_m5,
                              double &lots,
                              bool &is_indivisible,
                              string &log_details,
                              double risk_mult = 1.0)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
      {
         log_details = "Account equity non-positive";
         return false;
      }

      // Structural risk allocation: Engine C gets 0.75 of standard risk (§7)
      double risk_pct = m_risk_per_trade_pct;
      if(engine == ENGINE_C_MEAN_REVERSION)
         risk_pct *= 0.75;

      // Confluence grade scales risk down for weaker setups (never above 1.5x)
      double rm = (risk_mult > 0.0) ? MathMin(risk_mult, 1.5) : 1.0;
      risk_pct *= rm;

      double risk_amount = equity * risk_pct;

      double sl_distance = MathAbs(entry_price - sl_price);
      if(sl_distance <= 0.0)
      {
         sl_distance = m_atr_sl_mult * atr_m5;
         sl_price    = (dir == DIR_LONG) ? (entry_price - sl_distance) : (entry_price + sl_distance);
      }

      // Spread-adjusted SL (§9):
      // If spread_now > 0.5 * atr_sl_mult * ATR_M5, widen SL by spread and reduce lot
      double spread_price = spread_pts * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(spread_price > (0.5 * m_atr_sl_mult * atr_m5))
      {
         sl_distance += spread_price;
         if(dir == DIR_LONG)
            sl_price = entry_price - sl_distance;
         else
            sl_price = entry_price + sl_distance;
      }

      // MT5 Tick and Point mechanics
      double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double lot_step   = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      double min_lot    = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double max_lot    = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);

      if(tick_size <= 0.0 || tick_value <= 0.0 || lot_step <= 0.0)
      {
         log_details = "Broker symbol specs invalid";
         return false;
      }

      double point_value = (tick_value / tick_size) * point;
      double sl_points   = sl_distance / point;
      double loss_per_lot = sl_points * point_value;

      if(loss_per_lot <= 0.0)
      {
         log_details = "Loss per lot calculation non-positive";
         return false;
      }

      double raw_lots = risk_amount / loss_per_lot;
      
      // Step normalization
      double stepped_lots = MathFloor(raw_lots / lot_step) * lot_step;
      if(stepped_lots < min_lot) stepped_lots = min_lot;
      if(stepped_lots > max_lot) stepped_lots = max_lot;

      lots = NormalizeDouble(stepped_lots, 2);

      // Trap B resolution: If lots < 2 * lot_step, position is indivisible (cannot partial close)
      is_indivisible = (lots < (2.0 * lot_step));

      log_details = StringFormat("Equity=%.2f, Risk=%.2f (%.2f%%), SL_Dist=%.2f pts, Lots=%.2f, Indivisible=%s",
                                 equity, risk_amount, risk_pct * 100.0, sl_points, lots, is_indivisible ? "YES" : "NO");
      return true;
   }
};
