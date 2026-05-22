//+------------------------------------------------------------------+
//|                                        太极·爱牛 Ultra V7.mq5    |
//|                                  根据参数面板复刻的多引擎策略      |
//+------------------------------------------------------------------+
#property copyright "太极·夔牛 Multi-Engine Framework"
#property version   "2.40"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade trade;
CPositionInfo positionInfo;
CAccountInfo accountInfo;

//+------------------------------------------------------------------+
//| === [图] 太极·玄武 授权认证 ===                                    |
//+------------------------------------------------------------------+
input group "=== [图] 太极·玄武 授权认证 ==="
input string LicenseKey = "";  // 请输入系统授权码 (License Key)

//+------------------------------------------------------------------+
//| === [SYS] 战队部署开关 (Squad Deployment) ===                     |
//+------------------------------------------------------------------+
input group "=== [SYS] 战队部署开关 (Squad Deployment) ==="
input bool Enable_DuShe_Grid = true;      // [开启] 毒蛇主网格 (异步双向协动)
input bool Enable_NiuGui_Squad = false;    // [开启] 牛龟战队 (实体动能突击)
input bool Enable_QingLong_Squad = true;  // [开启] 青龙战队 (云观远控狙击)

//+------------------------------------------------------------------+
//| === [A] 全局风控与资金 ===                                         |
//+------------------------------------------------------------------+
input group "=== [A] 全局风控与资金 ==="
input double BaseLotSize = 0.05;           // 基础起步手数
input double MaxRiskPercent = 50.0;        // 最大保证金占用占余额比例 (%)

input group "=== [A1] 订单归属 (Phase1) ==="
input long   MagicNumber = 20260522;       // EA 魔术号
input bool   ManageOnlyOwnMagic = true;    // 仅管理本 EA 订单(兼容无魔术号历史单)

input group "=== [A2] 账户级风控 (Phase1) ==="
input double Risk_Warn_Account_Drawdown_Pct = 8.0;    // 预警: 净值回撤%
input double Risk_Freeze_Account_Drawdown_Pct = 12.0; // 冻结新开仓: 净值回撤%
input double Risk_Max_Account_Drawdown_Pct = 18.0;    // 熔断: 净值回撤%
input double Risk_Daily_Loss_Limit_Pct = 5.0;         // 单日最大亏损%
input double Risk_Min_Margin_Level_Pct = 350.0;       // 最低保证金水平%
input bool   Risk_Close_All_On_Circuit_Breaker = true;// 熔断时平掉本 EA 全部仓位
input int    Risk_Cooldown_After_Circuit_Minutes = 1440; // 熔断后冷却(分钟)

input group "=== [A3] 品种级风控 (Phase1) ==="
input double Risk_Symbol_Max_Loss_Pct = 8.0;          // 本品种最大浮亏占余额%
input double Risk_Symbol_Max_Total_Lots = 2.0;        // 本 EA 品种最大总手数
input double Risk_Direction_Max_Lots = 1.0;           // 单方向最大手数
input int    Risk_Symbol_Max_Positions = 18;          // 本 EA 最大持仓数

input group "=== [A4] 网格方向风控 (Phase1) ==="
input int    Grid_Safe_Max_Levels = 6;                // 安全最大网格层数
input double Grid_Max_Multiplier = 1.2;               // 网格倍率上限
input double Grid_Direction_Max_Loss_Pct = 4.0;       // 单方向浮亏%→冻结加仓
input double Grid_Direction_Hard_Loss_Pct = 6.0;      // 单方向浮亏%→方向止损
input double Grid_Trend_Freeze_ADX = 25.0;            // 强趋势 ADX 阈值(M15)
input double Grid_Trend_Freeze_ATR_Distance = 1.8;    // 距方向锚点 ATR 倍数
input bool   Grid_Allow_Against_Strong_Trend = false; // 允许强趋势逆势网格
input double ADX_Strength_Threshold = 25.0;           // ADX 强度阈值(与周期分离)

input group "=== [A5] 交易执行与运维 (Phase2) ==="
input int    Trade_Deviation_Points = 20;             // 市价单滑点(点)
input bool   Enable_Runtime_Config = true;            // 启用 KuiNiu_config.set 热更新
input int    Config_Poll_Seconds = 3;                 // 配置轮询间隔(秒)
input int    Zhuque_Max_Losses_Per_Day = 3;           // 朱雀单日最大亏损次数
input bool   Zhuque_Use_Closed_M1_Bar = true;         // 朱雀仅用已收盘 M1 K线
input double Regime_High_Vol_ATR_Multiple = 2.0;      // 高波动: ATR 相对均值倍数

//+------------------------------------------------------------------+
//| === [B] 纯物理空间观察雷达 (0惯后防爆盾) ===                        |
//+------------------------------------------------------------------+
input group "=== [B] 纯物理空间观察雷达 (0惯后防爆盾) ==="
input double M1_Candle_Range_Limit = 999.0; // M1单根K线轻量标幅判定 (绝巧计差基金)
input int Range_Freeze_Minutes = 15;        // K线振幅超限后冻结开仓时长(分钟)
input int ADX_Period = 14;                  // 宏观趋势强度(ADX)
input int ATR_Period = 14;                  // 宏观波动基(ATR)
input int Tick_Speed_Limit = 25;            // [未启用] 备用 Tick 狂暴滤速

//+------------------------------------------------------------------+
//| === [Δ] V7 专属：极端时段异步沙盒体系 ===                           |
//+------------------------------------------------------------------+
input group "=== [Δ] V7 专属：极端时段异步沙盒体系 ==="
input double Sandbox_Trigger_Profit = 10.0;     // 沙盒触发：期间非位移爬升喷(基金)
input double Sandbox_Max_Drawdown = 2.5;        // 沙盒触发：期间最大允许物理回撤(基金)
input double Sandbox_Strike_Profit = 1.5;       // 沙盒出击：M1未收线实时播针组击商(基金)
input int Sandbox_Exit_Profit_Orders = 5;       // 沙盒退出：削峰自救降至安全水位层数

//+------------------------------------------------------------------+
//| === [C] 主引擎：异步双向网格 (挂单 M1 空间张力防爆盾) ===            |
//+------------------------------------------------------------------+
input group "=== [C] 主引擎：异步双向网格 (挂单 M1 空间张力防爆盾) ==="
input int Grid_Cooldown_Seconds = 3;        // 野控令触时间 (秒)
input double Grid_Spacing_Points = 250;     // 基础网格间距 (微点)
input double Grid_Multiplier = 1.5;         // 网格倍投系数
input int Grid_Max_Levels = 10;             // 吸星之塔 (绝杀上限)
input int Grid_Profit_Orders_Threshold = 6; // 激活削峰自救层数
input double Grid_Hedge_Target_Profit = 1.0;// 首尾对冲目标利润 ($)

//+------------------------------------------------------------------+
//| === [C1] 主网格趋势过滤器 (M5均线+MACD双重确认) ===                 |
//+------------------------------------------------------------------+
input group "=== [C1] 主网格趋势过滤器 (M5均线+MACD双重确认) ==="
input bool Enable_Trend_Filter = true;     // 启用趋势过滤器
input bool Grid_Trend_First_Layer_Immediate = true; // 趋势方向首层不等待间距回撤
input bool Enable_Trade_Diagnostics = true;  // 无仓时周期性输出不下单原因
input int Trade_Diagnostics_Interval_Sec = 60; // 诊断日志间隔(秒)
input int M5_MA_Period = 20;                // M5均线周期
input int M5_MACD_Fast = 12;                // MACD快线周期
input int M5_MACD_Slow = 26;                // MACD慢线周期
input int M5_MACD_Signal = 9;               // MACD信号线周期

//+------------------------------------------------------------------+
//| === [C2] 主网格分阶移动止盈 (上带视角呼吸追踪) ===                   |
//+------------------------------------------------------------------+
input group "=== [C2] 主网格分阶移动止盈 (上带视角呼吸追踪) ==="
input double TP_Level1_Trigger = 5.0;       // 第1层(单兵)追踪激活线(美金)
input double TP_Level2_4_Trigger = 10.0;    // 第2-4层单边盈追踪激活线(美金)
input double TP_Level5_7_Trigger = 20.0;    // 第5-7层单边盈追踪激活线(美金)
input double TP_Level8_Plus_Trigger = 50.0; // 爱牛杀水区(8层+)追踪激活线(美金)
input double TP_Drawback_Threshold = 2.0;   // 【动态基数】极值回撤最新底线(美金)

//+------------------------------------------------------------------+
//| === [D] 辅引擎：朱雀双模突击 (V7实体闭环高胜率版) ===                |
//+------------------------------------------------------------------+
input group "=== [D] 辅引擎：朱雀双模突击 (V7实体闭环高胜率版) ==="
input double Zhuque_Base_Lot = 0.1;         // 朱雀突击基础手数
input double Zhuque_Max_Lot_Limit = 2.0;    // 朱雀突击极限防爆合手数上限
input double Zhuque_TP_Trigger = 50.0;      // 极值止损止盈激活线 (美金)
input double Zhuque_Drawback_Ratio = 0.2;   // 极值最高利润回撤新比例
input double Zhuque_Hard_SL = 15.0;         // 绝对物理硬止损线 (美金)

//+------------------------------------------------------------------+
//| === [E] 辅引擎：青龙宏观波段 (结构慢体推土机) ===                    |
//+------------------------------------------------------------------+
input group "=== [E] 辅引擎：青龙宏观波段 (结构慢体推土机) ==="
input double Qinglong_Base_Lot = 0.05;      // 青龙含量手基数
input int Qinglong_Max_Add_Times = 5;       // 极慢单边顺势最大加仓层数
input int Qinglong_SR_Period = 10;          // 寻找合/波峰结构支撑K线周期数
input double Qinglong_Structure_SL = 0.2;   // [未启用] 结构止损缓冲
input double Qinglong_Hard_SL = 5.0;        // 备用物理硬止损(美金)
input bool   Qinglong_Enable_ATR_Trail = true;   // 启用 ATR 追踪止损
input double Qinglong_ATR_SL_Multiple = 1.8;     // 初始止损 = ATR × 倍数
input double Qinglong_ATR_Trail_Multiple = 2.2;  // 追踪止损距市价 ATR 倍数
input double Qinglong_Trail_Step_ATR = 0.3;      // SL 更新最小推进(ATR 倍数)
input bool   Qinglong_Profit_Add_Only = true;    // 仅篮子浮盈时允许加仓
input double Qinglong_TP_Activate_Money = 8.0;   // 篮子盈利达此金额激活追踪止盈
input double Qinglong_TP_Drawback_Ratio = 0.25;  // 从峰值回撤此比例则平仓
input double Qinglong_TP_Min_Peak_Money = 3.0;   // 峰值盈利最低要求(防抖动)

input group "=== [F] 减灾引擎 (削减敞口，非补仓) ==="
input bool   Enable_Rescue_Engine = true;           // 启用减灾引擎
input int    Rescue_Min_Grid_Levels_To_Act = 3;     // 至少 N 层常规网格才渐进减仓
input int    Rescue_Target_Max_Levels = 3;           // 减仓目标：常规网格最多保留层数
input int    Rescue_Layers_Per_Action = 1;          // 每次减灾最多平仓层数
input int    Rescue_Action_Cooldown_Seconds = 60;   // 单方向减灾动作冷却(秒)
input double Rescue_Warning_Loss_Pct_Of_Budget = 40.0; // 达方向预算此%→清理微利层
input bool   Rescue_Close_Tail_Layers_First = true;  // 优先平最晚加仓(尾部)
input bool   Rescue_Close_Worst_Loss_Layer = true;   // 优先平浮亏最大的一层
input bool   Rescue_Close_Sniper_In_Risk = true;     // 风险态平掉沙盒狙击单
input bool   Rescue_Use_Peak_Cut = true;             // 启用首尾削峰(盈利配对)

input group "=== [G] 保护性对冲 (有限敞口，非网格化) ==="
input bool   Enable_Protective_Hedge = true;          // 启用保护性对冲
input double Hedge_Max_Ratio_Of_Grid_Lots = 0.5;    // 对冲手数 ≤ 该方向网格手数×比例
input double Hedge_Min_Grid_Loss_Money = 3.0;       // 方向网格浮亏达此金额(USD)才对冲
input int    Hedge_Min_Risk_State = 2;              // 最低风险态: 2=禁加 3=只减
input int    Hedge_Max_Hold_Minutes = 120;          // 最长持有分钟
input double Hedge_Unlock_Profit_Money = 2.0;       // 对冲单盈利达此金额解锁平仓
input bool   Hedge_Unlock_On_Risk_Normal = true;    // 方向恢复「正常」时平对冲
input int    Hedge_Action_Cooldown_Seconds = 120;   // 单方向开仓冷却(秒)

input group "=== [H] 新闻过滤 ==="
input bool   News_Filter_Enabled = true;              // 启用经济日历新闻过滤
input int    News_Before_Minutes = 30;                // 新闻发布前冻结(分钟)
input int    News_After_Minutes = 30;                 // 新闻发布后冻结(分钟)
input bool   News_High_Importance = true;             // 过滤高重要性
input bool   News_Medium_Importance = false;          // 过滤中重要性
input bool   News_Include_USD_For_Metals = true;      // 黄金/金属品种匹配 USD 新闻
input bool   News_Freeze_When_Calendar_Unavailable = false; // 日历不可用时是否冻结(默认否，避免长期不下单)
input bool   News_Block_New_Opens = true;             // 新闻窗口内禁止新开仓

//+------------------------------------------------------------------+
//| 全局变量                                                           |
//+------------------------------------------------------------------+
// 网格系统
struct GridOrder {
   ulong ticket;
   int level;
   double openPrice;
   double lots;
   int type; // 0=BUY, 1=SELL
   datetime openTime;
   string comment;
};
GridOrder gridOrders[];

struct DirectionBattle {
   double anchorPrice;
   double maxProfit;
   bool trailingActive;
   datetime lastSniperBarTime;
   int sniperLevel;  // 沙盒狙击独立层级计数
};
DirectionBattle buyBattle;
DirectionBattle sellBattle;
ulong closingTickets[];

// 朱雀引擎
struct ZhuquePosition {
   ulong ticket;
   double openPrice;
   double maxProfit;
   int type;
};
ZhuquePosition zhuquePos;

// 青龙引擎
struct QinglongPosition {
   ulong ticket;
   double openPrice;
   int addTimes;
   int type;
   double basketMaxProfit;
};
QinglongPosition qinglongPos;

struct ProtectiveHedgeSlot {
   ulong ticket;
   int protectedDirection;
   datetime openTime;
   double lots;
};
ProtectiveHedgeSlot g_hedgeBuySide;
ProtectiveHedgeSlot g_hedgeSellSide;
datetime g_lastHedgeOpenBuy = 0;
datetime g_lastHedgeOpenSell = 0;

// 沙盒系统
bool sandboxActive = false;
bool sandboxBuyDisabled = false;
bool sandboxSellDisabled = false;
double sandboxTriggerEquity = 0;
int sandboxMode = 0; // -1=极端阴跌(禁多), 1=极端慢涨(禁空)
datetime lastSandboxCheckedBarTime = 0;

// 时间控制
datetime lastGridOrderTime = 0;
datetime lastZhuqueSignalTime = 0;
datetime lastGridBuyOrderTime = 0;
datetime lastGridSellOrderTime = 0;
datetime lastGridBuyOpenBarTime = 0;
datetime lastGridSellOpenBarTime = 0;
datetime lastZhuqueSignalBarTime = 0;
datetime lastQinglongSignalBarTime = 0;
datetime lastQinglongAddBarTime = 0;
datetime lastQinglongActionTime = 0;

// 防爆盾：K线振幅冻结
datetime rangeFreezeUntilTime = 0;  // 冻结开仓直到此时间
double lastTriggerRange = 0;        // 触发冻结的K线振幅

// 趋势过滤器
datetime lastM5BarTime = 0;         // 上次检查的M5 K线时间
datetime g_lastDiagPrintTime = 0;
datetime g_lastGridDenyLogBuy = 0;
datetime g_lastGridDenyLogSell = 0;
int trendDirection = 0;             // 趋势方向：1=只开多，-1=只开空，0=双向

// 指标句柄
int handleADX;
int handleATR;
int handleM5_MA;
int handleM5_MACD;

// 账户初始状态
double initialEquity = 0;

//--- Phase1: 引擎与风险状态
enum EngineType {
   ENGINE_GRID = 0,
   ENGINE_TREND = 1,
   ENGINE_BREAKOUT = 2,
   ENGINE_RESCUE = 3,
   ENGINE_HEDGE = 4
};

enum GlobalRiskState {
   GRISK_NORMAL = 0,
   GRISK_WARN = 1,
   GRISK_FREEZE = 2,
   GRISK_CIRCUIT = 3
};

enum DirectionRiskState {
   DIR_RISK_NORMAL = 0,
   DIR_RISK_WARNING = 1,
   DIR_RISK_FREEZE_ADD = 2,
   DIR_RISK_REDUCE_ONLY = 3,
   DIR_RISK_CUT_LOSS = 4
};

long g_expertMagic = 0;
GlobalRiskState g_globalRisk = GRISK_NORMAL;
string g_lastRiskDenyReason = "";
string g_lastRiskEvent = "";
datetime g_circuitCooldownUntil = 0;
datetime g_dailyBaselineDay = 0;
double g_dailyStartEquity = 0;
double g_peakEquity = 0;
DirectionRiskState g_buyDirRisk = DIR_RISK_NORMAL;
DirectionRiskState g_sellDirRisk = DIR_RISK_NORMAL;
DirectionRiskState g_prevBuyDirRisk = DIR_RISK_NORMAL;
DirectionRiskState g_prevSellDirRisk = DIR_RISK_NORMAL;
bool g_allowNewPositions = true;
int handleM15_MA_Fast = INVALID_HANDLE;
int handleM15_MA_Slow = INVALID_HANDLE;
int handleM15_ADX = INVALID_HANDLE;

enum MarketRegime {
   REGIME_RANGE = 0,
   REGIME_TREND_UP = 1,
   REGIME_TREND_DOWN = 2,
   REGIME_HIGH_VOLATILITY = 3,
   REGIME_RECOVERY = 4,
   REGIME_NEWS_RISK = 5
};

MarketRegime g_marketRegime = REGIME_RANGE;
bool g_newsRiskActive = false;
string g_lastNewsTitle = "";
bool g_calendarUnavailable = false;
bool g_eff_News_Filter_Enabled = true;
int g_eff_News_Before_Minutes = 30;
int g_eff_News_After_Minutes = 30;
bool g_eff_News_High_Importance = true;
bool g_eff_News_Medium_Importance = false;
bool g_eff_News_Include_USD_For_Metals = true;
bool g_eff_News_Freeze_When_Calendar_Unavailable = false;
bool g_eff_News_Block_New_Opens = true;
datetime g_lastM5ClosedBarTime = 0;
datetime g_lastConfigApplied = 0;
datetime g_lastOpenFailTime = 0;
datetime g_lastCloseFailTime = 0;
int g_openFailCount = 0;
int g_closeFailCount = 0;
int g_zhuqueLossCountToday = 0;
datetime g_zhuqueLossDay = 0;

bool g_eff_IsPaused = false;
bool g_eff_Enable_DuShe_Grid = true;
bool g_eff_Enable_NiuGui_Squad = false;
bool g_eff_Enable_QingLong_Squad = true;
double g_eff_Risk_Warn_Account_Drawdown_Pct = 8.0;
double g_eff_Risk_Freeze_Account_Drawdown_Pct = 12.0;
double g_eff_Risk_Max_Account_Drawdown_Pct = 18.0;
double g_eff_Risk_Daily_Loss_Limit_Pct = 5.0;
int g_eff_Grid_Safe_Max_Levels = 6;
bool g_eff_Enable_Rescue_Engine = true;
int g_eff_Rescue_Target_Max_Levels = 3;
datetime g_lastRescueBuyTime = 0;
datetime g_lastRescueSellTime = 0;
string g_lastRescueAction = "";
bool g_eff_Enable_Protective_Hedge = true;

#define KN_UI_PREFIX "KN_"
const int KN_BTN_WIDTH_DEF  = 100;
const int KN_BTN_HEIGHT_DEF = 24;
const int KN_BTN_BASE_Y     = 28;   // 底部时间轴/状态栏留白
const int KN_BTN_MIN_STEP   = 20;
const int KN_BTN_RIGHT_RESERVE_MIN = 96;  // 价位刻度+滚动条最小留白
bool g_uiPanelExpanded = true;
int g_uiBtnWidth = KN_BTN_WIDTH_DEF;
int g_uiBtnHeight = KN_BTN_HEIGHT_DEF;
int g_uiBtnStep = 28;
int g_uiPanelLeftX = 8;   // 面板左缘距图表左缘(CORNER_LEFT_LOWER)
int g_uiBtnColGap = 6;

