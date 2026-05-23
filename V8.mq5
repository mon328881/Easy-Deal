//+------------------------------------------------------------------+
//|                          太极·夔牛 V8 Adaptive (ATR+ADX 双引擎).mq5|
//|  - 状态识别: ATR + ADX 双指标 (M15)                               |
//|  - 震荡态  : 双向网格 (固定止损 + 篮子止盈)                        |
//|  - 趋势态  : 突破单    (分级动态止损: 保本 -> ATR 移动止损)        |
//|  作者: Quant Engineer (精炼自 复刻牛.mq5)                          |
//+------------------------------------------------------------------+
#property copyright "太极·夔牛 V8 Adaptive"
#property version   "8.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;
CAccountInfo  accInfo;
CSymbolInfo   symInfo;

//==================================================================
// 输入参数
//==================================================================
// ============================================================
// V8.3 双周期过滤 (基于黄金走势图分析: M15 周期无法捕捉 30min 内的真实趋势):
//   原理: H1 EMA50 vs EMA200 确定大方向, M15 状态机仅在大方向同向时触发
//   - 解决「在 H1 大涨中被 M15 假反弹诱导做空」的灾难性入场
//   - 增加 H1 ADX 门槛 (默认 20), 大周期不够强时全停 (例如盘整日)
//   预期: 全年笔数再下降 30-50%, 但每笔都是「大小周期共振」, 胜率显著提升
//
// V8.2.1 出场逻辑修复 (基于 V8.2 回测 12笔/50%胜率/盈亏比0.70 的诊断):
//   - InpBO_SL_ATR_Mult       2.0 → 1.5  (单笔最大亏损 -25%)
//   - InpBO_BE_TriggerATR     1.0 → 1.5  (不再过早保本吐利润)
//   - InpBO_TrailStartATR     1.8 → 2.5  (让趋势真正发展再锁利)
//   - InpBO_TrailDistATR      1.5 → 0.8  (锁利后抓得更紧)
//
// V8.2 Trend-Only 重构 (基于 V8.1 回测 -97% 后的痛定思痛):
//   - 关掉网格 (网格在反复打耳光行情中两头挨打, 死亡螺旋)
//   - 状态防抖 1→3 根 K 线, ADX 门槛 22→25
//   - 「鞭打市场过滤器」: 1小时内状态切换 >3 次, 冻结 4 小时
//   - 「趋势冷启动」: 刚切入趋势态后 N 根 K 线内不开仓
//   - 「单趋势期最多 N 笔」: 防止反复入场
//   - 日亏熔断 3%, 回撤熔断 8%
// ============================================================

input group "=== [A] 总开关与归属 ==="
input long   InpMagic              = 20260522;   // EA 魔术号 (区分本 EA 持仓)
input string InpComment            = "KN_V8";    // 订单注释前缀
input bool   InpEnableGrid         = false;      // ★ V8.2: 默认关闭网格 (反复打耳光行情会爆仓)
input bool   InpEnableBreakout     = true;       // 启用趋势突破引擎
input int    InpSlippagePoints     = 50;         // 市价滑点 (点) | 黄金建议 50, 外汇 20

input group "=== [B] 资金管理与单笔风控 ==="
input double InpRiskPercent        = 1.0;        // 单笔风险占余额% (止损损失上限)
input double InpFixedLotFallback   = 0.01;       // 风险计算失败时的兜底手数
input double InpMaxLotPerTrade     = 1.0;        // 单笔最大手数硬上限
input double InpMaxMarginUsedPct   = 50.0;       // 保证金占用上限 (% of Balance)

input group "=== [C] 账户级熔断 ==="
input double InpDailyLossLimitPct  = 3.0;        // 单日最大亏损% (达成立即全平+冻结)
input double InpMaxDrawdownPct     = 8.0;        // 账户最大回撤% (V8.2 收紧到 8%)
input int    InpCircuitCooldownMin = 720;        // 熔断冷却分钟数
input bool   InpDailyLossForceClose = true;      // ★ 触发日亏限制时是否强制平掉所有本EA持仓

input group "=== [D] 市场状态识别 (ATR + ADX) - V8.2 收紧 ==="
input ENUM_TIMEFRAMES InpRegimeTF  = PERIOD_M15; // 状态识别周期
input int    InpADX_Period         = 14;         // ADX 周期
input double InpADX_RangeMax       = 20.0;       // ADX < 此值 → 震荡 (扩宽缓冲带)
input double InpADX_TrendMin       = 25.0;       // ADX ≥ 此值 → 趋势 (扩宽缓冲带, 提高入场门槛)
input int    InpATR_Period         = 14;         // ATR 周期
input int    InpATR_AvgLookback    = 20;         // ATR 均值回看根数
input double InpATR_HighVolMult    = 2.5;        // ATR > 均值 × 此值 → 极端波动(冻结)
input int    InpRegimeMinHoldBars  = 3;          // 状态确认最少持续 K 线 (★ V8.2: 1→3 强力防抖)

input group "=== [D2] 鞭打市场过滤器 (V8.2 新增) ==="
input bool   InpEnableWhipsawFilter = true;      // 启用鞭打市场过滤器
input int    InpWhipsawWindowMin   = 60;         // 检测窗口(分钟)
input int    InpWhipsawMaxSwitches = 3;          // 窗口内最多容忍 N 次状态切换
input int    InpWhipsawFreezeMin   = 240;        // 触发后冻结时长(分钟)

input group "=== [D3] H1 大趋势偏好过滤 (V8.3 新增, 解决周期错配) ==="
// 原理: M15/M5 看到的"趋势"在 H1 上可能只是震荡; 用 H1 EMA50 vs EMA200 判断
// 大方向, 仅允许在与 H1 偏好同方向时入场. 这能从根本上消除"在大涨中做空"
input bool   InpEnableH1Bias       = true;       // 启用 H1 大趋势偏好过滤
input ENUM_TIMEFRAMES InpH1_TF     = PERIOD_H1;  // 大趋势识别周期
input int    InpH1_FastEMA         = 50;         // 快线 EMA 周期
input int    InpH1_SlowEMA         = 200;        // 慢线 EMA 周期
input double InpH1_MinADX          = 20.0;       // H1 ADX 低于此值 → 视为无大趋势, 全停
input int    InpH1_ADX_Period      = 14;         // H1 ADX 周期

input group "=== [E] 网格引擎 (震荡态) - V8.1 安全化重构 ==="
input double InpGrid_SpacingATR    = 0.5;        // 网格层间距 = ATR × 此值
input int    InpGrid_MaxLevels     = 4;          // 单方向最大网格层数 (降为4层防爆)
input double InpGrid_LotMultiplier = 1.0;        // 网格手数倍率 (1.0=等手数, 强烈建议不要>1.1)
input double InpGrid_TP_ATR_Mult   = 1.0;        // 单笔止盈 = ATR × 此值 (单笔有TP, 无SL)
input double InpGrid_BasketTP_USD  = 30.0;       // 整篮浮盈达此(USD) → 全平 | 外汇改回 15
input double InpGrid_BasketSL_Pct  = 2.0;        // 整篮浮亏达余额% → 全部止损 (硬限制, 降到2%)
input int    InpGrid_CooldownSec   = 60;         // 同向网格加仓冷却(秒, 拉长避免连开)
input bool   InpGrid_CloseOnTrendSwitch = true;  // ★ 状态切到趋势时立即平掉所有网格 (强烈建议开)

input group "=== [F] 突破引擎 (趋势态) - 模式 A: Donchian 突破 ==="
input bool   InpBO_EnableDonchian  = true;       // 启用 Donchian 突破入场 (保守, 捕捉新趋势)
input int    InpBO_Lookback        = 20;         // 突破回看K线数 (Donchian)
input bool   InpBO_RequireAccel    = false;      // 是否强制要求 ATR 加速 (false=放宽)
input double InpBO_ATR_AccelMult   = 1.05;       // ATR现值 > ATR前值 × 此值 (仅当上一项为 true 才生效)

input group "=== [F2] 突破引擎 - 模式 B: 趋势跟随 (新增) ==="
input bool   InpBO_EnableTrendFollow = true;     // 启用趋势跟随入场 (激进, 跟随已确立趋势)
input double InpBO_TF_MinADX       = 30.0;       // ADX 达此值才认为趋势强 (默认 30)
input double InpBO_TF_PullbackATR  = 0.5;        // 价格回调至均线/锚点 ≤ ATR × 此值时入场
input ENUM_TIMEFRAMES InpBO_TF_AnchorTF = PERIOD_M5; // 趋势跟随锚点周期 (取均线作为回调基准)
input int    InpBO_TF_AnchorMAPer  = 20;         // 锚点均线周期 (EMA)
input int    InpBO_TF_CooldownSec  = 180;        // 趋势跟随入场冷却(秒, 避免连开)

