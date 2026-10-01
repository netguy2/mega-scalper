//+------------------------------------------------------------------+
//|                                                     PanelGUI.mqh |
//|                             XAU-MEGA-SCALPER  OPERATOR PANEL v3  |
//|                                  Copyright 2026, Advanced Algo   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Algo"
#property link      "https://github.com"
#property strict

#include "Defines.mqh"
#include "TradeManager.mqh"
#include "ExecutionStateMachine.mqh"
#include "DecisionLogger.mqh"

//+------------------------------------------------------------------+
//| DESIGN NOTES                                                     |
//|  * One question drives the layout: "why is it (not) trading?"    |
//|      1. VERDICT card  - one state word + the first missing       |
//|                         ingredient, in plain language.           |
//|      2. PIPELINE      - REGIME > M5 LOCATION > M1 TRIGGER >      |
//|                         EXECUTION, each colour-coded.            |
//|      3. CHECKLISTS    - the exact numbers behind each stage.     |
//|      4. FUNNEL        - where today's M1 bars died.              |
//|  * Trend score is diagnostics only (SYSTEM tab); it never gates. |
//|  * Colour is semantic: green = pass, amber = waiting, red =      |
//|    blocked, cyan = live trade, grey = not applicable.            |
//|  * No emoji (MT5 GDI renders them inconsistently) - status is    |
//|    drawn with small squares, not glyphs.                         |
//|  * Widgets are cached by signature: only changed objects are     |
//|    touched, so the 250ms refresh does not flicker.               |
//+------------------------------------------------------------------+
#define GUI_PREFIX "XMS_"
#define FONT_MAIN  "Segoe UI"
#define FONT_BOLD  "Segoe UI Semibold"

// Palette (dark slate, single cyan accent)
#define COL_BG     C'13,17,23'
#define COL_CARD   C'21,27,37'
#define COL_CARD2  C'31,40,55'
#define COL_LINE   C'38,48,63'
#define COL_TXT    C'226,232,240'
#define COL_SUB    C'148,163,184'
#define COL_MUTE   C'100,114,134'
#define COL_DIM    C'58,70,90'
#define COL_CYAN   C'56,189,248'
#define COL_CYAN_D C'30,110,150'
#define COL_GRN    C'52,211,153'
#define COL_RED    C'248,113,113'
#define COL_AMB    C'251,191,36'
#define TINT_GRN   C'14,46,40'
#define TINT_RED   C'55,24,29'
#define TINT_AMB   C'54,43,16'
#define TINT_CYAN  C'12,42,60'

// Pipeline stage states
#define ST_IDLE    0
#define ST_WAIT    1
#define ST_PASS    2
#define ST_BLOCK   3
#define ST_LIVE    4

enum ENUM_GUI_TAB
{
   TAB_SCALP  = 0,
   TAB_SYSTEM = 1
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
   bool                    m_collapsed;
   bool                    m_close_all_confirming;
   uint                    m_confirm_tick;

   bool                    m_is_dragging;
   int                     m_drag_offset_x;
   int                     m_drag_offset_y;

   int                     m_layout_key;
   bool                    m_have_data;

   // Telemetry cache (drag / click re-render without waiting for the EA)
   SRegimeState            m_last_regime;
   SGateResults            m_last_gates;
   SSignalResult           m_last_signal;
   SStrategyDiagnostic     m_last_diagnostic;
   SDrySignal              m_last_dry_a;
   SDrySignal              m_last_dry_b;
   SDrySignal              m_last_dry_c;
   SScalpState             m_last_scalp;
   SFunnel                 m_last_funnel;

   // Widget cache: name + style signature + "seen this frame" flag
   string                  m_c_name[];
   string                  m_c_sig[];
   bool                    m_c_used[];
   int                     m_c_n;

   //================================================================
   //  WIDGET LAYER
   //================================================================
   // Returns true when the widget is new or its style/text signature changed
   bool Touch(const string name, const string sig)
   {
      int i = -1;
      for(int k = 0; k < m_c_n; k++)
      {
         if(m_c_name[k] == name) { i = k; break; }
      }

      if(i < 0)
      {
         if(m_c_n >= ArraySize(m_c_name))
         {
            ArrayResize(m_c_name, m_c_n + 64);
            ArrayResize(m_c_sig,  m_c_n + 64);
            ArrayResize(m_c_used, m_c_n + 64);
         }
         i = m_c_n++;
         m_c_name[i] = name;
         m_c_sig[i]  = sig;
         m_c_used[i] = true;
         return true;
      }

      m_c_used[i] = true;
      if(m_c_sig[i] == sig) return false;
      m_c_sig[i] = sig;
      return true;
   }

   void BeginFrame(void)
   {
      for(int i = 0; i < m_c_n; i++) m_c_used[i] = false;
   }

   // Remove widgets that were not drawn this frame (e.g. second reason line gone)
   void EndFrame(void)
   {
      for(int i = m_c_n - 1; i >= 0; i--)
      {
         if(m_c_used[i]) continue;
         ObjectDelete(m_chart_id, GUI_PREFIX + m_c_name[i]);
         m_c_n--;
         m_c_name[i] = m_c_name[m_c_n];
         m_c_sig[i]  = m_c_sig[m_c_n];
         m_c_used[i] = m_c_used[m_c_n];
      }
   }