int GetChartRightReservePx(const int chartW) {
   int margin = KN_BTN_RIGHT_RESERVE_MIN;
   if(chartW < 500) margin = 72;
   else if(chartW < 800) margin = 88;
   else margin = MathMax(KN_BTN_RIGHT_RESERVE_MIN, chartW / 10);
   if(ChartGetInteger(0, CHART_SHOW_PRICE_SCALE) == 0) {
      margin = MathMax(48, margin - 36);
   }
   return margin;
}

void CalcControlPanelLayout(const int rowCount) {
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(chartH < 120) chartH = 120;
   if(chartW < 200) chartW = 200;

   int reserveTop = 12;
   int reserveBottom = 24;
   int availH = chartH - reserveTop - reserveBottom;
   int rows = MathMax(1, rowCount);

   g_uiBtnHeight = KN_BTN_HEIGHT_DEF;
   g_uiBtnStep = g_uiBtnHeight + 4;
   int needH = KN_BTN_BASE_Y + rows * g_uiBtnStep;
   if(needH > availH) {
      g_uiBtnStep = MathMax(KN_BTN_MIN_STEP, availH / rows);
      g_uiBtnHeight = MathMax(18, g_uiBtnStep - 4);
   }

   int rightReserve = GetChartRightReservePx(chartW);
   int maxBlockW = chartW - rightReserve - 16;
   g_uiBtnColGap = 6;
   g_uiBtnWidth = MathMin(KN_BTN_WIDTH_DEF, (maxBlockW - g_uiBtnColGap) / 2);
   if(g_uiBtnWidth < 76) g_uiBtnWidth = 76;

   int blockW = g_uiBtnWidth * 2 + g_uiBtnColGap;
   g_uiPanelLeftX = chartW - rightReserve - blockW;
   if(g_uiPanelLeftX < 8) g_uiPanelLeftX = 8;
}

void SeedEffectiveParams() {
   g_eff_IsPaused = false;
   g_eff_Enable_DuShe_Grid = Enable_DuShe_Grid;
   g_eff_Enable_NiuGui_Squad = Enable_NiuGui_Squad;
   g_eff_Enable_QingLong_Squad = Enable_QingLong_Squad;
   g_eff_Risk_Warn_Account_Drawdown_Pct = Risk_Warn_Account_Drawdown_Pct;
   g_eff_Risk_Freeze_Account_Drawdown_Pct = Risk_Freeze_Account_Drawdown_Pct;
   g_eff_Risk_Max_Account_Drawdown_Pct = Risk_Max_Account_Drawdown_Pct;
   g_eff_Risk_Daily_Loss_Limit_Pct = Risk_Daily_Loss_Limit_Pct;
   g_eff_Grid_Safe_Max_Levels = Grid_Safe_Max_Levels;
   g_eff_Enable_Rescue_Engine = Enable_Rescue_Engine;
   g_eff_Rescue_Target_Max_Levels = Rescue_Target_Max_Levels;
   g_eff_Enable_Protective_Hedge = Enable_Protective_Hedge;
   g_eff_News_Filter_Enabled = News_Filter_Enabled;
   g_eff_News_Before_Minutes = News_Before_Minutes;
   g_eff_News_After_Minutes = News_After_Minutes;
   g_eff_News_High_Importance = News_High_Importance;
   g_eff_News_Medium_Importance = News_Medium_Importance;
   g_eff_News_Include_USD_For_Metals = News_Include_USD_For_Metals;
   g_eff_News_Freeze_When_Calendar_Unavailable = News_Freeze_When_Calendar_Unavailable;
   g_eff_News_Block_New_Opens = News_Block_New_Opens;
   g_hedgeBuySide.ticket = 0;
   g_hedgeBuySide.protectedDirection = 0;
   g_hedgeSellSide.ticket = 0;
   g_hedgeSellSide.protectedDirection = 1;
}

bool ParseBoolConfig(const string val) {
   string v = val;
   StringToLower(v);
   StringTrimLeft(v);
   StringTrimRight(v);
   return (v == "true" || v == "1" || v == "yes" || v == "on");
}

bool ValidateRuntimeValue(const string key, const string val, string &err) {
   err = "";
   if(key == "KN_IsPaused" || key == "Enable_DuShe_Grid" || key == "Enable_NiuGui_Squad" ||
      key == "Enable_QingLong_Squad" || key == "Enable_Rescue_Engine" ||
      key == "Enable_Protective_Hedge" || key == "News_Filter_Enabled" ||
      key == "News_High_Importance" || key == "News_Medium_Importance" ||
      key == "News_Block_New_Opens") {
      return true;
   }
   if(key == "News_Before_Minutes" || key == "News_After_Minutes") {
      int i = (int)StringToInteger(val);
      if(i < 0 || i > 240) { err = key + " out of range"; return false; }
      return true;
   }
   if(key == "Rescue_Target_Max_Levels") {
      int i = (int)StringToInteger(val);
      if(i < 1 || i > 15) { err = "Rescue_Target_Max_Levels out of range"; return false; }
      return true;
   }
   if(StringFind(key, "Risk_") == 0 || key == "Grid_Safe_Max_Levels") {
      double d = StringToDouble(val);
      int i = (int)StringToInteger(val);
      if(key == "Grid_Safe_Max_Levels") {
         if(i < 1 || i > 20) { err = "Grid_Safe_Max_Levels out of range"; return false; }
         return true;
      }
      if(d < 0 || d > 100) { err = key + " out of range"; return false; }
      return true;
   }
   err = "unknown key";
   return false;
}

bool ApplyRuntimeOverride(const string key, const string val) {
   string err = "";
   if(!ValidateRuntimeValue(key, val, err)) {
      Print("⚠️ [配置] 拒绝 ", key, "=", val, " (", err, ")");
      return false;
   }
   if(key == "KN_IsPaused") { g_eff_IsPaused = ParseBoolConfig(val); return true; }
   if(key == "Enable_DuShe_Grid") { g_eff_Enable_DuShe_Grid = ParseBoolConfig(val); return true; }
   if(key == "Enable_NiuGui_Squad") { g_eff_Enable_NiuGui_Squad = ParseBoolConfig(val); return true; }
   if(key == "Enable_QingLong_Squad") { g_eff_Enable_QingLong_Squad = ParseBoolConfig(val); return true; }
   if(key == "Risk_Warn_Account_Drawdown_Pct") { g_eff_Risk_Warn_Account_Drawdown_Pct = StringToDouble(val); return true; }
   if(key == "Risk_Freeze_Account_Drawdown_Pct") { g_eff_Risk_Freeze_Account_Drawdown_Pct = StringToDouble(val); return true; }
   if(key == "Risk_Max_Account_Drawdown_Pct") { g_eff_Risk_Max_Account_Drawdown_Pct = StringToDouble(val); return true; }
   if(key == "Risk_Daily_Loss_Limit_Pct") { g_eff_Risk_Daily_Loss_Limit_Pct = StringToDouble(val); return true; }
   if(key == "Grid_Safe_Max_Levels") { g_eff_Grid_Safe_Max_Levels = (int)StringToInteger(val); return true; }
   if(key == "Enable_Rescue_Engine") { g_eff_Enable_Rescue_Engine = ParseBoolConfig(val); return true; }
   if(key == "Rescue_Target_Max_Levels") { g_eff_Rescue_Target_Max_Levels = (int)StringToInteger(val); return true; }
   if(key == "Enable_Protective_Hedge") { g_eff_Enable_Protective_Hedge = ParseBoolConfig(val); return true; }
   if(key == "News_Filter_Enabled") { g_eff_News_Filter_Enabled = ParseBoolConfig(val); return true; }
   if(key == "News_Before_Minutes") { g_eff_News_Before_Minutes = (int)StringToInteger(val); return true; }
   if(key == "News_After_Minutes") { g_eff_News_After_Minutes = (int)StringToInteger(val); return true; }
   if(key == "News_High_Importance") { g_eff_News_High_Importance = ParseBoolConfig(val); return true; }
   if(key == "News_Medium_Importance") { g_eff_News_Medium_Importance = ParseBoolConfig(val); return true; }
   if(key == "News_Block_New_Opens") { g_eff_News_Block_New_Opens = ParseBoolConfig(val); return true; }
   if(key == "News_Freeze_When_Calendar_Unavailable") {
      g_eff_News_Freeze_When_Calendar_Unavailable = ParseBoolConfig(val);
      return true;
   }
   return false;
}

bool ReloadRuntimeConfig(const bool forceApply) {
   if(!Enable_Runtime_Config) return false;
   string filename = "KuiNiu_config.set";
   if(!FileIsExist(filename, FILE_COMMON)) return false;

   int fh = FileOpen(filename, FILE_READ | FILE_TXT | FILE_COMMON);
   if(fh == INVALID_HANDLE) return false;

   datetime mtime = (datetime)FileGetInteger(fh, FILE_MODIFY_DATE);
   if(!forceApply && mtime > 0 && mtime <= g_lastConfigApplied) {
      FileClose(fh);
      return false;
   }

   int applied = 0, rejected = 0;
   while(!FileIsEnding(fh)) {
      string line = FileReadString(fh);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(line == "" || StringGetCharacter(line, 0) == '#') continue;
      int eq = StringFind(line, "=");
      if(eq <= 0) continue;
      string key = StringSubstr(line, 0, eq);
      string val = StringSubstr(line, eq + 1);
      StringTrimLeft(key);
      StringTrimRight(key);
      StringTrimLeft(val);
      StringTrimRight(val);
      if(ApplyRuntimeOverride(key, val)) applied++;
      else rejected++;
   }
   FileClose(fh);
   if(mtime > 0) g_lastConfigApplied = mtime;
   if(applied > 0) {
      PrintFormat("📁 [配置] 热更新 %d 项 (拒绝 %d)", applied, rejected);
   }
   return applied > 0;
}

ENUM_ORDER_TYPE_FILLING GetSymbolFillingMode() {
   long fillingMode = 0;
   if(!SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE, fillingMode)) {
      return ORDER_FILLING_IOC;
   }
   if((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   if((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   long executionMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   if(executionMode != SYMBOL_TRADE_EXECUTION_MARKET) return ORDER_FILLING_RETURN;
   return ORDER_FILLING_IOC;
}

//+------------------------------------------------------------------+
//| Phase1: 手数规范化                                                 |
//+------------------------------------------------------------------+
double NormalizeVolume(double volume) {
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0) vstep = 0.01;
   volume = MathFloor(volume / vstep + 1e-8) * vstep;
   if(volume < vmin) volume = vmin;
   if(volume > vmax) volume = vmax;
   return NormalizeDouble(volume, (int)MathMax(2, MathCeil(-MathLog10(vstep))));
}

//+------------------------------------------------------------------+
//| Phase1: 本 EA 注释识别(含历史单)                                    |
//+------------------------------------------------------------------+
bool IsHedgeComment(const string comment) {
   return (StringFind(comment, "QK|HEDGE") == 0);
}

int GetHedgeProtectedDirection(const string comment) {
   if(StringFind(comment, "|D0") >= 0) return 0;
   if(StringFind(comment, "|D1") >= 0) return 1;
   if(StringFind(comment, "QK|HEDGE|SELL") == 0) return 0;
   if(StringFind(comment, "QK|HEDGE|BUY") == 0) return 1;
   return -1;
}

bool IsLegacyEAComment(const string comment) {
   if(StringFind(comment, "Grid_") == 0) return true;
   if(StringFind(comment, "ZhuQue_") == 0) return true;
   if(StringFind(comment, "QingLong") == 0) return true;
   if(StringFind(comment, "QK|") == 0) return true;
   return false;
}

bool IsOurPositionByMagic(const long magic, const string comment) {
   if(magic == g_expertMagic) return true;
   if(ManageOnlyOwnMagic) {
      return (magic == 0 && IsLegacyEAComment(comment));
   }
   return IsLegacyEAComment(comment);
}

bool IsOurPositionSelected() {
   if(positionInfo.Symbol() != _Symbol) return false;
   return IsOurPositionByMagic((long)positionInfo.Magic(), positionInfo.Comment());
}

//+------------------------------------------------------------------+
//| Phase1: 账户回撤与日内基准                                          |
//+------------------------------------------------------------------+
void RefreshDailyBaseline() {
   datetime today = (datetime)((long)TimeCurrent() / 86400 * 86400);
   if(g_dailyBaselineDay != today || g_dailyStartEquity <= 0) {
      g_dailyBaselineDay = today;
      g_dailyStartEquity = accountInfo.Equity();
   }
}

double GetAccountDrawdownPct() {
   if(initialEquity <= 0) return 0;
   double eq = accountInfo.Equity();
   if(eq > g_peakEquity) g_peakEquity = eq;
   if(g_peakEquity <= 0) return 0;
   return (g_peakEquity - eq) / g_peakEquity * 100.0;
}

double GetDailyLossPct() {
   RefreshDailyBaseline();
   if(g_dailyStartEquity <= 0) return 0;
   double eq = accountInfo.Equity();
   if(eq >= g_dailyStartEquity) return 0;
   return (g_dailyStartEquity - eq) / g_dailyStartEquity * 100.0;
}

double GetOurSymbolFloatingPnL() {
   double pnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(!IsOurPositionSelected()) continue;
      pnl += positionInfo.Profit() + positionInfo.Swap();
   }
   return pnl;
}

int CountOurPositions() {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(IsOurPositionSelected()) n++;
   }
   return n;
}

double GetOurTotalLots() {
   double lots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(!IsOurPositionSelected()) continue;
      lots += positionInfo.Volume();
   }
   return lots;
}

double GetOurDirectionLots(int direction) {
   double lots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(!IsOurPositionSelected()) continue;
      int type = (positionInfo.Type() == POSITION_TYPE_BUY) ? 0 : 1;
      string comment = positionInfo.Comment();
      if(IsGridComment(comment)) {
         int cdir = GetGridDirectionFromComment(comment);
         if(cdir >= 0) type = cdir;
      }
      if(type == direction) lots += positionInfo.Volume();
   }
   return lots;
}

double GetGridDirectionFloatingLossMoney(int direction) {
   double pnl = GetGridBasketProfit(direction);
   return (pnl < 0) ? -pnl : 0;
}

void ResetHedgeSlotByDirection(const int protectedDirection) {
   if(protectedDirection == 0) {
      g_hedgeBuySide.ticket = 0;
      g_hedgeBuySide.openTime = 0;
      g_hedgeBuySide.lots = 0;
      g_hedgeBuySide.protectedDirection = 0;
   } else {
      g_hedgeSellSide.ticket = 0;
      g_hedgeSellSide.openTime = 0;
      g_hedgeSellSide.lots = 0;
      g_hedgeSellSide.protectedDirection = 1;
   }
}

ulong GetHedgeTicket(const int protectedDirection) {
   return (protectedDirection == 0) ? g_hedgeBuySide.ticket : g_hedgeSellSide.ticket;
}

double GetGridOnlyDirectionLots(const int direction) {
   double lots = 0;
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type != direction) continue;
      if(StringFind(gridOrders[i].comment, "_Sniper") >= 0) continue;
      if(PositionSelectByTicket(gridOrders[i].ticket)) {
         lots += PositionGetDouble(POSITION_VOLUME);
      }
   }
   return lots;
}

void SyncProtectiveHedgeSlots() {
   ResetHedgeSlotByDirection(0);
   ResetHedgeSlotByDirection(1);

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(!IsOurPositionSelected()) continue;
      string comment = positionInfo.Comment();
      if(!IsHedgeComment(comment)) continue;
      int pd = GetHedgeProtectedDirection(comment);
      if(pd < 0) continue;
      if(pd == 0) {
         g_hedgeBuySide.ticket = positionInfo.Ticket();
         g_hedgeBuySide.protectedDirection = 0;
         g_hedgeBuySide.openTime = (datetime)positionInfo.Time();
         g_hedgeBuySide.lots = positionInfo.Volume();
      } else {
         g_hedgeSellSide.ticket = positionInfo.Ticket();
         g_hedgeSellSide.protectedDirection = 1;
         g_hedgeSellSide.openTime = (datetime)positionInfo.Time();
         g_hedgeSellSide.lots = positionInfo.Volume();
      }
   }
}

void CloseProtectiveHedge(const int protectedDirection, const string reason) {
   ulong ticket = GetHedgeTicket(protectedDirection);
   if(ticket == 0) return;
   if(PositionSelectByTicket(ticket)) {
      CloseTrackedPosition(ticket);
      Print("🛡️ [对冲解锁] 保护方向=", protectedDirection, " ", reason);
   }
   ResetHedgeSlotByDirection(protectedDirection);
}

bool HedgeRiskStateAllowsOpen(const int protectedDirection) {
   DirectionRiskState st = (protectedDirection == 0) ? g_buyDirRisk : g_sellDirRisk;
   if(Hedge_Min_Risk_State <= (int)DIR_RISK_FREEZE_ADD) {
      return (st >= DIR_RISK_FREEZE_ADD);
   }
   return (st >= DIR_RISK_REDUCE_ONLY);
}

bool CanOpenProtectiveHedge(const int protectedDirection, double &lots, string &reason) {
   reason = "";
   if(!g_eff_Enable_Protective_Hedge) {
      reason = "hedge disabled";
      return false;
   }
   if(!HedgeRiskStateAllowsOpen(protectedDirection)) {
      reason = "direction risk below hedge threshold";
      return false;
   }
   ulong activeTicket = GetHedgeTicket(protectedDirection);
   if(activeTicket > 0 && PositionSelectByTicket(activeTicket)) {
      reason = "hedge already active";
      return false;
   }

   double gridLots = GetGridOnlyDirectionLots(protectedDirection);
   if(gridLots <= 0) {
      reason = "no grid lots on protected side";
      return false;
   }
   double dirLoss = GetGridDirectionFloatingLossMoney(protectedDirection);
   if(dirLoss < Hedge_Min_Grid_Loss_Money) {
      reason = "grid loss below hedge minimum";
      return false;
   }

   datetime lastOpen = (protectedDirection == 0) ? g_lastHedgeOpenBuy : g_lastHedgeOpenSell;
   if(lastOpen > 0 && TimeCurrent() - lastOpen < Hedge_Action_Cooldown_Seconds) {
      reason = "hedge open cooldown";
      return false;
   }

   lots = NormalizeVolume(gridLots * Hedge_Max_Ratio_Of_Grid_Lots);
   if(lots <= 0) {
      reason = "hedge lots zero after normalize";
      return false;
   }

   ENUM_ORDER_TYPE hedgeType = (protectedDirection == 0) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   if(!CheckMarginForLots(lots, hedgeType, reason)) return false;

   double price = (hedgeType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(!PreOrderCheckDeal(hedgeType, lots, price, 0, 0, reason)) return false;
   return true;
}

bool OpenProtectiveHedge(const int protectedDirection) {
   double lots = 0;
   string reason = "";
   if(!CanOpenProtectiveHedge(protectedDirection, lots, reason)) {
      return false;
   }

   ENUM_ORDER_TYPE hedgeType = (protectedDirection == 0) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   string comment = (protectedDirection == 0) ? "QK|HEDGE|SELL|D0" : "QK|HEDGE|BUY|D1";
   if(!ExecutePositionOpen(ENGINE_HEDGE, hedgeType, lots, 0, 0, comment, reason)) {
      return false;
   }

   ulong ticket = FindLatestPositionTicketByComment(comment);
   if(protectedDirection == 0) {
      g_hedgeBuySide.ticket = ticket;
      g_hedgeBuySide.protectedDirection = 0;
      g_hedgeBuySide.openTime = TimeCurrent();
      g_hedgeBuySide.lots = lots;
      g_lastHedgeOpenBuy = TimeCurrent();
   } else {
      g_hedgeSellSide.ticket = ticket;
      g_hedgeSellSide.protectedDirection = 1;
      g_hedgeSellSide.openTime = TimeCurrent();
      g_hedgeSellSide.lots = lots;
      g_lastHedgeOpenSell = TimeCurrent();
   }

   g_lastRescueAction = "HEDGE_OPEN_D" + IntegerToString(protectedDirection);
   Print("🛡️ [保护对冲] 方向", protectedDirection, " 开仓 ", comment,
         " 手数=", DoubleToString(lots, 2));
   return true;
}

void CheckProtectiveHedgeUnlock(const int protectedDirection) {
   ulong ticket = GetHedgeTicket(protectedDirection);
   if(ticket == 0 || !PositionSelectByTicket(ticket)) {
      ResetHedgeSlotByDirection(protectedDirection);
      return;
   }

   datetime openTime = (protectedDirection == 0) ? g_hedgeBuySide.openTime : g_hedgeSellSide.openTime;
   double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   DirectionRiskState st = (protectedDirection == 0) ? g_buyDirRisk : g_sellDirRisk;

   if(Hedge_Max_Hold_Minutes > 0 && openTime > 0 &&
      TimeCurrent() - openTime >= Hedge_Max_Hold_Minutes * 60) {
      CloseProtectiveHedge(protectedDirection, "MAX_HOLD");
      return;
   }
   if(Hedge_Unlock_Profit_Money > 0 && profit >= Hedge_Unlock_Profit_Money) {
      CloseProtectiveHedge(protectedDirection, "UNLOCK_PROFIT");
      return;
   }
   if(Hedge_Unlock_On_Risk_Normal && st == DIR_RISK_NORMAL) {
      CloseProtectiveHedge(protectedDirection, "RISK_NORMAL");
      return;
   }
   if(GetGridOnlyDirectionLots(protectedDirection) <= 0) {
      CloseProtectiveHedge(protectedDirection, "NO_GRID_LEFT");
      return;
   }
   if(st == DIR_RISK_CUT_LOSS) {
      CloseProtectiveHedge(protectedDirection, "DIR_CUT_LOSS");
   }
}

void ManageProtectiveHedge() {
   if(!g_eff_Enable_Protective_Hedge) return;
   if(g_globalRisk == GRISK_CIRCUIT) return;

   SyncProtectiveHedgeSlots();
   CheckProtectiveHedgeUnlock(0);
   CheckProtectiveHedgeUnlock(1);

   if(g_buyDirRisk >= DIR_RISK_FREEZE_ADD && GetGridOnlyDirectionLots(0) > 0) {
      if(GetHedgeTicket(0) == 0 || !PositionSelectByTicket(GetHedgeTicket(0))) {
         OpenProtectiveHedge(0);
      }
   }
   if(g_sellDirRisk >= DIR_RISK_FREEZE_ADD && GetGridOnlyDirectionLots(1) > 0) {
      if(GetHedgeTicket(1) == 0 || !PositionSelectByTicket(GetHedgeTicket(1))) {
         OpenProtectiveHedge(1);
      }
   }
}

double GetQinglongBasketProfit() {
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(!IsOurPositionSelected()) continue;
      if(StringFind(positionInfo.Comment(), "QingLong") < 0) continue;
      total += positionInfo.Profit() + positionInfo.Swap();
   }
   return total;
}