input group "=== [F3] 突破引擎 - 通用 ==="
input int    InpBO_MaxSameSide     = 1;          // 同向突破最大持仓 (V8.2 已收紧至 1)
// ★★★ V8.2.1 出场逻辑全面修复 (基于上一次回测胜率50%但盈亏比0.70的诊断):
// 原参数让赢家被保本/追踪过早吃掉, 输家却扛足2xATR. 现修复:
//   - 止损 2.0→1.5: 单笔最大亏损从 -14.80 降到 -11.10 (-25%)
//   - 保本触发 1.0→1.5: 不再过早把利润吐回去
//   - 追踪启动 1.8→2.5: 让趋势真正发展起来再开始锁利
//   - 追踪距离 1.5→0.8: 一旦锁利就抓得更紧, 减少吐回
// 目标: 盈亏比 0.70 → 1.20+, 平衡胜率 58.8% → 46% (现胜率50%即可盈利)
input double InpBO_SL_ATR_Mult     = 1.5;        // 初始止损 = ATR × 此值 (V8.2.1: 2.0→1.5)
input double InpBO_BE_TriggerATR   = 1.5;        // 浮盈达 ATR × 此值 → 移动到保本 (V8.2.1: 1.0→1.5)
input double InpBO_TrailStartATR   = 2.5;        // 浮盈达 ATR × 此值 → 启动追踪 (V8.2.1: 1.8→2.5)
input double InpBO_TrailDistATR    = 0.8;        // 追踪止损距市价 = ATR × 此值 (V8.2.1: 1.5→0.8)
input double InpBO_TrailStepATR    = 0.3;        // SL 推进最小步长 (ATR 倍数)
input int    InpBO_CooldownSec     = 120;        // Donchian 突破信号冷却(秒)

input group "=== [F4] V8.2 趋势期入场保护 ==="
input int    InpTrendColdStartBars = 2;          // 切入趋势后冷启动 N 根 K 线不开仓 (确认稳定)
input int    InpMaxEntriesPerTrend = 2;          // 同一趋势期(未切换)最多入场 N 次

input group "=== [G] 通用过滤器 ==="
input double InpMaxSpreadPoints    = 500.0;      // 最大允许点差 | 黄金 500, 外汇改回 50
input bool   InpUseSessionFilter   = false;      // 启用交易时段过滤
input int    InpSessionStartHour   = 8;          // 时段开始 (服务器时间)
input int    InpSessionEndHour     = 22;         // 时段结束 (服务器时间)

input group "=== [H] 诊断与 UI ==="
input bool   InpEnableDiagnostic   = true;       // 启用诊断日志 (无仓时定时输出阻塞原因)
input int    InpDiagnosticIntervalSec = 30;      // 诊断日志间隔(秒)
input bool   InpShowControlPanel   = true;       // 显示右侧控制按钮面板

//==================================================================
// 枚举与全局结构
//==================================================================
enum MarketRegime {
   REGIME_UNKNOWN = 0,
   REGIME_RANGE   = 1,   // 震荡 → 网格
   REGIME_TREND_UP   = 2,// 强势上涨 → 多头突破
   REGIME_TREND_DOWN = 3,// 强势下跌 → 空头突破
   REGIME_NEUTRAL = 4,   // 缓冲带 (ADX 20~25), 仅管存量, 不开新
   REGIME_HIGH_VOL = 5   // 极端波动, 全冻结
};

enum EngineType {
   ENG_NONE     = 0,
   ENG_GRID     = 1,
   ENG_BREAKOUT = 2
};

// 指标句柄
int g_hADX      = INVALID_HANDLE;
int g_hATR      = INVALID_HANDLE;
int g_hATR_Exec = INVALID_HANDLE;   // 当前周期 ATR (用于止损/手数计算)
int g_hTF_MA    = INVALID_HANDLE;   // 趋势跟随锚点 EMA
int g_hH1_FastEMA = INVALID_HANDLE; // V8.3: H1 大趋势快线
int g_hH1_SlowEMA = INVALID_HANDLE; // V8.3: H1 大趋势慢线
int g_hH1_ADX     = INVALID_HANDLE; // V8.3: H1 ADX

// V8.3: H1 大趋势偏好状态
enum TrendBias {
   BIAS_NONE  = 0,  // 无大趋势 (H1 ADX 不足或快慢线交错)
   BIAS_LONG  = 1,  // 大趋势多头 (fastEMA > slowEMA, ADX 够)
   BIAS_SHORT = 2   // 大趋势空头 (fastEMA < slowEMA, ADX 够)
};
TrendBias g_h1Bias = BIAS_NONE;
datetime  g_lastH1BarTime = 0;
double    g_h1FastVal = 0, g_h1SlowVal = 0, g_h1AdxVal = 0;

datetime g_lastTFOpenBuy  = 0;
datetime g_lastTFOpenSell = 0;

// 状态机
MarketRegime g_regime = REGIME_UNKNOWN;
MarketRegime g_regimeCandidate = REGIME_UNKNOWN;
int          g_regimeCandidateBars = 0;
datetime     g_lastRegimeBarTime = 0;

// V8.2 新增: 趋势期入场保护
datetime g_regimeEnterTime  = 0;  // 当前 regime 开始时间
int      g_entriesThisTrend = 0;  // 当前趋势期已入场次数

// V8.2 新增: 鞭打市场过滤器 (环形缓冲存状态切换时间戳, 取近 100 次)
#define WHIPSAW_BUF 100
datetime g_regimeSwitchHist[WHIPSAW_BUF];
int      g_regimeSwitchIdx = 0;
int      g_regimeSwitchCnt = 0;
datetime g_whipsawFreezeUntil = 0;

// 账户基线
double   g_dailyStartEquity = 0;
double   g_peakEquity       = 0;
datetime g_dailyBaselineDay = 0;
datetime g_circuitUntil     = 0;
bool     g_circuitActive    = false;

// 引擎时间控制
datetime g_lastGridOpenBuy  = 0;
datetime g_lastGridOpenSell = 0;
datetime g_lastBOOpenBuy    = 0;
datetime g_lastBOOpenSell   = 0;

// 突破单状态 (持仓 ticket -> 是否已保本/已启动追踪)
struct BOState {
   ulong  ticket;
   bool   beMoved;     // 已移动至保本
   bool   trailActive; // 已启动追踪止损
   double peakProfitATR; // 峰值浮盈(ATR单位)
};
BOState g_boStates[];

// 运行时开关 (按钮面板可改, 优先级高于 input)
bool g_runEnableGrid     = true;
bool g_runEnableBreakout = true;
bool g_runPaused         = false;

// 诊断
datetime g_lastDiagTime = 0;
string   g_lastBlockReason = "";  // 最近一次拒单原因, 写入看板

//==================================================================
// UI 按钮面板 (右上角)
//==================================================================
#define UI_PREFIX "V8BTN_"
const int UI_BTN_W  = 110;
const int UI_BTN_H  = 26;
const int UI_BTN_X  = 8;   // 距右边距 (CORNER_RIGHT_UPPER)
const int UI_BTN_Y0 = 30;
const int UI_BTN_GAP= 4;

void CreateButton(const string id, const string text, int row, color bg, color fg = clrWhite) {
   string name = UI_PREFIX + id;
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, UI_BTN_X + UI_BTN_W);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, UI_BTN_W);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, UI_BTN_H);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDimGray);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString (0, name, OBJPROP_FONT, "Microsoft YaHei");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, UI_BTN_Y0 + row * (UI_BTN_H + UI_BTN_GAP));
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}

void CreateControlPanel() {
   if(!InpShowControlPanel) return;
   CreateButton("Pause",     g_runPaused ? "▶ 恢复 EA" : "⏸ 暂停 EA",
                0, g_runPaused ? clrDarkGreen : clrDarkOrange);
   CreateButton("Grid",      g_runEnableGrid ? "🟢 网格 ON" : "⚪ 网格 OFF",
                1, g_runEnableGrid ? clrDarkGreen : clrDimGray);
   CreateButton("Breakout",  g_runEnableBreakout ? "🟢 突破 ON" : "⚪ 突破 OFF",
                2, g_runEnableBreakout ? clrDarkGreen : clrDimGray);
   CreateButton("BuyNow",    "↑ 手动买入测试",  3, clrSteelBlue);
   CreateButton("SellNow",   "↓ 手动卖出测试",  4, clrSteelBlue);
   CreateButton("CloseGrid", "✕ 平网格仓",      5, clrMaroon);
   CreateButton("CloseBO",   "✕ 平突破仓",      6, clrMaroon);
   CreateButton("CloseAll",  "✕✕ 平全部",        7, clrCrimson);
   CreateButton("Diag",      "📋 输出诊断日志", 8, clrDarkSlateBlue);
}

void DeleteControlPanel() {
   string ids[] = {"Pause","Grid","Breakout","BuyNow","SellNow",
                   "CloseGrid","CloseBO","CloseAll","Diag"};
   for(int i = 0; i < ArraySize(ids); i++) ObjectDelete(0, UI_PREFIX + ids[i]);
}

//==================================================================
// 工具函数
//==================================================================

//--- 安全获取 ATR 当前值 (失败返回 0)
double GetATR(int handle, int shift = 0) {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) < 1) return 0.0;
   return buf[0];
}

//--- 安全获取 ADX 当前值 (主线, buffer 0)
double GetADX(int shift = 0) {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hADX, 0, shift, 1, buf) < 1) return 0.0;
   return buf[0];
}

//--- ADX +DI / -DI 判断方向 (buffer 1 = +DI, buffer 2 = -DI)
//    返回: 1=多头主导, -1=空头主导, 0=无主导
int GetADX_Direction(int shift = 0) {
   double plus[], minus[];
   ArraySetAsSeries(plus, true);
   ArraySetAsSeries(minus, true);
   if(CopyBuffer(g_hADX, 1, shift, 1, plus) < 1) return 0;
   if(CopyBuffer(g_hADX, 2, shift, 1, minus) < 1) return 0;
   if(plus[0] > minus[0] + 1.0) return 1;
   if(minus[0] > plus[0] + 1.0) return -1;
   return 0;
}

//--- ATR 均值 (用于极端波动识别)
double GetATR_Mean(int handle, int lookback) {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, 1, lookback, buf) < lookback) return 0.0;
   double sum = 0;
   for(int i = 0; i < lookback; i++) sum += buf[i];
   return sum / lookback;
}

