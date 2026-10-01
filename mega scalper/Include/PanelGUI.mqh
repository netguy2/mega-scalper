//+------------------------------------------------------------------+
//|                                                     PanelGUI.mqh |
//|                             XAU-MEGA-SCALPER Formal Spec v0.2    |
//|                             CLEAN DUAL-TAB RESEARCH DASHBOARD    |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"
#include "TradeManager.mqh"
#include "ExecutionStateMachine.mqh"
#include "DecisionLogger.mqh"

#define GUI_PREFIX "XMS_"
#define FONT_MAIN  "Segoe UI"
#define FONT_BOLD  "Segoe UI Semibold"

enum ENUM_GUI_TAB
{
   TAB_DASHBOARD  = 0,
   TAB_DIAGNOSTIC = 1
};

class CPanelGUI
{
private:
   long                    m_chart_id;
   int                     m_subwin;
   CTradeManager          *m_trade_mgr;
   CExecutionStateMachine *m_exec_sm;
   CDecisionLogger        *m_dec_logger;

   int                     m_x;
   int                     m_y;
   int                     m_width;
   int                     m_height;

   ENUM_GUI_TAB            m_active_tab;
   bool                    m_close_all_confirming;
   datetime                m_confirm_timeout;

   // Dragging State
   bool                    m_is_dragging;
   int                     m_drag_offset_x;
   int                     m_drag_offset_y;

   // Cached Telemetry for Drag Re-rendering
   SRegimeState            m_last_regime;
   SGateResults            m_last_gates;
   SSignalResult           m_last_signal;
   SStrategyDiagnostic     m_last_diagnostic;
   SDrySignal              m_last_dry_a;
   SDrySignal              m_last_dry_b;
   SDrySignal              m_last_dry_c;

   // Safe Label Creator / Updater (Never leaves default "Label" text)
   void SetLabel(string name, string text, int x, int y, color text_col, int font_size = 8, bool is_bold = false, int z_order = 5)
   {
      string obj_name = GUI_PREFIX + name;
      if(ObjectFind(m_chart_id, obj_name) < 0)
      {
         ObjectCreate(m_chart_id, obj_name, OBJ_LABEL, m_subwin, 0, 0);
         ObjectSetInteger(m_chart_id, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
         ObjectSetString(m_chart_id, obj_name, OBJPROP_FONT, is_bold ? FONT_BOLD : FONT_MAIN);
      }
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
      ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, (text == "" ? " " : text));
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, text_col);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_FONTSIZE, font_size);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_ZORDER, z_order);
   }

   // Background Panels & Dividers (Always FOREGROUND with Z-order so it blocks grid & candles)
   void SetRect(string name, int x, int y, int w, int h, color bg_col, color border_col, int z_order = 0)
   {
      string obj_name = GUI_PREFIX + name;
      if(ObjectFind(m_chart_id, obj_name) < 0)
      {
         ObjectCreate(m_chart_id, obj_name, OBJ_RECTANGLE_LABEL, m_subwin, 0, 0);
         ObjectSetInteger(m_chart_id, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YSIZE, h);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BGCOLOR, bg_col);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BORDER_COLOR, border_col);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false); // BLOCKS CHART CANDLES & GRID
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_ZORDER, z_order);
   }

   void SetButton(string name, string text, int x, int y, int w, int h, color bg_col, color text_col, int font_size = 8, int z_order = 10)
   {
      string obj_name = GUI_PREFIX + name;
      if(ObjectFind(m_chart_id, obj_name) < 0)
      {
         ObjectCreate(m_chart_id, obj_name, OBJ_BUTTON, m_subwin, 0, 0);
         ObjectSetInteger(m_chart_id, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetString(m_chart_id, obj_name, OBJPROP_FONT, FONT_BOLD);
         ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YSIZE, h);
      ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BGCOLOR, bg_col);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, text_col);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_FONTSIZE, font_size);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chart_id, obj_name, OBJPROP_ZORDER, z_order);
   }

   void PurgeLegacyObjects(void)
   {
      string legacy[] = {"SUB_CRD_1", "SUB_CRD_2", "SUB_CRD_3", "SUB_CRD_4",
                         "TAB_2", "TAB_3", "TAB_4",
                         "CRD_COND", "CRD_ACTION", "CRD_REJ", "CRD_MKT", "CRD_ACC", "CRD_POS",
                         "CARD_1", "CARD_2", "CARD_3", "CARD_4"};
      for(int i = 0; i < ArraySize(legacy); i++)
         ObjectDelete(m_chart_id, GUI_PREFIX + legacy[i]);
   }

   void HideAllContentRows(void)
   {
      for(int i = 0; i < 30; i++)
      {
         SetLabel(StringFormat("ROW_L_%d", i), " ", -500, -500, clrNONE);
         SetLabel(StringFormat("ROW_V_%d", i), " ", -500, -500, clrNONE);
      }
      PurgeLegacyObjects();
   }