double GetQinglongATR() {
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 1, atr) < 1) return 0;
   return atr[0];
}

double CalcQinglongSLPrice(const int posType, const double refPrice, const double atrMultiple) {
   double atr = GetQinglongATR();
   if(atr <= 0) {
      double cashDist = CashToPriceDistance(Qinglong_Hard_SL, Qinglong_Base_Lot);
      return (posType == 0) ? refPrice - cashDist : refPrice + cashDist;
   }
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * _Point;
   double dist = MathMax(atr * atrMultiple, minDist);
   if(posType == 0) return NormalizeDouble(refPrice - dist, _Digits);
   return NormalizeDouble(refPrice + dist, _Digits);
}

bool ModifyPositionSL(const ulong ticket, const double newSL) {
   if(!PositionSelectByTicket(ticket)) return false;
   int posType = (int)PositionGetInteger(POSITION_TYPE);
   double tp = PositionGetDouble(POSITION_TP);
   double curSL = PositionGetDouble(POSITION_SL);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * _Point;
   double sl = newSL;

   if(posType == POSITION_TYPE_BUY) {
      if(sl <= 0 || bid - sl < minDist) sl = bid - minDist;
      if(sl >= bid - _Point) return false;
      if(curSL > 0 && sl <= curSL + _Point * 0.5) return false;
   } else {
      if(sl <= 0 || sl - ask < minDist) sl = ask + minDist;
      if(sl <= ask + _Point) return false;
      if(curSL > 0 && sl >= curSL - _Point * 0.5) return false;
   }
   sl = NormalizeDouble(sl, _Digits);
   trade.SetExpertMagicNumber(g_expertMagic);
   if(!trade.PositionModify(ticket, sl, tp)) {
      PrintFormat("⚠️ [青龙] SL修改失败 ticket=%I64u ret=%u %s",
                  ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
   }
   return true;
}

void CheckQinglongATRTrail() {
   if(!Qinglong_Enable_ATR_Trail) return;
   double atr = GetQinglongATR();
   if(atr <= 0) return;
   double stepDist = atr * Qinglong_Trail_Step_ATR;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(!IsOurPositionSelected()) continue;
      if(StringFind(positionInfo.Comment(), "QingLong") < 0) continue;

      ulong ticket = positionInfo.Ticket();
      int posType = (positionInfo.Type() == POSITION_TYPE_BUY) ? 0 : 1;
      double profit = positionInfo.Profit();
      if(profit <= 0) continue;

      double trailSL = CalcQinglongSLPrice(posType,
         (posType == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK),
         Qinglong_ATR_Trail_Multiple);
      ModifyPositionSL(ticket, trailSL);
   }
}

//+------------------------------------------------------------------+
//| Phase1: 强趋势识别(M15 MA + ADX + ATR距离)                         |
//+------------------------------------------------------------------+
bool IsStrongTrendAgainstDirection(int direction) {
   if(Grid_Allow_Against_Strong_Trend) return false;

   double adx[];
   ArraySetAsSeries(adx, true);
   if(handleM15_ADX == INVALID_HANDLE || CopyBuffer(handleM15_ADX, 0, 0, 1, adx) < 1) return false;
   if(adx[0] < Grid_Trend_Freeze_ADX) return false;

   double maFast[], maSlow[];
   ArraySetAsSeries(maFast, true);
   ArraySetAsSeries(maSlow, true);
   if(CopyBuffer(handleM15_MA_Fast, 0, 0, 1, maFast) < 1) return false;
   if(CopyBuffer(handleM15_MA_Slow, 0, 0, 1, maSlow) < 1) return false;

   bool trendDown = maFast[0] < maSlow[0];
   bool trendUp = maFast[0] > maSlow[0];
   if(direction == 0 && !trendDown) return false;
   if(direction == 1 && !trendUp) return false;

   int levels = CountGridOrdersByDirection(direction);
   if(levels <= 0) return false;

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 1, atr) < 1 || atr[0] <= 0) return true;

   DirectionBattle battle = (direction == 0) ? buyBattle : sellBattle;
   double anchor = battle.anchorPrice;
   if(anchor <= 0) return true;

   double price = (direction == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double dist = (direction == 0) ? (anchor - price) : (price - anchor);
   return (dist >= Grid_Trend_Freeze_ATR_Distance * atr[0]);
}

DirectionRiskState EvaluateGridDirectionRisk(int direction) {
   if(g_globalRisk == GRISK_CIRCUIT) return DIR_RISK_CUT_LOSS;

   double balance = accountInfo.Balance();
   if(balance <= 0) balance = accountInfo.Equity();
   double dirLoss = GetGridDirectionFloatingLossMoney(direction);
   double dirLossBudget = (Grid_Direction_Max_Loss_Pct > 0)
      ? balance * Grid_Direction_Max_Loss_Pct / 100.0 : 0;

   if(Grid_Direction_Hard_Loss_Pct > 0 && dirLoss >= balance * Grid_Direction_Hard_Loss_Pct / 100.0)
      return DIR_RISK_CUT_LOSS;

   double dirLots = GetOurDirectionLots(direction);
   if(Risk_Direction_Max_Lots > 0 && dirLots >= Risk_Direction_Max_Lots)
      return DIR_RISK_REDUCE_ONLY;

   int levels = CountGridOrdersByDirection(direction);
   int maxLevels = (int)MathMin(Grid_Max_Levels, g_eff_Grid_Safe_Max_Levels);
   if(levels >= maxLevels) return DIR_RISK_FREEZE_ADD;

   if(dirLossBudget > 0 && dirLoss >= dirLossBudget)
      return DIR_RISK_FREEZE_ADD;
   if(dirLossBudget > 0 && dirLoss >= dirLossBudget * Rescue_Warning_Loss_Pct_Of_Budget / 100.0)
      return DIR_RISK_WARNING;

   if(IsStrongTrendAgainstDirection(direction)) return DIR_RISK_FREEZE_ADD;

   if(g_globalRisk >= GRISK_WARN && levels >= 2) return DIR_RISK_WARNING;

   return DIR_RISK_NORMAL;
}

void ApplyDirectionCutLossIfNeeded() {
   if(g_buyDirRisk == DIR_RISK_CUT_LOSS && g_prevBuyDirRisk != DIR_RISK_CUT_LOSS) {
      CloseProtectiveHedge(0, "CUT_LOSS");
      BatchCloseGridOrders(0, "方向风险: 多单网格止损");
      g_lastRiskEvent = "CUT_LOSS BUY grid";
      Print("🛑 [风控] 多单方向 DIR_RISK_CUT_LOSS，批量平网格");
   }
   if(g_sellDirRisk == DIR_RISK_CUT_LOSS && g_prevSellDirRisk != DIR_RISK_CUT_LOSS) {
      CloseProtectiveHedge(1, "CUT_LOSS");
      BatchCloseGridOrders(1, "方向风险: 空单网格止损");
      g_lastRiskEvent = "CUT_LOSS SELL grid";
      Print("🛑 [风控] 空单方向 DIR_RISK_CUT_LOSS，批量平网格");
   }
   g_prevBuyDirRisk = g_buyDirRisk;
   g_prevSellDirRisk = g_sellDirRisk;
}

void CloseAllEAPositions(const string reason) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(!IsOurPositionSelected()) continue;
      CloseTrackedPosition(positionInfo.Ticket());
   }
   Print("🛑 [风控] 账户熔断清仓: ", reason);
}

//+------------------------------------------------------------------+
//| Phase1: 每 Tick 风险巡检                                           |
//+------------------------------------------------------------------+
void UpdateRiskSupervisor() {
   RefreshDailyBaseline();
   double eq = accountInfo.Equity();
   if(eq > g_peakEquity) g_peakEquity = eq;

   if(g_circuitCooldownUntil > 0 && TimeCurrent() < g_circuitCooldownUntil) {
      g_globalRisk = GRISK_CIRCUIT;
      g_allowNewPositions = false;
      g_buyDirRisk = DIR_RISK_CUT_LOSS;
      g_sellDirRisk = DIR_RISK_CUT_LOSS;
      return;
   }

   double dd = GetAccountDrawdownPct();
   double dailyLoss = GetDailyLossPct();
   double marginLevel = accountInfo.MarginLevel();

   g_allowNewPositions = true;
   g_globalRisk = GRISK_NORMAL;

   if(g_eff_Risk_Max_Account_Drawdown_Pct > 0 && dd >= g_eff_Risk_Max_Account_Drawdown_Pct) {
      if(g_globalRisk != GRISK_CIRCUIT) {
         g_lastRiskEvent = StringFormat("CIRCUIT dd=%.2f%%", dd);
         if(Risk_Close_All_On_Circuit_Breaker) {
            CloseAllEAPositions(g_lastRiskEvent);
         }
         g_circuitCooldownUntil = TimeCurrent() + Risk_Cooldown_After_Circuit_Minutes * 60;
         Print("🛑 [风控] 账户熔断 回撤=", DoubleToString(dd, 2), "% 冷却至 ",
               TimeToString(g_circuitCooldownUntil, TIME_DATE|TIME_MINUTES));
      }
      g_globalRisk = GRISK_CIRCUIT;
      g_allowNewPositions = false;
      g_buyDirRisk = DIR_RISK_CUT_LOSS;
      g_sellDirRisk = DIR_RISK_CUT_LOSS;
      return;
   }

   if(g_eff_Risk_Daily_Loss_Limit_Pct > 0 && dailyLoss >= g_eff_Risk_Daily_Loss_Limit_Pct) {
      g_globalRisk = GRISK_FREEZE;
      g_allowNewPositions = false;
      g_lastRiskEvent = StringFormat("DAILY_LOSS %.2f%%", dailyLoss);
   } else if(g_eff_Risk_Freeze_Account_Drawdown_Pct > 0 && dd >= g_eff_Risk_Freeze_Account_Drawdown_Pct) {
      g_globalRisk = GRISK_FREEZE;
      g_allowNewPositions = false;
      g_lastRiskEvent = StringFormat("FREEZE dd=%.2f%%", dd);
   } else if(g_eff_Risk_Warn_Account_Drawdown_Pct > 0 && dd >= g_eff_Risk_Warn_Account_Drawdown_Pct) {
      g_globalRisk = GRISK_WARN;
      g_lastRiskEvent = StringFormat("WARN dd=%.2f%%", dd);
   }

   if(Risk_Min_Margin_Level_Pct > 0 && marginLevel > 0 && marginLevel < Risk_Min_Margin_Level_Pct) {
      g_globalRisk = GRISK_FREEZE;
      g_allowNewPositions = false;
      g_lastRiskEvent = StringFormat("MARGIN_LEVEL %.1f%%", marginLevel);
   }

   double symPnl = GetOurSymbolFloatingPnL();
   double balance = accountInfo.Balance();
   if(balance <= 0) balance = eq;
   if(Risk_Symbol_Max_Loss_Pct > 0 && symPnl <= -balance * Risk_Symbol_Max_Loss_Pct / 100.0) {
      g_allowNewPositions = false;
      if(g_globalRisk < GRISK_FREEZE) g_globalRisk = GRISK_FREEZE;
      g_lastRiskEvent = StringFormat("SYMBOL_LOSS %.2f", symPnl);
   }

   g_buyDirRisk = EvaluateGridDirectionRisk(0);
   g_sellDirRisk = EvaluateGridDirectionRisk(1);
   ApplyDirectionCutLossIfNeeded();
}

string GlobalRiskStateText() {
   switch(g_globalRisk) {
      case GRISK_WARN: return "预警";
      case GRISK_FREEZE: return "冻结";
      case GRISK_CIRCUIT: return "熔断";
      default: return "正常";
   }
}

string DirectionRiskStateText(DirectionRiskState s) {
   switch(s) {
      case DIR_RISK_WARNING: return "预警";
      case DIR_RISK_FREEZE_ADD: return "禁加";
      case DIR_RISK_REDUCE_ONLY: return "只减";
      case DIR_RISK_CUT_LOSS: return "止损";
      default: return "正常";
   }
}

//+------------------------------------------------------------------+
//| Phase1: 保证金检查(原 CheckRiskLimit 增强)                          |
//+------------------------------------------------------------------+
bool CheckMarginForLots(double lots, ENUM_ORDER_TYPE orderType, string &reason) {
   double balance = accountInfo.Balance();
   double margin = accountInfo.Margin();
   double freeMargin = accountInfo.FreeMargin();

   double requiredMargin = 0;
   double marginPrice = (orderType == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                      : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(!OrderCalcMargin(orderType, _Symbol, lots, marginPrice, requiredMargin)) {
      reason = "OrderCalcMargin failed";
      return false;
   }

   double maxAllowedMargin = balance * MaxRiskPercent / 100.0;
   if(maxAllowedMargin > 0 && margin + requiredMargin > maxAllowedMargin) {
      reason = StringFormat("margin cap %.2f", maxAllowedMargin);
      return false;
   }

   if(requiredMargin > freeMargin) {
      reason = "insufficient free margin";
      return false;
   }
   return true;
}

bool PreOrderCheckDeal(ENUM_ORDER_TYPE orderType, double lots, double price, double sl, double tp, string &reason) {
   MqlTradeRequest request;
   MqlTradeCheckResult check;
   ZeroMemory(request);
   ZeroMemory(check);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = orderType;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = Trade_Deviation_Points;
   request.magic = g_expertMagic;
   request.type_filling = GetSymbolFillingMode();

   ResetLastError();
   if(!OrderCheck(request, check)) {
      reason = StringFormat("OrderCheck err=%d ret=%u %s", GetLastError(), check.retcode, check.comment);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Phase1: 统一开仓审批                                                |
//+------------------------------------------------------------------+
bool CanOpenPosition(EngineType engine, ENUM_ORDER_TYPE orderType, double lots, string &reason) {
   reason = "";
   if(!g_allowNewPositions) {
      reason = "global new positions frozen: " + g_lastRiskEvent;
      return false;
   }
   if(g_globalRisk == GRISK_CIRCUIT) {
      reason = "account circuit breaker";
      return false;
   }
   if(g_eff_Risk_Daily_Loss_Limit_Pct > 0 && GetDailyLossPct() >= g_eff_Risk_Daily_Loss_Limit_Pct) {
      reason = "daily loss limit";
      return false;
   }

   if(g_eff_News_Block_New_Opens && g_eff_News_Filter_Enabled && g_newsRiskActive) {
      reason = "news freeze: " + g_lastNewsTitle;
      g_lastRiskDenyReason = reason;
      return false;
   }

   lots = NormalizeVolume(lots);
   if(lots <= 0) {
      reason = "invalid normalized volume";
      return false;
   }

   if(Risk_Symbol_Max_Total_Lots > 0 && GetOurTotalLots() + lots > Risk_Symbol_Max_Total_Lots + 1e-8) {
      reason = "symbol max total lots";
      return false;
   }

   int dir = (orderType == ORDER_TYPE_BUY) ? 0 : 1;
   if(engine == ENGINE_GRID && Risk_Direction_Max_Lots > 0 &&
      GetOurDirectionLots(dir) + lots > Risk_Direction_Max_Lots + 1e-8) {
      reason = "direction max lots";
      return false;
   }

   if(CountOurPositions() >= Risk_Symbol_Max_Positions) {
      reason = "symbol max positions";
      return false;
   }

   if(engine == ENGINE_GRID) {
      DirectionRiskState dr = (dir == 0) ? g_buyDirRisk : g_sellDirRisk;
      if(dr == DIR_RISK_FREEZE_ADD || dr == DIR_RISK_REDUCE_ONLY || dr == DIR_RISK_CUT_LOSS) {
         reason = "grid direction risk: " + DirectionRiskStateText(dr);
         return false;
      }
      if(g_globalRisk == GRISK_WARN && IsStrongTrendAgainstDirection(dir)) {
         reason = "account warn + strong trend against grid";
         return false;
      }
   }

   if(engine == ENGINE_BREAKOUT && g_globalRisk >= GRISK_WARN) {
      reason = "breakout blocked in account warn";
      return false;
   }

   if(engine == ENGINE_HEDGE) {
      if(!CheckMarginForLots(lots, orderType, reason)) return false;
      double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(!PreOrderCheckDeal(orderType, lots, price, 0, 0, reason)) return false;
      return true;
   }

   if(!CheckMarginForLots(lots, orderType, reason)) return false;

   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(!PreOrderCheckDeal(orderType, lots, price, 0, 0, reason)) return false;

   return true;
}

bool CanAddGrid(int direction, double lots, string &reason) {
   if(g_globalRisk == GRISK_WARN) {
      if(IsStrongTrendAgainstDirection(direction)) {
         reason = "warn: counter-trend grid blocked";
         return false;
      }
   }
   if(sandboxActive) {
      if(direction == 0 && sandboxBuyDisabled) { reason = "sandbox buy disabled"; return false; }
      if(direction == 1 && sandboxSellDisabled) { reason = "sandbox sell disabled"; return false; }
   }
   ENUM_ORDER_TYPE orderType = (direction == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   return CanOpenPosition(ENGINE_GRID, orderType, lots, reason);
}

//+------------------------------------------------------------------+
//| Phase2: 交易执行器                                                  |
//+------------------------------------------------------------------+
int TradeBackoffRemaining(const datetime lastFail, const int failCount) {
   if(lastFail == 0) return 0;
   int elapsed = (int)(TimeCurrent() - lastFail);
   if(elapsed >= 300) return 0;
   int wait = 5;
   if(failCount >= 2) wait = 30;
   if(failCount >= 3) wait = 120;
   return (elapsed >= wait) ? 0 : (wait - elapsed);
}

bool CanRetryOpen() {
   return TradeBackoffRemaining(g_lastOpenFailTime, g_openFailCount) == 0;
}

bool CanRetryClose() {
   return TradeBackoffRemaining(g_lastCloseFailTime, g_closeFailCount) == 0;
}

void RecordOpenSuccess() {
   g_openFailCount = 0;
   g_lastOpenFailTime = 0;
}

void RecordOpenFail() {
   g_lastOpenFailTime = TimeCurrent();
   g_openFailCount++;
}

void RecordCloseSuccess() {
   g_closeFailCount = 0;
   g_lastCloseFailTime = 0;
}

void RecordCloseFail() {
   g_lastCloseFailTime = TimeCurrent();
   g_closeFailCount++;
}

ulong GetPositionTicketFromDeal(const ulong dealTicket) {
   if(dealTicket == 0) return 0;
   if(!HistoryDealSelect(dealTicket)) return 0;
   ulong posId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   if(posId == 0) return 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i)) {
         if((ulong)positionInfo.Identifier() == posId) {
            return positionInfo.Ticket();
         }
      }
   }
   return 0;
}

ulong SendMarketDealOpen(ENUM_ORDER_TYPE orderType, double volume, double sl, double tp,
                         const string comment, string &reason) {
   if(!CanRetryOpen()) {
      reason = StringFormat("open backoff %ds", TradeBackoffRemaining(g_lastOpenFailTime, g_openFailCount));
      return 0;
   }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = volume;
   request.type = orderType;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = Trade_Deviation_Points;
   request.magic = g_expertMagic;
   request.comment = comment;
   request.type_filling = GetSymbolFillingMode();

   ResetLastError();
   if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE) {
      RecordOpenFail();
      reason = StringFormat("OrderSend retcode=%u %s lastErr=%d", result.retcode, result.comment, GetLastError());
      PrintFormat("❌ [开仓失败] %s %s vol=%.2f price=%.5f filling=%d | %s",
                  comment, (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"), volume, price,
                  (int)request.type_filling, reason);
      return 0;
   }

   RecordOpenSuccess();
   ulong ticket = GetPositionTicketFromDeal(result.deal);
   if(ticket == 0 && result.order > 0) ticket = (ulong)result.order;
   return ticket;
}

bool SendMarketDealClose(const ulong ticket, string &reason) {
   if(!CanRetryClose()) {
      reason = StringFormat("close backoff %ds", TradeBackoffRemaining(g_lastCloseFailTime, g_closeFailCount));
      return false;
   }
   if(!PositionSelectByTicket(ticket)) {
      reason = "position not found";
      return false;
   }

   int type = (int)PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);
   string symbol = PositionGetString(POSITION_SYMBOL);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.position = ticket;
   request.volume = volume;
   request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID)
                                               : SymbolInfoDouble(symbol, SYMBOL_ASK);
   request.deviation = Trade_Deviation_Points;
   request.magic = (ulong)PositionGetInteger(POSITION_MAGIC);
   request.comment = "KN|CLOSE";
   request.type_filling = GetSymbolFillingMode();

   ResetLastError();
   if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE) {
      if(result.retcode != TRADE_RETCODE_CLOSE_ORDER_EXIST) {
         RecordCloseFail();
      }
      reason = StringFormat("close retcode=%u %s", result.retcode, result.comment);
      PrintFormat("❌ [平仓失败] ticket=%I64u | %s", ticket, reason);
      return false;
   }
   RecordCloseSuccess();
   return true;
}