//--- 规范化手数 (符合 broker step/min/max)
double NormalizeLots(double lots) {
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0) vstep = 0.01;
   lots = MathFloor(lots / vstep + 1e-9) * vstep;
   if(lots < vmin) lots = vmin;
   if(lots > vmax) lots = vmax;
   if(lots > InpMaxLotPerTrade) lots = InpMaxLotPerTrade;
   int digits = (int)MathMax(2, MathCeil(-MathLog10(vstep)));
   return NormalizeDouble(lots, digits);
}

//--- 风险敞口 → 手数:
//    手数 = (账户余额 × 风险%) / (止损距离价格 × tickValue/tickSize)
//    若任一关键值非法, 返回 InpFixedLotFallback
double CalcLotByRisk(double slDistancePrice) {
   if(slDistancePrice <= 0) return InpFixedLotFallback;
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0) return InpFixedLotFallback;

   double riskMoney = accInfo.Balance() * InpRiskPercent / 100.0;
   // 1 手单价跳动产生的盈亏: tickVal; 总价格距离 / tickSize = 跳动数
   double lossPer1Lot = (slDistancePrice / tickSize) * tickVal;
   if(lossPer1Lot <= 0) return InpFixedLotFallback;

   double lots = riskMoney / lossPer1Lot;
   return NormalizeLots(lots);
}

//--- 保证金占用检查
bool IsMarginAcceptable(ENUM_ORDER_TYPE type, double lots, string &reason) {
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double need = 0;
   if(!OrderCalcMargin(type, _Symbol, lots, price, need)) {
      reason = "OrderCalcMargin failed";
      return false;
   }
   double cap = accInfo.Balance() * InpMaxMarginUsedPct / 100.0;
   if(cap > 0 && accInfo.Margin() + need > cap) {
      reason = StringFormat("margin cap reached: used %.2f + need %.2f > cap %.2f",
                            accInfo.Margin(), need, cap);
      return false;
   }
   if(need > accInfo.FreeMargin()) {
      reason = "insufficient free margin";
      return false;
   }
   return true;
}

//--- 是否本 EA 持仓
bool IsOurPosition() {
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   if(PositionGetInteger(POSITION_MAGIC) != InpMagic) return false;
   return true;
}

//--- 统计本 EA 同向持仓
//    engine: ENG_GRID / ENG_BREAKOUT / ENG_NONE(全部)
int CountOurPositions(int direction, EngineType engine) {
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(!IsOurPosition()) continue;
      int dir = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 0 : 1;
      if(direction >= 0 && dir != direction) continue;
      if(engine != ENG_NONE) {
         string cmt = posInfo.Comment();
         bool isGrid = (StringFind(cmt, InpComment + "_G") >= 0);
         bool isBO   = (StringFind(cmt, InpComment + "_B") >= 0);
         if(engine == ENG_GRID && !isGrid) continue;
         if(engine == ENG_BREAKOUT && !isBO) continue;
      }
      cnt++;
   }
   return cnt;
}

//--- 累计本 EA 浮盈
double SumOurFloatingProfit(EngineType engine) {
   double sum = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(!IsOurPosition()) continue;
      if(engine != ENG_NONE) {
         string cmt = posInfo.Comment();
         bool isGrid = (StringFind(cmt, InpComment + "_G") >= 0);
         bool isBO   = (StringFind(cmt, InpComment + "_B") >= 0);
         if(engine == ENG_GRID && !isGrid) continue;
         if(engine == ENG_BREAKOUT && !isBO) continue;
      }
      sum += posInfo.Profit() + posInfo.Swap();
   }
   return sum;
}

//--- 通用过滤: 点差 + 时段
bool PassesGlobalFilters(string &reason) {
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints) {
      reason = StringFormat("spread %d > limit %.0f", (int)spread, InpMaxSpreadPoints);
      return false;
   }
   if(InpUseSessionFilter) {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < InpSessionStartHour || dt.hour >= InpSessionEndHour) {
         reason = StringFormat("out of session %d:00-%d:00",
                               InpSessionStartHour, InpSessionEndHour);
         return false;
      }
   }
   return true;
}

//==================================================================
// 账户级风控 (回撤/日亏/熔断)
//==================================================================
void RefreshDailyBaseline() {
   datetime today = (datetime)((long)TimeCurrent() / 86400 * 86400);
   if(g_dailyBaselineDay != today) {
      g_dailyBaselineDay  = today;
      g_dailyStartEquity  = accInfo.Equity();
   }
}

double GetDailyLossPct() {
   if(g_dailyStartEquity <= 0) return 0;
   double diff = g_dailyStartEquity - accInfo.Equity();
   if(diff <= 0) return 0;
   return diff / g_dailyStartEquity * 100.0;
}

double GetDrawdownPct() {
   if(g_peakEquity < accInfo.Equity()) g_peakEquity = accInfo.Equity();
   if(g_peakEquity <= 0) return 0;
   double diff = g_peakEquity - accInfo.Equity();
   if(diff <= 0) return 0;
   return diff / g_peakEquity * 100.0;
}

//--- 平掉本 EA 全部持仓
void CloseAllOurs(const string reason) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(!IsOurPosition()) continue;
      ulong tk = posInfo.Ticket();
      if(!trade.PositionClose(tk, (ulong)InpSlippagePoints)) {
         PrintFormat("⚠ 平仓失败 ticket=%I64u err=%d retcode=%u", tk,
                     GetLastError(), trade.ResultRetcode());
      }
   }
   PrintFormat("🛑 [熔断] 全平触发: %s", reason);
}

//--- 全局监督: 必须每 tick 调用 (尽早)
//    V8.1 重大修复: 日亏触发现在强制平仓 (可选), 不再放任存量持仓继续亏损
void UpdateRiskSupervisor() {
   RefreshDailyBaseline();
   if(g_peakEquity < accInfo.Equity()) g_peakEquity = accInfo.Equity();

   // 熔断冷却期
   if(g_circuitActive) {
      if(TimeCurrent() >= g_circuitUntil) {
         g_circuitActive = false;
         g_peakEquity = accInfo.Equity();
         // 同时重置日基线, 避免恢复后立刻再次触发
         g_dailyStartEquity = accInfo.Equity();
         Print("✅ 熔断冷却结束, 恢复观察");
      }
      return;
   }

   double dd  = GetDrawdownPct();
   double dl  = GetDailyLossPct();

   // 1) 账户最大回撤 → 强平 + 长冷却
   if(InpMaxDrawdownPct > 0 && dd >= InpMaxDrawdownPct) {
      CloseAllOurs(StringFormat("DD %.2f%% ≥ %.2f%%", dd, InpMaxDrawdownPct));
      g_circuitActive = true;
      g_circuitUntil = TimeCurrent() + InpCircuitCooldownMin * 60;
      return;
   }

   // 2) 单日亏损 → V8.1 改为可选强平 (默认开)
   if(InpDailyLossLimitPct > 0 && dl >= InpDailyLossLimitPct) {
      if(InpDailyLossForceClose) {
         int total = CountOurPositions(-1, ENG_NONE);
         if(total > 0) {
            CloseAllOurs(StringFormat("日亏 %.2f%% ≥ %.2f%% → 强制全平", dl, InpDailyLossLimitPct));
         }
         // 短期冻结 (当日剩余时间不开新仓)
         g_circuitActive = true;
         g_circuitUntil = TimeCurrent() + 240 * 60; // 冻结 4 小时
         PrintFormat("🛑 [日亏熔断] 冻结开仓 4 小时");
         return;
      }
      // 若用户关闭强平, 至少在 CanOpenNew 拦截新开 (原行为)
   }
}

//--- 是否允许新开
bool CanOpenNew(string &reason) {
   if(g_circuitActive) { reason = "circuit breaker active"; return false; }
   if(IsWhipsawFrozen()) {
      reason = StringFormat("鞭打市场冻结中 (到 %s)",
                             TimeToString(g_whipsawFreezeUntil, TIME_DATE | TIME_MINUTES));
      return false;
   }
   if(InpDailyLossLimitPct > 0 && GetDailyLossPct() >= InpDailyLossLimitPct) {
      reason = StringFormat("daily loss %.2f%% reached", GetDailyLossPct());
      return false;
   }
   if(!PassesGlobalFilters(reason)) return false;
   return true;
}