   void PutRect(const string name, int x, int y, int w, int h, color fill, color border)
   {
      if(w < 1) w = 1;
      if(h < 1) h = 1;
      string sig = StringFormat("%d|%d|%d|%d|%d|%d", x, y, w, h, (int)fill, (int)border);
      bool need = Touch(name, sig);
      string on = GUI_PREFIX + name;
      if(ObjectFind(m_chart_id, on) < 0)
      {
         ObjectCreate(m_chart_id, on, OBJ_RECTANGLE_LABEL, m_subwin, 0, 0);
         ObjectSetInteger(m_chart_id, on, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chart_id, on, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(m_chart_id, on, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart_id, on, OBJPROP_BACK, false);
         ObjectSetInteger(m_chart_id, on, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         need = true;
      }
      if(!need) return;
      ObjectSetInteger(m_chart_id, on, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart_id, on, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart_id, on, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chart_id, on, OBJPROP_YSIZE, h);
      ObjectSetInteger(m_chart_id, on, OBJPROP_BGCOLOR, fill);
      ObjectSetInteger(m_chart_id, on, OBJPROP_COLOR, border);   // border colour of a flat rectangle label
   }

   // align: 0 = left edge at x, 1 = right edge at x, 2 = centred on x,y
   void PutText(const string name, const string text, int x, int y, color col,
                int size = 8, bool bold = false, int align = 0)
   {
      string shown = (text == "") ? " " : text;
      string sig = StringFormat("%s|%d|%d|%d|%d|%d|%d", shown, x, y, (int)col, size, (int)bold, align);
      bool need = Touch(name, sig);
      string on = GUI_PREFIX + name;
      if(ObjectFind(m_chart_id, on) < 0)
      {
         ObjectCreate(m_chart_id, on, OBJ_LABEL, m_subwin, 0, 0);
         ObjectSetInteger(m_chart_id, on, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chart_id, on, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart_id, on, OBJPROP_BACK, false);
         ObjectSetInteger(m_chart_id, on, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         need = true;
      }
      if(!need) return;
      ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER;
      if(align == 1) anchor = ANCHOR_RIGHT_UPPER;
      else if(align == 2) anchor = ANCHOR_CENTER;
      ObjectSetString(m_chart_id, on, OBJPROP_FONT, bold ? FONT_BOLD : FONT_MAIN);
      ObjectSetInteger(m_chart_id, on, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(m_chart_id, on, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart_id, on, OBJPROP_YDISTANCE, y);
      ObjectSetString(m_chart_id, on, OBJPROP_TEXT, shown);
      ObjectSetInteger(m_chart_id, on, OBJPROP_COLOR, col);
      ObjectSetInteger(m_chart_id, on, OBJPROP_FONTSIZE, size);
   }

   void PutButton(const string name, const string text, int x, int y, int w, int h,
                  color fill, color fg, color border, int size = 8)
   {
      string sig = StringFormat("%s|%d|%d|%d|%d|%d|%d|%d|%d", text, x, y, w, h, (int)fill, (int)fg, (int)border, size);
      bool need = Touch(name, sig);
      string on = GUI_PREFIX + name;
      if(ObjectFind(m_chart_id, on) < 0)
      {
         ObjectCreate(m_chart_id, on, OBJ_BUTTON, m_subwin, 0, 0);
         ObjectSetInteger(m_chart_id, on, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chart_id, on, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart_id, on, OBJPROP_BACK, false);
         ObjectSetInteger(m_chart_id, on, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         ObjectSetString(m_chart_id, on, OBJPROP_FONT, FONT_BOLD);
         need = true;
      }
      if(!need) return;
      ObjectSetInteger(m_chart_id, on, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart_id, on, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart_id, on, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chart_id, on, OBJPROP_YSIZE, h);
      ObjectSetString(m_chart_id, on, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chart_id, on, OBJPROP_BGCOLOR, fill);
      ObjectSetInteger(m_chart_id, on, OBJPROP_COLOR, fg);
      ObjectSetInteger(m_chart_id, on, OBJPROP_BORDER_COLOR, border);
      ObjectSetInteger(m_chart_id, on, OBJPROP_FONTSIZE, size);
      ObjectSetInteger(m_chart_id, on, OBJPROP_STATE, false);
   }

   //================================================================
   //  SMALL HELPERS
   //================================================================
   string Clip(const string s, int n)
   {
      if(StringLen(s) <= n) return s;
      if(n < 3) return StringSubstr(s, 0, n);
      return StringSubstr(s, 0, n - 2) + "..";
   }

   // Wrap onto two lines at a word boundary; the second line is clipped
   void WrapTwo(const string text, int n, string &l1, string &l2)
   {
      l1 = text;
      l2 = "";
      if(StringLen(text) <= n) return;

      int cut = -1;
      for(int i = n; i > n / 2; i--)
      {
         if(StringGetCharacter(text, i) == 32) { cut = i; break; }
      }
      if(cut < 0)
      {
         l1 = StringSubstr(text, 0, n);
         l2 = Clip(StringSubstr(text, n), n);
      }
      else
      {
         l1 = StringSubstr(text, 0, cut);
         l2 = Clip(StringSubstr(text, cut + 1), n);
      }
   }

   string Money(double v)
   {
      return StringFormat("%s$%.2f", (v >= 0.0 ? "+" : "-"), MathAbs(v));
   }

   color StageColor(int st)
   {
      switch(st)
      {
         case ST_PASS:  return COL_GRN;
         case ST_WAIT:  return COL_AMB;
         case ST_BLOCK: return COL_RED;
         case ST_LIVE:  return COL_CYAN;
         default:       return COL_DIM;
      }
   }

   color StageTextColor(int st)
   {
      return (st == ST_IDLE) ? COL_MUTE : StageColor(st);
   }

   string RegimeShort(ENUM_REGIME r)
   {
      switch(r)
      {
         case REGIME_TREND_UP:  return "TREND UP";
         case REGIME_TREND_DN:  return "TREND DN";
         case REGIME_EXPANSION: return "EXPANSION";
         case REGIME_RANGE:     return "RANGE";
         case REGIME_CHAOS:     return "CHAOS";
         default:               return "WARMUP";
      }
   }

   color RegimeColor(ENUM_REGIME r)
   {
      switch(r)
      {
         case REGIME_TREND_UP:  return COL_GRN;
         case REGIME_TREND_DN:  return COL_RED;
         case REGIME_EXPANSION: return COL_AMB;
         case REGIME_RANGE:     return COL_CYAN;
         case REGIME_CHAOS:     return COL_RED;
         default:               return COL_MUTE;
      }
   }

   bool HasPosition(void)
   {
      return (m_trade_mgr != NULL && m_trade_mgr.HasActivePosition());
   }

   // Live (per-tick) reason entries are currently blocked. "" = nothing blocking.
   // g2 / g3 are refreshed every tick by the EA; G1/G4/G5/G6/G7 come from the last M1 evaluation.
   string LiveBlock(string &short_name)
   {
      short_name = "";
      const SGateResults g = m_last_gates;

      if(!g.g2_session)
      {
         short_name = "SESSION";
         return "Outside trading session (server 07:00-20:00, no rollover / late Friday)";
      }
      if(!g.g3_spread)
      {
         short_name = "SPREAD";
         return StringFormat("Spread %.0f pts = %.2f ATR(M5), limit %.2f ATR", g.spread_pts, g.spread_atr_ratio, g.spread_limit_ratio);
      }
      if(g.all_passed) return "";

      string fg = g.fail_gate;
      if(fg == "" || fg == "G2_SESSION" || fg == "G3_SPREAD") return "";   // stale; live checks above already passed

      if(fg == "G6_RISK" && StringFind(g.fail_reason, "Open positions") >= 0 && g.open_positions < g.max_positions)
         return "";                                                         // position closed since last evaluation

      if(fg == "G1_WARMUP")       short_name = "WARMUP";
      else if(fg == "G4_NEWS")    short_name = "NEWS";
      else if(fg == "G5_REGIME")  short_name = "REGIME";
      else if(fg == "G6_RISK")    short_name = "RISK";
      else                        short_name = "EXECUTION";
      return g.fail_reason;
   }

   //================================================================
   //  VERDICT  (the one-line answer)
   //================================================================
   void BuildVerdict(string &title, string &reason, color &accent, color &tint)
   {
      const SScalpState sc = m_last_scalp;
      ENUM_EA_RUN_STATE rs = (m_exec_sm != NULL) ? m_exec_sm.GetRunState() : EA_STATE_STOPPED;
      string blk_name = "";
      string blk = LiveBlock(blk_name);

      if(HasPosition())
      {
         SPositionTrack pos = m_trade_mgr.GetCurrentPosition();
         title  = StringFormat("IN TRADE - %s", DirectionToString(pos.direction));
         reason = "Managing the open position (break-even, partial, ATR trail). New entries wait until it closes.";
         accent = COL_CYAN; tint = TINT_CYAN;
      }
      else if(m_exec_sm != NULL && m_exec_sm.IsSessionDisabled())
      {
         title  = "ENTRIES LOCKED";
         reason = StringFormat("%d order rejections this session. Press START to unlock and try again.", m_exec_sm.GetSessionRejections());
         accent = COL_RED; tint = TINT_RED;
      }
      else if(rs != EA_STATE_RUNNING)
      {
         title  = "PAUSED";
         reason = "Entries are switched off. Press START to resume scanning.";
         accent = COL_AMB; tint = TINT_AMB;
      }
      else if(blk != "")
      {
         title  = "BLOCKED - " + blk_name;
         reason = blk;
         accent = COL_RED; tint = TINT_RED;
      }
      else if(!sc.regime_ok)
      {
         title  = "STANDBY - NO SETUP REGIME";
         reason = (sc.reason != "") ? sc.reason : StringFormat("Regime is %s", RegimeToString(m_last_regime.active_regime));
         accent = COL_SUB; tint = COL_CARD;
      }
      else if(!sc.location_ok)
      {
         title  = (sc.mode == 2) ? "HUNTING A LIQUIDITY SWEEP" : "WAITING FOR PULLBACK";
         reason = sc.reason;
         accent = COL_AMB; tint = TINT_AMB;
      }
      else if(!sc.trigger_ok)
      {
         title  = (sc.mode == 2) ? "SWEEP SEEN - AWAITING CONFIRMATION" : "ARMED - WAITING FOR M1 TRIGGER";
         reason = sc.reason;
         accent = COL_AMB; tint = TINT_AMB;
      }
      else if(!sc.entry_ready)
      {
         title  = "SETUP FOUND - FILTERED OUT";
         reason = sc.reason;
         accent = COL_AMB; tint = TINT_AMB;
      }
      else
      {
         title  = StringFormat("TRIGGER READY - GRADE %s", sc.grade);
         reason = StringFormat("%s %s. Entry fires on the next tick at %.2fx risk.", sc.mode_name, DirectionToString(sc.direction), sc.risk_mult);
         accent = COL_GRN; tint = TINT_GRN;
      }
   }

   //================================================================
   //  CHROME  (header, status pill, collapse, tabs)
   //================================================================
   int RenderChrome(void)
   {
      PutRect("HDR", m_x, m_y, m_width, 46, COL_CARD, COL_CARD);
      PutRect("HDR_LINE", m_x, m_y + 46, m_width, 1, COL_LINE, COL_LINE);
      PutText("TITLE", "XAU MEGA SCALPER", m_x + 14, m_y + 7, COL_TXT, 10, true);
      PutText("SUB", "M15 BIAS  >  M5 LOCATION  >  M1 TRIGGER", m_x + 14, m_y + 28, COL_MUTE, 7);

      // Run-state pill
      ENUM_EA_RUN_STATE rs = (m_exec_sm != NULL) ? m_exec_sm.GetRunState() : EA_STATE_STOPPED;
      bool locked = (m_exec_sm != NULL && m_exec_sm.IsSessionDisabled());
      string pill = "RUNNING";
      color  pill_fg = COL_GRN, pill_bg = TINT_GRN;
      if(locked)                       { pill = "LOCKED";   pill_fg = COL_RED; pill_bg = TINT_RED; }
      else if(rs == EA_STATE_STOPPED)  { pill = "STOPPED";  pill_fg = COL_RED; pill_bg = TINT_RED; }
      else if(rs == EA_STATE_STARTING) { pill = "STARTING"; pill_fg = COL_AMB; pill_bg = TINT_AMB; }

      int pill_w = 76;
      int pill_x = m_x + m_width - 14 - 24 - 6 - pill_w;
      PutRect("PILL", pill_x, m_y + 13, pill_w, 20, pill_bg, pill_fg);
      PutText("PILL_T", pill, pill_x + pill_w / 2, m_y + 23, pill_fg, 8, true, 2);

      // Collapse toggle
      PutButton("BTN_COLLAPSE", m_collapsed ? "+" : "-", m_x + m_width - 14 - 24, m_y + 11, 24, 24,
                COL_CARD2, COL_SUB, COL_LINE, 10);

      if(m_collapsed) return m_y + 56;

      // Tabs
      int tab_y = m_y + 54;
      int tab_w = (m_width - 28) / 2;
      bool t0 = (m_active_tab == TAB_SCALP);
      PutButton("TAB_0", "SCALP",  m_x + 14,         tab_y, tab_w, 26, t0 ? COL_CARD2 : COL_BG, t0 ? COL_TXT : COL_MUTE, t0 ? COL_CARD2 : COL_BG, 8);
      PutButton("TAB_1", "SYSTEM", m_x + 14 + tab_w, tab_y, tab_w, 26, t0 ? COL_BG : COL_CARD2, t0 ? COL_MUTE : COL_TXT, t0 ? COL_BG : COL_CARD2, 8);
      PutRect("TAB_UL", m_x + 14 + (t0 ? 0 : tab_w), tab_y + 24, tab_w, 2, COL_CYAN, COL_CYAN);
      PutRect("TAB_DIV", m_x + 14, tab_y + 26, m_width - 28, 1, COL_LINE, COL_LINE);
      return tab_y + 36;
   }

   //================================================================
   //  SCALP TAB BUILDING BLOCKS
   //================================================================
   int RenderVerdict(int cy)
   {
      int iw = m_width - 28;
      int h  = 66;
      string title, reason;
      color accent, tint;
      BuildVerdict(title, reason, accent, tint);

      PutRect("V_CARD", m_x + 14, cy, iw, h, tint, tint);
      PutRect("V_ACC",  m_x + 14, cy, 3, h, accent, accent);
      PutText("V_TITLE", title, m_x + 28, cy + 9, accent, 10, true);

      string l1, l2;
      WrapTwo(reason, 56, l1, l2);
      PutText("V_R1", l1, m_x + 28, cy + 31, COL_SUB, 8);
      PutText("V_R2", l2, m_x + 28, cy + 46, COL_SUB, 8);

      SScalpState sc = m_last_scalp;
      string bias = "NONE";
      color  bias_col = COL_MUTE;
      if(sc.direction == DIR_LONG)       { bias = "LONG";  bias_col = COL_GRN; }
      else if(sc.direction == DIR_SHORT) { bias = "SHORT"; bias_col = COL_RED; }
      PutText("V_BIAS_L", "M15 BIAS", m_x + 14 + iw - 12, cy + 9, COL_MUTE, 7, false, 1);
      PutText("V_BIAS", bias, m_x + 14 + iw - 12, cy + 21, bias_col, 10, true, 1);

      return cy + h + 8;
   }

   int RenderPipeline(int cy)
   {
      int iw  = m_width - 28;
      int gap = 6;
      int cw  = (iw - 3 * gap) / 4;
      int ch  = 44;
      const SScalpState sc = m_last_scalp;
      const SRegimeState rg = m_last_regime;

      string labels[4];
      string vals[4];
      int    stg[4];
      labels[0] = "REGIME";
      labels[1] = sc.regime_ok ? sc.loc_title : "LOCATION";
      labels[2] = sc.regime_ok ? sc.trg_title : "TRIGGER";
      labels[3] = "EXECUTION";

      // 1. Regime (tradable = trend, or range while sweeps are enabled)
      vals[0] = RegimeShort(rg.active_regime);
      stg[0]  = sc.regime_ok ? ST_PASS : ((rg.active_regime == REGIME_CHAOS) ? ST_BLOCK : ST_WAIT);

      // 2. Location / liquidity level
      if(!sc.regime_ok) { vals[1] = "--"; stg[1] = ST_IDLE; }
      else
      {
         vals[1] = StringFormat("%d / 3", sc.loc_n);
         stg[1]  = sc.location_ok ? ST_PASS : ST_WAIT;
      }

      // 3. Trigger / confirmation (grey until the location is valid, but the count is still shown)
      if(!sc.regime_ok) { vals[2] = "--"; stg[2] = ST_IDLE; }
      else
      {
         vals[2] = StringFormat("%d / 2", sc.trg_n);
         stg[2]  = sc.trigger_ok ? (sc.location_ok ? ST_PASS : ST_IDLE) : (sc.location_ok ? ST_WAIT : ST_IDLE);
      }

      // 4. Execution
      string blk_name = "";
      string blk = LiveBlock(blk_name);
      ENUM_EA_RUN_STATE rs = (m_exec_sm != NULL) ? m_exec_sm.GetRunState() : EA_STATE_STOPPED;
      if(HasPosition())                                            { vals[3] = "IN TRADE"; stg[3] = ST_LIVE; }
      else if(m_exec_sm != NULL && m_exec_sm.IsSessionDisabled())  { vals[3] = "LOCKED";   stg[3] = ST_BLOCK; }
      else if(rs != EA_STATE_RUNNING)                              { vals[3] = "PAUSED";   stg[3] = ST_WAIT; }
      else if(blk != "")                                           { vals[3] = blk_name;   stg[3] = ST_BLOCK; }
      else                                                         { vals[3] = "READY";    stg[3] = ST_PASS; }

      for(int i = 0; i < 4; i++)
      {
         int x = m_x + 14 + i * (cw + gap);
         PutRect(StringFormat("PL_%d", i), x, cy, cw, ch, COL_CARD, COL_CARD);
         PutText(StringFormat("PL_L%d", i), labels[i], x + 8, cy + 7, COL_MUTE, 7, true);
         PutText(StringFormat("PL_V%d", i), vals[i], x + 8, cy + 21, StageTextColor(stg[i]), 9, true);
         PutRect(StringFormat("PL_B%d", i), x, cy + ch - 3, cw, 3, StageColor(stg[i]), StageColor(stg[i]));
      }
      return cy + ch + 12;
   }

   // One checklist row: status square + label (left) and measured value (right)
   void CheckRow(const string key, const string label, const string value, bool pass, bool active,
                 int x, int y, int w)
   {
      color dot = !active ? COL_DIM : (pass ? COL_GRN : COL_RED);
      color lab = !active ? COL_MUTE : (pass ? COL_TXT : COL_SUB);
      color val = !active ? COL_MUTE : (pass ? COL_GRN : COL_RED);
      PutRect("CK_D_" + key, x, y + 5, 7, 7, dot, dot);
      PutText("CK_L_" + key, label, x + 15, y + 1, lab, 8);
      PutText("CK_V_" + key, value, x + w, y + 1, val, 8, false, 1);
   }

   int RenderChecklists(int cy)
   {
      int iw   = m_width - 28;
      int colw = (iw - 12) / 2;
      int x0   = m_x + 14;
      int x1   = m_x + 14 + colw + 12;
      const SScalpState sc = m_last_scalp;
      bool act = sc.regime_ok;

      PutText("CK_H0", sc.loc_title, x0, cy, COL_MUTE, 7, true);
      PutText("CK_H1", sc.trg_title, x1, cy, COL_MUTE, 7, true);
      PutText("CK_MODE", sc.regime_ok ? sc.mode_name : "", m_x + 14 + iw, cy, COL_CYAN, 7, true, 1);
      PutRect("CK_DIV", m_x + 14 + colw + 5, cy, 1, 14 + 3 * 18, COL_LINE, COL_LINE);
      int ry = cy + 15;

      string keys[6] = {"A", "B", "C", "D", "E", "F"};
      for(int i = 0; i < 6; i++)
      {
         int col_x = (i < 3) ? x0 : x1;
         int row_y = ry + (i % 3) * 18;
         CheckRow(keys[i], sc.ck_label[i], sc.ck_value[i], sc.ck_pass[i], act, col_x, row_y, colw);
      }

      PutText("CK_NOTE", Clip(sc.rule, 84), m_x + 14, ry + 56, COL_MUTE, 7);
      return ry + 56 + 18;
   }

   void GateChip(const string key, const string label, const string value, int st, int x, int y)
   {
      color c = StageColor(st);
      PutRect("GT_D_" + key, x, y + 3, 7, 7, c, c);
      PutText("GT_L_" + key, label, x + 13, y, COL_MUTE, 7, true);
      PutText("GT_V_" + key, value, x + 13, y + 12, (st == ST_IDLE) ? COL_MUTE : COL_TXT, 8);
   }

   int RenderContextGrid(int cy)
   {
      int iw = m_width - 28;
      int cw = iw / 5;
      const SGateResults g = m_last_gates;
      const SScalpState sc = m_last_scalp;
      bool in_trade = HasPosition();
      bool have_dir = (sc.regime_ok && sc.direction != DIR_NONE);

      PutText("GS_H", "CONTEXT & GATES", m_x + 14, cy, COL_MUTE, 7, true);
      PutText("GS_HR", have_dir ? StringFormat("grade %s  x%.2f risk", sc.grade, sc.risk_mult) : "", m_x + 14 + iw, cy, COL_SUB, 7, false, 1);
      int y1 = cy + 15;
      int y2 = y1 + 30;
      int x  = m_x + 14;

      // ---- Row 1: market context --------------------------------------
      string bias = (sc.h1_bias > 0) ? "UP" : ((sc.h1_bias < 0) ? "DOWN" : "NEUTRAL");
      int bias_st = !have_dir ? ST_IDLE : (!sc.ctx_bias_ok ? ST_BLOCK : (((int)sc.direction == sc.h1_bias) ? ST_PASS : ST_WAIT));
      GateChip("B", "H1 BIAS", bias, bias_st, x, y1);

      string room = (sc.room_atr >= 50.0) ? "clear" : StringFormat("%.1f %s", sc.room_atr, Clip(sc.room_level, 7));
      GateChip("R", "ROOM", room, !have_dir ? ST_IDLE : (sc.ctx_room_ok ? ST_PASS : ST_BLOCK), x + cw, y1);

      GateChip("I", "RSI M1", StringFormat("%.0f", sc.rsi_m1), !have_dir ? ST_IDLE : (sc.ctx_rsi_ok ? ST_PASS : ST_BLOCK), x + 2 * cw, y1);
      GateChip("V", "ATR M5", StringFormat("$%.2f", sc.atr_usd), sc.ctx_vol_ok ? ST_PASS : (sc.atr_usd > 0.0 ? ST_BLOCK : ST_IDLE), x + 3 * cw, y1);

      int grade_st = !have_dir ? ST_IDLE : ((sc.grade_pts >= 3) ? ST_PASS : ((sc.grade_pts == 2) ? ST_WAIT : ST_IDLE));
      GateChip("G", "GRADE", have_dir ? StringFormat("%s (%d pts)", sc.grade, sc.grade_pts) : "--", grade_st, x + 4 * cw, y1);

      // ---- Row 2: execution gates ----------------------------------------
      GateChip("S", "SESSION", g.g2_session ? sc.session_name : "CLOSED", g.g2_session ? ((sc.session_id == 3 || sc.session_id == 2) ? ST_PASS : ST_WAIT) : ST_BLOCK, x, y2);
      GateChip("P", "SPREAD",  StringFormat("%.2f/%.2f", g.spread_atr_ratio, g.spread_limit_ratio), g.g3_spread ? ST_PASS : ST_BLOCK, x + cw, y2);
      GateChip("N", "NEWS",    g.g4_news ? "CLEAR" : "BLACKOUT", g.g4_news ? ST_PASS : ST_BLOCK, x + 2 * cw, y2);
      GateChip("K", "RISK",    StringFormat("%d/%d pos", g.open_positions, g.max_positions),
               in_trade ? ST_LIVE : (g.g6_risk ? ST_PASS : ST_BLOCK), x + 3 * cw, y2);
      GateChip("M", "MODE",    sc.regime_ok ? ((sc.mode == 2) ? "SWEEP" : "TREND") : "--", sc.regime_ok ? ST_LIVE : ST_IDLE, x + 4 * cw, y2);
      return y2 + 34;
   }

   int RenderFunnel(int cy)
   {
      int iw = m_width - 28;
      const SFunnel f = m_last_funnel;

      PutText("FN_H", "TODAY'S FUNNEL", m_x + 14, cy, COL_MUTE, 7, true);
      PutText("FN_HR", "closed M1 bars, server day", m_x + 14 + iw, cy, COL_MUTE, 7, false, 1);

      string names[7];
      int    cnt[7];
      int passed_filters = MathMax(0, f.trigger_ok - f.ctx_blocked - f.cooldown_blocked);
      names[0] = "M1 bars scanned";   cnt[0] = f.scanned;
      names[1] = "Passed all gates";  cnt[1] = f.gates_passed;
      names[2] = "Regime tradable";   cnt[2] = f.regime_ok;
      names[3] = "Location / level";  cnt[3] = f.location_ok;
      names[4] = "Trigger / sweep";   cnt[4] = f.trigger_ok;
      names[5] = "Passed filters";    cnt[5] = passed_filters;
      names[6] = "Entries sent";      cnt[6] = f.dispatched;

      int base    = MathMax(1, f.scanned);
      int lab_w   = 112;
      int track_x = m_x + 14 + lab_w;
      int track_w = iw - lab_w - 44;
      int y = cy + 16;

      for(int i = 0; i < 7; i++)
      {
         color fill = (i == 6) ? COL_GRN : COL_CYAN_D;
         int fw = (cnt[i] > 0) ? (int)MathMax(2.0, MathRound((double)track_w * (double)cnt[i] / (double)base)) : 1;
         PutText(StringFormat("FN_L%d", i), names[i], m_x + 14, y, (i == 6) ? COL_TXT : COL_SUB, 8);
         PutRect(StringFormat("FN_T%d", i), track_x, y + 5, track_w, 6, COL_CARD2, COL_CARD2);
         PutRect(StringFormat("FN_F%d", i), track_x, y + 5, fw, 6, (cnt[i] > 0) ? fill : COL_CARD2, (cnt[i] > 0) ? fill : COL_CARD2);
         PutText(StringFormat("FN_C%d", i), IntegerToString(cnt[i]), m_x + 14 + iw, y, (i == 6 && cnt[i] > 0) ? COL_GRN : COL_TXT, 8, true, 1);
         y += 16;
      }

      // Where the rest went
      string parts = "";
      int no_trend = MathMax(0, f.gates_passed - f.regime_ok);
      if(f.session_blocked > 0) parts += StringFormat("Session %d  ", f.session_blocked);
      if(f.spread_blocked > 0)  parts += StringFormat("Spread %d  ", f.spread_blocked);
      if(f.news_blocked > 0)    parts += StringFormat("News %d  ", f.news_blocked);
      if(f.regime_blocked > 0)  parts += StringFormat("Chaos/dwell %d  ", f.regime_blocked);
      if(f.risk_blocked > 0)    parts += StringFormat("Risk %d  ", f.risk_blocked);
      if(f.exec_blocked > 0)    parts += StringFormat("Exec %d  ", f.exec_blocked);
      if(f.warmup_blocked > 0)  parts += StringFormat("Warmup %d  ", f.warmup_blocked);
      if(no_trend > 0)          parts += StringFormat("No-setup-regime %d  ", no_trend);
      if(f.ctx_blocked > 0)     parts += StringFormat("Filters %d  ", f.ctx_blocked);
      if(f.cooldown_blocked > 0) parts += StringFormat("Cooldown/cap %d  ", f.cooldown_blocked);
      if(f.in_trade > 0)        parts += StringFormat("In-trade %d  ", f.in_trade);
      if(parts == "") parts = (f.scanned == 0) ? "Waiting for the first closed M1 bar" : "No blocks recorded";

      string l1, l2;
      if(f.sweep_entries > 0) parts += StringFormat("| sweep entries %d", f.sweep_entries);
      WrapTwo("Dropped at: " + parts, 78, l1, l2);
      PutText("FN_X1", l1, m_x + 14, y + 2, COL_MUTE, 7);
      PutText("FN_X2", l2, m_x + 14, y + 14, COL_MUTE, 7);
      return y + (l2 == "" ? 20 : 32);
   }

   int RenderPositionStrip(int cy)
   {
      int iw = m_width - 28;
      int h  = 48;
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eqt = AccountInfoDouble(ACCOUNT_EQUITY);
      STradeStats st;
      st.net_profit = 0.0; st.wins = 0; st.losses = 0; st.total_trades = 0;
      if(m_trade_mgr != NULL) st = m_trade_mgr.GetGlobalStats();

      PutRect("PS_CARD", m_x + 14, cy, iw, h, COL_CARD, COL_CARD);

      if(HasPosition())
      {
         SPositionTrack pos = m_trade_mgr.GetCurrentPosition();
         double pnl = 0.0;
         if(PositionSelectByTicket(pos.ticket)) pnl = PositionGetDouble(POSITION_PROFIT);
         double px  = (pos.direction == DIR_LONG) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double pts = (_Point > 0.0) ? ((pos.direction == DIR_LONG) ? (px - pos.entry_price) : (pos.entry_price - px)) / _Point : 0.0;
         color  dc  = (pos.direction == DIR_LONG) ? COL_GRN : COL_RED;
         color  pc  = (pnl >= 0.0) ? COL_GRN : COL_RED;
         string stage = "INITIAL";
         if(pos.stage == STAGE_1_BREAKEVEN) stage = "BREAK-EVEN";
         else if(pos.stage == STAGE_2_PARTIAL_CLOSE) stage = "PARTIAL";
         else if(pos.stage == STAGE_3_ATR_TRAIL) stage = "ATR TRAIL";

         string mtag = (pos.mode == 2) ? "SWEEP" : ((pos.mode == 1) ? "TREND" : "M5");
         PutText("PS_A", StringFormat("%s  %.2f lots  [%s]", DirectionToString(pos.direction), pos.current_lots, mtag), m_x + 26, cy + 8, dc, 9, true);
         PutText("PS_B", StringFormat("%s  (%+.0f pts)", Money(pnl), pts), m_x + 14 + iw - 12, cy + 8, pc, 9, true, 1);
         PutText("PS_C", StringFormat("Entry %.2f   SL %.2f   Stage: %s", pos.entry_price, pos.current_sl, stage), m_x + 26, cy + 29, COL_SUB, 8);
         PutText("PS_D", "", m_x + 14 + iw - 12, cy + 29, COL_SUB, 8, false, 1);
      }
      else
      {
         double flt = eqt - bal;
         PutText("PS_A", "No open position", m_x + 26, cy + 8, COL_SUB, 9, true);
         PutText("PS_B", StringFormat("Equity $%.2f", eqt), m_x + 14 + iw - 12, cy + 8, COL_TXT, 9, true, 1);
         PutText("PS_C", StringFormat("Floating %s   Closed %s", Money(flt), Money(st.net_profit)), m_x + 26, cy + 29, COL_SUB, 8);
         PutText("PS_D", StringFormat("W/L %d/%d", st.wins, st.losses), m_x + 14 + iw - 12, cy + 29, COL_SUB, 8, false, 1);
      }
      return cy + h + 10;
   }

   int RenderControls(int cy)
   {
      int iw = m_width - 28;
      int gap = 8;
      int bw = (iw - 2 * gap) / 3;
      int bh = 30;
      ENUM_EA_RUN_STATE rs = (m_exec_sm != NULL) ? m_exec_sm.GetRunState() : EA_STATE_STOPPED;
      bool running = (rs == EA_STATE_RUNNING);
      bool locked  = (m_exec_sm != NULL && m_exec_sm.IsSessionDisabled());
      int x = m_x + 14;

      // The relevant button is bright, the redundant one is quiet
      PutButton("BTN_START", locked ? "UNLOCK" : "START", x, cy, bw, bh,
                (running && !locked) ? COL_CARD2 : C'18,110,80', (running && !locked) ? COL_MUTE : clrWhite,
                (running && !locked) ? COL_LINE : COL_GRN);
      PutButton("BTN_STOP", "STOP", x + bw + gap, cy, bw, bh,
                running ? C'140,40,48' : COL_CARD2, running ? clrWhite : COL_MUTE, running ? COL_RED : COL_LINE);

      if(m_close_all_confirming)
         PutButton("BTN_CLOSE_ALL", "CONFIRM?", x + 2 * (bw + gap), cy, bw, bh, C'200,30,60', clrWhite, COL_RED);
      else
         PutButton("BTN_CLOSE_ALL", "CLOSE ALL", x + 2 * (bw + gap), cy, bw, bh,
                   HasPosition() ? C'110,36,44' : COL_CARD2, HasPosition() ? clrWhite : COL_MUTE, HasPosition() ? COL_RED : COL_LINE);
      return cy + bh + 14;
   }

   //================================================================
   //  SCALP TAB
   //================================================================
   int RenderScalpTab(int cy)
   {
      cy = RenderVerdict(cy);
      cy = RenderPipeline(cy);
      if(m_collapsed) return cy;
      cy = RenderChecklists(cy);
      cy = RenderContextGrid(cy);
      cy = RenderFunnel(cy);
      cy = RenderPositionStrip(cy);
      return cy;
   }

   //================================================================
   //  SYSTEM TAB
   //================================================================
   int Header(const string key, const string title, const string right, int cy)
   {
      int iw = m_width - 28;
      PutText("H_" + key, title, m_x + 14, cy, COL_MUTE, 7, true);
      PutText("HR_" + key, right, m_x + 14 + iw, cy, COL_MUTE, 7, false, 1);
      return cy + 15;
   }

   void KV(const string key, const string k, const string v, color vc, int x, int y, int w)
   {
      PutText("KV_K_" + key, k, x, y, COL_SUB, 8);
      PutText("KV_V_" + key, v, x + w, y, vc, 8, true, 1);
   }

   int RenderSystemTab(int cy)
   {
      int iw   = m_width - 28;
      int colw = (iw - 12) / 2;
      int x0   = m_x + 14;
      int x1   = m_x + 14 + colw + 12;
      const SRegimeState r = m_last_regime;
      const SGateResults g = m_last_gates;

      // ---- Regime -----------------------------------------------------
      cy = Header("REG", "REGIME ENGINE", "M15 classification, M5 close", cy);
      bool persist_ok = (r.persist_count >= r.persist_required);
      KV("raw", "Raw",         RegimeToString(r.raw_regime),    RegimeColor(r.raw_regime),    x0, cy,      colw);
      KV("act", "Active",      RegimeToString(r.active_regime), RegimeColor(r.active_regime), x0, cy + 16, colw);
      KV("per", "Persistence", StringFormat("%d / %d", r.persist_count, r.persist_required),  persist_ok ? COL_GRN : COL_AMB, x0, cy + 32, colw);
      KV("dwl", "Dwell",       StringFormat("%d / %d", r.dwell_count, r.dwell_required),      r.dwell_ok ? COL_GRN : COL_AMB, x0, cy + 48, colw);
      KV("chs", "Chaos",       r.primary_chaos_reason == "NONE" ? "CLEAN" : r.primary_chaos_reason, r.primary_chaos_reason == "NONE" ? COL_GRN : COL_RED, x1, cy,      colw);
      KV("atr", "ATR M5",      StringFormat("%.2f (x%.2f)", r.atr_m5, r.atr_ratio),            COL_TXT, x1, cy + 16, colw);
      KV("adx", "ADX M15",     StringFormat("%.1f", r.adx_m15),                                (r.adx_m15 > 25.0) ? COL_GRN : COL_SUB, x1, cy + 32, colw);
      KV("vws", "VWAP slope",  StringFormat("%+.3f", r.vwap_slope),                            COL_TXT, x1, cy + 48, colw);
      cy += 70;
      PutRect("SY_D1", m_x + 14, cy, iw, 1, COL_LINE, COL_LINE);
      cy += 10;

      // ---- Trend score (diagnostic only) ------------------------------
      cy = Header("SCO", StringFormat("TREND SCORE   %d / 100", r.total_trend_score), "diagnostic only - never gates a trade", cy);
      string sn[6];
      int    sv[6];
      int    sm[6];
      sn[0] = "M15 EMA alignment"; sv[0] = r.score_ema_alignment; sm[0] = 20;
      sn[1] = "M15 ADX strength";  sv[1] = r.score_adx;           sm[1] = 20;
      sn[2] = "VWAP position";     sv[2] = r.score_vwap_pos;      sm[2] = 15;
      sn[3] = "VWAP slope";        sv[3] = r.score_vwap_slope;    sm[3] = 15;
      sn[4] = "M5 structure";      sv[4] = r.score_structure;     sm[4] = 15;
      sn[5] = "M5 momentum";       sv[5] = r.score_momentum;      sm[5] = 15;

      int lab_w   = 112;
      int track_x = m_x + 14 + lab_w;
      int track_w = iw - lab_w - 50;
      for(int i = 0; i < 6; i++)
      {
         int fw = (sv[i] > 0) ? (int)MathMax(2.0, MathRound((double)track_w * (double)sv[i] / (double)sm[i])) : 1;
         PutText(StringFormat("SC_L%d", i), sn[i], m_x + 14, cy, COL_SUB, 8);
         PutRect(StringFormat("SC_T%d", i), track_x, cy + 5, track_w, 6, COL_CARD2, COL_CARD2);
         PutRect(StringFormat("SC_F%d", i), track_x, cy + 5, fw, 6, (sv[i] > 0) ? COL_CYAN_D : COL_CARD2, (sv[i] > 0) ? COL_CYAN_D : COL_CARD2);
         PutText(StringFormat("SC_V%d", i), StringFormat("%d / %d", sv[i], sm[i]), m_x + 14 + iw, cy, COL_TXT, 8, true, 1);
         cy += 16;
      }
      cy += 4;
      PutRect("SY_D2", m_x + 14, cy, iw, 1, COL_LINE, COL_LINE);
      cy += 10;

      // ---- Gates G1..G7 -------------------------------------------------
      cy = Header("GAT", "EXECUTION GATES", g.all_passed ? "all passed" : ("first fail: " + g.fail_gate), cy);
      string gl[7] = {"G1 WARM", "G2 SESS", "G3 SPRD", "G4 NEWS", "G5 REGM", "G6 RISK", "G7 EXEC"};
      bool   gp[7];
      gp[0] = g.g1_warmup; gp[1] = g.g2_session; gp[2] = g.g3_spread; gp[3] = g.g4_news;
      gp[4] = g.g5_regime; gp[5] = g.g6_risk;    gp[6] = g.g7_execution;
      int gw = iw / 7;
      for(int j = 0; j < 7; j++)
      {
         color c = gp[j] ? COL_GRN : COL_RED;
         PutRect(StringFormat("G_D%d", j), m_x + 14 + j * gw, cy + 3, 7, 7, c, c);
         PutText(StringFormat("G_L%d", j), gl[j], m_x + 14 + j * gw + 12, cy, gp[j] ? COL_SUB : COL_RED, 7, true);
      }
      cy += 18;
      string gdetail = g.all_passed ? StringFormat("History M15 %d/%d   M5 %d/%d   M1 %d/%d", g.m15_bars_have, g.m15_bars_req, g.m5_bars_have, g.m5_bars_req, g.m1_bars_have, g.m1_bars_req)
                                    : Clip(g.fail_reason, 80);
      PutText("G_DET", gdetail, m_x + 14, cy, g.all_passed ? COL_MUTE : COL_SUB, 7);
      cy += 20;
      PutRect("SY_D3", m_x + 14, cy, iw, 1, COL_LINE, COL_LINE);
      cy += 10;

      // ---- Legacy M5 engines ---------------------------------------------
      cy = Header("ENG", "M5-CLOSE ENGINES", "regime-routed, unchanged", cy);
      cy = EngineRow("A", "A  Trend-Pullback", m_last_dry_a, cy);
      cy = EngineRow("B", "B  Breakout",       m_last_dry_b, cy);
      cy = EngineRow("C", "C  Mean-Reversion", m_last_dry_c, cy);
      cy += 4;
      PutRect("SY_D4", m_x + 14, cy, iw, 1, COL_LINE, COL_LINE);
      cy += 10;

      // ---- Latest decision --------------------------------------------------
      cy = Header("LOG", "LATEST DECISION", "MQL5/Files/XAU_MEGA_DECISIONS.log", cy);
      string latest = "No decisions logged yet";
      color  lc = COL_MUTE;
      if(m_dec_logger != NULL && m_dec_logger.GetRecentCount() > 0)
      {
         latest = m_dec_logger.GetRecentLine(0);
         lc = (StringFind(latest, "TRADE:") >= 0 || StringFind(latest, "SCALP_TRIGGER") >= 0) ? COL_GRN : COL_SUB;
      }
      string l1, l2;
      WrapTwo(latest, 80, l1, l2);
      PutText("LG_1", l1, m_x + 14, cy, lc, 7);
      PutText("LG_2", l2, m_x + 14, cy + 12, lc, 7);
      cy += (l2 == "" ? 22 : 34);
      return cy;
   }

   int EngineRow(const string key, const string name, const SDrySignal &dry, int cy)
   {
      string status;
      color  col;
      if(dry.setup_found)                     { status = "CANDIDATE";                                       col = COL_GRN; }
      else if(dry.primary_rejection_reason != "") { status = Clip(dry.primary_rejection_reason, 44);         col = COL_SUB; }
      else                                    { status = "no setup";                                         col = COL_MUTE; }
      PutText("EN_L" + key, name, m_x + 14, cy, COL_TXT, 8);
      PutText("EN_V" + key, status, m_x + m_width - 14, cy + 1, col, 7, false, 1);
      return cy + 16;
   }

public:
   CPanelGUI(void) : m_chart_id(0),
                     m_subwin(0),
                     m_trade_mgr(NULL),
                     m_exec_sm(NULL),
                     m_dec_logger(NULL),
                     m_x(18),
                     m_y(22),
                     m_width(392),
                     m_height(520),
                     m_active_tab(TAB_SCALP),
                     m_collapsed(false),
                     m_close_all_confirming(false),
                     m_confirm_tick(0),
                     m_is_dragging(false),
                     m_drag_offset_x(0),
                     m_drag_offset_y(0),
                     m_layout_key(-1),
                     m_have_data(false),
                     m_c_n(0)
   {
   }

   ~CPanelGUI(void)
   {
   }

   void Init(CTradeManager *trade_mgr, CExecutionStateMachine *exec_sm, CDecisionLogger *dec_logger)
   {
      m_chart_id   = ChartID();
      m_subwin     = 0;
      m_trade_mgr  = trade_mgr;
      m_exec_sm    = exec_sm;
      m_dec_logger = dec_logger;
      m_active_tab = TAB_SCALP;
      m_collapsed  = false;
      m_is_dragging = false;
      m_close_all_confirming = false;
      m_have_data  = false;
      m_layout_key = -1;
      m_c_n        = 0;

      ChartSetInteger(m_chart_id, CHART_EVENT_MOUSE_MOVE, true);
      ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);

      // Restore the last dragged position
      string gv_x = StringFormat("XMS_POS_X_%I64d", m_chart_id);
      string gv_y = StringFormat("XMS_POS_Y_%I64d", m_chart_id);
      if(GlobalVariableCheck(gv_x)) m_x = (int)GlobalVariableGet(gv_x);
      if(GlobalVariableCheck(gv_y)) m_y = (int)GlobalVariableGet(gv_y);

      // Remove anything left by earlier panel versions
      ObjectsDeleteAll(m_chart_id, GUI_PREFIX);
   }

   void Destroy(void)
   {
      if(m_chart_id == 0) return;
      ChartSetInteger(m_chart_id, CHART_EVENT_MOUSE_MOVE, false);
      ObjectsDeleteAll(m_chart_id, GUI_PREFIX);
      m_c_n = 0;
      ChartRedraw(m_chart_id);
   }

   //+------------------------------------------------------------------+
   //| Draw everything from the cached telemetry                        |
   //+------------------------------------------------------------------+
   void Render(void)
   {
      if(!m_have_data || m_chart_id == 0) return;

      if(m_close_all_confirming && GetTickCount() > m_confirm_tick)
         m_close_all_confirming = false;

      // A different widget set (tab / collapsed / trade open) -> rebuild in z-order
      int key = (int)m_active_tab + (m_collapsed ? 10 : 0) + (HasPosition() ? 100 : 0);
      if(key != m_layout_key)
      {
         ObjectsDeleteAll(m_chart_id, GUI_PREFIX);
         m_c_n = 0;
         m_layout_key = key;
      }

      BeginFrame();

      // Background first (z-order = creation order); final height is applied at the end
      PutRect("BG", m_x, m_y, m_width, m_height, COL_BG, COL_LINE);

      int cy = RenderChrome();
      if(m_active_tab == TAB_SCALP || m_collapsed)
         cy = RenderScalpTab(cy);
      else
         cy = RenderSystemTab(cy);

      if(!m_collapsed)
         cy = RenderControls(cy);

      m_height = (cy - m_y) + (m_collapsed ? 4 : 0);
      PutRect("BG", m_x, m_y, m_width, m_height, COL_BG, COL_LINE);

      EndFrame();
      ChartRedraw(m_chart_id);
   }

   //+------------------------------------------------------------------+
   //| Master refresh call (signature extended with scalp + funnel)     |
   //+------------------------------------------------------------------+
   void Update(const SRegimeState &regime,
               const SGateResults &gates,
               const SSignalResult &last_signal,
               const SStrategyDiagnostic &diagnostic,
               const SDrySignal &dry_a,
               const SDrySignal &dry_b,
               const SDrySignal &dry_c,
               const SScalpState &scalp,
               const SFunnel &funnel)
   {
      m_last_regime     = regime;
      m_last_gates      = gates;
      m_last_signal     = last_signal;
      m_last_diagnostic = diagnostic;
      m_last_dry_a      = dry_a;
      m_last_dry_b      = dry_b;
      m_last_dry_c      = dry_c;
      m_last_scalp      = scalp;
      m_last_funnel     = funnel;
      m_have_data       = true;

      Render();
   }

   //+------------------------------------------------------------------+
   //| Click & drag                                                     |
   //+------------------------------------------------------------------+
   bool OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
   {
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
               GlobalVariableSet(StringFormat("XMS_POS_X_%I64d", m_chart_id), (double)m_x);
               GlobalVariableSet(StringFormat("XMS_POS_Y_%I64d", m_chart_id), (double)m_y);
            }
            return false;
         }

         if(!m_is_dragging)
         {
            // Header strip, but not over the collapse button
            if(mouse_x >= m_x && mouse_x <= m_x + m_width - 44 &&
               mouse_y >= m_y && mouse_y <= m_y + 46)
            {
               m_is_dragging   = true;
               m_drag_offset_x = mouse_x - m_x;
               m_drag_offset_y = mouse_y - m_y;
               return true;
            }
            return false;
         }

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
            Render();
         }
         return true;
      }

      if(id == CHARTEVENT_OBJECT_CLICK)
      {
         if(StringFind(sparam, GUI_PREFIX) != 0) return false;

         if(sparam == GUI_PREFIX + "TAB_0")
         {
            m_active_tab = TAB_SCALP;
            Render();
            return true;
         }
         if(sparam == GUI_PREFIX + "TAB_1")
         {
            m_active_tab = TAB_SYSTEM;
            Render();
            return true;
         }
         if(sparam == GUI_PREFIX + "BTN_COLLAPSE")
         {
            m_collapsed = !m_collapsed;
            Render();
            return true;
         }

         if(sparam == GUI_PREFIX + "BTN_START")
         {
            if(m_exec_sm != NULL)
            {
               m_exec_sm.SetRunState(EA_STATE_RUNNING);
               if(m_dec_logger != NULL) m_dec_logger.AddRecentLine("START EA -> entries enabled");
            }
            ObjectSetInteger(m_chart_id, sparam, OBJPROP_STATE, false);
            Render();
            return true;
         }

         if(sparam == GUI_PREFIX + "BTN_STOP")
         {
            if(m_exec_sm != NULL)
            {
               m_exec_sm.SetRunState(EA_STATE_STOPPED);
               if(m_dec_logger != NULL) m_dec_logger.AddRecentLine("STOP EA -> new entries paused");
            }
            ObjectSetInteger(m_chart_id, sparam, OBJPROP_STATE, false);
            Render();
            return true;
         }

         if(sparam == GUI_PREFIX + "BTN_CLOSE_ALL")
         {
            if(!m_close_all_confirming)
            {
               m_close_all_confirming = true;
               m_confirm_tick = GetTickCount() + 5000;
               if(m_dec_logger != NULL) m_dec_logger.AddRecentLine("Close all requested -> confirm within 5s");
            }
            else
            {
               m_close_all_confirming = false;
               if(m_trade_mgr != NULL)
               {
                  string report = "";
                  m_trade_mgr.CloseAllNow(report);
                  if(m_dec_logger != NULL) m_dec_logger.AddRecentLine("CLOSED ALL: " + report);
               }
            }
            ObjectSetInteger(m_chart_id, sparam, OBJPROP_STATE, false);
            Render();
            return true;
         }
      }

      return false;
   }
};