string MarketRegimeText(const MarketRegime r) {
   switch(r) {
      case REGIME_TREND_UP: return "趋势↑";
      case REGIME_TREND_DOWN: return "趋势↓";
      case REGIME_HIGH_VOLATILITY: return "高波动";
      case REGIME_RECOVERY: return "恢复";
      case REGIME_NEWS_RISK: return "新闻";
      default: return "震荡";
   }
}

bool SymbolMatchesNewsCurrency(const string eventCurrency) {
   if(eventCurrency == "") return false;
   string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string profit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   if(StringFind(eventCurrency, base) >= 0) return true;
   if(StringFind(eventCurrency, profit) >= 0) return true;
   if(g_eff_News_Include_USD_For_Metals) {
      string sym = _Symbol;
      StringToUpper(sym);
      if((StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0) && eventCurrency == "USD") {
         return true;
      }
   }
   return false;
}

bool IsNewsTime(string &newsTitle, bool &calendarOk) {
   newsTitle = "";
   calendarOk = true;
   if(!g_eff_News_Filter_Enabled) return false;

   datetime now = TimeCurrent();
   datetime start = now - g_eff_News_After_Minutes * 60;
   datetime end = now + g_eff_News_Before_Minutes * 60;
   MqlCalendarValue values[];

   ResetLastError();
   if(!CalendarValueHistory(values, start, end, NULL, NULL)) {
      calendarOk = false;
      g_calendarUnavailable = true;
      return false;
   }
   g_calendarUnavailable = false;

   for(int i = 0; i < ArraySize(values); i++) {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event)) continue;

      bool importanceMatch = false;
      if(g_eff_News_High_Importance && event.importance == CALENDAR_IMPORTANCE_HIGH) {
         importanceMatch = true;
      }
      if(g_eff_News_Medium_Importance && event.importance == CALENDAR_IMPORTANCE_MODERATE) {
         importanceMatch = true;
      }
      if(!importanceMatch) continue;

      string eventCurrency = "";
      MqlCalendarCountry country;
      if(CalendarCountryById(event.country_id, country)) {
         eventCurrency = country.currency;
      }
      if(!SymbolMatchesNewsCurrency(eventCurrency)) continue;

      newsTitle = event.name;
      return true;
   }
   return false;
}

void UpdateNewsRiskState() {
   g_newsRiskActive = false;
   g_lastNewsTitle = "";

   if(!g_eff_News_Filter_Enabled) return;

   string title = "";
   bool calendarOk = true;
   if(IsNewsTime(title, calendarOk)) {
      g_newsRiskActive = true;
      g_lastNewsTitle = title;
      return;
   }

   if(!calendarOk) {
      g_lastNewsTitle = "CALENDAR_UNAVAILABLE";
      if(g_eff_News_Freeze_When_Calendar_Unavailable) {
         g_newsRiskActive = true;
      }
   }
}

void UpdateMarketRegime() {
   UpdateNewsRiskState();

   if(g_globalRisk == GRISK_CIRCUIT || (g_circuitCooldownUntil > 0 && TimeCurrent() < g_circuitCooldownUntil)) {
      g_marketRegime = REGIME_RECOVERY;
      return;
   }
   if(g_newsRiskActive) {
      g_marketRegime = REGIME_NEWS_RISK;
      return;
   }
   if(IsRangeFrozen()) {
      g_marketRegime = REGIME_HIGH_VOLATILITY;
      return;
   }

   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(handleM15_ADX, 0, 0, 1, adx) < 1) return;

   double maFast[], maSlow[];
   ArraySetAsSeries(maFast, true);
   ArraySetAsSeries(maSlow, true);
   if(CopyBuffer(handleM15_MA_Fast, 0, 0, 1, maFast) < 1) return;
   if(CopyBuffer(handleM15_MA_Slow, 0, 0, 1, maSlow) < 1) return;

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 20, atr) < 20) return;
   double atrMean = 0;
   for(int i = 1; i < 20; i++) atrMean += atr[i];
   atrMean /= 19.0;
   if(atrMean > 0 && atr[0] >= atrMean * Regime_High_Vol_ATR_Multiple) {
      g_marketRegime = REGIME_HIGH_VOLATILITY;
      return;
   }

   if(adx[0] >= Grid_Trend_Freeze_ADX) {
      if(maFast[0] > maSlow[0]) g_marketRegime = REGIME_TREND_UP;
      else if(maFast[0] < maSlow[0]) g_marketRegime = REGIME_TREND_DOWN;
      else g_marketRegime = REGIME_RANGE;
      return;
   }
   g_marketRegime = REGIME_RANGE;
}

bool IsEngineAllowedByRegime(const EngineType engine) {
   if(g_eff_IsPaused) return false;
   if(g_marketRegime == REGIME_NEWS_RISK) return false;
   if(engine == ENGINE_HEDGE) {
      return (g_marketRegime != REGIME_RECOVERY);
   }
   switch(g_marketRegime) {
      case REGIME_HIGH_VOLATILITY:
         return false;
      case REGIME_TREND_UP:
         if(engine == ENGINE_GRID) return false;
         return true;
      case REGIME_TREND_DOWN:
         if(engine == ENGINE_GRID) return false;
         return true;
      case REGIME_RECOVERY:
         return false;
      default:
         return true;
   }
}

bool IsZhuqueDailyLossLimitReached() {
   datetime today = (datetime)((long)TimeCurrent() / 86400 * 86400);
   if(g_zhuqueLossDay != today) {
      g_zhuqueLossDay = today;
      g_zhuqueLossCountToday = 0;
   }
   return (Zhuque_Max_Losses_Per_Day > 0 && g_zhuqueLossCountToday >= Zhuque_Max_Losses_Per_Day);
}

void RegisterZhuqueLoss() {
   datetime today = (datetime)((long)TimeCurrent() / 86400 * 86400);
   if(g_zhuqueLossDay != today) {
      g_zhuqueLossDay = today;
      g_zhuqueLossCountToday = 0;
   }
   g_zhuqueLossCountToday++;
}

void RebuildDirectionBattles() {
   double buyAnchor = 0, sellAnchor = 0;
   datetime buyTime = 0, sellTime = 0;
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(!PositionSelectByTicket(gridOrders[i].ticket)) continue;
      if(StringFind(gridOrders[i].comment, "_Sniper") >= 0) continue;
      if(gridOrders[i].type == 0) {
         if(buyTime == 0 || gridOrders[i].openTime < buyTime) {
            buyTime = gridOrders[i].openTime;
            buyAnchor = gridOrders[i].openPrice;
         }
      } else {
         if(sellTime == 0 || gridOrders[i].openTime < sellTime) {
            sellTime = gridOrders[i].openTime;
            sellAnchor = gridOrders[i].openPrice;
         }
      }
   }
   if(buyAnchor > 0) buyBattle.anchorPrice = buyAnchor;
   if(sellAnchor > 0) sellBattle.anchorPrice = sellAnchor;
}

void ReloadEAState() {
   ArrayResize(gridOrders, 0);
   ResetZhuquePosition();
   ResetQinglongPosition();
   qinglongPos.addTimes = 0;

   int orphanCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(positionInfo.Symbol() != _Symbol) continue;
      if(!IsOurPositionSelected()) continue;

      string comment = positionInfo.Comment();
      ulong ticket = positionInfo.Ticket();
      int type = (positionInfo.Type() == POSITION_TYPE_BUY) ? 0 : 1;
      if(IsGridComment(comment)) {
         int cdir = GetGridDirectionFromComment(comment);
         if(cdir >= 0) type = cdir;
         SyncGridOrder(ticket, comment, type, positionInfo.PriceOpen(),
                       positionInfo.Volume(), (datetime)positionInfo.Time());
      } else if(StringFind(comment, "QingLong_Add") == 0) {
         qinglongPos.addTimes++;
      } else if(!IsLegacyEAComment(comment)) {
         orphanCount++;
         Print("⚠️ [恢复] 孤儿持仓 ticket=", ticket, " comment=", comment);
      }
   }

   UpdatePositions();
   SyncProtectiveHedgeSlots();
   RebuildDirectionBattles();
   PrintFormat("✅ [恢复] 网格=%d 青龙加仓计数=%d 孤儿=%d",
               ArraySize(gridOrders), qinglongPos.addTimes, orphanCount);
}

void DumpRiskStateJson() {
   string fn = "KuiNiu_risk_state.json";
   int fh = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(fh == INVALID_HANDLE) return;
   string json = "{\n";
   json += "  \"time\": \"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",\n";
   json += "  \"globalRisk\": \"" + GlobalRiskStateText() + "\",\n";
   json += "  \"regime\": \"" + MarketRegimeText(g_marketRegime) + "\",\n";
   json += "  \"drawdownPct\": " + DoubleToString(GetAccountDrawdownPct(), 2) + ",\n";
   json += "  \"buyDirRisk\": \"" + DirectionRiskStateText(g_buyDirRisk) + "\",\n";
   json += "  \"sellDirRisk\": \"" + DirectionRiskStateText(g_sellDirRisk) + "\",\n";
   json += "  \"lastEvent\": \"" + g_lastRiskEvent + "\",\n";
   json += "  \"lastRescue\": \"" + g_lastRescueAction + "\",\n";
   json += "  \"paused\": " + (g_eff_IsPaused ? "true" : "false") + ",\n";
   json += "  \"rescueOn\": " + (g_eff_Enable_Rescue_Engine ? "true" : "false") + ",\n";
   json += "  \"hedgeBuy\": " + IntegerToString((int)g_hedgeBuySide.ticket) + ",\n";
   json += "  \"hedgeSell\": " + IntegerToString((int)g_hedgeSellSide.ticket) + ",\n";
   json += "  \"newsRisk\": " + (g_newsRiskActive ? "true" : "false") + ",\n";
   json += "  \"newsTitle\": \"" + g_lastNewsTitle + "\"\n";
   json += "}\n";
   FileWriteString(fh, json);
   FileClose(fh);
}

void DumpRuntimeJson() {
   string fn = "KuiNiu_runtime.json";
   int fh = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(fh == INVALID_HANDLE) return;
   string json = "{\n";
   json += "  \"symbol\": \"" + _Symbol + "\",\n";
   json += "  \"magic\": " + IntegerToString((int)g_expertMagic) + ",\n";
   json += "  \"equity\": " + DoubleToString(accountInfo.Equity(), 2) + ",\n";
   json += "  \"gridCount\": " + IntegerToString(ArraySize(gridOrders)) + ",\n";
   json += "  \"regime\": \"" + MarketRegimeText(g_marketRegime) + "\",\n";
   json += "  \"eff\": {\n";
   json += "    \"paused\": " + (g_eff_IsPaused ? "true" : "false") + ",\n";
   json += "    \"gridOn\": " + (g_eff_Enable_DuShe_Grid ? "true" : "false") + ",\n";
   json += "    \"breakoutOn\": " + (g_eff_Enable_NiuGui_Squad ? "true" : "false") + ",\n";
   json += "    \"trendOn\": " + (g_eff_Enable_QingLong_Squad ? "true" : "false") + "\n";
   json += "  }\n}\n";
   FileWriteString(fh, json);
   FileClose(fh);
}

// rowFromBottom: 0=最靠下; col: 0=面板左列 1=面板右列(近价位轴); colSpan=2 跨两列
// 使用 CORNER_LEFT_LOWER：X 为按钮左缘距图表左缘，避免 RIGHT 锚点导致右侧裁切
void CreateControlButtonEx(const string name, const string text, const int rowFromBottom,
                           const int col, const int colSpan,
                           const color bgColor, const color textColor) {
   string obj = KN_UI_PREFIX + name;
   int y = KN_BTN_BASE_Y + rowFromBottom * g_uiBtnStep;
   int w = g_uiBtnWidth;
   if(colSpan == 2) {
      w = g_uiBtnWidth * 2 + g_uiBtnColGap;
   }
   int x = g_uiPanelLeftX;
   if(col == 1) {
      x = g_uiPanelLeftX + g_uiBtnWidth + g_uiBtnColGap;
   }

   if(ObjectFind(0, obj) < 0) {
      ObjectCreate(0, obj, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, clrDimGray);
      ObjectSetString(0, obj, OBJPROP_FONT, "Microsoft YaHei");
   }
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, g_uiBtnHeight);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, (g_uiBtnHeight >= 22 ? 9 : 8));
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, textColor);
}

void DeleteControlButtons() {
   string names[] = {"BtnToggle", "BtnPause", "BtnGrid", "BtnBreakout", "BtnTrend",
                     "BtnRescue", "BtnHedge", "BtnReload", "BtnCloseAll"};
   for(int i = 0; i < ArraySize(names); i++) {
      string obj = KN_UI_PREFIX + names[i];
      if(ObjectFind(0, obj) >= 0) {
         ObjectDelete(0, obj);
      }
   }
}

void CreateControlGUI() {
   DeleteControlButtons();

   int rows = g_uiPanelExpanded ? 5 : 1;
   CalcControlPanelLayout(rows);

   int row = 0;
   string toggleText = g_uiPanelExpanded ? "▲ 收起面板" : "▼ 展开面板";
   CreateControlButtonEx("BtnToggle", toggleText, row++, 0, 2, clrDimGray, clrWhite);
   if(!g_uiPanelExpanded) return;

   // 左列(col0)远离价位轴；右列(col1)靠近价位轴但仍完整落在图表内
   if(g_eff_Enable_NiuGui_Squad) {
      CreateControlButtonEx("BtnBreakout", "牛龟·开", row, 0, 1, clrSteelBlue, clrWhite);
   } else {
      CreateControlButtonEx("BtnBreakout", "牛龟·关", row, 0, 1, clrGray, clrWhite);
   }
   if(g_eff_IsPaused) {
      CreateControlButtonEx("BtnPause", "▶ 继续", row, 1, 1, clrForestGreen, clrWhite);
   } else {
      CreateControlButtonEx("BtnPause", "⏸ 暂停", row, 1, 1, clrGoldenrod, clrBlack);
   }
   row++;

   if(g_eff_Enable_QingLong_Squad) {
      CreateControlButtonEx("BtnTrend", "青龙·开", row, 0, 1, clrSteelBlue, clrWhite);
   } else {
      CreateControlButtonEx("BtnTrend", "青龙·关", row, 0, 1, clrGray, clrWhite);
   }
   if(g_eff_Enable_DuShe_Grid) {
      CreateControlButtonEx("BtnGrid", "网格·开", row, 1, 1, clrSteelBlue, clrWhite);
   } else {
      CreateControlButtonEx("BtnGrid", "网格·关", row, 1, 1, clrGray, clrWhite);
   }
   row++;

   if(g_eff_Enable_Protective_Hedge) {
      CreateControlButtonEx("BtnHedge", "对冲·开", row, 0, 1, clrTeal, clrWhite);
   } else {
      CreateControlButtonEx("BtnHedge", "对冲·关", row, 0, 1, clrGray, clrWhite);
   }
   if(g_eff_Enable_Rescue_Engine) {
      CreateControlButtonEx("BtnRescue", "减灾·开", row, 1, 1, clrTeal, clrWhite);
   } else {
      CreateControlButtonEx("BtnRescue", "减灾·关", row, 1, 1, clrGray, clrWhite);
   }
   row++;

   CreateControlButtonEx("BtnCloseAll", "⚠ 全平", row, 0, 1, clrFireBrick, clrWhite);
   CreateControlButtonEx("BtnReload", "↻ 重载", row, 1, 1, clrDarkSlateGray, clrWhite);
}

void UpdateControlGUI() {
   CreateControlGUI();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| 不下单原因诊断（Experts 日志 + 面板）                                |
//+------------------------------------------------------------------+
string GetTrendFilterText() {
   if(!Enable_Trend_Filter) return "关";
   if(trendDirection == 1) return "只多";
   if(trendDirection == -1) return "只空";
   return "双向";
}

string BuildTradeDiagnosticText() {
   string lines = "";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
      lines += "终端禁止交易;";
   }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) {
      lines += "EA属性未允交易;";
   }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) {
      lines += "账户未允EA;";
   }
   if(g_eff_IsPaused) {
      lines += "已暂停;";
   }
   if(!g_allowNewPositions) {
      lines += "全局禁开(" + g_lastRiskEvent + ");";
   }
   if(g_newsRiskActive) {
      lines += "新闻冻结(" + g_lastNewsTitle + ");";
   } else if(g_calendarUnavailable) {
      lines += "日历不可用(未冻结，可正常交易);";
   }
   if(g_globalRisk == GRISK_CIRCUIT) {
      lines += "账户熔断;";
   }
   if(IsRangeFrozen()) {
      lines += "振幅冻结;";
   }
   if(g_eff_Enable_DuShe_Grid) {
      if(!IsEngineAllowedByRegime(ENGINE_GRID)) {
         lines += "网格被行情态拦截(" + MarketRegimeText(g_marketRegime) + ");";
      } else {
         lines += StringFormat("网格多[%s]空[%s]趋势%s间距%.0f点;",
                               DirectionRiskStateText(g_buyDirRisk),
                               DirectionRiskStateText(g_sellDirRisk),
                               GetTrendFilterText(), Grid_Spacing_Points);
      }
   } else {
      lines += "网格关;";
   }
   if(g_eff_Enable_QingLong_Squad) {
      if(!IsEngineAllowedByRegime(ENGINE_TREND)) {
         lines += "青龙被行情态拦截;";
      } else if(DetectQinglongSignal() == 0) {
         lines += "青龙无信号(ADX/突破);";
      }
   }
   if(!g_eff_Enable_NiuGui_Squad) {
      lines += "牛龟关;";
   }
   if(lines == "") lines = "条件满足，等待触发";
   return lines;
}

void DiagnoseAndLogTradingBlockers(const bool forceLog) {
   if(!Enable_Trade_Diagnostics) return;
   if(CountOurPositions() > 0 && !forceLog) return;

   datetime now = TimeCurrent();
   if(!forceLog && g_lastDiagPrintTime > 0 &&
      now - g_lastDiagPrintTime < Trade_Diagnostics_Interval_Sec) {
      return;
   }
   g_lastDiagPrintTime = now;

   static string lastPrintedDiag = "";
   string diag = BuildTradeDiagnosticText();
   if(forceLog || diag != lastPrintedDiag) {
      Print("🔍 [交易诊断] ", diag);
      lastPrintedDiag = diag;
   }
}

void LogGridOpenDeny(const int direction, const string deny) {
   if(deny == "") return;
   datetime now = TimeCurrent();
   if(direction == 0) {
      if(now - g_lastGridDenyLogBuy < 30) return;
      g_lastGridDenyLogBuy = now;
   } else {
      if(now - g_lastGridDenyLogSell < 30) return;
      g_lastGridDenyLogSell = now;
   }
   g_lastRiskDenyReason = deny;
   string dirText = (direction == 0) ? "多" : "空";
   Print("⛔ [网格未开-", dirText, "] ", deny);
}