//==================================================================
// 市场状态机: ATR + ADX (M15)
//==================================================================
void UpdateMarketRegime() {
   // 仅在 M15 K 线收盘后重新评估, 减少噪音
   datetime t[];
   ArraySetAsSeries(t, true);
   if(CopyTime(_Symbol, InpRegimeTF, 0, 1, t) < 1) return;
   if(t[0] == g_lastRegimeBarTime) return;  // 本根已评估
   // 注意: 这里允许在当前未收盘 K 线上做"试探性"识别, 用 shift=0
   // 但确认仍依赖 InpRegimeMinHoldBars 防抖

   double adx  = GetADX(0);
   int    dir  = GetADX_Direction(0);
   double atr  = GetATR(g_hATR, 0);
   double atrAvg = GetATR_Mean(g_hATR, InpATR_AvgLookback);

   MarketRegime newRegime;
   if(atrAvg > 0 && atr >= atrAvg * InpATR_HighVolMult) {
      newRegime = REGIME_HIGH_VOL;
   } else if(adx < InpADX_RangeMax) {
      newRegime = REGIME_RANGE;
   } else if(adx >= InpADX_TrendMin) {
      if(dir > 0)      newRegime = REGIME_TREND_UP;
      else if(dir < 0) newRegime = REGIME_TREND_DOWN;
      else             newRegime = REGIME_NEUTRAL;
   } else {
      newRegime = REGIME_NEUTRAL;  // ADX 在 20~25 缓冲带
   }

   // 防抖: 候选状态需连续 N 根 K 线一致才正式切换
   if(newRegime == g_regimeCandidate) {
      g_regimeCandidateBars++;
   } else {
      g_regimeCandidate = newRegime;
      g_regimeCandidateBars = 1;
   }

   if(g_regimeCandidateBars >= InpRegimeMinHoldBars && newRegime != g_regime) {
      MarketRegime oldRegime = g_regime;
      PrintFormat("🔄 [状态切换] %s → %s | ADX=%.1f ATR=%.5f (avg %.5f)",
                  RegimeText(oldRegime), RegimeText(newRegime), adx, atr, atrAvg);
      g_regime = newRegime;

      // ★ V8.2: 重置趋势期入场计数器 + 记录入场时间
      g_regimeEnterTime = TimeCurrent();
      g_entriesThisTrend = 0;

      // ★ V8.2: 鞭打市场检测 - 记录状态切换时间, 看窗口内是否过于频繁
      RecordRegimeSwitch();

      // ★ V8.1 关键修复: 从震荡切到趋势/高波动时, 强平网格
      bool exitFromRange = (oldRegime == REGIME_RANGE);
      bool intoTrend = (newRegime == REGIME_TREND_UP || newRegime == REGIME_TREND_DOWN ||
                         newRegime == REGIME_HIGH_VOL);
      if(InpGrid_CloseOnTrendSwitch && exitFromRange && intoTrend) {
         int gridCount = CountOurPositions(-1, ENG_GRID);
         if(gridCount > 0) {
            CloseEngine(ENG_GRID,
                StringFormat("⚠ 状态切到 %s, 网格逆势风险高 → 强制平仓 %d 笔",
                             RegimeText(newRegime), gridCount));
         }
      }
   }
   g_lastRegimeBarTime = t[0];
}

//==================================================================
// V8.2: 鞭打市场过滤器
//==================================================================
void RecordRegimeSwitch() {
   if(!InpEnableWhipsawFilter) return;
   datetime now = TimeCurrent();
   g_regimeSwitchHist[g_regimeSwitchIdx] = now;
   g_regimeSwitchIdx = (g_regimeSwitchIdx + 1) % WHIPSAW_BUF;
   if(g_regimeSwitchCnt < WHIPSAW_BUF) g_regimeSwitchCnt++;

   // 计算窗口内切换次数
   datetime windowStart = now - InpWhipsawWindowMin * 60;
   int cnt = 0;
   for(int i = 0; i < g_regimeSwitchCnt; i++) {
      if(g_regimeSwitchHist[i] >= windowStart) cnt++;
   }
   if(cnt > InpWhipsawMaxSwitches) {
      g_whipsawFreezeUntil = now + InpWhipsawFreezeMin * 60;
      PrintFormat("⛔ [鞭打市场] 过去 %d 分钟内状态切换 %d 次 (上限 %d), 冻结到 %s",
                  InpWhipsawWindowMin, cnt, InpWhipsawMaxSwitches,
                  TimeToString(g_whipsawFreezeUntil, TIME_DATE | TIME_MINUTES));
      // 鞭打市场触发时, 强平所有持仓避免被反复打脸
      CloseEngine(ENG_GRID, "鞭打市场触发, 全平网格");
      CloseEngine(ENG_BREAKOUT, "鞭打市场触发, 全平突破");
   }
}

bool IsWhipsawFrozen() {
   return InpEnableWhipsawFilter && TimeCurrent() < g_whipsawFreezeUntil;
}

//==================================================================
// V8.2: 趋势冷启动 + 单趋势入场次数限制
//==================================================================
bool TrendCooldownOK() {
   if(InpTrendColdStartBars <= 0) return true;
   if(g_regimeEnterTime == 0) return true;
   int tfSec = PeriodSeconds(InpRegimeTF);
   datetime cooldownEnd = g_regimeEnterTime + InpTrendColdStartBars * tfSec;
   return TimeCurrent() >= cooldownEnd;
}

bool TrendEntryQuotaOK() {
   if(InpMaxEntriesPerTrend <= 0) return true;
   return g_entriesThisTrend < InpMaxEntriesPerTrend;
}

string RegimeText(MarketRegime r) {
   switch(r) {
      case REGIME_RANGE:      return "震荡";
      case REGIME_TREND_UP:   return "趋势↑";
      case REGIME_TREND_DOWN: return "趋势↓";
      case REGIME_NEUTRAL:    return "中性";
      case REGIME_HIGH_VOL:   return "极端波动";
      default:                return "未知";
   }
}

string BiasText(TrendBias b) {
   switch(b) {
      case BIAS_LONG:  return "H1多头";
      case BIAS_SHORT: return "H1空头";
      default:         return "H1无趋势";
   }
}

