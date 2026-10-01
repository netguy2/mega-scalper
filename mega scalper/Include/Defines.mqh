//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|                             XAU-MEGA-SCALPER Formal Spec v0.2    |
//|                             DEBUG & CONTINUOUS RESEARCH EDITION  |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

//--- Market & Order Constants
#define SYMBOL_XAUUSD "XAUUSD"

//--- Regime Classification (§4)
enum ENUM_REGIME
{
   REGIME_NONE       = 0,
   REGIME_CHAOS      = 1,
   REGIME_EXPANSION  = 2,
   REGIME_TREND_UP   = 3,
   REGIME_TREND_DN   = 4,
   REGIME_RANGE      = 5
};

//--- Engine Identity
enum ENUM_ENGINE_TYPE
{
   ENGINE_NONE              = 0,
   ENGINE_A_TREND_PULLBACK  = 1,
   ENGINE_B_BREAKOUT        = 2,
   ENGINE_C_MEAN_REVERSION  = 3
};

//--- Signal Direction
enum ENUM_TRADE_DIRECTION
{
   DIR_NONE  = 0,
   DIR_LONG  = 1,
   DIR_SHORT = -1
};

//--- Execution State Machine (§10)
enum ENUM_EXEC_STATE
{
   STATE_IDLE              = 0,
   STATE_PRE_TRADE_CHECK   = 1,
   STATE_ORDER_SENT        = 2,
   STATE_FILLED            = 3,
   STATE_REJECTED          = 4,
   STATE_PARTIAL           = 5,
   STATE_PROTECTED         = 6,
   STATE_MANAGED           = 7,
   STATE_EXIT_REQUEST      = 8,
   STATE_CLOSED            = 9
};

//--- Trade Management Stages (§11)
enum ENUM_TRADE_STAGE
{
   STAGE_INITIAL           = 0,
   STAGE_1_BREAKEVEN       = 1, // +0.5R
   STAGE_2_PARTIAL_CLOSE   = 2, // +1.0R (close 50% or lock-in)
   STAGE_3_ATR_TRAIL       = 3  // +1.5R (ratchet 1.2 ATR)
};

//--- UI Operational Control States
enum ENUM_EA_RUN_STATE
{
   EA_STATE_STOPPED  = 0,
   EA_STATE_STARTING = 1,
   EA_STATE_RUNNING  = 2
};

//--- Bar Structure
struct SBar
{
   datetime time;
   double   open;
   double   high;
   double   low;
   double   close;
   long     tick_volume;
   int      spread;
};

//--- Gate Check Status & Explicit Telemetry (§3)
struct SGateResults
{
   bool   all_passed;
   bool   g1_warmup;
   bool   g2_session;
   bool   g3_spread;
   bool   g4_news;
   bool   g5_regime;
   bool   g6_risk;
   bool   g7_execution;
   string fail_gate;
   string fail_reason;
   
   // Raw metrics vs limits for debugging (§4)
   int    m15_bars_have;
   int    m15_bars_req;
   int    m5_bars_have;
   int    m5_bars_req;
   int    m1_bars_have;
   int    m1_bars_req;
   int    vwap_bars_have;
   int    vwap_bars_req;

   double spread_pts;
   double spread_price;
   double spread_atr_ratio;
   double spread_limit_ratio;
   
   double daily_dd_pct;
   int    consec_losses;
   int    open_positions;
   int    max_positions;
};

//--- Regime State Tracking with Full Debug Telemetry (§1, §2, §3, §6)
struct SRegimeState
{
   ENUM_REGIME raw_regime;
   ENUM_REGIME active_regime;
   ENUM_REGIME candidate_regime;
   
   int         persist_count;
   int         persist_required;
   int         dwell_count;
   int         dwell_required;
   bool        dwell_ok;
   
   // Chaos Breakdown Sub-checks (§3)
   bool        chaos_spread_mult_fail;
   double      chaos_spread_mult_val;
   double      chaos_spread_mult_limit;
   
   bool        chaos_spread_abs_fail;
   double      chaos_spread_abs_val;
   double      chaos_spread_abs_limit;
   
   bool        chaos_atr_p99_fail;
   double      chaos_atr_p99_val;
   double      chaos_atr_p99_limit;
   
   string      primary_chaos_reason;
   
   // Indicators & Baselines
   double      atr_m15;
   double      atr_m5;
   double      atr_pct;
   double      atr_pct_p99;
   double      atr_ratio;
   double      spread_avg;
   double      session_vwap;
   double      vwap_slope;
   double      ema9_m15;
   double      ema21_m15;
   double      ema50_m15;
   double      adx_m15;
   
   // Modular Multi-factor Trend Score Components (Sum = 100) (§1)
   int         score_ema_alignment; // max 20
   int         score_adx;           // max 20
   int         score_vwap_pos;      // max 15
   int         score_vwap_slope;    // max 15
   int         score_structure;     // max 15
   int         score_momentum;      // max 15
   int         total_trend_score;   // 0 - 100
};