//+------------------------------------------------------------------+
//| Phase1: 统一市价开仓                                                |
//+------------------------------------------------------------------+
bool ExecutePositionOpen(EngineType engine, ENUM_ORDER_TYPE orderType, double lots,
                         double sl, double tp, const string comment, string &reason) {
   lots = NormalizeVolume(lots);
   if(!CanOpenPosition(engine, orderType, lots, reason)) {
      if(reason != "") Print("⛔ [风控拒绝] ", comment, " | ", reason);
      g_lastRiskDenyReason = reason;
      return false;
   }
   if(!IsEngineAllowedByRegime(engine)) {
      reason = "engine blocked by regime/pause";
      g_lastRiskDenyReason = reason;
      return false;
   }

   ulong ticket = SendMarketDealOpen(orderType, lots, sl, tp, comment, reason);
   if(ticket == 0) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // 检查账户类型
   if(accountInfo.MarginMode() == ACCOUNT_MARGIN_MODE_RETAIL_NETTING) {
      Print("❌ ACCOUNT_MARGIN_MODE属于多空被合并类型,无法执行锁仓等操作,退出EA");
      return INIT_FAILED;
   }
   
   // 初始化指标
   handleADX = iADX(_Symbol, PERIOD_M1, ADX_Period);
   handleATR = iATR(_Symbol, PERIOD_M1, ATR_Period);
   handleM5_MA = iMA(_Symbol, PERIOD_M5, M5_MA_Period, 0, MODE_SMA, PRICE_CLOSE);
   handleM5_MACD = iMACD(_Symbol, PERIOD_M5, M5_MACD_Fast, M5_MACD_Slow, M5_MACD_Signal, PRICE_CLOSE);
   
   if(handleADX == INVALID_HANDLE || handleATR == INVALID_HANDLE || 
      handleM5_MA == INVALID_HANDLE || handleM5_MACD == INVALID_HANDLE) {
      Print("❌ 指标初始化失败");
      return INIT_FAILED;
   }
   
   // 记录初始权益
   initialEquity = accountInfo.Equity();
   g_peakEquity = initialEquity;
   g_dailyStartEquity = initialEquity;
   g_dailyBaselineDay = (datetime)((long)TimeCurrent() / 86400 * 86400);
   g_expertMagic = MagicNumber;
   trade.SetExpertMagicNumber(g_expertMagic);

   handleM15_MA_Fast = iMA(_Symbol, PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
   handleM15_MA_Slow = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   handleM15_ADX = iADX(_Symbol, PERIOD_M15, ADX_Period);
   if(handleM15_MA_Fast == INVALID_HANDLE || handleM15_MA_Slow == INVALID_HANDLE ||
      handleM15_ADX == INVALID_HANDLE) {
      Print("❌ M15 趋势指标初始化失败");
      return INIT_FAILED;
   }
   
   // 初始化数组
   ArrayResize(gridOrders, 0);
   ArrayResize(closingTickets, 0);
   
   // 重置结构体
   ResetZhuquePosition();
   ResetQinglongPosition();
   ResetDirectionBattle(buyBattle);
   ResetDirectionBattle(sellBattle);
   
   // 初始化趋势过滤器（等待第一个M5 K线收盘前1秒再检查）
   trendDirection = 0;  // 初始为双向，等待首次检查
   
   SeedEffectiveParams();
   ReloadRuntimeConfig(true);
   ReloadEAState();
   EventSetTimer(MathMax(1, Config_Poll_Seconds));
   CreateControlGUI();

   Print("✅ 太极·夔牛 Framework v2.40 初始化 | Magic=", g_expertMagic,
         " | 减灾=", g_eff_Enable_Rescue_Engine ? "开" : "关",
         " | 对冲=", g_eff_Enable_Protective_Hedge ? "开" : "关",
         " | 新闻=", g_eff_News_Filter_Enabled ? "开" : "关");
   Print("📊 初始权益: $", DoubleToString(initialEquity, 2));
   Print("🔧 毒蛇网格: ", Enable_DuShe_Grid ? "开启" : "关闭");
   Print("🔧 牛龟突击: ", Enable_NiuGui_Squad ? "开启" : "关闭");
   Print("🔧 青龙波段: ", Enable_QingLong_Squad ? "开启" : "关闭");
   
   if(Enable_Trend_Filter) {
      Print("🎯 趋势过滤器: 已启用 (MA", M5_MA_Period, " + MACD)");
   }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
      Print("⚠️ 终端未允许算法交易，请点工具栏「算法交易」");
   }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) {
      Print("⚠️ 本 EA 属性未勾选「允许算法交易」");
   }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) {
      Print("⚠️ 账户属性未允许 EA 交易");
   }
   DiagnoseAndLogTradingBlockers(true);

   string dummyTitle = "";
   bool calOk = true;
   IsNewsTime(dummyTitle, calOk);
   if(!calOk) {
      Print("ℹ️ [新闻] 经济日历不可用。若要启用新闻过滤：工具→选项→服务器→勾选允许新闻；",
            " 或设 News_Freeze_When_Calendar_Unavailable=false（当前默认）");
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   ObjectsDeleteAll(0, KN_UI_PREFIX);

   // 删除所有图形对象
   ObjectDelete(0, "EA_Title");
   ObjectDelete(0, "EA_Env");
   ObjectDelete(0, "EA_Line1");
   ObjectDelete(0, "EA_Money");
   ObjectDelete(0, "EA_Line2");
   ObjectDelete(0, "EA_GridBuy");
   ObjectDelete(0, "EA_GridSell");
   ObjectDelete(0, "EA_Line3");
   ObjectDelete(0, "EA_Zhuque");
   ObjectDelete(0, "EA_Qinglong");
   ObjectDelete(0, "EA_Line4");
   ObjectDelete(0, "EA_M1Range");
   ObjectDelete(0, "EA_RangeShield");
   ObjectDelete(0, "EA_Risk");
   ObjectDelete(0, "EA_Rescue");
   ObjectDelete(0, "EA_Hedge");
   ObjectDelete(0, "EA_News");
   ObjectDelete(0, "EA_Diagnose");
   ObjectDelete(0, "EA_Protocol");
   
   IndicatorRelease(handleADX);
   IndicatorRelease(handleATR);
   IndicatorRelease(handleM5_MA);
   IndicatorRelease(handleM5_MACD);
   IndicatorRelease(handleM15_MA_Fast);
   IndicatorRelease(handleM15_MA_Slow);
   IndicatorRelease(handleM15_ADX);
   Print("太极·夔牛 Framework v2.40 已停止");
}

//+------------------------------------------------------------------+
//| Timer: 配置热更新 / 状态 JSON                                       |
//+------------------------------------------------------------------+
void OnTimer() {
   UpdateNewsRiskState();
   if(ReloadRuntimeConfig(false)) {
      UpdateControlGUI();
   }
   DumpRuntimeJson();
   DumpRiskStateJson();
}

//+------------------------------------------------------------------+
//| 图表按钮事件                                                        |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_CHART_CHANGE) {
      UpdateControlGUI();
      return;
   }
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == KN_UI_PREFIX + "BtnToggle") {
      g_uiPanelExpanded = !g_uiPanelExpanded;
      UpdateControlGUI();
      return;
   }

   if(sparam == KN_UI_PREFIX + "BtnPause") {
      g_eff_IsPaused = !g_eff_IsPaused;
      Print(g_eff_IsPaused ? "⏸️ [运维] 策略已暂停" : "▶️ [运维] 策略已恢复");
      UpdateControlGUI();
   } else if(sparam == KN_UI_PREFIX + "BtnReload") {
      ReloadEAState();
      Print("↻ [运维] 已重载 EA 状态");
   } else if(sparam == KN_UI_PREFIX + "BtnCloseAll") {
      CloseAllEAPositions("manual close all");
      ReloadEAState();
      Print("⚠ [运维] 已平掉本 EA 全部持仓");
   } else if(sparam == KN_UI_PREFIX + "BtnGrid") {
      g_eff_Enable_DuShe_Grid = !g_eff_Enable_DuShe_Grid;
      Print("🐍 [运维] 毒蛇网格: ", g_eff_Enable_DuShe_Grid ? "开启" : "关闭");
      UpdateControlGUI();
   } else if(sparam == KN_UI_PREFIX + "BtnBreakout") {
      g_eff_Enable_NiuGui_Squad = !g_eff_Enable_NiuGui_Squad;
      Print("🐢 [运维] 牛龟突击: ", g_eff_Enable_NiuGui_Squad ? "开启" : "关闭");
      UpdateControlGUI();
   } else if(sparam == KN_UI_PREFIX + "BtnTrend") {
      g_eff_Enable_QingLong_Squad = !g_eff_Enable_QingLong_Squad;
      Print("🐉 [运维] 青龙波段: ", g_eff_Enable_QingLong_Squad ? "开启" : "关闭");
      UpdateControlGUI();
   } else if(sparam == KN_UI_PREFIX + "BtnRescue") {
      g_eff_Enable_Rescue_Engine = !g_eff_Enable_Rescue_Engine;
      Print("🛟 [运维] 减灾引擎: ", g_eff_Enable_Rescue_Engine ? "开启" : "关闭");
      UpdateControlGUI();
   } else if(sparam == KN_UI_PREFIX + "BtnHedge") {
      g_eff_Enable_Protective_Hedge = !g_eff_Enable_Protective_Hedge;
      Print("🛡 [运维] 保护对冲: ", g_eff_Enable_Protective_Hedge ? "开启" : "关闭");
      UpdateControlGUI();
   } else {
      return;
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   UpdateRiskSupervisor();
   UpdateMarketRegime(); // 内含 UpdateNewsRiskState

   if(g_globalRisk == GRISK_CIRCUIT && TimeCurrent() < g_circuitCooldownUntil) {
      UpdateChartDisplay();
      return;
   }

   UpdatePositions();

   if(g_eff_Enable_Rescue_Engine) {
      ManageRescueEngine();
   } else if(g_eff_Enable_Protective_Hedge) {
      ManageProtectiveHedge();
   }

   if(g_eff_IsPaused) {
      UpdateChartDisplay();
      return;
   }
   
   if(Enable_Trend_Filter) {
      CheckTrendFilter();
   }
   
   CheckCandleRangeShield();
   CheckSandboxStatus();
   
   if(g_eff_Enable_DuShe_Grid && IsEngineAllowedByRegime(ENGINE_GRID)) {
      ManageGridSystem();
   }
   
   if(g_eff_Enable_NiuGui_Squad && IsEngineAllowedByRegime(ENGINE_BREAKOUT)) {
      ManageZhuqueEngine();
   }
   
   if(g_eff_Enable_QingLong_Squad && IsEngineAllowedByRegime(ENGINE_TREND)) {
      ManageQinglongEngine();
   }

   DiagnoseAndLogTradingBlockers(false);
   
   // 更新图表显示
   UpdateChartDisplay();
}

//+------------------------------------------------------------------+
//| 更新图表显示                                                       |
//+------------------------------------------------------------------+
void UpdateChartDisplay() {
   // 获取ADX和ATR值
   double adx[], atr[];
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);
   CopyBuffer(handleADX, 0, 0, 1, adx);
   CopyBuffer(handleATR, 0, 0, 1, atr);
   
   // 统计网格持仓
   int buyGridCount = 0, sellGridCount = 0;
   double buyGridProfit = 0, sellGridProfit = 0;
   
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(PositionSelectByTicket(gridOrders[i].ticket)) {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(gridOrders[i].type == 0) {
            buyGridCount++;
            buyGridProfit += profit;
         } else {
            sellGridCount++;
            sellGridProfit += profit;
         }
      }
   }
   
   // 统计朱雀持仓
   double zhuqueProfit = 0;
   string zhuqueStatus = "[已休眠]";
   if(zhuquePos.ticket > 0 && PositionSelectByTicket(zhuquePos.ticket)) {
      zhuqueProfit = PositionGetDouble(POSITION_PROFIT);
      zhuqueStatus = "[已出击]";
   }
   
   // 统计青龙持仓
   double qinglongProfit = 0;
   string qinglongStatus = "0单";
   int qinglongCount = 0;
   if(qinglongPos.ticket > 0) {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(positionInfo.SelectByIndex(i)) {
            if(IsOurPositionSelected() &&
               StringFind(positionInfo.Comment(), "QingLong") >= 0) {
               qinglongProfit += positionInfo.Profit();
               qinglongCount++;
            }
         }
      }
      qinglongStatus = IntegerToString(qinglongCount) + "单";
   }
   
   // M1物理振幅
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   double m1Range = 0;
   if(CopyRates(_Symbol, PERIOD_M1, 0, 1, rates) == 1) {
      m1Range = (rates[0].high - rates[0].low) / _Point * 0.01;
   }
   
   // 沙盒状态
   string sandboxText = sandboxActive ? "⚠" : "✓";
   string sandboxDesc = sandboxActive ? "沙盒异步狙击中" : "常态空间循环中";
   
   // 创建图形对象显示
   int yPos = 20;
   int lineHeight = 18;
   
   // 标题 - 黄色大字
   CreateLabel("EA_Title", 10, yPos, "太极·夔牛 Framework v2.40", clrGold, 14);
   yPos += lineHeight + 5;
   
   // 环境雷达 - 青色
   CreateLabel("EA_Env", 10, yPos, 
               StringFormat("环境: %s | 模式 %s | ADX(%.1f)", _Symbol,
                           MarketRegimeText(g_marketRegime), GlobalRiskStateText(), adx[0]),
               clrCyan, 10);
   yPos += lineHeight;
   string newsLine = "新闻: 正常";
   if(g_newsRiskActive) {
      newsLine = StringFormat("新闻: ⚠ 冻结 %s", g_lastNewsTitle);
   } else if(g_calendarUnavailable) {
      newsLine = "新闻: 日历不可用(未冻结)";
   }
   color newsColor = g_newsRiskActive ? clrOrange : (g_calendarUnavailable ? clrYellow : clrSilver);
   CreateLabel("EA_News", 10, yPos, newsLine, newsColor, 9);
   yPos += lineHeight;
   if(Enable_Trade_Diagnostics && CountOurPositions() == 0) {
      string diagShort = BuildTradeDiagnosticText();
      if(StringLen(diagShort) > 72) diagShort = StringSubstr(diagShort, 0, 72) + "...";
      CreateLabel("EA_Diagnose", 10, yPos, "诊断: " + diagShort, clrOrange, 8);
      yPos += lineHeight;
   } else {
      ObjectDelete(0, "EA_Diagnose");
   }
   yPos += 3;
   
   // 分隔线
   CreateLabel("EA_Line1", 10, yPos, "━━━━━━━━━━━━━━━━━━━━━━━━", clrDimGray, 10);
   yPos += lineHeight;
   
   // 资金中枢 - 白色
   int safeMaxLv = (int)MathMin(Grid_Max_Levels, g_eff_Grid_Safe_Max_Levels);
   CreateLabel("EA_Money", 10, yPos,
               StringFormat("资金中枢: 净值 $%.2f | 可用 $%.2f | 回撤 %.2f%%", 
                           accountInfo.Equity(), accountInfo.FreeMargin(), GetAccountDrawdownPct()),
               clrWhite, 10);
   yPos += lineHeight;

   color riskColor = (g_globalRisk >= GRISK_FREEZE) ? clrRed : (g_globalRisk == GRISK_WARN ? clrOrange : clrSilver);
   CreateLabel("EA_Risk", 10, yPos,
               StringFormat("风控: %s | 多[%s] 空[%s] | %s",
                           GlobalRiskStateText(),
                           DirectionRiskStateText(g_buyDirRisk),
                           DirectionRiskStateText(g_sellDirRisk),
                           (g_lastRiskDenyReason != "" ? g_lastRiskDenyReason : g_lastRiskEvent)),
               riskColor, 9);
   yPos += lineHeight;
   string rescueLine = g_eff_Enable_Rescue_Engine
      ? StringFormat("减灾: 开 | 目标≤%d层 | %s", g_eff_Rescue_Target_Max_Levels,
                     (g_lastRescueAction != "" ? g_lastRescueAction : "待命"))
      : "减灾: 关";
   CreateLabel("EA_Rescue", 10, yPos, rescueLine, clrDarkOrange, 9);
   yPos += lineHeight;
   string hedgeLine = "对冲: ";
   if(g_hedgeBuySide.ticket > 0 && PositionSelectByTicket(g_hedgeBuySide.ticket)) {
      hedgeLine += StringFormat("护多#%I64u ", g_hedgeBuySide.ticket);
   }
   if(g_hedgeSellSide.ticket > 0 && PositionSelectByTicket(g_hedgeSellSide.ticket)) {
      hedgeLine += StringFormat("护空#%I64u ", g_hedgeSellSide.ticket);
   }
   if(StringFind(hedgeLine, "#") < 0) hedgeLine += "无";
   CreateLabel("EA_Hedge", 10, yPos, hedgeLine, clrDarkSlateBlue, 9);
   yPos += lineHeight + 3;
   
   // 分隔线
   CreateLabel("EA_Line2", 10, yPos, "━━━━━━━━━━━━━━━━━━━━━━━━", clrDimGray, 10);
   yPos += lineHeight;
   
   // 主网格(多) - 绿色或红色
   color buyColor = (buyGridProfit >= 0) ? clrLime : clrRed;
   string buySign = (buyGridProfit >= 0) ? "+" : "";
   string buyTrailing = (buyGridProfit > 5.0) ? " [🔒追踪]" : "";
   CreateLabel("EA_GridBuy", 10, yPos,
               StringFormat("[主]网格(多): %d/%d | 盈 %s$%.2f%s", 
                           buyGridCount, safeMaxLv, buySign, buyGridProfit, buyTrailing),
               buyColor, 10);
   yPos += lineHeight;
   
   // 主网格(空) - 绿色或红色
   color sellColor = (sellGridProfit >= 0) ? clrLime : clrRed;
   string sellSign = (sellGridProfit >= 0) ? "+" : "";
   string sellTrailing = (sellGridProfit > 5.0) ? " [🔒追踪]" : "";
   CreateLabel("EA_GridSell", 10, yPos,
               StringFormat("[主]网格(空): %d/%d | 盈 %s$%.2f%s", 
                           sellGridCount, safeMaxLv, sellSign, sellGridProfit, sellTrailing),
               sellColor, 10);
   yPos += lineHeight + 3;
   
   // 分隔线
   CreateLabel("EA_Line3", 10, yPos, "━━━━━━━━━━━━━━━━━━━━━━━━", clrDimGray, 10);
   yPos += lineHeight;
   
   // 朱雀突击 - 深红色
   CreateLabel("EA_Zhuque", 10, yPos,
               StringFormat("[辅]朱雀双模突击: %s", zhuqueStatus),
               clrDarkRed, 10);
   yPos += lineHeight;
   
   // 青龙波段 - 青色
   color qinglongColor = (qinglongProfit >= 0) ? clrCyan : clrRed;
   string qinglongSign = (qinglongProfit >= 0) ? "+" : "";
   CreateLabel("EA_Qinglong", 10, yPos,
               StringFormat("[辅]青龙宏观波段: %s | 盈 %s$%.2f", 
                           qinglongStatus, qinglongSign, MathAbs(qinglongProfit)),
               qinglongColor, 10);
   yPos += lineHeight + 3;
   
   // 分隔线
   CreateLabel("EA_Line4", 10, yPos, "━━━━━━━━━━━━━━━━━━━━━━━━", clrDimGray, 10);
   yPos += lineHeight;
   
   // M1物理振幅 - 青色
   CreateLabel("EA_M1Range", 10, yPos,
               StringFormat("M1物理振幅: [%s] %.2f USD", 
                           GetRangeBar(m1Range, M1_Candle_Range_Limit), m1Range),
               clrCyan, 10);
   yPos += lineHeight;
   
   // 防爆盾状态 - 红色/绿色
   if(IsRangeFrozen()) {
      int remainSeconds = (int)(rangeFreezeUntilTime - TimeCurrent());
      int remainMinutes = remainSeconds / 60;
      int remainSecs = remainSeconds % 60;
      CreateLabel("EA_RangeShield", 10, yPos,
                  StringFormat("🛡️ 防爆盾: 冻结中 (%.2f USD) 剩余 %d:%02d", 
                              lastTriggerRange, remainMinutes, remainSecs),
                  clrRed, 10);
   } else {
      CreateLabel("EA_RangeShield", 10, yPos,
                  StringFormat("🛡️ 防爆盾: 正常 (限制 %.2f USD)", M1_Candle_Range_Limit),
                  clrLime, 10);
   }
   yPos += lineHeight;
   
   // 执行协议 - 绿色或黄色
   color protocolColor = sandboxActive ? clrYellow : clrLime;
   CreateLabel("EA_Protocol", 10, yPos,
               StringFormat("执行协议: [%s] %s", sandboxText, sandboxDesc),
               protocolColor, 10);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| 创建文本标签                                                       |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   }
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| 更新持仓信息                                                       |
//+------------------------------------------------------------------+
void UpdatePositions() {
   PurgeClosingTickets();

   ulong latestZhuqueTicket = 0;
   datetime latestZhuqueTime = 0;
   int latestZhuqueType = -1;
   double latestZhuqueOpenPrice = 0;

   ulong latestQinglongTicket = 0;
   datetime latestQinglongTime = 0;
   int latestQinglongType = -1;
   double latestQinglongOpenPrice = 0;

   // 先扫描所有持仓，按原版注释同步角色
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i)) {
         if(positionInfo.Symbol() != _Symbol) continue;
         if(!IsOurPositionSelected()) continue;
         
         string comment = positionInfo.Comment();
         ulong ticket = positionInfo.Ticket();
         int type = (positionInfo.Type() == POSITION_TYPE_BUY) ? 0 : 1;
         double openPrice = positionInfo.PriceOpen();
         datetime openTime = (datetime)positionInfo.Time();

         if(IsGridComment(comment)) {
            int commentType = GetGridDirectionFromComment(comment);
            if(commentType >= 0) {
               type = commentType;
            }
            SyncGridOrder(ticket, comment, type, openPrice, positionInfo.Volume(), openTime);
         } else if(StringFind(comment, "ZhuQue_") == 0) {
            if(openTime >= latestZhuqueTime) {
               latestZhuqueTime = openTime;
               latestZhuqueTicket = ticket;
               latestZhuqueType = type;
               latestZhuqueOpenPrice = openPrice;
            }
         } else if(StringFind(comment, "QingLong") == 0) {
            if(openTime >= latestQinglongTime) {
               latestQinglongTime = openTime;
               latestQinglongTicket = ticket;
               latestQinglongType = type;
               latestQinglongOpenPrice = openPrice;
            }
         }
      }
   }
   
   // 更新网格订单状态
   for(int i = ArraySize(gridOrders) - 1; i >= 0; i--) {
      if(!PositionSelectByTicket(gridOrders[i].ticket)) {
         UnmarkClosingTicket(gridOrders[i].ticket);
         ArrayRemove(gridOrders, i, 1);
         continue;
      }
   }

   CheckDirectionBattleTrail(0);
   CheckDirectionBattleTrail(1);
   
   // 更新朱雀持仓
   if(latestZhuqueTicket > 0) {
      if(zhuquePos.ticket != latestZhuqueTicket) {
         zhuquePos.ticket = latestZhuqueTicket;
         zhuquePos.openPrice = latestZhuqueOpenPrice;
         zhuquePos.maxProfit = 0;
         zhuquePos.type = latestZhuqueType;
      }
      if(PositionSelectByTicket(zhuquePos.ticket)) {
         double currentProfit = PositionGetDouble(POSITION_PROFIT);
         if(currentProfit > zhuquePos.maxProfit) {
            zhuquePos.maxProfit = currentProfit;
         }
         CheckZhuqueTrailingStop();
      }
   } else {
      ResetZhuquePosition();
   }
   
   SyncProtectiveHedgeSlots();

   double qlBasket = GetQinglongBasketProfit();
   if(qlBasket > qinglongPos.basketMaxProfit) {
      qinglongPos.basketMaxProfit = qlBasket;
   }

   if(latestQinglongTicket > 0) {
      if(qinglongPos.ticket != latestQinglongTicket) {
         qinglongPos.ticket = latestQinglongTicket;
         qinglongPos.openPrice = latestQinglongOpenPrice;
         qinglongPos.type = latestQinglongType;
      }
      CheckQinglongStop();
      CheckQinglongATRTrail();
   } else {
      ResetQinglongPosition();
   }
}