//==================================================================
// V8.3: H1 大趋势偏好计算 (每 H1 K 线收盘后重算一次)
//==================================================================
void UpdateTrendBias() {
   if(!InpEnableH1Bias) { g_h1Bias = BIAS_NONE; return; }
   if(g_hH1_FastEMA == INVALID_HANDLE) return;

   datetime t[];
   ArraySetAsSeries(t, true);
   if(CopyTime(_Symbol, InpH1_TF, 0, 1, t) < 1) return;
   if(t[0] == g_lastH1BarTime) return;  // 本根 H1 已算过

   double fast[], slow[], adx[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(adx, true);

   if(CopyBuffer(g_hH1_FastEMA, 0, 0, 1, fast) < 1) return;
   if(CopyBuffer(g_hH1_SlowEMA, 0, 0, 1, slow) < 1) return;
   if(CopyBuffer(g_hH1_ADX,     0, 0, 1, adx)  < 1) return;

   g_h1FastVal = fast[0];
   g_h1SlowVal = slow[0];
   g_h1AdxVal  = adx[0];

   TrendBias newBias;
   if(g_h1AdxVal < InpH1_MinADX) {
      newBias = BIAS_NONE;  // 大周期 ADX 不足, 视为震荡, 拒绝跟随
   } else if(g_h1FastVal > g_h1SlowVal) {
      newBias = BIAS_LONG;
   } else if(g_h1FastVal < g_h1SlowVal) {
      newBias = BIAS_SHORT;
   } else {
      newBias = BIAS_NONE;
   }

   if(newBias != g_h1Bias) {
      PrintFormat("🌐 [H1偏好切换] %s → %s | FastEMA=%.5f SlowEMA=%.5f ADX=%.1f",
                  BiasText(g_h1Bias), BiasText(newBias),
                  g_h1FastVal, g_h1SlowVal, g_h1AdxVal);
      g_h1Bias = newBias;
   }
   g_lastH1BarTime = t[0];
}

//--- 检查当前方向是否与 H1 偏好对齐
//    type=BUY → 需要 BIAS_LONG, type=SELL → 需要 BIAS_SHORT
bool IsAlignedWithH1Bias(ENUM_ORDER_TYPE type) {
   if(!InpEnableH1Bias) return true;  // 未启用过滤, 全部通过
   if(type == ORDER_TYPE_BUY)  return (g_h1Bias == BIAS_LONG);
   if(type == ORDER_TYPE_SELL) return (g_h1Bias == BIAS_SHORT);
   return false;
}

//==================================================================
// 通用下单 (含完整校验)
//==================================================================
//--- 计算 SL/TP 价格 (基于 ATR 距离)
//    type: ORDER_TYPE_BUY / ORDER_TYPE_SELL
void CalcSLTP(ENUM_ORDER_TYPE type, double atr, double slMult, double tpMult,
              double &slPrice, double &tpPrice) {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stops * point;

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = atr * slMult;
   double tpDist = atr * tpMult;
   if(slDist < minDist) slDist = minDist + point * 5;
   if(tpDist > 0 && tpDist < minDist) tpDist = minDist + point * 5;

   if(type == ORDER_TYPE_BUY) {
      slPrice = NormalizeDouble(price - slDist, _Digits);
      tpPrice = (tpMult > 0) ? NormalizeDouble(price + tpDist, _Digits) : 0;
   } else {
      slPrice = NormalizeDouble(price + slDist, _Digits);
      tpPrice = (tpMult > 0) ? NormalizeDouble(price - tpDist, _Digits) : 0;
   }
}

//--- 统一下市价单
//    返回 ticket; 失败返回 0
ulong OpenMarketOrder(ENUM_ORDER_TYPE type, double lots, double sl, double tp, const string cmt) {
   string reason;
   if(!IsMarginAcceptable(type, lots, reason)) {
      PrintFormat("✋ 拒绝下单 %s lots=%.2f: %s", EnumToString(type), lots, reason);
      return 0;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints((ulong)InpSlippagePoints);

   bool ok = (type == ORDER_TYPE_BUY) ? trade.Buy(lots, _Symbol, 0, sl, tp, cmt)
                                       : trade.Sell(lots, _Symbol, 0, sl, tp, cmt);
   if(!ok) {
      PrintFormat("❌ 下单失败 %s lots=%.2f sl=%.5f tp=%.5f err=%d retcode=%u",
                  EnumToString(type), lots, sl, tp,
                  GetLastError(), trade.ResultRetcode());
      return 0;
   }
   ulong deal = trade.ResultDeal();
   ulong pos  = trade.ResultOrder();
   PrintFormat("✅ 下单成功 %s lots=%.2f sl=%.5f tp=%.5f deal=%I64u",
               EnumToString(type), lots, sl, tp, deal);
   return pos;
}

//==================================================================
// 诊断: 收集"为何没下单"的所有可能原因
//==================================================================
string BuildDiagnosticReport() {
   string s = "";
   s += StringFormat("【状态】%s | ADX=%.1f ATR=%.5f (avg %.5f)\n",
                      RegimeText(g_regime), GetADX(0),
                      GetATR(g_hATR, 0), GetATR_Mean(g_hATR, InpATR_AvgLookback));
   s += StringFormat("【运行】Paused=%s Grid=%s BO=%s\n",
                      g_runPaused ? "是" : "否",
                      g_runEnableGrid ? "开" : "关",
                      g_runEnableBreakout ? "开" : "关");

   string reason;
   bool canOpen = CanOpenNew(reason);
   s += StringFormat("【风控】可开新仓=%s%s\n", canOpen ? "是" : "否",
                      canOpen ? "" : (" 原因: " + reason));

   // V8.2: 趋势期入场配额 + 鞭打状态
   if(g_regime == REGIME_TREND_UP || g_regime == REGIME_TREND_DOWN) {
      s += StringFormat("【趋势期】入场 %d/%d 笔 | 冷启动=%s\n",
                         g_entriesThisTrend, InpMaxEntriesPerTrend,
                         TrendCooldownOK() ? "已完成" : "进行中");
   }
   // V8.3: H1 大趋势偏好显示
   if(InpEnableH1Bias) {
      s += StringFormat("【H1偏好】%s | FastEMA=%.5f SlowEMA=%.5f ADX=%.1f (需≥%.1f)\n",
                         BiasText(g_h1Bias), g_h1FastVal, g_h1SlowVal,
                         g_h1AdxVal, InpH1_MinADX);
   }
   if(InpEnableWhipsawFilter) {
      datetime windowStart = TimeCurrent() - InpWhipsawWindowMin * 60;
      int swCnt = 0;
      for(int i = 0; i < g_regimeSwitchCnt; i++) {
         if(g_regimeSwitchHist[i] >= windowStart) swCnt++;
      }
      s += StringFormat("【鞭打过滤】近%d分钟切换%d次 (上限%d) %s\n",
                         InpWhipsawWindowMin, swCnt, InpWhipsawMaxSwitches,
                         IsWhipsawFrozen() ? "🔴冻结中" : "✓正常");
   }

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   s += StringFormat("【市场】点差=%d (上限%.0f) Bid=%.5f Ask=%.5f\n",
                      (int)spread, InpMaxSpreadPoints,
                      SymbolInfoDouble(_Symbol, SYMBOL_BID),
                      SymbolInfoDouble(_Symbol, SYMBOL_ASK));

   // 突破引擎诊断
   if(g_regime == REGIME_TREND_UP || g_regime == REGIME_TREND_DOWN) {
      double atr = GetATR(g_hATR_Exec, 0);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // 模式 A: Donchian
      if(InpBO_EnableDonchian) {
         MqlRates r[];
         ArraySetAsSeries(r, true);
         double hh = 0, ll = 0;
         if(CopyRates(_Symbol, _Period, 1, InpBO_Lookback, r) >= InpBO_Lookback) {
            hh = r[0].high; ll = r[0].low;
            for(int i = 1; i < InpBO_Lookback; i++) {
               if(r[i].high > hh) hh = r[i].high;
               if(r[i].low  < ll) ll = r[i].low;
            }
         }
         s += StringFormat("【Donchian模式】上轨=%.5f 下轨=%.5f\n", hh, ll);
         s += StringFormat("                Ask>HH? %s (差 %.5f)  Bid<LL? %s (差 %.5f)\n",
                            (ask > hh) ? "是" : "否", ask - hh,
                            (bid < ll) ? "是" : "否", ll - bid);
         if(InpBO_RequireAccel) {
            double atrPrev = GetATR(g_hATR_Exec, 1);
            bool accelOk = (atrPrev > 0 && atr >= atrPrev * InpBO_ATR_AccelMult);
            s += StringFormat("                ATR加速? %s (cur=%.5f prev=%.5f 需≥%.5f)\n",
                               accelOk ? "是" : "否", atr, atrPrev,
                               atrPrev * InpBO_ATR_AccelMult);
         } else {
            s += "                ATR加速检查已禁用 (RequireAccel=false)\n";
         }
      }

      // 模式 B: 趋势跟随
      if(InpBO_EnableTrendFollow && g_hTF_MA != INVALID_HANDLE) {
         double maArr[];
         ArraySetAsSeries(maArr, true);
         double anchor = 0;
         if(CopyBuffer(g_hTF_MA, 0, 0, 1, maArr) >= 1) anchor = maArr[0];
         double adx = GetADX(0);
         double pullbackDist = atr * InpBO_TF_PullbackATR;
         s += StringFormat("【趋势跟随模式】锚点EMA=%.5f ADX=%.1f (需≥%.1f) 回调窗口=±%.5f\n",
                            anchor, adx, InpBO_TF_MinADX, pullbackDist);
         if(g_regime == REGIME_TREND_UP) {
            bool inZone = (anchor > 0 && ask >= anchor && ask <= anchor + pullbackDist);
            s += StringFormat("                多头入场? %s (Ask=%.5f 距锚点 %.5f, 需 0~%.5f)\n",
                               inZone ? "是" : "否", ask, ask - anchor, pullbackDist);
         } else if(g_regime == REGIME_TREND_DOWN) {
            bool inZone = (anchor > 0 && bid <= anchor && bid >= anchor - pullbackDist);
            s += StringFormat("                空头入场? %s (Bid=%.5f 距锚点 %.5f, 需 0~%.5f)\n",
                               inZone ? "是" : "否", bid, anchor - bid, pullbackDist);
         }
      }
   }
   // 网格引擎诊断
   if(g_regime == REGIME_RANGE) {
      double atr = GetATR(g_hATR_Exec, 0);
      s += StringFormat("【网格】ATR=%.5f 间距=%.5f 多/空 %d/%d (max %d)\n",
                         atr, atr * InpGrid_SpacingATR,
                         CountOurPositions(0, ENG_GRID),
                         CountOurPositions(1, ENG_GRID),
                         InpGrid_MaxLevels);
   }
   if(g_lastBlockReason != "") {
      s += "【最近拒单】" + g_lastBlockReason + "\n";
   }
   return s;
}

void PrintDiagnostic(const bool force) {
   if(!force && !InpEnableDiagnostic) return;
   if(!force && TimeCurrent() - g_lastDiagTime < InpDiagnosticIntervalSec) return;
   // 仅在没有本 EA 持仓且不在熔断时定时输出
   int total = CountOurPositions(-1, ENG_NONE);
   if(!force && total > 0) { g_lastDiagTime = TimeCurrent(); return; }
   Print("──────── V8 诊断 ────────\n", BuildDiagnosticReport(),
         "────────────────────────");
   g_lastDiagTime = TimeCurrent();
}

//==================================================================
// 网格引擎 (震荡态)
//==================================================================
void ManageGridEngine() {
   if(!g_runEnableGrid || !InpEnableGrid) return;
   if(g_regime != REGIME_RANGE) return;

   string reason;
   if(!CanOpenNew(reason)) { g_lastBlockReason = "网格被拒: " + reason; return; }

   double atr = GetATR(g_hATR_Exec, 0);
   if(atr <= 0) return;

   double spacing = atr * InpGrid_SpacingATR;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // --- 多头网格 ---
   int buyCount = CountOurPositions(0, ENG_GRID);
   if(buyCount < InpGrid_MaxLevels &&
      TimeCurrent() - g_lastGridOpenBuy >= InpGrid_CooldownSec) {
      double lastBuyPrice = GetFurthestGridPrice(0);
      // 首层立即下; 后续层需价格回撤 >= spacing
      bool ready = (buyCount == 0) || (lastBuyPrice > 0 && ask <= lastBuyPrice - spacing);
      if(ready) PlaceGridOrder(ORDER_TYPE_BUY, atr, buyCount);
   }

   // --- 空头网格 ---
   int sellCount = CountOurPositions(1, ENG_GRID);
   if(sellCount < InpGrid_MaxLevels &&
      TimeCurrent() - g_lastGridOpenSell >= InpGrid_CooldownSec) {
      double lastSellPrice = GetFurthestGridPrice(1);
      bool ready = (sellCount == 0) || (lastSellPrice > 0 && bid >= lastSellPrice + spacing);
      if(ready) PlaceGridOrder(ORDER_TYPE_SELL, atr, sellCount);
   }
}

//--- 取该方向最远 (多头=最低/空头=最高) 持仓价, 用于决定加层位置
double GetFurthestGridPrice(int direction) {
   double best = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(!IsOurPosition()) continue;
      if(StringFind(posInfo.Comment(), InpComment + "_G") < 0) continue;
      int dir = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 0 : 1;
      if(dir != direction) continue;
      double p = posInfo.PriceOpen();
      if(best == 0) best = p;
      else if(direction == 0 && p < best) best = p;  // 多头取最低
      else if(direction == 1 && p > best) best = p;  // 空头取最高
   }
   return best;
}

//--- 下单一层网格
void PlaceGridOrder(ENUM_ORDER_TYPE type, double atr, int currentLevel) {
   // V8.1 重构: 网格单笔 NO SL (避免顺势中反复止损), TP 保留
   //   篮子层面用 BasketTP / BasketSL 双保护 + 趋势切换强平
   double tpDist = atr * InpGrid_TP_ATR_Mult;
   long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minDist = stops * point + point * 5;
   if(tpDist < minDist) tpDist = minDist;

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tpPrice = (type == ORDER_TYPE_BUY) ? NormalizeDouble(price + tpDist, _Digits)
                                              : NormalizeDouble(price - tpDist, _Digits);

   // 手数: 用篮子止损上限反推 = (余额 × BasketSL% / MaxLevels) / 假定亏损距离
   //   假定每层最坏亏损 = SpacingATR × MaxLevels × 1.5 (给点 buffer)
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double baseLots = InpFixedLotFallback;
   if(tickVal > 0 && tickSize > 0) {
      double riskBudget = accInfo.Balance() * InpGrid_BasketSL_Pct / 100.0;
      double perLayerBudget = riskBudget / MathMax(1, InpGrid_MaxLevels);
      double worstDist = atr * InpGrid_SpacingATR * InpGrid_MaxLevels * 1.5;
      double lossPer1Lot = (worstDist / tickSize) * tickVal;
      if(lossPer1Lot > 0) baseLots = perLayerBudget / lossPer1Lot;
   }
   double lots = NormalizeLots(baseLots * MathPow(InpGrid_LotMultiplier, currentLevel));

   string cmt = StringFormat("%s_G%d", InpComment, currentLevel + 1);
   ulong tk = OpenMarketOrder(type, lots, 0, tpPrice, cmt); // sl=0 表示不挂硬止损
   if(tk > 0) {
      if(type == ORDER_TYPE_BUY) g_lastGridOpenBuy = TimeCurrent();
      else                       g_lastGridOpenSell = TimeCurrent();
   }
}

//--- 整篮止盈/止损 + 趋势态强平 (针对网格篮子)
//    V8.1: 三重保护
//      1) 篮子止盈
//      2) 篮子止损 (余额% 硬限制)
//      3) 趋势态持续 N 秒仍持有网格 → 强平 (双保险)
void ManageGridBasket() {
   int total = CountOurPositions(-1, ENG_GRID);
   if(total <= 0) return;

   double profit = SumOurFloatingProfit(ENG_GRID);

   // 1) 篮子止盈
   if(InpGrid_BasketTP_USD > 0 && profit >= InpGrid_BasketTP_USD) {
      CloseEngine(ENG_GRID, StringFormat("篮子止盈 +%.2f USD", profit));
      return;
   }
   // 2) 篮子止损 (硬限制)
   if(InpGrid_BasketSL_Pct > 0) {
      double cap = accInfo.Balance() * InpGrid_BasketSL_Pct / 100.0;
      if(profit <= -cap) {
         CloseEngine(ENG_GRID, StringFormat("篮子止损 %.2f USD (cap %.2f)", profit, cap));
         return;
      }
   }
   // 3) 双保险: 当前是趋势/高波动态, 网格还在持仓 → 强平 (修复状态切换可能错过的情况)
   if(InpGrid_CloseOnTrendSwitch &&
      (g_regime == REGIME_TREND_UP || g_regime == REGIME_TREND_DOWN ||
       g_regime == REGIME_HIGH_VOL)) {
      CloseEngine(ENG_GRID,
         StringFormat("⚠ 当前状态[%s], 网格不应持仓 → 强平 %d 笔",
                      RegimeText(g_regime), total));
   }
}

//--- 按引擎平仓 (只动该引擎仓位)
void CloseEngine(EngineType eng, const string reason) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(!IsOurPosition()) continue;
      string cmt = posInfo.Comment();
      bool isGrid = (StringFind(cmt, InpComment + "_G") >= 0);
      bool isBO   = (StringFind(cmt, InpComment + "_B") >= 0);
      if(eng == ENG_GRID && !isGrid) continue;
      if(eng == ENG_BREAKOUT && !isBO) continue;
      ulong tk = posInfo.Ticket();
      if(!trade.PositionClose(tk, (ulong)InpSlippagePoints)) {
         PrintFormat("⚠ 平 %s ticket=%I64u 失败 err=%d retcode=%u",
                     (eng == ENG_GRID ? "网格" : "突破"),
                     tk, GetLastError(), trade.ResultRetcode());
      }
   }
   PrintFormat("🎯 [%s] 平仓: %s", (eng == ENG_GRID ? "网格" : "突破"), reason);
}