public:
   CPanelGUI(void) : m_chart_id(0),
                     m_subwin(0),
                     m_trade_mgr(NULL),
                     m_exec_sm(NULL),
                     m_dec_logger(NULL),
                     m_x(18),
                     m_y(22),
                     m_width(350),
                     m_height(430),
                     m_active_tab(TAB_DASHBOARD),
                     m_close_all_confirming(false),
                     m_confirm_timeout(0),
                     m_is_dragging(false),
                     m_drag_offset_x(0),
                     m_drag_offset_y(0)
   {
   }

   ~CPanelGUI(void)
   {
      Destroy();
   }

   void Init(CTradeManager *trade_mgr, CExecutionStateMachine *exec_sm, CDecisionLogger *dec_logger)
   {
      m_chart_id   = ChartID();
      m_subwin     = 0;
      m_trade_mgr  = trade_mgr;
      m_exec_sm    = exec_sm;
      m_dec_logger = dec_logger;
      m_active_tab = TAB_DASHBOARD;
      m_is_dragging = false;

      // Enable mouse events for dragging
      ChartSetInteger(m_chart_id, CHART_EVENT_MOUSE_MOVE, true);
      // Ensure chart candles and grid are drawn behind UI objects
      ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);

      // Restore persistent coordinates if available
      string gv_x = StringFormat("XMS_POS_X_%I64d", m_chart_id);
      string gv_y = StringFormat("XMS_POS_Y_%I64d", m_chart_id);
      if(GlobalVariableCheck(gv_x)) m_x = (int)GlobalVariableGet(gv_x);
      if(GlobalVariableCheck(gv_y)) m_y = (int)GlobalVariableGet(gv_y);

      // Nuke any old objects completely to prevent ghost elements
      ObjectsDeleteAll(m_chart_id, GUI_PREFIX);

      BuildStaticChrome();
   }

   void Destroy(void)
   {
      ChartSetInteger(m_chart_id, CHART_EVENT_MOUSE_MOVE, false);
      ObjectsDeleteAll(m_chart_id, GUI_PREFIX);
      ChartRedraw(m_chart_id);
   }

   void BuildStaticChrome(void)
   {
      PurgeLegacyObjects();

      // Master Panel Canvas (Z-order 0: Solid opaque dark slate covering chart candles/grid)
      SetRect("BG", m_x, m_y, m_width, m_height, C'16,20,26', C'45,55,70', 0);
      // Header Bar (Z-order 1: Drag handle)
      SetRect("HEADER", m_x, m_y, m_width, 42, C'24,30,40', C'55,68,88', 1);

      // Title & Clean Subtitle
      SetLabel("TITLE", "XAU-MEGA-SCALPER v0.2", m_x + 14, m_y + 6, C'255,215,0', 9, true, 5);
      SetLabel("SUBTITLE", "CONTINUOUS RESEARCH PIPELINE", m_x + 14, m_y + 24, C'0,210,255', 7, false, 5);
      // Explicit drag handle indicator
      SetLabel("DRAG_CUE", "[ ✥ DRAG ]", m_x + m_width - 66, m_y + 8, C'120,140,165', 7, true, 5);

      // Clean 2-Tab Navigation
      int tab_w = 162;
      int tab_y = m_y + 46;
      SetButton("TAB_0", "📊 DASHBOARD & CONTROLS", m_x + 10, tab_y, tab_w, 24,
                (m_active_tab == TAB_DASHBOARD) ? C'0,125,210' : C'28,36,48', clrWhite, 8, 10);
      SetButton("TAB_1", "🔍 DIAGNOSTIC & AUDIT", m_x + 10 + tab_w + 6, tab_y, tab_w, 24,
                (m_active_tab == TAB_DIAGNOSTIC) ? C'0,125,210' : C'28,36,48', clrWhite, 8, 10);

      // Divider below tabs (1 pixel thin line, Z-order 2)
      SetRect("TAB_DIV", m_x + 10, m_y + 73, m_width - 20, 1, C'45,55,70', C'45,55,70', 2);

      ChartRedraw(m_chart_id);
   }

   void RebuildPositions(void)
   {
      BuildStaticChrome();
      HideAllContentRows();
      if(m_active_tab == TAB_DASHBOARD)
      {
         RenderDashboardTab(m_last_regime, m_last_gates);
      }
      else
      {
         RenderDiagnosticTab(m_last_regime, m_last_gates, m_last_diagnostic, m_last_dry_a, m_last_dry_b, m_last_dry_c);
      }
   }

   //+------------------------------------------------------------------+
   //| Master Refresh Call                                              |
   //+------------------------------------------------------------------+
   void Update(const SRegimeState &regime,
               const SGateResults &gates,
               const SSignalResult &last_signal,
               const SStrategyDiagnostic &diagnostic,
               const SDrySignal &dry_a,
               const SDrySignal &dry_b,
               const SDrySignal &dry_c)
   {
      // Cache states for dragging re-render
      m_last_regime     = regime;
      m_last_gates      = gates;
      m_last_signal     = last_signal;
      m_last_diagnostic = diagnostic;
      m_last_dry_a      = dry_a;
      m_last_dry_b      = dry_b;
      m_last_dry_c      = dry_c;

      PurgeLegacyObjects();

      int tab_w = 162;
      int tab_y = m_y + 46;
      SetButton("TAB_0", "📊 DASHBOARD & CONTROLS", m_x + 10, tab_y, tab_w, 24,
                (m_active_tab == TAB_DASHBOARD) ? C'0,135,225' : C'28,36,48',
                (m_active_tab == TAB_DASHBOARD) ? clrWhite : C'160,175,195', 8, 10);

      SetButton("TAB_1", "🔍 DIAGNOSTIC & AUDIT", m_x + 10 + tab_w + 6, tab_y, tab_w, 24,
                (m_active_tab == TAB_DIAGNOSTIC) ? C'0,135,225' : C'28,36,48',
                (m_active_tab == TAB_DIAGNOSTIC) ? clrWhite : C'160,175,195', 8, 10);

      HideAllContentRows();

      if(m_active_tab == TAB_DASHBOARD)
      {
         RenderDashboardTab(regime, gates);
      }
      else
      {
         RenderDiagnosticTab(regime, gates, diagnostic, dry_a, dry_b, dry_c);
      }

      // Check timeout on Close All confirmation
      if(m_close_all_confirming && TimeCurrent() > m_confirm_timeout)
      {
         m_close_all_confirming = false;
         SetButton("BTN_CLOSE_ALL", "[ ⚠ CLOSE ALL POSITIONS ]", m_x + 12, m_y + 389, 326, 26, C'140,35,35', clrWhite, 8, 10);
      }

      ChartRedraw(m_chart_id);
   }

   //+------------------------------------------------------------------+
   //| Tab 1: DASHBOARD & CONTROLS (Zero Overlap, Crystal Clear)       |
   //+------------------------------------------------------------------+
   void RenderDashboardTab(const SRegimeState &regime, const SGateResults &gates)
   {
      int cy = m_y + 80;

      // 1. Status & Regime Section
      ENUM_EA_RUN_STATE r_state = (m_exec_sm != NULL) ? m_exec_sm.GetRunState() : EA_STATE_STOPPED;
      string status_str = (r_state == EA_STATE_RUNNING) ? "🟢 RUNNING" :
                          ((r_state == EA_STATE_STARTING) ? "🟡 STARTING" : "🔴 STOPPED");
      color status_col  = (r_state == EA_STATE_RUNNING) ? C'46,204,113' :
                          ((r_state == EA_STATE_STARTING) ? C'241,196,15' : C'231,76,60');

      color raw_col = (regime.raw_regime == REGIME_TREND_UP) ? C'46,204,113' :
                      ((regime.raw_regime == REGIME_TREND_DN) ? C'231,76,60' :
                      ((regime.raw_regime == REGIME_EXPANSION) ? C'241,196,15' :
                      ((regime.raw_regime == REGIME_RANGE) ? C'140,185,225' : C'255,80,80')));

      color act_col = (regime.active_regime == REGIME_TREND_UP) ? C'46,204,113' :
                      ((regime.active_regime == REGIME_TREND_DN) ? C'231,76,60' :
                      ((regime.active_regime == REGIME_EXPANSION) ? C'241,196,15' :
                      ((regime.active_regime == REGIME_RANGE) ? C'140,185,225' : C'255,80,80')));

      SetLabel("ROW_L_0", "EA STATUS:", m_x + 14, cy, C'135,155,180', 8, true);
      SetLabel("ROW_V_0", status_str,    m_x + 85, cy, status_col, 8, true);

      SetLabel("ROW_L_1", "MODE:",       m_x + 185, cy, C'135,155,180', 8, true);
      SetLabel("ROW_V_1", "CONTINUOUS",  m_x + 235, cy, C'0,210,255', 8, true);

      cy += 18;
      SetLabel("ROW_L_2", "RAW REGIME:", m_x + 14, cy, C'135,155,180', 8);
      SetLabel("ROW_V_2", RegimeToString(regime.raw_regime), m_x + 95, cy, raw_col, 8, true);

      SetLabel("ROW_L_3", "ACTIVE REGIME:", m_x + 185, cy, C'135,155,180', 8);
      SetLabel("ROW_V_3", RegimeToString(regime.active_regime), m_x + 265, cy, act_col, 8, true);

      cy += 18;
      SetLabel("ROW_L_4", "Persistence:", m_x + 14, cy, C'135,155,180', 8);
      SetLabel("ROW_V_4", StringFormat("%d / %d %s", regime.persist_count, regime.persist_required, (regime.persist_count >= regime.persist_required ? "✓" : "WAIT")),
               m_x + 85, cy, (regime.persist_count >= regime.persist_required ? C'46,204,113' : C'241,196,15'), 8);

      SetLabel("ROW_L_5", "Dwell:",       m_x + 185, cy, C'135,155,180', 8);
      SetLabel("ROW_V_5", StringFormat("%d / %d %s", regime.dwell_count, regime.dwell_required, (regime.dwell_ok ? "✓" : "WAIT")),
               m_x + 235, cy, (regime.dwell_ok ? C'46,204,113' : C'241,196,15'), 8);

      cy += 18;
      SetLabel("ROW_L_6", "Trend Score:", m_x + 14, cy, C'135,155,180', 8);
      SetLabel("ROW_V_6", StringFormat("%d / 100", regime.total_trend_score), m_x + 85, cy, C'220,230,240', 8, true);

      SetLabel("ROW_L_7", "Chaos Check:", m_x + 185, cy, C'135,155,180', 8);
      SetLabel("ROW_V_7", regime.primary_chaos_reason == "NONE" ? "NONE (CLEAN) ✓" : regime.primary_chaos_reason,
               m_x + 250, cy, regime.primary_chaos_reason == "NONE" ? C'46,204,113' : C'231,76,60', 8, true);

      // Thin Divider line
      cy += 20;
      SetRect("DIV_1", m_x + 10, cy, m_width - 20, 1, C'38,48,62', C'38,48,62');

      // 2. Market Telemetry Section
      cy += 8;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double spread_pts = SymbolInfoDouble(_Symbol, SYMBOL_POINT) > 0 ? (ask - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT) : 0;

      SetLabel("ROW_L_8", "XAUUSD Bid:", m_x + 14, cy, C'135,155,180', 8);
      SetLabel("ROW_V_8", StringFormat("%.2f", bid), m_x + 85, cy, C'220,230,240', 8, true);

      SetLabel("ROW_L_9", "Spread:",    m_x + 185, cy, C'135,155,180', 8);
      color spd_col = gates.g3_spread ? C'46,204,113' : C'231,76,60';
      SetLabel("ROW_V_9", StringFormat("%.1f pts (%.3f ATR) %s", spread_pts, gates.spread_atr_ratio, gates.g3_spread ? "✓" : "✗"),
               m_x + 235, cy, spd_col, 8, true);

      cy += 18;
      SetLabel("ROW_L_10", "ATR (M5):",   m_x + 14, cy, C'135,155,180', 8);
      SetLabel("ROW_V_10", StringFormat("%.2f (Ratio: %.2f)", regime.atr_m5, regime.atr_ratio), m_x + 85, cy, C'220,230,240', 8);

      SetLabel("ROW_L_11", "Session:",   m_x + 185, cy, C'135,155,180', 8);
      SetLabel("ROW_V_11", gates.g2_session ? "LONDON + NY ✓" : "BLACKOUT ✗", m_x + 235, cy, gates.g2_session ? C'46,204,113' : C'231,76,60', 8, true);

      // Thin Divider line
      cy += 20;
      SetRect("DIV_2", m_x + 10, cy, m_width - 20, 1, C'38,48,62', C'38,48,62');

      // 3. Account Telemetry Section
      cy += 8;
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eqt = AccountInfoDouble(ACCOUNT_EQUITY);
      double flt = eqt - bal;

      SetLabel("ROW_L_12", "Balance:",   m_x + 14, cy, C'135,155,180', 8);
      SetLabel("ROW_V_12", StringFormat("$%.2f", bal), m_x + 85, cy, C'220,230,240', 8);

      SetLabel("ROW_L_13", "Equity:",    m_x + 185, cy, C'135,155,180', 8);
      SetLabel("ROW_V_13", StringFormat("$%.2f", eqt), m_x + 235, cy, C'220,230,240', 8);

      cy += 18;
      SetLabel("ROW_L_14", "Floating:",  m_x + 14, cy, C'135,155,180', 8);
      SetLabel("ROW_V_14", StringFormat("%s$%.2f", (flt >= 0 ? "+" : ""), flt), m_x + 85, cy, (flt >= 0 ? C'46,204,113' : C'231,76,60'), 8, true);

      double closed_pnl = (m_trade_mgr != NULL) ? m_trade_mgr.GetGlobalStats().net_profit : 0.0;
      SetLabel("ROW_L_15", "Closed PnL:", m_x + 185, cy, C'135,155,180', 8);
      SetLabel("ROW_V_15", StringFormat("%s$%.2f", (closed_pnl >= 0 ? "+" : ""), closed_pnl), m_x + 250, cy, (closed_pnl >= 0 ? C'46,204,113' : C'231,76,60'), 8, true);

      // Thin Divider line
      cy += 20;
      SetRect("DIV_3", m_x + 10, cy, m_width - 20, 1, C'38,48,62', C'38,48,62');

      // 4. Active Position Section
      cy += 8;
      if(m_trade_mgr != NULL && m_trade_mgr.HasActivePosition())
      {
         SPositionTrack pos = m_trade_mgr.GetCurrentPosition();
         double cur_price = (pos.direction == DIR_LONG) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double diff_pts = (pos.direction == DIR_LONG) ? (cur_price - pos.entry_price) / _Point : (pos.entry_price - cur_price) / _Point;
         double pos_pnl = PositionGetDouble(POSITION_PROFIT);

         SetLabel("ROW_L_16", StringFormat("OPEN: %s %s %.2f Lots", _Symbol, DirectionToString(pos.direction), pos.current_lots),
                  m_x + 14, cy, (pos.direction == DIR_LONG ? C'46,204,113' : C'231,76,60'), 8, true);
         SetLabel("ROW_V_16", StringFormat("%s$%.2f (%+.1f pts)", (pos_pnl >= 0 ? "+" : ""), pos_pnl, diff_pts),
                  m_x + 215, cy, (diff_pts >= 0 ? C'46,204,113' : C'231,76,60'), 8, true);

         cy += 18;
         SetLabel("ROW_L_17", StringFormat("Entry: %.2f  |  SL: %.2f  |  Stage %d (BE)", pos.entry_price, pos.current_sl, (int)pos.stage),
                  m_x + 14, cy, C'135,155,180', 8);
      }
      else
      {
         SetLabel("ROW_L_16", "ACTIVE POSITION: NONE", m_x + 14, cy, C'110,125,145', 8, true);
         SetLabel("ROW_V_16", "SCANNING...", m_x + 245, cy, C'0,210,255', 8);

         cy += 18;
         SetLabel("ROW_L_17", "Actively scanning market. Next valid trigger takes trade.", m_x + 14, cy, C'135,155,180', 8);
      }

      // 5. Control Buttons
      int btn_y = m_y + 355;
      SetButton("BTN_START", "[ 🟢 START EA ]", m_x + 12, btn_y, 158, 28, C'20,105,50', clrWhite, 8);
      SetButton("BTN_STOP",  "[ 🔴 STOP EA ]",  m_x + 178, btn_y, 160, 28, C'145,30,30', clrWhite, 8);
      
      if(!m_close_all_confirming)
         SetButton("BTN_CLOSE_ALL", "[ ⚠ CLOSE ALL POSITIONS ]", m_x + 12, btn_y + 34, 326, 26, C'140,35,35', clrWhite, 8);
   }

   //+------------------------------------------------------------------+
   //| Tab 2: DIAGNOSTIC & AUDIT (Exact Values, Dry Scans, Zero Overlap)|
   //+------------------------------------------------------------------+
   void RenderDiagnosticTab(const SRegimeState &regime, const SGateResults &gates,
                            const SStrategyDiagnostic &diagnostic,
                            const SDrySignal &dry_a, const SDrySignal &dry_b, const SDrySignal &dry_c)
   {
      int cy = m_y + 80;

      // 1. Dispatched Engine & Next Action
      SetLabel("ROW_L_0", "DISPATCHED ENGINE:", m_x + 14, cy, C'255,215,0', 8, true);
      SetLabel("ROW_V_0", diagnostic.active_engine_name, m_x + 130, cy, C'0,210,255', 8, true);

      cy += 18;
      SetLabel("ROW_L_1", "NEXT ACTION:", m_x + 14, cy, C'241,196,15', 8, true);
      SetLabel("ROW_V_1", diagnostic.next_action, m_x + 95, cy, clrWhite, 8, true);

      // Thin Divider line
      cy += 20;
      SetRect("DIV_1", m_x + 10, cy, m_width - 20, 1, C'38,48,62', C'38,48,62');

      // 2. Trend Score Components (§1)
      cy += 8;
      SetLabel("ROW_L_2", StringFormat("TREND SCORE: %d / 100", regime.total_trend_score), m_x + 14, cy, C'255,215,0', 8, true);

      cy += 16;
      SetLabel("ROW_L_3", StringFormat("EMA Align: %d/20  ADX: %d/20  VWAP Pos: %d/15",
                                       regime.score_ema_alignment, regime.score_adx, regime.score_vwap_pos),
               m_x + 14, cy, C'140,165,190', 7);

      cy += 14;
      SetLabel("ROW_L_4", StringFormat("Slope: %d/15  Structure: %d/15  Momentum: %d/15",
                                       regime.score_vwap_slope, regime.score_structure, regime.score_momentum),
               m_x + 14, cy, C'140,165,190', 7);

      // Thin Divider line
      cy += 18;
      SetRect("DIV_2", m_x + 10, cy, m_width - 20, 1, C'38,48,62', C'38,48,62');

      // 3. Dry Candidate Scans for all 3 Engines (§12)
      cy += 8;
      SetLabel("ROW_L_5", "STRATEGY CANDIDATE SCANS (ALL 3 ENGINES):", m_x + 14, cy, C'255,215,0', 8, true);

      cy += 18;
      color col_a = dry_a.setup_found ? C'46,204,113' : C'140,165,190';
      SetLabel("ROW_L_6", "1. Trend-Pullback:", m_x + 14, cy, C'0,210,255', 8);
      SetLabel("ROW_V_6", StringFormat("%s (%s)", dry_a.status_desc, (dry_a.primary_rejection_reason != "" ? dry_a.primary_rejection_reason : "Ready")),
               m_x + 115, cy, col_a, 7);

      cy += 16;
      color col_b = dry_b.setup_found ? C'46,204,113' : C'140,165,190';
      SetLabel("ROW_L_7", "2. Breakout:", m_x + 14, cy, C'0,210,255', 8);
      SetLabel("ROW_V_7", StringFormat("%s (%s)", dry_b.status_desc, (dry_b.primary_rejection_reason != "" ? dry_b.primary_rejection_reason : "Ready")),
               m_x + 115, cy, col_b, 7);

      cy += 16;
      color col_c = dry_c.setup_found ? C'46,204,113' : C'140,165,190';
      SetLabel("ROW_L_8", "3. Mean Reversion:", m_x + 14, cy, C'0,210,255', 8);
      SetLabel("ROW_V_8", StringFormat("%s (%s)", dry_c.status_desc, (dry_c.primary_rejection_reason != "" ? dry_c.primary_rejection_reason : "Ready")),
               m_x + 115, cy, col_c, 7);

      // Thin Divider line
      cy += 20;
      SetRect("DIV_3", m_x + 10, cy, m_width - 20, 1, C'38,48,62', C'38,48,62');

      // 4. Execution Gates Checklist (G1-G7)
      cy += 8;
      SetLabel("ROW_L_9", "EXECUTION GATES CHECKLIST (G1-G7):", m_x + 14, cy, C'255,215,0', 8, true);

      cy += 16;
      SetLabel("ROW_L_10", StringFormat("G1 Warmup: %s (M15:%d M5:%d M1:%d)", gates.g1_warmup ? "PASS ✓" : "FAIL ✗", gates.m15_bars_have, gates.m5_bars_have, gates.m1_bars_have),
               m_x + 14, cy, gates.g1_warmup ? C'46,204,113' : C'231,76,60', 7);

      cy += 14;
      SetLabel("ROW_L_11", StringFormat("G2 Session: %s (07:00-20:00 server)", gates.g2_session ? "PASS ✓" : "FAIL ✗"),
               m_x + 14, cy, gates.g2_session ? C'46,204,113' : C'231,76,60', 7);

      cy += 14;
      SetLabel("ROW_L_12", StringFormat("G3 Spread:  %s (%.3f <= %.3f ATR)  G4 News: %s",
                                        gates.g3_spread ? "PASS ✓" : "FAIL ✗", gates.spread_atr_ratio, gates.spread_limit_ratio,
                                        gates.g4_news ? "PASS ✓" : "FAIL ✗"),
               m_x + 14, cy, (gates.g3_spread && gates.g4_news) ? C'46,204,113' : C'231,76,60', 7);

      cy += 14;
      SetLabel("ROW_L_13", StringFormat("G5 Regime:  %s (Dwell:%d/3)  G6 Risk: %s (Pos:%d/1)",
                                        gates.g5_regime ? "PASS ✓" : "FAIL ✗", regime.dwell_count,
                                        gates.g6_risk ? "PASS ✓" : "FAIL ✗", gates.open_positions),
               m_x + 14, cy, (gates.g5_regime && gates.g6_risk) ? C'46,204,113' : C'231,76,60', 7);

      // 5. Recent Decision Line
      cy += 20;
      if(m_dec_logger != NULL && m_dec_logger.GetRecentCount() > 0)
      {
         string latest_dec = m_dec_logger.GetRecentLine(0);
         color dec_col = (StringFind(latest_dec, "TRADE:") >= 0) ? C'46,204,113' : C'241,196,15';
         SetLabel("ROW_L_14", StringFormat("LATEST LOG: %s", latest_dec), m_x + 14, cy, dec_col, 7);
      }
      else
      {
         SetLabel("ROW_L_14", "Audit log active -> File: MQL5/Files/XAU_MEGA_DECISIONS.log", m_x + 14, cy, C'110,135,160', 7);
      }
   }

   //+------------------------------------------------------------------+
   //| Interactive Click & Drag Event Dispatcher                        |
   //+------------------------------------------------------------------+
   bool OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
   {
      // 1. Mouse Dragging via Header
      if(id == CHARTEVENT_MOUSE_MOVE)
      {
         int mouse_x    = (int)lparam;
         int mouse_y    = (int)dparam;
         uint mouse_btn = (uint)StringToInteger(sparam);
         bool left_down = ((mouse_btn & 1) != 0);

         if(!left_down)
         {
            if(m_is_dragging)
            {
               m_is_dragging = false;
               string gv_x = StringFormat("XMS_POS_X_%I64d", m_chart_id);
               string gv_y = StringFormat("XMS_POS_Y_%I64d", m_chart_id);
               GlobalVariableSet(gv_x, (double)m_x);
               GlobalVariableSet(gv_y, (double)m_y);
            }
            return false;
         }

         // Left mouse button pressed
         if(!m_is_dragging)
         {
            // Check if mouse clicked inside Header bar (y to y+44)
            if(mouse_x >= m_x && mouse_x <= m_x + m_width &&
               mouse_y >= m_y && mouse_y <= m_y + 44)
            {
               m_is_dragging   = true;
               m_drag_offset_x = mouse_x - m_x;
               m_drag_offset_y = mouse_y - m_y;
               return true;
            }
         }
         else
         {
            // Actively dragging
            int new_x = mouse_x - m_drag_offset_x;
            int new_y = mouse_y - m_drag_offset_y;

            if(new_x < 5) new_x = 5;
            if(new_y < 5) new_y = 5;
            int chart_w = (int)ChartGetInteger(m_chart_id, CHART_WIDTH_IN_PIXELS);
            int chart_h = (int)ChartGetInteger(m_chart_id, CHART_HEIGHT_IN_PIXELS);
            if(chart_w > 0 && new_x > chart_w - 60) new_x = chart_w - 60;
            if(chart_h > 0 && new_y > chart_h - 40) new_y = chart_h - 40;

            if(new_x != m_x || new_y != m_y)
            {
               m_x = new_x;
               m_y = new_y;
               RebuildPositions();
               ChartRedraw(m_chart_id);
            }
            return true;
         }
         return false;
      }

      if(id == CHARTEVENT_OBJECT_CLICK)
      {
         // Tab 0
         if(sparam == GUI_PREFIX + "TAB_0")
         {
            m_active_tab = TAB_DASHBOARD;
            ObjectSetInteger(m_chart_id, sparam, OBJPROP_STATE, false);
            ChartRedraw(m_chart_id);
            return true;
         }

         // Tab 1
         if(sparam == GUI_PREFIX + "TAB_1")
         {
            m_active_tab = TAB_DIAGNOSTIC;
            ObjectSetInteger(m_chart_id, sparam, OBJPROP_STATE, false);
            ChartRedraw(m_chart_id);
            return true;
         }

         // START Button
         if(sparam == GUI_PREFIX + "BTN_START")
         {
            if(m_exec_sm != NULL)
            {
               m_exec_sm.SetRunState(EA_STATE_RUNNING);
               if(m_dec_logger != NULL) m_dec_logger.AddRecentLine("START EA -> Continuous scanning enabled");
            }
            ObjectSetInteger(m_chart_id, sparam, OBJPROP_STATE, false);
            ChartRedraw(m_chart_id);
            return true;
         }

         // STOP Button
         if(sparam == GUI_PREFIX + "BTN_STOP")
         {
            if(m_exec_sm != NULL)
            {
               m_exec_sm.SetRunState(EA_STATE_STOPPED);
               if(m_dec_logger != NULL) m_dec_logger.AddRecentLine("STOP EA -> New entries paused");
            }
            ObjectSetInteger(m_chart_id, sparam, OBJPROP_STATE, false);
            ChartRedraw(m_chart_id);
            return true;
         }

         // CLOSE ALL POSITIONS Button (2-step confirm)
         if(sparam == GUI_PREFIX + "BTN_CLOSE_ALL")
         {
            if(!m_close_all_confirming)
            {
               m_close_all_confirming = true;
               m_confirm_timeout      = TimeCurrent() + 5;
               SetButton("BTN_CLOSE_ALL", "[ ⚠ CONFIRM CLOSE ALL? ]", m_x + 12, m_y + 389, 326, 26, C'220,20,60', clrWhite, 8);
               if(m_dec_logger != NULL) m_dec_logger.AddRecentLine("Close all requested -> Confirm needed");
            }
            else
            {
               m_close_all_confirming = false;
               SetButton("BTN_CLOSE_ALL", "[ ⚠ CLOSE ALL POSITIONS ]", m_x + 12, m_y + 389, 326, 26, C'140,35,35', clrWhite, 8);
               if(m_trade_mgr != NULL)
               {
                  string report = "";
                  m_trade_mgr.CloseAllNow(report);
                  if(m_dec_logger != NULL) m_dec_logger.AddRecentLine("CLOSED ALL: " + report);
               }
            }

            ObjectSetInteger(m_chart_id, sparam, OBJPROP_STATE, false);
            ChartRedraw(m_chart_id);
            return true;
         }
      }

      return false;
   }
};