//+------------------------------------------------------------------+
//| 检查沙盒状态                                                       |
//+------------------------------------------------------------------+
void CheckSandboxStatus() {
   double currentEquity = accountInfo.Equity();
   double spacing = Grid_Spacing_Points * _Point;

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 3, atr) < 3) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M1, 0, 6, rates) < 6) return;

   datetime closedBarTime = rates[1].time;
   if(closedBarTime == lastSandboxCheckedBarTime) {
      return;
   }
   lastSandboxCheckedBarTime = closedBarTime;

   double closedMove = rates[1].close - rates[5].close;
   double triggerMove = MathMax(atr[1] * 1.2, spacing * 0.8);
   int buyCount = CountGridOrdersByDirection(0);
   int sellCount = CountGridOrdersByDirection(1);
   
   // 检查是否需要触发沙盒
   if(!sandboxActive) {
      bool hasGridExposure = (buyCount + sellCount) > 0;
      bool drawdownTriggered = hasGridExposure && (initialEquity - currentEquity >= Sandbox_Max_Drawdown);
      bool profitTriggered = hasGridExposure && (currentEquity - initialEquity >= Sandbox_Trigger_Profit);

      if((drawdownTriggered || profitTriggered) && closedMove <= -triggerMove) {
         ActivateSandbox(-1, "🚨 [沙盒确诊] 侦测到极端阴跌！多头网格已被拉入沙盒防御！空头继续常态追踪！");
         return;
      }

      if((drawdownTriggered || profitTriggered) && closedMove >= triggerMove) {
         ActivateSandbox(1, "🚨 [沙盒确诊] 侦测到极端慢涨！空头网格已被拉入沙盒防御！多头继续常态追踪！");
         return;
      }
   }
   
   if(sandboxActive) {
      if(sandboxBuyDisabled) {
         double recentHigh = rates[2].high;
         for(int i = 3; i <= 4; i++) {
            if(rates[i].high > recentHigh) recentHigh = rates[i].high;
         }
         double closedBody = rates[1].close - rates[1].open;
         if(rates[1].close > recentHigh || (closedBody > 0 && closedBody > atr[1] * 0.6)) {
            DeactivateSandbox("[异常交接] 阴跌结构破裂！主力爆拉开始，多头交还常态引擎！");
            return;
         }
      }

      if(sandboxSellDisabled) {
         double recentLow = rates[2].low;
         for(int i = 3; i <= 4; i++) {
            if(rates[i].low < recentLow) recentLow = rates[i].low;
         }
         double closedBody = rates[1].open - rates[1].close;
         if(rates[1].close < recentLow || (closedBody > 0 && closedBody > atr[1] * 0.6)) {
            DeactivateSandbox("[异常交接] 慢涨结构破裂！主力砸盘开始，空头交还常态引擎！");
            return;
         }
      }

      if(sandboxBuyDisabled && buyCount < Sandbox_Exit_Profit_Orders) {
         DeactivateSandbox("✅ [沙盒退出] 多头订单数降至" + IntegerToString(buyCount) + "，恢复常态引擎");
         return;
      }
      
      if(sandboxSellDisabled && sellCount < Sandbox_Exit_Profit_Orders) {
         DeactivateSandbox("✅ [沙盒退出] 空头订单数降至" + IntegerToString(sellCount) + "，恢复常态引擎");
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| 激活沙盒                                                           |
//+------------------------------------------------------------------+
void ActivateSandbox(int mode, string reason) {
   sandboxActive = true;
   sandboxMode = mode;
   sandboxBuyDisabled = (mode < 0);
   sandboxSellDisabled = (mode > 0);
   sandboxTriggerEquity = accountInfo.Equity();
   Print(reason);
}

//+------------------------------------------------------------------+
//| 关闭沙盒                                                           |
//+------------------------------------------------------------------+
void DeactivateSandbox(string reason) {
   sandboxActive = false;
   sandboxMode = 0;
   sandboxBuyDisabled = false;
   sandboxSellDisabled = false;
   // 重置沙盒狙击层级
   buyBattle.sniperLevel = 0;
   sellBattle.sniperLevel = 0;
   Print(reason);
}

//+------------------------------------------------------------------+
//| 检查K线振幅防爆盾                                                   |
//+------------------------------------------------------------------+
void CheckCandleRangeShield() {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M1, 0, 2, rates) < 2) return;
   
   // 只检查已收盘的K线（rates[1]），避免当前K线（rates[0]）频繁触发
   static datetime lastCheckedBarTime = 0;
   if(rates[1].time == lastCheckedBarTime) return;
   lastCheckedBarTime = rates[1].time;
   
   // 计算已收盘K线的振幅（美元）
   double m1Range = (rates[1].high - rates[1].low) / _Point * 0.01;
   
   // 如果振幅超过限制，激活冻结
   if(m1Range > M1_Candle_Range_Limit) {
      datetime currentTime = TimeCurrent();
      bool wasNotFrozen = (currentTime >= rangeFreezeUntilTime);  // 之前未冻结
      
      rangeFreezeUntilTime = currentTime + Range_Freeze_Minutes * 60;
      lastTriggerRange = m1Range;
      
      // 只在首次触发冻结时打印日志（避免连续K线刷屏）
      if(wasNotFrozen) {
         Print("🛡️ [防爆盾] M1振幅超限: ", DoubleToString(m1Range, 2), " USD > ", 
               DoubleToString(M1_Candle_Range_Limit, 2), " USD，冻结开仓", 
               Range_Freeze_Minutes, "分钟");
      }
   }
}

//+------------------------------------------------------------------+
//| 检查是否处于冻结期                                                 |
//+------------------------------------------------------------------+
bool IsRangeFrozen() {
   datetime currentTime = TimeCurrent();
   if(currentTime < rangeFreezeUntilTime) {
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 检查趋势过滤器（M5 K线收盘前1秒）                                   |
//+------------------------------------------------------------------+
void CheckTrendFilter() {
   MqlRates m5Rates[];
   ArraySetAsSeries(m5Rates, true);
   if(CopyRates(_Symbol, PERIOD_M5, 0, 3, m5Rates) < 3) return;

   datetime closedBarTime = m5Rates[1].time;
   if(closedBarTime == g_lastM5ClosedBarTime) return;
   g_lastM5ClosedBarTime = closedBarTime;
   lastM5BarTime = m5Rates[0].time;

   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(handleM5_MA, 0, 1, 2, ma) < 2) return;
   double maSlope = ma[0] - ma[1];

   double macdMain[], macdSignal[];
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   if(CopyBuffer(handleM5_MACD, 0, 1, 2, macdMain) < 2) return;
   if(CopyBuffer(handleM5_MACD, 1, 1, 2, macdSignal) < 2) return;

   bool macdGoldenCross = (macdMain[1] <= macdSignal[1]) && (macdMain[0] > macdSignal[0]);
   bool macdDeadCross = (macdMain[1] >= macdSignal[1]) && (macdMain[0] < macdSignal[0]);
   
   // 更新趋势方向
   int oldTrendDirection = trendDirection;
   
   if(maSlope > 0 && macdGoldenCross) {
      trendDirection = 1;  // 只开多
      Print("📈 [趋势过滤] MA斜率朝上(", DoubleToString(maSlope, 5), ") + MACD金叉 → 只开多单");
   }
   else if(maSlope < 0 && macdDeadCross) {
      trendDirection = -1; // 只开空
      Print("📉 [趋势过滤] MA斜率朝下(", DoubleToString(maSlope, 5), ") + MACD死叉 → 只开空单");
   }
   else if(maSlope > 0) {
      trendDirection = 1;  // MA朝上，只开多
      if(oldTrendDirection != 1) {
         Print("📊 [趋势过滤] MA斜率朝上(", DoubleToString(maSlope, 5), ") → 只开多单");
      }
   }
   else if(maSlope < 0) {
      trendDirection = -1; // MA朝下，只开空
      if(oldTrendDirection != -1) {
         Print("📊 [趋势过滤] MA斜率朝下(", DoubleToString(maSlope, 5), ") → 只开空单");
      }
   } else {
      trendDirection = 0;
   }
   
   // 如果趋势方向改变，打印日志
   if(trendDirection != oldTrendDirection) {
      string dirText = (trendDirection == 1) ? "只开多" : (trendDirection == -1) ? "只开空" : "双向";
      Print("🔄 [趋势过滤] 方向切换: ", dirText);
   }
}

//+------------------------------------------------------------------+
//| 统计盈利订单数                                                     |
//+------------------------------------------------------------------+
int CountProfitOrders() {
   int count = 0;
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(PositionSelectByTicket(gridOrders[i].ticket)) {
         if(PositionGetDouble(POSITION_PROFIT) > 0) {
            count++;
         }
      }
   }
   
   if(zhuquePos.ticket > 0 && PositionSelectByTicket(zhuquePos.ticket)) {
      if(PositionGetDouble(POSITION_PROFIT) > 0) count++;
   }
   
   if(qinglongPos.ticket > 0 && PositionSelectByTicket(qinglongPos.ticket)) {
      if(PositionGetDouble(POSITION_PROFIT) > 0) count++;
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| 管理网格系统                                                       |
//+------------------------------------------------------------------+
void ManageGridSystem() {
   CheckHeadTailHedge();

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M1, 0, 1, rates) < 1) return;
   datetime currentBarTime = rates[0].time;

   double buyPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sellPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(!sandboxBuyDisabled) {
      CheckGridExpansion(0, buyPrice, currentBarTime);
   }

   if(!sandboxSellDisabled) {
      CheckGridExpansion(1, sellPrice, currentBarTime);
   }

   CheckSandboxSniper();
}

//+------------------------------------------------------------------+
//| 部署初始网格                                                       |
//+------------------------------------------------------------------+
// [Phase2 待移除] 挂单首层网格，注释 Grid_L* 与当前同步逻辑不兼容
void DeployInitialGrid() {
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double gridSpacing = Grid_Spacing_Points * _Point;
   
   Print("📐 开始部署初始网格，当前价格: ", currentPrice);
   
   // 部署多头网格
   if(!sandboxBuyDisabled) {
      for(int i = 1; i <= Grid_Max_Levels; i++) {
         double price = currentPrice - i * gridSpacing;
         double lots = BaseLotSize * MathPow(Grid_Multiplier, i - 1);
         PlaceGridOrder(ORDER_TYPE_BUY_LIMIT, price, lots, i);
      }
   }
   
   // 部署空头网格
   if(!sandboxSellDisabled) {
      for(int i = 1; i <= Grid_Max_Levels; i++) {
         double price = currentPrice + i * gridSpacing;
         double lots = BaseLotSize * MathPow(Grid_Multiplier, i - 1);
         PlaceGridOrder(ORDER_TYPE_SELL_LIMIT, price, lots, i);
      }
   }
}

//+------------------------------------------------------------------+
//| 下网格挂单                                                         |
//+------------------------------------------------------------------+
void PlaceGridOrder(ENUM_ORDER_TYPE orderType, double price, double lots, int level) {
   // 检查冷却时间
   if(TimeCurrent() - lastGridOrderTime < Grid_Cooldown_Seconds) {
      return;
   }
   
   // 检查资金限制
   if(!CheckRiskLimit(lots)) {
      return;
   }
   
   // 标准化价格和手数
   price = NormalizeDouble(price, _Digits);
   lots = NormalizeDouble(lots, 2);
   
   // 下单
   if(trade.OrderOpen(_Symbol, orderType, lots, 0, price, 0, 0, ORDER_TIME_GTC, 0, "Grid_L" + IntegerToString(level))) {
      lastGridOrderTime = TimeCurrent();
      Print("📌 网格挂单成功: ", EnumToString(orderType), " @ ", price, " Lots: ", lots, " Level: ", level);
   }
}

//+------------------------------------------------------------------+
//| 检查网格扩展                                                       |
//+------------------------------------------------------------------+
void CheckGridExpansion(int direction, double currentPrice, datetime barTime) {
   int positionCount = CountGridOrdersByDirection(direction);
   if(positionCount >= Grid_Max_Levels) return;

   double gridSpacing = Grid_Spacing_Points * _Point;
   bool openedThisBar = (direction == 0) ? (lastGridBuyOpenBarTime == barTime)
                                         : (lastGridSellOpenBarTime == barTime);

   if(positionCount == 0) {
      bool tryImmediate = (Grid_Trend_First_Layer_Immediate && Enable_Trend_Filter);
      if(direction == 0) {
         if(tryImmediate && trendDirection == 1 && !openedThisBar) {
            if(OpenGridPosition(0, false)) {
               lastGridBuyOpenBarTime = barTime;
               buyBattle.anchorPrice = currentPrice;
            }
            return;
         }
         if(buyBattle.anchorPrice == 0 || currentPrice > buyBattle.anchorPrice) {
            buyBattle.anchorPrice = currentPrice;
         }
         if(!openedThisBar && currentPrice <= buyBattle.anchorPrice - gridSpacing) {
            if(OpenGridPosition(0, false)) {
               lastGridBuyOpenBarTime = barTime;
            }
            buyBattle.anchorPrice = currentPrice;
         }
      } else {
         if(tryImmediate && trendDirection == -1 && !openedThisBar) {
            if(OpenGridPosition(1, false)) {
               lastGridSellOpenBarTime = barTime;
               sellBattle.anchorPrice = currentPrice;
            }
            return;
         }
         if(sellBattle.anchorPrice == 0 || currentPrice < sellBattle.anchorPrice) {
            sellBattle.anchorPrice = currentPrice;
         }
         if(!openedThisBar && currentPrice >= sellBattle.anchorPrice + gridSpacing) {
            if(OpenGridPosition(1, false)) {
               lastGridSellOpenBarTime = barTime;
            }
            sellBattle.anchorPrice = currentPrice;
         }
      }
      return;
   }

   double furthestPrice = GetGridExtremePrice(direction);
   if(direction == 0 && !openedThisBar && currentPrice <= furthestPrice - gridSpacing) {
      if(OpenGridPosition(0, false)) {
         lastGridBuyOpenBarTime = barTime;
      }
   }

   if(direction == 1 && !openedThisBar && currentPrice >= furthestPrice + gridSpacing) {
      if(OpenGridPosition(1, false)) {
         lastGridSellOpenBarTime = barTime;
      }
   }
}

//+------------------------------------------------------------------+
//| 检查网格移动止盈                                                   |
//+------------------------------------------------------------------+
// [Phase2 待实现] 单层网格移动止损
void CheckGridTrailingStop(int index) {
   return;
}

//+------------------------------------------------------------------+
//| 管理朱雀引擎                                                       |
//+------------------------------------------------------------------+
void ManageZhuqueEngine() {
   if(IsZhuqueDailyLossLimitReached()) return;

   // 如果已有持仓，检查止盈止损
   if(zhuquePos.ticket > 0) {
      return; // 已在UpdatePositions中处理
   }
   
   // 检查是否可以开新仓
   if(TimeCurrent() - lastZhuqueSignalTime < 60) {
      return; // 冷却时间
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int barShift = Zhuque_Use_Closed_M1_Bar ? 1 : 0;
   if(CopyRates(_Symbol, PERIOD_M1, 0, barShift + 1, rates) < barShift + 1) return;
   if(lastZhuqueSignalBarTime == rates[barShift].time) {
      return;
   }
   
   // 检查总手数限制
   double totalZhuqueLots = GetZhuqueTotalLots();
   if(totalZhuqueLots >= Zhuque_Max_Lot_Limit) {
      return;
   }
   
   // 检测突破信号
   int signal = DetectZhuqueSignal();
   if(signal != 0) {
      if(OpenZhuquePosition(signal)) {
         lastZhuqueSignalBarTime = rates[barShift].time;
      }
   }
}

//+------------------------------------------------------------------+
//| 检测朱雀突破信号                                                   |
//+------------------------------------------------------------------+
int DetectZhuqueSignal() {
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 3, atr) < 3) return 0;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M1, 0, 6, rates) < 6) return 0;

   int b = Zhuque_Use_Closed_M1_Bar ? 1 : 0;
   int atrIdx = Zhuque_Use_Closed_M1_Bar ? 1 : 0;
   double currentBody = MathAbs(rates[b].close - rates[b].open);

   double highestHigh = rates[b + 1].high;
   double lowestLow = rates[b + 1].low;
   for(int i = b + 2; i <= b + 3; i++) {
      if(rates[i].high > highestHigh) highestHigh = rates[i].high;
      if(rates[i].low < lowestLow) lowestLow = rates[i].low;
   }

   if(currentBody > atr[atrIdx] * 0.5 &&
      rates[b].close > rates[b].open &&
      rates[b].close > highestHigh) {
      return 1;
   }

   if(currentBody > atr[atrIdx] * 0.5 &&
      rates[b].close < rates[b].open &&
      rates[b].close < lowestLow) {
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| 开朱雀持仓                                                         |
//+------------------------------------------------------------------+
bool OpenZhuquePosition(int signal) {
   // 检查防爆盾冻结
   if(IsRangeFrozen()) {
      return false;
   }
   
   ENUM_ORDER_TYPE orderType = (signal > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (signal > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDistance = CashToPriceDistance(Zhuque_Hard_SL, Zhuque_Base_Lot);
   double sl = (signal > 0) ? price - slDistance : price + slDistance;
   sl = NormalizeDouble(sl, _Digits);

   string comment = (signal > 0) ? "ZhuQue_B" : "ZhuQue_S";
   string deny = "";
   if(!ExecutePositionOpen(ENGINE_BREAKOUT, orderType, Zhuque_Base_Lot, sl, 0, comment, deny)) {
      return false;
   }
   zhuquePos.ticket = FindLatestPositionTicketByComment(comment);
   zhuquePos.openPrice = price;
   zhuquePos.maxProfit = 0;
   zhuquePos.type = (signal > 0) ? 0 : 1;
   lastZhuqueSignalTime = TimeCurrent();
   
   string direction = (signal > 0) ? "做多" : "做空";
   Print("🦅 [朱雀出击] 饱满真突破！", direction, "！止损设于动能原点防线。");
   return true;
}

//+------------------------------------------------------------------+
//| 检查朱雀移动止盈                                                   |
//+------------------------------------------------------------------+
void CheckZhuqueTrailingStop() {
   if(!PositionSelectByTicket(zhuquePos.ticket)) return;
   
   double currentProfit = PositionGetDouble(POSITION_PROFIT);
   
   // 检查止损
   if(currentProfit <= -Zhuque_Hard_SL) {
      CloseTrackedPosition(zhuquePos.ticket);
      RegisterZhuqueLoss();
      Print("🦅 [朱雀撤退] 触发硬止损: $", DoubleToString(currentProfit, 2));
      return;
   }
   
   // 检查移动止盈
   if(zhuquePos.maxProfit >= Zhuque_TP_Trigger) {
      double drawback = zhuquePos.maxProfit - currentProfit;
      double drawbackRatio = drawback / zhuquePos.maxProfit;
      
      if(drawbackRatio >= Zhuque_Drawback_Ratio) {
         CloseTrackedPosition(zhuquePos.ticket);
         if(currentProfit < 0) RegisterZhuqueLoss();
         Print("🦅 [朱雀凯旋] 极限利润斩杀完成！");
      }
   }
}

//+------------------------------------------------------------------+
//| 获取朱雀总手数                                                     |
//+------------------------------------------------------------------+
double GetZhuqueTotalLots() {
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i)) {
         if(IsOurPositionSelected() &&
            StringFind(positionInfo.Comment(), "ZhuQue_") == 0) {
            total += positionInfo.Volume();
         }
      }
   }
   return total;
}