//==================================================================
// 突破引擎 (趋势态)
//==================================================================
void ManageBreakoutEngine() {
   if(!g_runEnableBreakout || !InpEnableBreakout) return;
   if(g_regime != REGIME_TREND_UP && g_regime != REGIME_TREND_DOWN) return;

   string reason;
   if(!CanOpenNew(reason)) { g_lastBlockReason = "突破被拒: " + reason; return; }

   // V8.2: 趋势冷启动 (刚切入趋势态, 让市场再走 N 根 K 线确认稳定)
   if(!TrendCooldownOK()) {
      g_lastBlockReason = StringFormat("趋势冷启动中 (需等 %d 根 %s K线)",
                                        InpTrendColdStartBars,
                                        EnumToString(InpRegimeTF));
      return;
   }
   // V8.2: 单趋势期入场次数配额
   if(!TrendEntryQuotaOK()) {
      g_lastBlockReason = StringFormat("本趋势期已入场 %d/%d 笔, 等下一段趋势",
                                        g_entriesThisTrend, InpMaxEntriesPerTrend);
      return;
   }

   double atr = GetATR(g_hATR_Exec, 0);
   if(atr <= 0) return;

   // 模式 A: Donchian 突破
   if(InpBO_EnableDonchian) {
      TryDonchianBreakout(atr);
   }
   // 模式 B: 趋势跟随 (回调入场)
   if(InpBO_EnableTrendFollow) {
      TryTrendFollow(atr);
   }
}

//--- 模式 A: Donchian 突破入场
void TryDonchianBreakout(double atr) {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, _Period, 1, InpBO_Lookback, r) < InpBO_Lookback) return;
   double hh = r[0].high, ll = r[0].low;
   for(int i = 1; i < InpBO_Lookback; i++) {
      if(r[i].high > hh) hh = r[i].high;
      if(r[i].low  < ll) ll = r[i].low;
   }

   // ATR 加速是可选项 (黄金/已成趋势时常不满足)
   bool accelOk = true;
   if(InpBO_RequireAccel) {
      double atrPrev = GetATR(g_hATR_Exec, 1);
      accelOk = (atrPrev > 0 && atr >= atrPrev * InpBO_ATR_AccelMult);
   }
   if(!accelOk) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(g_regime == REGIME_TREND_UP && ask > hh) {
      if(!IsAlignedWithH1Bias(ORDER_TYPE_BUY)) {
         g_lastBlockReason = StringFormat("Donchian多头被H1过滤: 大趋势=%s", BiasText(g_h1Bias));
      } else if(CountOurPositions(0, ENG_BREAKOUT) < InpBO_MaxSameSide &&
         TimeCurrent() - g_lastBOOpenBuy >= InpBO_CooldownSec) {
         PrintFormat("🚀 [Donchian] 多头突破 Ask=%.5f > HH=%.5f (H1=%s)", ask, hh, BiasText(g_h1Bias));
         OpenBreakoutPosition(ORDER_TYPE_BUY, atr);
      }
   }
   if(g_regime == REGIME_TREND_DOWN && bid < ll) {
      if(!IsAlignedWithH1Bias(ORDER_TYPE_SELL)) {
         g_lastBlockReason = StringFormat("Donchian空头被H1过滤: 大趋势=%s", BiasText(g_h1Bias));
      } else if(CountOurPositions(1, ENG_BREAKOUT) < InpBO_MaxSameSide &&
         TimeCurrent() - g_lastBOOpenSell >= InpBO_CooldownSec) {
         PrintFormat("🚀 [Donchian] 空头突破 Bid=%.5f < LL=%.5f (H1=%s)", bid, ll, BiasText(g_h1Bias));
         OpenBreakoutPosition(ORDER_TYPE_SELL, atr);
      }
   }
}

//--- 模式 B: 趋势跟随 (强趋势中回调到均线附近时入场)
//    条件: ADX ≥ 阈值, 趋势方向已确立, 价格回调到锚点均线 ATR×系数 范围内
void TryTrendFollow(double atr) {
   if(g_hTF_MA == INVALID_HANDLE) return;
   double adx = GetADX(0);
   if(adx < InpBO_TF_MinADX) return;

   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(g_hTF_MA, 0, 0, 1, ma) < 1) return;
   double anchor = ma[0];
   if(anchor <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pullbackDist = atr * InpBO_TF_PullbackATR;

   // 多头趋势: 价格回调至均线上方 (≤ pullbackDist) 时入场
   if(g_regime == REGIME_TREND_UP) {
      bool inZone = (ask >= anchor) && (ask <= anchor + pullbackDist);
      if(inZone && !IsAlignedWithH1Bias(ORDER_TYPE_BUY)) {
         g_lastBlockReason = StringFormat("趋势跟随多头被H1过滤: 大趋势=%s", BiasText(g_h1Bias));
      } else if(inZone &&
         CountOurPositions(0, ENG_BREAKOUT) < InpBO_MaxSameSide &&
         TimeCurrent() - g_lastTFOpenBuy >= InpBO_TF_CooldownSec) {
         PrintFormat("🌊 [趋势跟随] 多头回调入场 Ask=%.5f Anchor=%.5f ADX=%.1f H1=%s",
                     ask, anchor, adx, BiasText(g_h1Bias));
         if(OpenBreakoutPositionTF(ORDER_TYPE_BUY, atr)) {
            g_lastTFOpenBuy = TimeCurrent();
         }
      }
   }
   // 空头趋势
   if(g_regime == REGIME_TREND_DOWN) {
      bool inZone = (bid <= anchor) && (bid >= anchor - pullbackDist);
      if(inZone && !IsAlignedWithH1Bias(ORDER_TYPE_SELL)) {
         g_lastBlockReason = StringFormat("趋势跟随空头被H1过滤: 大趋势=%s", BiasText(g_h1Bias));
      } else if(inZone &&
         CountOurPositions(1, ENG_BREAKOUT) < InpBO_MaxSameSide &&
         TimeCurrent() - g_lastTFOpenSell >= InpBO_TF_CooldownSec) {
         PrintFormat("🌊 [趋势跟随] 空头回调入场 Bid=%.5f Anchor=%.5f ADX=%.1f H1=%s",
                     bid, anchor, adx, BiasText(g_h1Bias));
         if(OpenBreakoutPositionTF(ORDER_TYPE_SELL, atr)) {
            g_lastTFOpenSell = TimeCurrent();
         }
      }
   }
}