//--- Dry Candidate Signal Structure (§12)
struct SDrySignal
{
   ENUM_ENGINE_TYPE     engine;
   ENUM_TRADE_DIRECTION candidate_dir;
   bool                 setup_found;
   string               status_desc;
   string               condition1_desc;
   bool                 condition1_pass;
   string               condition2_desc;
   bool                 condition2_pass;
   string               condition3_desc;
   bool                 condition3_pass;
   string               primary_rejection_reason;
};

//--- Scalp layer configuration (filled from EA inputs)
struct SScalpConfig
{
   bool     enabled;
   bool     sweep_enabled;
   bool     use_h1_bias;
   // trend-pullback mode
   int      lookback_bars;
   int      swing_bars;
   double   zone_atr;
   double   hold_atr;
   double   max_ext_atr;
   double   min_body_frac;
   double   sl_buffer_atr;
   double   min_sl_atr;
   double   atr_sl_mult;
   // context filters
   double   min_room_atr;
   double   rsi_max;
   double   min_atr_usd;
   int      min_grade_pts;
   // liquidity-sweep mode
   double   sweep_min_depth;
   double   sweep_max_depth;
   double   sweep_close_pos;
   double   sweep_disp_mult;
   double   round_step;
   // session windows (broker server hours)
   int      asian_start;
   int      asian_end;
   int      london_start;
   int      overlap_start;
   int      overlap_end;
   int      ny_end;
};

//--- Scalp Engine live state. Mode-agnostic: the engine fills six generic checklist
//    rows (3 "location" + 3 "trigger") so the panel never needs to know the mode.
struct SScalpState
{
   ENUM_TRADE_DIRECTION direction;      // trade direction under evaluation
   int      mode;                       // 0 none, 1 trend pullback, 2 liquidity sweep
   string   mode_name;
   bool     regime_ok;                  // regime is tradable by the scalp layer

   string   loc_title;
   string   trg_title;
   string   rule;                       // human description of the trigger rule
   string   ck_label[6];
   string   ck_value[6];
   bool     ck_pass[6];
   int      loc_n;                      // satisfied location rows (0-3)
   int      trg_n;                      // satisfied trigger units (0-2)
   bool     location_ok;
   bool     trigger_ok;

   // Context filters
   int      h1_bias;                    // +1 up, -1 down, 0 neutral
   bool     ctx_bias_ok;
   double   room_atr;                   // free space to the next key level, in ATR(M5)
   string   room_level;
   bool     ctx_room_ok;
   double   rsi_m1;
   bool     ctx_rsi_ok;
   double   atr_usd;
   bool     ctx_vol_ok;
   int      session_id;                 // 0 off, 1 asia, 2 london, 3 overlap, 4 ny
   string   session_name;
   bool     ctx_ok;
   string   ctx_reason;

   // Confluence grade (drives position size)
   int      grade_pts;
   string   grade;
   double   risk_mult;

   bool     entry_ready;
   double   sl_price;
   datetime eval_time;
   string   reason;                     // first missing ingredient, human readable

   void Reset(void)
   {
      direction = DIR_NONE; mode = 0; mode_name = "-"; regime_ok = false;
      loc_title = "LOCATION"; trg_title = "TRIGGER"; rule = "";
      for(int i = 0; i < 6; i++) { ck_label[i] = "-"; ck_value[i] = "--"; ck_pass[i] = false; }
      loc_n = 0; trg_n = 0; location_ok = false; trigger_ok = false;
      h1_bias = 0; ctx_bias_ok = false;
      room_atr = 0.0; room_level = ""; ctx_room_ok = false;
      rsi_m1 = 50.0; ctx_rsi_ok = false;
      atr_usd = 0.0; ctx_vol_ok = false;
      session_id = 0; session_name = "OFF";
      ctx_ok = false; ctx_reason = "";
      grade_pts = 0; grade = "-"; risk_mult = 1.0;
      entry_ready = false; sl_price = 0.0; eval_time = 0; reason = "";
   }
};

//--- Daily decision funnel: where did every scanned M1 bar die?
struct SFunnel
{
   int scanned;          // M1 bars evaluated
   int warmup_blocked;   // G1
   int session_blocked;  // G2
   int spread_blocked;   // G3
   int news_blocked;     // G4
   int regime_blocked;   // G5 (chaos / dwell)
   int risk_blocked;     // G6 (daily DD / consec losses / cooldown)
   int exec_blocked;     // G7 + dispatch refusals
   int in_trade;         // bars skipped because a position was already open
   int gates_passed;     // all gates OK
   int regime_ok;        // ...and regime tradable by the scalp layer
   int location_ok;      // ...and location / liquidity level valid
   int trigger_ok;       // ...and trigger / sweep confirmation valid
   int ctx_blocked;      // trigger valid but a context filter (bias / room / RSI / vol / grade) refused
   int cooldown_blocked; // post-loss cooldown or daily entry cap
   int dispatched;       // entries actually sent to the execution state machine
   int sweep_entries;    // ...of which liquidity-sweep entries