//+------------------------------------------------------------------+
//| 管理青龙引擎                                                       |
//+------------------------------------------------------------------+
void ManageQinglongEngine() {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M1, 0, 1, rates) < 1) return;
   datetime currentBarTime = rates[0].time;

   // 如果已有持仓，检查加仓和止损
   if(qinglongPos.ticket > 0) {
      CheckQinglongAddPosition(currentBarTime);
      return;
   }

    if(currentBarTime == lastQinglongSignalBarTime) {
      return;
   }

   if(TimeCurrent() - lastQinglongActionTime < 10) {
      return;
   }
   
   // 检测趋势信号
   int signal = DetectQinglongSignal();
   if(signal == 1 && g_marketRegime == REGIME_TREND_DOWN) signal = 0;
   if(signal == -1 && g_marketRegime == REGIME_TREND_UP) signal = 0;
   if(signal != 0) {
      if(OpenQinglongPosition(signal)) {
         lastQinglongSignalBarTime = currentBarTime;
         lastQinglongActionTime = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| 检测青龙趋势信号                                                   |
//+------------------------------------------------------------------+
int DetectQinglongSignal() {
   // 获取ADX
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(handleADX, 0, 0, 3, adx) < 3) return 0;
   
   // 获取K线数据
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M1, 0, Qinglong_SR_Period + 1, rates) < Qinglong_SR_Period + 1) return 0;
   
   // 计算支撑阻力
   double highest = rates[1].high;
   double lowest = rates[1].low;
   for(int i = 2; i <= Qinglong_SR_Period; i++) {
      if(rates[i].high > highest) highest = rates[i].high;
      if(rates[i].low < lowest) lowest = rates[i].low;
   }
   
   double currentPrice = rates[0].close;
   
   // 上涨趋势：ADX强势 + 突破阻力
   if(adx[0] > ADX_Strength_Threshold && currentPrice > highest) {
      return 1; // BUY
   }
   
   // 下跌趋势：ADX强势 + 跌破支撑
   if(adx[0] > ADX_Strength_Threshold && currentPrice < lowest) {
      return -1; // SELL
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| 开青龙持仓                                                         |
//+------------------------------------------------------------------+
bool OpenQinglongPosition(int signal) {
   // 检查防爆盾冻结
   if(IsRangeFrozen()) {
      return false;
   }
   
   ENUM_ORDER_TYPE orderType = (signal > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   int posType = (signal > 0) ? 0 : 1;
   double price = (signal > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0;
   if(Qinglong_Enable_ATR_Trail) {
      sl = CalcQinglongSLPrice(posType, price, Qinglong_ATR_SL_Multiple);
   } else {
      double slDistance = CashToPriceDistance(Qinglong_Hard_SL, Qinglong_Base_Lot);
      sl = (signal > 0) ? price - slDistance : price + slDistance;
      sl = NormalizeDouble(sl, _Digits);
   }

   string comment = (signal > 0) ? "QingLong_B" : "QingLong_S";
   string deny = "";
   if(!ExecutePositionOpen(ENGINE_TREND, orderType, Qinglong_Base_Lot, sl, 0, comment, deny)) {
      return false;
   }
   qinglongPos.ticket = FindLatestPositionTicketByComment(comment);
   qinglongPos.openPrice = price;
   qinglongPos.addTimes = 0;
   qinglongPos.type = posType;
   qinglongPos.basketMaxProfit = 0;
   
   string direction = (signal > 0) ? "做多" : "做空";
   Print("🐉 [青龙波段] 宏观趋势确认！", direction, " SL=", DoubleToString(sl, _Digits));
   return true;
}

//+------------------------------------------------------------------+
//| 检查青龙加仓                                                       |
//+------------------------------------------------------------------+
void CheckQinglongAddPosition(datetime currentBarTime) {
   if(qinglongPos.addTimes >= Qinglong_Max_Add_Times) return;
   if(currentBarTime == lastQinglongAddBarTime) return;
   if(TimeCurrent() - lastQinglongActionTime < 10) return;
   
   // 检查防爆盾冻结
   if(IsRangeFrozen()) {
      return;
   }
   
   // 简化加仓逻辑：趋势延续时加仓
   if(Qinglong_Profit_Add_Only && GetQinglongBasketProfit() <= 0) {
      return;
   }

   int signal = DetectQinglongSignal();
   if(signal == (qinglongPos.type == 0 ? 1 : -1)) {
      double price = (qinglongPos.type == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                                                SymbolInfoDouble(_Symbol, SYMBOL_BID);
      ENUM_ORDER_TYPE orderType = (qinglongPos.type == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double sl = 0;
      if(Qinglong_Enable_ATR_Trail) {
         sl = CalcQinglongSLPrice(qinglongPos.type, price, Qinglong_ATR_SL_Multiple);
      } else if(PositionSelectByTicket(qinglongPos.ticket)) {
         sl = PositionGetDouble(POSITION_SL);
      }
      if(sl <= 0) {
         double slDistance = CashToPriceDistance(Qinglong_Hard_SL, Qinglong_Base_Lot);
         sl = (qinglongPos.type == 0) ? price - slDistance : price + slDistance;
         sl = NormalizeDouble(sl, _Digits);
      }
      string deny = "";
      if(ExecutePositionOpen(ENGINE_TREND, orderType, Qinglong_Base_Lot, sl, 0, "QingLong_Add", deny)) {
         qinglongPos.addTimes++;
         lastQinglongAddBarTime = currentBarTime;
         lastQinglongActionTime = TimeCurrent();
         Print("🐉 [青龙加仓] 第", qinglongPos.addTimes, "次加仓 SL=", DoubleToString(sl, _Digits));
      }
   }
}

//+------------------------------------------------------------------+
//| 检查青龙止损                                                       |
//+------------------------------------------------------------------+
void CheckQinglongStop() {
   double basketProfit = GetQinglongBasketProfit();
   if(basketProfit > qinglongPos.basketMaxProfit) {
      qinglongPos.basketMaxProfit = basketProfit;
   }

   if(basketProfit <= -Qinglong_Hard_SL) {
      BatchCloseByCommentPrefix("QingLong");
      Print("🐉 [青龙止损] 篮子硬止损: $", DoubleToString(basketProfit, 2));
      ResetQinglongPosition();
      return;
   }

   if(Qinglong_TP_Activate_Money > 0 && qinglongPos.basketMaxProfit >= Qinglong_TP_Activate_Money &&
      qinglongPos.basketMaxProfit >= Qinglong_TP_Min_Peak_Money) {
      double drawback = qinglongPos.basketMaxProfit - basketProfit;
      double drawbackRatio = drawback / qinglongPos.basketMaxProfit;
      if(drawbackRatio >= Qinglong_TP_Drawback_Ratio) {
         BatchCloseByCommentPrefix("QingLong");
         Print("🐉 [青龙止盈] 峰值$", DoubleToString(qinglongPos.basketMaxProfit, 2),
               " 回撤", DoubleToString(drawbackRatio * 100.0, 1), "% 平仓 $",
               DoubleToString(basketProfit, 2));
         ResetQinglongPosition();
         return;
      }
   }

   int signal = DetectQinglongSignal();
   if(signal == (qinglongPos.type == 0 ? -1 : 1)) {
      BatchCloseByCommentPrefix("QingLong");
      Print("🐉 [青龙止损] 结构破位，篮子盈亏 $", DoubleToString(basketProfit, 2));
      ResetQinglongPosition();
   }
}

//+------------------------------------------------------------------+
//| 检查资金风险限制                                                   |
//+------------------------------------------------------------------+
// 兼容旧调用；新代码请使用 CanOpenPosition / ExecutePositionOpen
bool CheckRiskLimit(double lots, ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY) {
   string reason = "";
   return CheckMarginForLots(NormalizeVolume(lots), orderType, reason);
}

//+------------------------------------------------------------------+
//| 重置朱雀持仓                                                       |
//+------------------------------------------------------------------+
void ResetZhuquePosition() {
   zhuquePos.ticket = 0;
   zhuquePos.openPrice = 0;
   zhuquePos.maxProfit = 0;
   zhuquePos.type = -1;
}

//+------------------------------------------------------------------+
//| 重置青龙持仓                                                       |
//+------------------------------------------------------------------+
void ResetQinglongPosition() {
   qinglongPos.ticket = 0;
   qinglongPos.openPrice = 0;
   qinglongPos.addTimes = 0;
   qinglongPos.type = -1;
   qinglongPos.basketMaxProfit = 0;
}

//+------------------------------------------------------------------+
//| 重置方向战役状态                                                   |
//+------------------------------------------------------------------+
void ResetDirectionBattle(DirectionBattle &battle) {
   battle.anchorPrice = 0;
   battle.maxProfit = 0;
   battle.trailingActive = false;
   battle.lastSniperBarTime = 0;
   battle.sniperLevel = 0;  // 重置沙盒狙击层级
}

//+------------------------------------------------------------------+
//| 重置战役追踪态（保留锚点与狙击节流）                               |
//+------------------------------------------------------------------+
void ResetDirectionBattleRuntime(DirectionBattle &battle) {
   battle.maxProfit = 0;
   battle.trailingActive = false;
}

//+------------------------------------------------------------------+
//| 是否为原版网格注释                                                 |
//+------------------------------------------------------------------+
bool IsGridComment(string comment) {
   return StringFind(comment, "Grid_B") == 0 || StringFind(comment, "Grid_S") == 0;
}

//+------------------------------------------------------------------+
//| 根据注释识别网格方向                                               |
//+------------------------------------------------------------------+
int GetGridDirectionFromComment(string comment) {
   if(StringFind(comment, "Grid_B") == 0) return 0;
   if(StringFind(comment, "Grid_S") == 0) return 1;
   return -1;
}

//+------------------------------------------------------------------+
//| 同步网格持仓                                                       |
//+------------------------------------------------------------------+
void SyncGridOrder(ulong ticket, string comment, int type, double openPrice, double lots, datetime openTime) {
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].ticket == ticket) {
         gridOrders[i].openPrice = openPrice;
         gridOrders[i].lots = lots;
         gridOrders[i].openTime = openTime;
         gridOrders[i].comment = comment;
         return;
      }
   }

   int size = ArraySize(gridOrders);
   ArrayResize(gridOrders, size + 1);
   gridOrders[size].ticket = ticket;
   gridOrders[size].openPrice = openPrice;
   gridOrders[size].lots = lots;
   gridOrders[size].type = type;
   gridOrders[size].openTime = openTime;
   gridOrders[size].comment = comment;
   gridOrders[size].level = InferGridLevel(comment, type, openTime);

   Print("📍 网格持仓已同步: Ticket=", ticket, " Comment=", comment,
         " Level=", gridOrders[size].level,
         " Type=", (type == 0 ? "BUY" : "SELL"));
}

//+------------------------------------------------------------------+
//| 推断网格层级                                                       |
//+------------------------------------------------------------------+
int InferGridLevel(string comment, int type, datetime openTime) {
   if(StringFind(comment, "Grid_B1") == 0 || StringFind(comment, "Grid_S1") == 0) {
      return 1;
   }

   int level = 1;
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      // 只统计常规网格订单，排除沙盒狙击订单
      bool isSniper = (StringFind(gridOrders[i].comment, "_Sniper") >= 0);
      if(!isSniper && gridOrders[i].type == type && gridOrders[i].openTime <= openTime) {
         level++;
      }
   }
   return level;
}

//+------------------------------------------------------------------+
//| 统计指定方向的网格数                                               |
//+------------------------------------------------------------------+
int CountGridOrdersByDirection(int direction) {
   int count = 0;
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type == direction && PositionSelectByTicket(gridOrders[i].ticket)) {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| 统计指定方向的沙盒狙击订单数（独立计数）                             |
//+------------------------------------------------------------------+
int CountSniperOrdersByDirection(int direction) {
   int count = 0;
   string sniperComment = (direction == 0) ? "Grid_B_Sniper" : "Grid_S_Sniper";
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type == direction && 
         gridOrders[i].comment == sniperComment &&
         PositionSelectByTicket(gridOrders[i].ticket)) {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| 获取指定方向网格总盈亏                                             |
//+------------------------------------------------------------------+
double GetGridBasketProfit(int direction) {
   double profit = 0;
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type == direction && PositionSelectByTicket(gridOrders[i].ticket)) {
         profit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
//| 获取指定方向的极端开仓价                                           |
//+------------------------------------------------------------------+
double GetGridExtremePrice(int direction) {
   double extremePrice = (direction == 0) ? DBL_MAX : 0;
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type != direction || !PositionSelectByTicket(gridOrders[i].ticket)) continue;

      if(direction == 0 && gridOrders[i].openPrice < extremePrice) {
         extremePrice = gridOrders[i].openPrice;
      }
      if(direction == 1 && gridOrders[i].openPrice > extremePrice) {
         extremePrice = gridOrders[i].openPrice;
      }
   }

   if(direction == 0 && extremePrice == DBL_MAX) {
      return SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   return extremePrice;
}

//+------------------------------------------------------------------+
//| 获取网格层级手数                                                   |
//+------------------------------------------------------------------+
double GetGridLotByLevel(int level) {
   double effMult = Grid_Multiplier;
   if(Grid_Max_Multiplier > 0 && effMult > Grid_Max_Multiplier) {
      effMult = Grid_Max_Multiplier;
   }
   return NormalizeVolume(BaseLotSize * MathPow(effMult, level - 1));
}

//+------------------------------------------------------------------+
//| 获取原版风格网格注释                                               |
//+------------------------------------------------------------------+
string GetGridComment(int direction, bool isSniper, int existingCount) {
   if(isSniper) {
      return (direction == 0) ? "Grid_B_Sniper" : "Grid_S_Sniper";
   }

   if(existingCount == 0) {
      return (direction == 0) ? "Grid_B1" : "Grid_S1";
   }

   return (direction == 0) ? "Grid_B_Add" : "Grid_S_Add";
}

//+------------------------------------------------------------------+
//| 开原版风格市价网格单                                               |
//+------------------------------------------------------------------+
bool OpenGridPosition(int direction, bool isSniper) {
   if(IsRangeFrozen()) {
      LogGridOpenDeny(direction, "M1振幅冻结");
      return false;
   }
   
   if(Enable_Trend_Filter) {
      if(trendDirection == 1 && direction == 1) {
         LogGridOpenDeny(direction, "趋势过滤:当前只允许多单");
         return false;
      }
      if(trendDirection == -1 && direction == 0) {
         LogGridOpenDeny(direction, "趋势过滤:当前只允许空单");
         return false;
      }
   }
   
   datetime currentTime = TimeCurrent();
   datetime lastDirectionOrderTime = (direction == 0) ? lastGridBuyOrderTime : lastGridSellOrderTime;
   if(currentTime - lastDirectionOrderTime < Grid_Cooldown_Seconds) {
      return false;
   }

   int existingCount = CountGridOrdersByDirection(direction);
   int maxLevels = (int)MathMin(Grid_Max_Levels, g_eff_Grid_Safe_Max_Levels);
   if(existingCount >= maxLevels) {
      return false;
   }

   int newLevel = existingCount + 1;
   double lots = GetGridLotByLevel(newLevel);
   string deny = "";
   if(!CanAddGrid(direction, lots, deny)) {
      LogGridOpenDeny(direction, deny);
      return false;
   }

   string comment = GetGridComment(direction, isSniper, existingCount);
   ENUM_ORDER_TYPE orderType = (direction == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!ExecutePositionOpen(ENGINE_GRID, orderType, lots, 0, 0, comment, deny)) {
      LogGridOpenDeny(direction, (deny != "" ? deny : "ExecutePositionOpen失败"));
      return false;
   }

   lastGridOrderTime = currentTime;
   if(direction == 0) {
      lastGridBuyOrderTime = currentTime;
   } else {
      lastGridSellOrderTime = currentTime;
   }
   string role = isSniper ? "沙盒狙击" : (existingCount == 0 ? "首层开仓" : "加仓递进");
   string directionText = (direction == 0) ? "多单" : "空单";
   string reason = "";
   
   if(isSniper) {
      reason = "沙盒狙击触发";
   } else if(existingCount == 0) {
      reason = "价格触发网格首层";
   } else {
      reason = StringFormat("价格下跌触发第%d层加仓", newLevel);
      if(direction == 1) reason = StringFormat("价格上涨触发第%d层加仓", newLevel);
   }
   
   double logPrice = (direction == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                      : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   Print("🐂 [夔牛布阵] ", role, " ", directionText, " ", comment, 
         " | 手数:", DoubleToString(lots, 2),
         " | 价格:", DoubleToString(logPrice, _Digits),
         " | 原因:", reason);
   return true;
}

//+------------------------------------------------------------------+
//| 沙盒狙击专用开仓函数（独立层级计数）                                 |
//+------------------------------------------------------------------+
bool OpenSniperPosition(int direction, int sniperLevel) {
   // 检查防爆盾冻结
   if(IsRangeFrozen()) {
      return false;
   }
   
   // 检查趋势过滤器
   if(Enable_Trend_Filter) {
      if(trendDirection == 1 && direction == 1) {
         // 趋势只允许开多，但要开空单
         return false;
      }
      if(trendDirection == -1 && direction == 0) {
         // 趋势只允许开空，但要开多单
         return false;
      }
   }
   
   datetime currentTime = TimeCurrent();
   datetime lastDirectionOrderTime = (direction == 0) ? lastGridBuyOrderTime : lastGridSellOrderTime;
   if(currentTime - lastDirectionOrderTime < Grid_Cooldown_Seconds) {
      return false;
   }

   if(g_globalRisk >= GRISK_WARN) {
      return false;
   }

   double lots = GetGridLotByLevel(sniperLevel);
   string deny = "";
   if(!CanAddGrid(direction, lots, deny)) {
      return false;
   }

   string comment = (direction == 0) ? "Grid_B_Sniper" : "Grid_S_Sniper";
   ENUM_ORDER_TYPE orderType = (direction == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!ExecutePositionOpen(ENGINE_GRID, orderType, lots, 0, 0, comment, deny)) {
      return false;
   }

   lastGridOrderTime = currentTime;
   if(direction == 0) {
      lastGridBuyOrderTime = currentTime;
   } else {
      lastGridSellOrderTime = currentTime;
   }
   
   string directionText = (direction == 0) ? "多单" : "空单";
   double logPrice = (direction == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                      : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   Print("🐂 [夔牛布阵] 沙盒狙击 ", directionText, " ", comment, 
         " | 手数:", DoubleToString(lots, 2),
         " | 价格:", DoubleToString(logPrice, _Digits),
         " | 原因: 沙盒异步狙击触发");
   return true;
}

//+------------------------------------------------------------------+
//| 获取单边战役追踪触发阈值                                           |
//+------------------------------------------------------------------+
double GetBattleTriggerProfit(int levelCount) {
   if(levelCount <= 1) return TP_Level1_Trigger;
   if(levelCount <= 4) return TP_Level2_4_Trigger;
   if(levelCount <= 7) return TP_Level5_7_Trigger;
   return TP_Level8_Plus_Trigger;
}

//+------------------------------------------------------------------+
//| 指定方向是否已有平仓进行中                                         |
//+------------------------------------------------------------------+
bool HasClosingGridOrders(int direction) {
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type == direction && IsTicketClosing(gridOrders[i].ticket)) {
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 检查单边战役追踪止盈                                               |
//+------------------------------------------------------------------+
void CheckDirectionBattleTrail(int direction) {
   int levelCount = CountGridOrdersByDirection(direction);
   if(direction == 0) {
      CheckDirectionBattleTrailImpl(levelCount, buyBattle, direction);
   } else {
      CheckDirectionBattleTrailImpl(levelCount, sellBattle, direction);
   }
}

//+------------------------------------------------------------------+
//| 执行单边战役追踪止盈                                               |
//+------------------------------------------------------------------+
void CheckDirectionBattleTrailImpl(int levelCount, DirectionBattle &battle, int direction) {

   if(levelCount == 0) {
      // 无仓位时只清理追踪止盈状态，保留锚点价给首单触发使用。
      ResetDirectionBattleRuntime(battle);
      return;
   }

   double basketProfit = GetGridBasketProfit(direction);
   if(basketProfit > battle.maxProfit) {
      battle.maxProfit = basketProfit;
   }

   double triggerProfit = GetBattleTriggerProfit(levelCount);
   if(basketProfit >= triggerProfit) {
      battle.trailingActive = true;
   }

   if(!battle.trailingActive || HasClosingGridOrders(direction)) {
      return;
   }

   double drawback = battle.maxProfit - basketProfit;
   double drawbackRatio = (battle.maxProfit > 0) ? (drawback / battle.maxProfit) : 0;

   if(drawbackRatio >= 0.30 || drawback >= TP_Drawback_Threshold) {
      int closeStarted = 0;
      for(int i = ArraySize(gridOrders) - 1; i >= 0; i--) {
         if(gridOrders[i].type == direction && PositionSelectByTicket(gridOrders[i].ticket)) {
            if(CloseTrackedPosition(gridOrders[i].ticket)) {
               closeStarted++;
            }
         }
      }

      if(closeStarted > 0) {
         string directionText = (direction == 0) ? "多单" : "空单";
         double triggerProfit = GetBattleTriggerProfit(levelCount);
         Print("👑 [上帝视角引擎] ", directionText, " ", levelCount, " 层战役完美收网！",
               " | 触发线:$", DoubleToString(triggerProfit, 2),
               " | 极值:$", DoubleToString(battle.maxProfit, 2),
               " | 最终斩获:$", DoubleToString(basketProfit, 2),
               " | 原因: 利润回撤达到", DoubleToString(TP_Drawback_Threshold, 2), "美元");
      }
   }
}

//+------------------------------------------------------------------+
//| 沙盒狙击                                                           |
//+------------------------------------------------------------------+
void CheckSandboxSniper() {
   if(!sandboxActive) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M1, 0, 2, rates) < 2) return;

   double spacing = Grid_Spacing_Points * _Point;
   double buyPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sellPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // 沙盒逻辑：禁止多单时（极端阴跌），狙击空单（做空反弹）
   if(sandboxBuyDisabled && sellBattle.lastSniperBarTime != rates[0].time) {
      // 沙盒狙击使用独立层级计数
      int sniperCount = CountSniperOrdersByDirection(1);  // 空单计数
      int nextSniperLevel = sniperCount + 1;
      double triggerDistance = MathMax(spacing * 0.35, CashToPriceDistance(Sandbox_Strike_Profit, GetGridLotByLevel(nextSniperLevel)));
      double rebound = buyPrice - rates[0].low;  // 反弹幅度
      if(rebound >= triggerDistance && rates[0].close > rates[0].open) {
         if(OpenSniperPosition(1, nextSniperLevel)) {  // 开空单
            sellBattle.lastSniperBarTime = rates[0].time;
            sellBattle.sniperLevel = nextSniperLevel;
            Print("🎯 [沙盒狙击] 空单狙击 | 原因: 极端阴跌中反弹，顶部重锤出击");
         }
      }
   }

   // 沙盒逻辑：禁止空单时（极端慢涨），狙击多单（做多回调）
   if(sandboxSellDisabled && buyBattle.lastSniperBarTime != rates[0].time) {
      // 沙盒狙击使用独立层级计数
      int sniperCount = CountSniperOrdersByDirection(0);  // 多单计数
      int nextSniperLevel = sniperCount + 1;
      double triggerDistance = MathMax(spacing * 0.35, CashToPriceDistance(Sandbox_Strike_Profit, GetGridLotByLevel(nextSniperLevel)));
      double pullback = rates[0].high - sellPrice;  // 回调幅度
      if(pullback >= triggerDistance && rates[0].close < rates[0].open) {
         if(OpenSniperPosition(0, nextSniperLevel)) {  // 开多单
            buyBattle.lastSniperBarTime = rates[0].time;
            buyBattle.sniperLevel = nextSniperLevel;
            Print("🎯 [沙盒狙击] 多单狙击 | 原因: 极端慢涨中回调，底部重锤出击");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 金额转价格距离                                                     |
//+------------------------------------------------------------------+
double CashToPriceDistance(double cashValue, double lots) {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0 || lots <= 0) {
      return cashValue * _Point;
   }

   double ticksNeeded = cashValue / (tickValue * lots);
   return ticksNeeded * tickSize;
}

//+------------------------------------------------------------------+
//| 查找最新持仓ticket                                                 |
//+------------------------------------------------------------------+
ulong FindLatestPositionTicketByComment(string comment) {
   ulong latestTicket = 0;
   datetime latestTime = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i)) {
         if(!IsOurPositionSelected()) continue;
         if(positionInfo.Comment() == comment) {
            if((datetime)positionInfo.Time() >= latestTime) {
               latestTime = (datetime)positionInfo.Time();
               latestTicket = positionInfo.Ticket();
            }
         }
      }
   }
   return latestTicket;
}

//+------------------------------------------------------------------+
//| 关闭持仓并防止重复平仓                                             |
//+------------------------------------------------------------------+
bool CloseTrackedPosition(ulong ticket) {
   if(ticket == 0) return false;
   if(IsTicketClosing(ticket)) return false;
   if(!PositionSelectByTicket(ticket)) {
      UnmarkClosingTicket(ticket);
      return false;
   }

   MarkClosingTicket(ticket);
   string reason = "";
   if(SendMarketDealClose(ticket, reason)) {
      return true;
   }
   UnmarkClosingTicket(ticket);
   return false;
}

//+------------------------------------------------------------------+
//| 清理已经消失的平仓ticket                                           |
//+------------------------------------------------------------------+
void PurgeClosingTickets() {
   for(int i = ArraySize(closingTickets) - 1; i >= 0; i--) {
      if(!PositionSelectByTicket(closingTickets[i])) {
         RemoveClosingTicketAt(i);
      }
   }
}

//+------------------------------------------------------------------+
//| 是否标记为平仓中                                                   |
//+------------------------------------------------------------------+
bool IsTicketClosing(ulong ticket) {
   for(int i = 0; i < ArraySize(closingTickets); i++) {
      if(closingTickets[i] == ticket) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 标记平仓                                                           |
//+------------------------------------------------------------------+
void MarkClosingTicket(ulong ticket) {
   if(IsTicketClosing(ticket)) return;
   int size = ArraySize(closingTickets);
   ArrayResize(closingTickets, size + 1);
   closingTickets[size] = ticket;
}

//+------------------------------------------------------------------+
//| 解除平仓标记                                                       |
//+------------------------------------------------------------------+
void UnmarkClosingTicket(ulong ticket) {
   for(int i = ArraySize(closingTickets) - 1; i >= 0; i--) {
      if(closingTickets[i] == ticket) {
         RemoveClosingTicketAt(i);
      }
   }
}

//+------------------------------------------------------------------+
//| 移除平仓ticket                                                     |
//+------------------------------------------------------------------+
void RemoveClosingTicketAt(int index) {
   int size = ArraySize(closingTickets);
   if(index < 0 || index >= size) return;
   for(int i = index; i < size - 1; i++) {
      closingTickets[i] = closingTickets[i + 1];
   }
   ArrayResize(closingTickets, size - 1);
}

//+------------------------------------------------------------------+
//| 按注释前缀批量平仓                                                 |
//+------------------------------------------------------------------+
void BatchCloseByCommentPrefix(string prefix) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i)) {
         if(!IsOurPositionSelected()) continue;
         if(StringFind(positionInfo.Comment(), prefix) == 0) {
            CloseTrackedPosition(positionInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 数组移除元素                                                       |
//+------------------------------------------------------------------+
void ArrayRemove(GridOrder &array[], int index, int count) {
   int size = ArraySize(array);
   if(index < 0 || index >= size || count <= 0) return;
   
   for(int i = index; i < size - count; i++) {
      array[i] = array[i + count];
   }
   
   ArrayResize(array, size - count);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 获取振幅条形图                                                     |
//+------------------------------------------------------------------+
string GetRangeBar(double range, double limit) {
   int barCount = (int)(range / limit * 10);
   if(barCount > 10) barCount = 10;
   if(barCount < 0) barCount = 0;
   
   string bar = "";
   for(int i = 0; i < barCount; i++) {
      bar += "█";
   }
   for(int i = barCount; i < 10; i++) {
      bar += "░";
   }
   return bar;
}

//+------------------------------------------------------------------+
//| 减灾引擎：统计常规网格层数(不含狙击)                                |
//+------------------------------------------------------------------+
int CountMainGridOrdersByDirection(const int direction) {
   int count = 0;
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type != direction) continue;
      if(StringFind(gridOrders[i].comment, "_Sniper") >= 0) continue;
      if(PositionSelectByTicket(gridOrders[i].ticket)) count++;
   }
   return count;
}

bool IsRescueCooldownActive(const int direction) {
   datetime last = (direction == 0) ? g_lastRescueBuyTime : g_lastRescueSellTime;
   if(last == 0) return false;
   return (TimeCurrent() - last < Rescue_Action_Cooldown_Seconds);
}

void MarkRescueAction(const int direction, const string actionTag) {
   if(direction == 0) g_lastRescueBuyTime = TimeCurrent();
   else g_lastRescueSellTime = TimeCurrent();
   g_lastRescueAction = actionTag;
   g_lastRiskEvent = "RESCUE:" + actionTag;
}

bool RescueCloseTicket(const ulong ticket, const int direction, const string actionTag) {
   if(ticket == 0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   if(CloseTrackedPosition(ticket)) {
      string side = (direction == 0) ? "多" : "空";
      Print("🛟 [减灾] ", side, " ", actionTag, " ticket=", ticket);
      MarkRescueAction(direction, actionTag);
      return true;
   }
   return false;
}

int RescueCloseSnipers(const int direction) {
   string sniperComment = (direction == 0) ? "Grid_B_Sniper" : "Grid_S_Sniper";
   int closed = 0;
   for(int i = ArraySize(gridOrders) - 1; i >= 0; i--) {
      if(gridOrders[i].type != direction) continue;
      if(gridOrders[i].comment != sniperComment) continue;
      if(RescueCloseTicket(gridOrders[i].ticket, direction, "CLOSE_SNIPER")) {
         closed++;
         return closed;
      }
   }
   return closed;
}

ulong FindWorstLossGridTicket(const int direction) {
   ulong worstTicket = 0;
   double worstProfit = 0;
   bool hasLoss = false;
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type != direction) continue;
      if(StringFind(gridOrders[i].comment, "_Sniper") >= 0) continue;
      if(!PositionSelectByTicket(gridOrders[i].ticket)) continue;
      double profit = PositionGetDouble(POSITION_PROFIT);
      if(profit >= 0) continue;
      if(!hasLoss || profit < worstProfit) {
         hasLoss = true;
         worstProfit = profit;
         worstTicket = gridOrders[i].ticket;
      }
   }
   return worstTicket;
}

ulong FindLatestTailGridTicket(const int direction) {
   ulong tailTicket = 0;
   datetime latestTime = 0;
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type != direction) continue;
      if(StringFind(gridOrders[i].comment, "_Sniper") >= 0) continue;
      if(!PositionSelectByTicket(gridOrders[i].ticket)) continue;
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(latestTime == 0 || openTime > latestTime) {
         latestTime = openTime;
         tailTicket = gridOrders[i].ticket;
      }
   }
   return tailTicket;
}

ulong FindSmallestProfitGridTicket(const int direction) {
   ulong pickTicket = 0;
   double smallestProfit = DBL_MAX;
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type != direction) continue;
      if(StringFind(gridOrders[i].comment, "_Sniper") >= 0) continue;
      if(!PositionSelectByTicket(gridOrders[i].ticket)) continue;
      double profit = PositionGetDouble(POSITION_PROFIT);
      if(profit <= 0) continue;
      if(profit < smallestProfit) {
         smallestProfit = profit;
         pickTicket = gridOrders[i].ticket;
      }
   }
   return pickTicket;
}

bool RescueTryPeakCut(const int direction) {
   if(!Rescue_Use_Peak_Cut) return false;
   if(CountMainGridOrdersByDirection(direction) < Grid_Profit_Orders_Threshold) return false;

   ulong firstTicket = 0, lastTicket = 0;
   datetime firstTime = 0, lastTime = 0;
   double firstProfit = 0, lastProfit = 0;

   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type != direction) continue;
      if(StringFind(gridOrders[i].comment, "_Sniper") >= 0) continue;
      if(!PositionSelectByTicket(gridOrders[i].ticket)) continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double profit = PositionGetDouble(POSITION_PROFIT);

      if(firstTime == 0 || openTime < firstTime) {
         firstTime = openTime;
         firstTicket = gridOrders[i].ticket;
         firstProfit = profit;
      }
      if(lastTime == 0 || openTime > lastTime) {
         lastTime = openTime;
         lastTicket = gridOrders[i].ticket;
         lastProfit = profit;
      }
   }

   if(firstTicket == 0 || lastTicket == 0 || firstTicket == lastTicket) return false;
   if(firstProfit + lastProfit < Grid_Hedge_Target_Profit) return false;

   bool ok1 = RescueCloseTicket(firstTicket, direction, "PEAK_CUT_HEAD");
   bool ok2 = RescueCloseTicket(lastTicket, direction, "PEAK_CUT_TAIL");
   return ok1 || ok2;
}