//--- 趋势跟随版下单 (与 Donchian 版共用 ATR×SL, 但 comment 用 _T 区分)
bool OpenBreakoutPositionTF(ENUM_ORDER_TYPE type, double atr) {
   double slPrice, tpDummy;
   CalcSLTP(type, atr, InpBO_SL_ATR_Mult, 0, slPrice, tpDummy);
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = MathAbs(price - slPrice);
   double lots = CalcLotByRisk(slDist);
   int sameSide = CountOurPositions((type == ORDER_TYPE_BUY) ? 0 : 1, ENG_BREAKOUT);
   string cmt = StringFormat("%s_B_TF%d", InpComment, sameSide + 1);
   ulong tk = OpenMarketOrder(type, lots, slPrice, 0, cmt);
   if(tk > 0) g_entriesThisTrend++;  // V8.2: 入场计数
   return (tk > 0);
}

void OpenBreakoutPosition(ENUM_ORDER_TYPE type, double atr) {
   double slPrice, tpDummy;
   CalcSLTP(type, atr, InpBO_SL_ATR_Mult, 0, slPrice, tpDummy); // 突破单无固定 TP, 用追踪

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = MathAbs(price - slPrice);
   double lots = CalcLotByRisk(slDist);

   int sameSide = CountOurPositions((type == ORDER_TYPE_BUY) ? 0 : 1, ENG_BREAKOUT);
   string cmt = StringFormat("%s_B%d", InpComment, sameSide + 1);
   ulong tk = OpenMarketOrder(type, lots, slPrice, 0, cmt);
   if(tk > 0) {
      if(type == ORDER_TYPE_BUY) g_lastBOOpenBuy = TimeCurrent();
      else                       g_lastBOOpenSell = TimeCurrent();
      g_entriesThisTrend++;  // V8.2: 入场计数
      // 注: 这里不主动注册 BOState, 因为 trade.ResultDeal() 是 deal ticket
      // 而我们用 position ticket 管理. SyncBOStates() 会在下次 OnTick 自动
      // 扫描 PositionsTotal 把新的突破仓位以默认状态(未保本/未追踪) 加入数组.
   }
}

//--- 同步突破单状态数组: 移除已平仓的, 用最新 position ticket 替换 deal ticket
void SyncBOStates() {
   // 收集当前所有突破单 ticket
   ulong active[];
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(!IsOurPosition()) continue;
      if(StringFind(posInfo.Comment(), InpComment + "_B") < 0) continue;
      int n = ArraySize(active);
      ArrayResize(active, n + 1);
      active[n] = posInfo.Ticket();
   }

   // 清理已不存在的, 同时补齐缺失的
   BOState fresh[];
   for(int i = 0; i < ArraySize(active); i++) {
      ulong tk = active[i];
      bool found = false;
      for(int j = 0; j < ArraySize(g_boStates); j++) {
         if(g_boStates[j].ticket == tk) {
            int n = ArraySize(fresh);
            ArrayResize(fresh, n + 1);
            fresh[n] = g_boStates[j];
            found = true;
            break;
         }
      }
      if(!found) {
         BOState st;
         st.ticket = tk;
         st.beMoved = false;
         st.trailActive = false;
         st.peakProfitATR = 0;
         int n = ArraySize(fresh);
         ArrayResize(fresh, n + 1);
         fresh[n] = st;
      }
   }
   ArrayResize(g_boStates, ArraySize(fresh));
   for(int i = 0; i < ArraySize(fresh); i++) g_boStates[i] = fresh[i];
}

//--- 修改某仓位 SL (含最小距离校验)
bool ModifyPositionSL(ulong ticket, double newSL) {
   if(!PositionSelectByTicket(ticket)) return false;
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   double price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                  : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minDist = stops * point + point * 2;
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
      if(newSL >= price - minDist) newSL = price - minDist;
      if(curSL > 0 && newSL <= curSL) return false; // 只上推
   } else {
      if(newSL <= price + minDist) newSL = price + minDist;
      if(curSL > 0 && newSL >= curSL) return false; // 只下推
   }
   newSL = NormalizeDouble(newSL, _Digits);
   if(!trade.PositionModify(ticket, newSL, curTP)) {
      PrintFormat("⚠ ModifySL ticket=%I64u 失败 err=%d retcode=%u",
                  ticket, GetLastError(), trade.ResultRetcode());
      return false;
   }
   return true;
}

//--- 突破单分级动态止损: 保本 → ATR 追踪
void ManageBreakoutTrailing() {
   SyncBOStates();
   double atr = GetATR(g_hATR_Exec, 0);
   if(atr <= 0) return;

   for(int i = 0; i < ArraySize(g_boStates); i++) {
      ulong tk = g_boStates[i].ticket;
      if(!PositionSelectByTicket(tk)) continue;
      ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openP = PositionGetDouble(POSITION_PRICE_OPEN);
      double curP  = (pType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitDist = (pType == POSITION_TYPE_BUY) ? (curP - openP) : (openP - curP);
      if(profitDist <= 0) continue; // 浮亏期间不动 SL
      double profitATR = profitDist / atr;

      // Stage 1: 保本
      if(!g_boStates[i].beMoved && profitATR >= InpBO_BE_TriggerATR) {
         double bePrice = openP;
         // 给保本加一个 buffer (1 个 spread)
         double spreadBuf = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double be = (pType == POSITION_TYPE_BUY) ? bePrice + spreadBuf : bePrice - spreadBuf;
         if(ModifyPositionSL(tk, be)) {
            g_boStates[i].beMoved = true;
            PrintFormat("🛡 [BO] ticket=%I64u 保本 @ %.5f (profit=%.2f ATR)",
                        tk, be, profitATR);
         }
      }
      // Stage 2: 追踪止损
      if(profitATR >= InpBO_TrailStartATR) {
         g_boStates[i].trailActive = true;
         if(profitATR > g_boStates[i].peakProfitATR) g_boStates[i].peakProfitATR = profitATR;
         double trailDist = atr * InpBO_TrailDistATR;
         double newSL = (pType == POSITION_TYPE_BUY) ? curP - trailDist : curP + trailDist;
         double curSL = PositionGetDouble(POSITION_SL);
         // 推进步长检查 (避免高频小幅修改)
         double stepDist = atr * InpBO_TrailStepATR;
         bool shouldUpdate = false;
         if(curSL == 0) shouldUpdate = true;
         else if(pType == POSITION_TYPE_BUY  && newSL - curSL >= stepDist) shouldUpdate = true;
         else if(pType == POSITION_TYPE_SELL && curSL - newSL >= stepDist) shouldUpdate = true;
         if(shouldUpdate) {
            if(ModifyPositionSL(tk, newSL)) {
               PrintFormat("📈 [BO] ticket=%I64u 追踪 SL→%.5f (peak %.2f ATR)",
                           tk, newSL, g_boStates[i].peakProfitATR);
            }
         }
      }
   }
}

//==================================================================
// 图表显示 (简洁版)
//==================================================================
void CreateLabel(const string name, int y, const string text, color clr, int fontSize = 10) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString (0, name, OBJPROP_FONT, "Consolas");
}

void UpdateDashboard() {
   double adx = GetADX(0);
   double atr = GetATR(g_hATR, 0);
   double atrAvg = GetATR_Mean(g_hATR, InpATR_AvgLookback);
   int gBuy  = CountOurPositions(0, ENG_GRID);
   int gSell = CountOurPositions(1, ENG_GRID);
   int bBuy  = CountOurPositions(0, ENG_BREAKOUT);
   int bSell = CountOurPositions(1, ENG_BREAKOUT);
   double gridPnL = SumOurFloatingProfit(ENG_GRID);
   double boPnL   = SumOurFloatingProfit(ENG_BREAKOUT);

   int y = 20, dy = 18;
   CreateLabel("V8_Title", y, "夔牛 V8 Adaptive (ATR+ADX)", clrGold, 12); y += dy + 4;
   CreateLabel("V8_Regime", y,
               StringFormat("市场: %s | ADX %.1f | ATR %.5f (avg %.5f)",
                            RegimeText(g_regime), adx, atr, atrAvg),
               clrCyan); y += dy;
   CreateLabel("V8_Acct", y,
               StringFormat("权益 $%.2f | 回撤 %.2f%% | 日亏 %.2f%%",
                            accInfo.Equity(), GetDrawdownPct(), GetDailyLossPct()),
               clrWhite); y += dy;
   color gridClr = (gridPnL >= 0) ? clrLime : clrRed;
   CreateLabel("V8_Grid", y,
               StringFormat("网格 多 %d / 空 %d | PnL $%.2f", gBuy, gSell, gridPnL),
               gridClr); y += dy;
   color boClr = (boPnL >= 0) ? clrLime : clrRed;
   CreateLabel("V8_BO", y,
               StringFormat("突破 多 %d / 空 %d | PnL $%.2f", bBuy, bSell, boPnL),
               boClr); y += dy;
   if(g_circuitActive) {
      int remain = (int)((g_circuitUntil - TimeCurrent()) / 60);
      CreateLabel("V8_Halt", y,
                  StringFormat("🛑 熔断中 剩余 %d 分钟", remain),
                  clrRed); y += dy;
   } else {
      ObjectDelete(0, "V8_Halt");
   }
   if(g_runPaused) {
      CreateLabel("V8_Pause", y, "⏸ EA 已暂停", clrYellow); y += dy;
   } else {
      ObjectDelete(0, "V8_Pause");
   }
   if(g_lastBlockReason != "") {
      string reasonShort = g_lastBlockReason;
      if(StringLen(reasonShort) > 60) reasonShort = StringSubstr(reasonShort, 0, 60) + "...";
      CreateLabel("V8_Reason", y, "阻塞: " + reasonShort, clrOrange, 9); y += dy;
   } else {
      ObjectDelete(0, "V8_Reason");
   }
}