   void Reset(void)
   {
      scanned = 0; warmup_blocked = 0; session_blocked = 0; spread_blocked = 0;
      news_blocked = 0; regime_blocked = 0; risk_blocked = 0; exec_blocked = 0;
      in_trade = 0; gates_passed = 0; regime_ok = 0; location_ok = 0;
      trigger_ok = 0; ctx_blocked = 0; cooldown_blocked = 0; dispatched = 0;
      sweep_entries = 0;
   }
};

//--- Live Strategy Diagnostic Structure (§9)
struct SStrategyDiagnostic
{
   string active_engine_name;
   string condition1_name;
   bool   condition1_pass;
   string condition1_val;
   string condition2_name;
   bool   condition2_pass;
   string condition2_val;
   string condition3_name;
   bool   condition3_pass;
   string condition3_val;
   string next_action;
};

//--- Signal Generation Structure
struct SSignalResult
{
   bool                 valid;
   ENUM_ENGINE_TYPE     engine;
   ENUM_TRADE_DIRECTION direction;
   bool                 is_stop_order;
   double               stop_entry_price;
   double               sl_price;
   double               atr_m5_at_signal;
   int                  stop_expire_bars;
   string               sub_type;
   string               pass_details;
   string               fail_code;
   string               fail_details;
   datetime             signal_time;
   int                  score;
   double               risk_mult;     // confluence-grade position size multiplier (1.0 = full risk)
};

//--- Position Lifecycle Tracking
struct SPositionTrack
{
   ulong                ticket;
   ulong                magic;
   ENUM_ENGINE_TYPE     engine;
   ENUM_TRADE_DIRECTION direction;
   double               entry_price;
   double               initial_sl;
   double               current_sl;
   double               initial_lots;
   double               current_lots;
   double               r_points;
   ENUM_TRADE_STAGE     stage;
   datetime             open_time;
   int                  bars_held_m5;
   bool                 indivisible;
   bool                 active;
   int                  mode;          // 0 = legacy M5 engines, 1 = trend-pullback scalp, 2 = liquidity sweep
};

//--- Per-Engine Attribution Metrics
struct SEngineStats
{
   int    total_trades;
   int    wins;
   int    losses;
   double gross_profit;
   double gross_loss;
   double net_profit;
   double win_rate;
};

//--- Global Performance Metrics
struct STradeStats
{
   int    total_trades;
   int    wins;
   int    losses;
   double win_rate;
   double gross_profit;
   double gross_loss;
   double net_profit;
   double profit_factor;
   double avg_win;
   double avg_loss;
   
   double avg_latency_ms;
   long   total_latency_ms;
   int    latency_samples;
   int    rejected_orders;
   int    partial_fills;
};

//+------------------------------------------------------------------+
//| Helpers to convert Enums to strings for CSV & Logs               |
//+------------------------------------------------------------------+
inline string RegimeToString(ENUM_REGIME r)
{
   switch(r)
   {
      case REGIME_CHAOS:     return "CHAOS";
      case REGIME_EXPANSION: return "EXPANSION";
      case REGIME_TREND_UP:  return "TREND_UP";
      case REGIME_TREND_DN:  return "TREND_DN";
      case REGIME_RANGE:     return "RANGE";
      default:               return "NONE";
   }
}

inline string EngineToString(ENUM_ENGINE_TYPE e)
{
   switch(e)
   {
      case ENGINE_A_TREND_PULLBACK: return "ENGINE_A";
      case ENGINE_B_BREAKOUT:       return "ENGINE_B";
      case ENGINE_C_MEAN_REVERSION: return "ENGINE_C";
      default:                      return "NONE";
   }
}

inline string EngineToName(ENUM_ENGINE_TYPE e)
{
   switch(e)
   {
      case ENGINE_A_TREND_PULLBACK: return "Trend-Pullback";
      case ENGINE_B_BREAKOUT:       return "Breakout";
      case ENGINE_C_MEAN_REVERSION: return "Mean Reversion";
      default:                      return "None";
   }
}

inline string DirectionToString(ENUM_TRADE_DIRECTION d)
{
   switch(d)
   {
      case DIR_LONG:  return "LONG";
      case DIR_SHORT: return "SHORT";
      default:        return "NONE";
   }
}

inline string StateToString(ENUM_EXEC_STATE s)
{
   switch(s)
   {
      case STATE_IDLE:            return "IDLE";
      case STATE_PRE_TRADE_CHECK: return "PRE_TRADE_CHECK";
      case STATE_ORDER_SENT:      return "ORDER_SENT";
      case STATE_FILLED:          return "FILLED";
      case STATE_REJECTED:        return "REJECTED";
      case STATE_PARTIAL:         return "PARTIAL";
      case STATE_PROTECTED:       return "PROTECTED";
      case STATE_MANAGED:         return "MANAGED";
      case STATE_EXIT_REQUEST:    return "EXIT_REQUEST";
      case STATE_CLOSED:          return "CLOSED";
      default:                    return "UNKNOWN";
   }
}