int RescueTrimLayers(const int direction, const DirectionRiskState state, const int maxClose) {
   int closed = 0;
   int mainCount = CountMainGridOrdersByDirection(direction);
   int target = g_eff_Rescue_Target_Max_Levels;

   while(closed < maxClose && mainCount > target) {
      ulong ticket = 0;
      if(Rescue_Close_Worst_Loss_Layer &&
         (state >= DIR_RISK_REDUCE_ONLY || state == DIR_RISK_FREEZE_ADD)) {
         ticket = FindWorstLossGridTicket(direction);
      }
      if(ticket == 0 && Rescue_Close_Tail_Layers_First) {
         ticket = FindLatestTailGridTicket(direction);
      }
      if(ticket == 0) break;
      if(!RescueCloseTicket(ticket, direction, "TRIM_LAYER")) break;
      closed++;
      mainCount--;
   }
   return closed;
}

bool RescueTryWarningTrim(const int direction, const DirectionRiskState state) {
   if(state != DIR_RISK_WARNING && state != DIR_RISK_FREEZE_ADD) return false;
   if(Grid_Direction_Max_Loss_Pct <= 0) return false;

   double balance = accountInfo.Balance();
   if(balance <= 0) balance = accountInfo.Equity();
   double budget = balance * Grid_Direction_Max_Loss_Pct / 100.0;
   double dirLoss = GetGridDirectionFloatingLossMoney(direction);
   if(dirLoss < budget * Rescue_Warning_Loss_Pct_Of_Budget / 100.0) return false;

   ulong ticket = FindSmallestProfitGridTicket(direction);
   if(ticket == 0) return false;
   return RescueCloseTicket(ticket, direction, "WARNING_TRIM_PROFIT");
}

bool RescueTrySandboxDeleverage(const int direction) {
   if(!sandboxActive) return false;
   if(direction == 0 && !sandboxBuyDisabled) return false;
   if(direction == 1 && !sandboxSellDisabled) return false;
   if(CountMainGridOrdersByDirection(direction) < Sandbox_Exit_Profit_Orders) return false;
   return RescueTrimLayers(direction, DIR_RISK_REDUCE_ONLY, Rescue_Layers_Per_Action) > 0;
}

void TryRescueDirection(const int direction) {
   DirectionRiskState state = (direction == 0) ? g_buyDirRisk : g_sellDirRisk;
   if(state == DIR_RISK_CUT_LOSS) return;

   if(IsRescueCooldownActive(direction)) return;

   if(state == DIR_RISK_NORMAL) {
      if(RescueTryPeakCut(direction)) return;
      return;
   }

   if(Rescue_Close_Sniper_In_Risk && state >= DIR_RISK_FREEZE_ADD) {
      if(RescueCloseSnipers(direction) > 0) return;
   }

   if(RescueTrySandboxDeleverage(direction)) return;

   if(RescueTryWarningTrim(direction, state)) return;

   if(RescueTryPeakCut(direction)) return;

   int mainLevels = CountMainGridOrdersByDirection(direction);
   if(mainLevels < Rescue_Min_Grid_Levels_To_Act) return;

   if(state >= DIR_RISK_FREEZE_ADD) {
      int layers = Rescue_Layers_Per_Action;
      if(state == DIR_RISK_REDUCE_ONLY) {
         layers = MathMax(layers, 2);
      }
      if(g_globalRisk >= GRISK_WARN) {
         layers = MathMax(layers, Rescue_Layers_Per_Action + 1);
      }
      if(RescueTrimLayers(direction, state, layers) > 0) return;
   }
}

void ManageRescueEngine() {
   if(!g_eff_Enable_Rescue_Engine) return;
   if(g_globalRisk == GRISK_CIRCUIT) return;

   TryRescueDirection(0);
   TryRescueDirection(1);

   if(g_globalRisk >= GRISK_FREEZE && Rescue_Action_Cooldown_Seconds > 0) {
      static datetime lastGlobalTrim = 0;
      if(TimeCurrent() - lastGlobalTrim >= Rescue_Action_Cooldown_Seconds * 2) {
         int trimmed = 0;
         trimmed += RescueTrimLayers(0, DIR_RISK_REDUCE_ONLY, 1);
         trimmed += RescueTrimLayers(1, DIR_RISK_REDUCE_ONLY, 1);
         if(trimmed > 0) {
            g_lastRescueAction = "GLOBAL_FREEZE_TRIM";
            lastGlobalTrim = TimeCurrent();
         }
      }
   }

   ManageProtectiveHedge();
}

//+------------------------------------------------------------------+
//| 检查指定方向的削峰自救 (兼容旧名，转减灾引擎)                        |
//+------------------------------------------------------------------+
void CheckPeakCutForDirection(int direction) {
   RescueTryPeakCut(direction);
}

void CheckBatchCloseConditions() {
   if(g_eff_Enable_Rescue_Engine) return;
   if(CountMainGridOrdersByDirection(0) >= Grid_Profit_Orders_Threshold) {
      CheckPeakCutForDirection(0);
   }
   if(CountMainGridOrdersByDirection(1) >= Grid_Profit_Orders_Threshold) {
      CheckPeakCutForDirection(1);
   }
}

//+------------------------------------------------------------------+
//| 批量平仓指定方向的网格订单                                         |
//+------------------------------------------------------------------+
void BatchCloseGridOrders(int direction, string reason) {
   for(int i = ArraySize(gridOrders) - 1; i >= 0; i--) {
      if(gridOrders[i].type == direction) {
         if(PositionSelectByTicket(gridOrders[i].ticket)) {
            CloseTrackedPosition(gridOrders[i].ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 批量平仓所有盈利的网格订单                                         |
//+------------------------------------------------------------------+
void BatchCloseProfitGridOrders(string reason) {
   for(int i = ArraySize(gridOrders) - 1; i >= 0; i--) {
      if(PositionSelectByTicket(gridOrders[i].ticket)) {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit > 0) {
            CloseTrackedPosition(gridOrders[i].ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 检查首尾对冲条件（暂不使用，已被削峰自救替代）                       |
//+------------------------------------------------------------------+
void CheckHeadTailHedge() {
   // 此功能已被削峰自救替代，保留接口以备后用
   return;
}