void DeleteDashboard() {
   string names[] = {"V8_Title","V8_Regime","V8_Acct","V8_Grid","V8_BO",
                     "V8_Halt","V8_Pause","V8_Reason"};
   for(int i = 0; i < ArraySize(names); i++) ObjectDelete(0, names[i]);
}

//==================================================================
// MQL5 生命周期
//==================================================================
int OnInit() {
   // 仅支持对冲账户 (本 EA 同时持多空)
   if(accInfo.MarginMode() == ACCOUNT_MARGIN_MODE_RETAIL_NETTING) {
      Print("❌ 当前为 NETTING 账户, 不支持双向持仓, EA 退出");
      return INIT_FAILED;
   }

   // 创建指标句柄 (一次性, 避免 OnTick 重复创建)
   g_hADX      = iADX(_Symbol, InpRegimeTF, InpADX_Period);
   g_hATR      = iATR(_Symbol, InpRegimeTF, InpATR_Period);
   g_hATR_Exec = iATR(_Symbol, _Period, InpATR_Period);
   g_hTF_MA    = iMA(_Symbol, InpBO_TF_AnchorTF, InpBO_TF_AnchorMAPer, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hADX == INVALID_HANDLE || g_hATR == INVALID_HANDLE ||
      g_hATR_Exec == INVALID_HANDLE || g_hTF_MA == INVALID_HANDLE) {
      Print("❌ 指标初始化失败 err=", GetLastError());
      return INIT_FAILED;
   }

   // V8.3: H1 大趋势偏好指标
   if(InpEnableH1Bias) {
      g_hH1_FastEMA = iMA(_Symbol, InpH1_TF, InpH1_FastEMA, 0, MODE_EMA, PRICE_CLOSE);
      g_hH1_SlowEMA = iMA(_Symbol, InpH1_TF, InpH1_SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
      g_hH1_ADX     = iADX(_Symbol, InpH1_TF, InpH1_ADX_Period);
      if(g_hH1_FastEMA == INVALID_HANDLE || g_hH1_SlowEMA == INVALID_HANDLE ||
         g_hH1_ADX == INVALID_HANDLE) {
         Print("❌ H1 偏好指标初始化失败 err=", GetLastError());
         return INIT_FAILED;
      }
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints((ulong)InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_dailyStartEquity  = accInfo.Equity();
   g_peakEquity        = accInfo.Equity();
   g_dailyBaselineDay  = (datetime)((long)TimeCurrent() / 86400 * 86400);

   ArrayResize(g_boStates, 0);
   SyncBOStates();

   // 同步运行时开关初始值
   g_runEnableGrid     = InpEnableGrid;
   g_runEnableBreakout = InpEnableBreakout;
   g_runPaused         = false;

   CreateControlPanel();

   PrintFormat("✅ 夔牛 V8 Adaptive 启动 | Symbol=%s Period=%s RegimeTF=%s Magic=%I64d",
               _Symbol, EnumToString(_Period), EnumToString(InpRegimeTF), InpMagic);
   PrintFormat("📊 风控: 单笔风险=%.2f%% | 回撤上限=%.2f%% | 日亏上限=%.2f%%",
               InpRiskPercent, InpMaxDrawdownPct, InpDailyLossLimitPct);
   if(InpEnableDiagnostic) {
      Print("📋 诊断已启用, 每 ", InpDiagnosticIntervalSec,
            " 秒在无仓时输出阻塞原因. 也可点[输出诊断日志]按钮立即查看.");
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if(g_hADX != INVALID_HANDLE)        IndicatorRelease(g_hADX);
   if(g_hATR != INVALID_HANDLE)        IndicatorRelease(g_hATR);
   if(g_hATR_Exec != INVALID_HANDLE)   IndicatorRelease(g_hATR_Exec);
   if(g_hTF_MA != INVALID_HANDLE)      IndicatorRelease(g_hTF_MA);
   if(g_hH1_FastEMA != INVALID_HANDLE) IndicatorRelease(g_hH1_FastEMA);
   if(g_hH1_SlowEMA != INVALID_HANDLE) IndicatorRelease(g_hH1_SlowEMA);
   if(g_hH1_ADX != INVALID_HANDLE)     IndicatorRelease(g_hH1_ADX);
   DeleteDashboard();
   DeleteControlPanel();
   PrintFormat("👋 夔牛 V8 Adaptive 停止 reason=%d", reason);
}

//==================================================================
// 按钮事件处理
//==================================================================
void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam) {
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(StringFind(sparam, UI_PREFIX) != 0) return;
   string btn = StringSubstr(sparam, StringLen(UI_PREFIX));

   if(btn == "Pause") {
      g_runPaused = !g_runPaused;
      PrintFormat("⏯ [按钮] EA %s", g_runPaused ? "已暂停" : "已恢复");
   }
   else if(btn == "Grid") {
      g_runEnableGrid = !g_runEnableGrid;
      PrintFormat("🔧 [按钮] 网格引擎 %s", g_runEnableGrid ? "ON" : "OFF");
   }
   else if(btn == "Breakout") {
      g_runEnableBreakout = !g_runEnableBreakout;
      PrintFormat("🔧 [按钮] 突破引擎 %s", g_runEnableBreakout ? "ON" : "OFF");
   }
   else if(btn == "BuyNow") {
      ManualOpenOrder(ORDER_TYPE_BUY);
   }
   else if(btn == "SellNow") {
      ManualOpenOrder(ORDER_TYPE_SELL);
   }
   else if(btn == "CloseGrid") {
      CloseEngine(ENG_GRID, "手动按钮平仓");
   }
   else if(btn == "CloseBO") {
      CloseEngine(ENG_BREAKOUT, "手动按钮平仓");
   }
   else if(btn == "CloseAll") {
      CloseAllOurs("手动按钮: 平掉全部本 EA 持仓");
   }
   else if(btn == "Diag") {
      PrintDiagnostic(true);
   }

   // 重置按钮的按下状态, 刷新文字
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   CreateControlPanel();
   ChartRedraw();
}

//--- 手动开单 (用 ATR×SL 倍数 + 风险百分比手数)
void ManualOpenOrder(ENUM_ORDER_TYPE type) {
   string reason;
   if(!CanOpenNew(reason)) {
      PrintFormat("✋ [手动] 拒绝开单: %s", reason);
      return;
   }
   double atr = GetATR(g_hATR_Exec, 0);
   if(atr <= 0) {
      Print("✋ [手动] ATR 取值失败, 拒绝开单");
      return;
   }
   double slPrice, tpDummy;
   CalcSLTP(type, atr, InpBO_SL_ATR_Mult, 0, slPrice, tpDummy);
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = MathAbs(price - slPrice);
   double lots = CalcLotByRisk(slDist);
   string cmt = StringFormat("%s_M", InpComment);
   ulong tk = OpenMarketOrder(type, lots, slPrice, 0, cmt);
   if(tk == 0) Print("✋ [手动] 下单失败, 详见上方日志");
}

void OnTick() {
   // 1) 账户级监督 (最高优先级)
   UpdateRiskSupervisor();

   // 2) 市场状态识别
   UpdateMarketRegime();
   UpdateTrendBias();  // V8.3: H1 大趋势偏好

   // 3) 永久执行: 已存在突破单的动态止损 (即使状态切回震荡, 旧单也要管)
   ManageBreakoutTrailing();

   // 4) 永久执行: 网格篮子止盈止损 (即使状态切到趋势, 旧网格也要管)
   ManageGridBasket();

   // 5) 暂停模式: 只管存量, 不开新
   if(g_runPaused) {
      g_lastBlockReason = "EA 已暂停 (点[恢复 EA])";
      UpdateDashboard();
      PrintDiagnostic(false);
      return;
   }

   // 6) 熔断/极端波动期间不开新仓
   if(g_circuitActive) {
      g_lastBlockReason = "账户熔断中";
      UpdateDashboard();
      PrintDiagnostic(false);
      return;
   }
   if(g_regime == REGIME_HIGH_VOL || g_regime == REGIME_NEUTRAL ||
      g_regime == REGIME_UNKNOWN) {
      g_lastBlockReason = StringFormat("当前状态[%s]不开新仓", RegimeText(g_regime));
      UpdateDashboard();
      PrintDiagnostic(false);
      return;
   }

   // 7) 分支引擎
   if(g_regime == REGIME_RANGE)              ManageGridEngine();
   if(g_regime == REGIME_TREND_UP ||
      g_regime == REGIME_TREND_DOWN)         ManageBreakoutEngine();

   // 8) 刷新看板 + 诊断
   UpdateDashboard();
   PrintDiagnostic(false);
}
//+------------------------------------------------------------------+
