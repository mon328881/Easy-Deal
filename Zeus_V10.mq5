//+------------------------------------------------------------------+
//|                              宙斯 V10 (Zeus EA - 状态路由架构)    |
//|                                                                  |
//|  设计哲学 (来自 V8/V9 7 轮迭代的血泪):                            |
//|   1. 「不做」比「做」更重要 — 黄金 70% 时间应 FREEZE              |
//|   2. 「点差」是先验, 「ADX/ATR」是后验                            |
//|   3. 「过滤器」是工具, 不是信仰 — 总数硬上限 ≤ 3                  |
//|   4. 「状态切换」是机会, 不是风险                                 |
//|   5. 「黄金 ≠ 外汇」 — 策略颗粒度必须粗一个数量级                 |
//|                                                                  |
//|  架构 (详见 宙斯_开发文档.md):                                    |
//|   L0 宏观 (D1/W1) → L1 主趋势 (H1/H4) → L2 状态机 (M15) →         |
//|   L3 信号 (M5) → L4 执行 (M1+点差护甲)                            |
//|                                                                  |
//|  与 V9 的核心区别:                                                |
//|   + SpreadGuard SP-01~07 (含 spread_ATR 双护甲)                   |
//|   + 品种自适应默认值 (黄金启动自动 set)                           |
//|   + BE 补偿点差 (修复 V9.1 浮盈 44USD 案例)                       |
//|   + 12 类市场状态 + 路由表 (分阶段, P3 先 6 类)                   |
//|   + 出场 Profile A/B/C (按路由派发)                               |
//|   + 自适应追单上限 (Q6 决策)                                      |
//|   + GATE-A 检查点: P4 后决定是否启动 ML (P4.5)                    |
//|                                                                  |
//|  当前阶段: P5/P6 — 路由引擎完善 + 出场 Profile + 自适应追单          |
//|  基线: V9.mq5 (夔牛 V9.1 News-Aware)                              |
//+------------------------------------------------------------------+
#property copyright "Zeus EA V10 — State-Routed Architecture"
#property version   "10.02"
#property description "宙斯 V10: 状态路由 + 出场Profile + 自适应追单"
#property description "详见 宙斯_开发文档.md v0.9"
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
// 输入参数 (宙斯 V10)
//==================================================================
// ============================================================
// V10 设计追溯 (每条参数变更对应 §0.5 中的一条教训):
//
// HC-01 (品种感知默认值): OnInit 检测 _Symbol, 黄金自动 set MaxSpread/Slippage
// HC-04 (过滤器 ≤3):     除点差/熔断/新闻外不引入新过滤器
// HC-05 (状态二元化):    ADX 严格单阈值 22, 无中性带
// HC-07 (BE 早于 SL×0.6): SL_ATR=1.5 → BE_ATR ≤ 0.9
// HC-08 (高点差关网格):   spread_ATR>0.25 时网格关闭
// SP-01 (绝对点差护甲):   MaxSpreadPoints, 黄金 500
// SP-02 (相对点差护甲):   spread_ATR ≤ 0.35 (V10 新增)
// SP-03 (盈利倍数护甲):   预期盈利 ≥ 3× 点差
// SP-05 (BE 补偿点差):    BE 价 = open ± spread_price (V10 新增)
// SP-06 (动态 BE 触发):   max(0.8, 2×spread_ATR) ATR
//
// V10 当前阶段: P0/P1 — 重塑 + SpreadGuard + BE 补偿
// 后续: P2 状态机 / P3 12 状态 / P4 路由表 / GATE-A → P4.5 / P5
// ============================================================

input group "=== [A] 总开关与归属 ==="
input long   InpMagic              = 20260522;   // EA 魔术号 (区分本 EA 持仓)
input string InpComment            = "ZEUS_V10"; // 订单注释前缀 (V10 重塑)
input bool   InpEnableGrid         = false;      // 网格强制常开 (true=忽略Q4条件, 路由为GRID时即允许)
input bool   InpGrid_HardDisable   = false;      // 网格硬禁用 (true=永不网格, 优先级最高)
input bool   InpEnableBreakout     = true;       // 启用趋势突破引擎
input int    InpSlippagePoints     = 50;         // 市价滑点 (点) | OnInit 按品种自适应

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

input group "=== [C2] 日盈利目标 (V10 新增, 赢了就跑) ==="
// 设计理念 (§0.5 第 1 条): "不做" 比 "做" 更重要 — 黄金 70% 时间应 FREEZE
// 一旦今日已达盈利目标, 继续交易边际收益低且风险增加, 应主动停手
input bool   InpEnableDailyProfitTarget = true;  // 启用日盈利达标自动停止
input double InpDailyProfitTargetPct    = 2.0;   // 日盈利目标 % (达成后暂停开新仓, 持仓继续管理)
input bool   InpDailyProfitForceClose   = false; // 是否同时强制平掉所有持仓 (默认 false, 让现有持仓自然出场)

input group "=== [D0] V10 P3+P4 状态扩展 (12 类全完成) ==="
// 详见 宙斯_开发文档.md §4 与 §5 路由表
input bool   InpEnableP3States      = true;       // 启用 V10 多状态识别 (S00-S12)
input int    InpDonch_Period        = 20;         // Donchian 通道回看根数 (S07/S08/S09 分辨)
input double InpDonchWideThresholdPct = 1.5;      // S07 宽幅震荡: (HH-LL)/Close ≥ 此% → 宽
input double InpDonchNarrowFloorPct = 0.3;        // S08 窄幅震荡: (HH-LL)/Close ≤ 此% → 窄
input double InpADX_StrongTrend     = 28.0;       // S03/S04 强趋势 ADX 门槛 (≥28)
// V10 P4 新增参数 (剩余 5 个状态识别)
input bool   InpEnableP4States      = true;       // 启用 P4 状态 (S01/S02/S05/S06/S08/S10/S11)
input double InpGap_ATR_Mult        = 1.5;        // S01 缺口阈值: 开盘价跳空 ≥ ATR×此值
input double InpPreBreakout_LowRatio  = 0.8;      // S02 爆发前夜: ATR_ratio 持续低于此值
input int    InpPreBreakout_LowBars   = 5;        // S02 爆发前夜: ATR_ratio 持续根数
input double InpPreBreakout_NowRatio  = 1.0;      // S02 爆发前夜: 当前根 ATR_ratio 反弹至此以上
input double InpLowVol_ATRRatio     = 0.6;        // S10 低波动: ATR_ratio ≤ 此值
input double InpReversal_DI_Cross   = 1.0;        // S11 反转: DI 翻转后 ADX 跌破阈值的延迟根数

input group "=== [D] 市场状态识别 (ATR + ADX) - V9 严格二元化 ==="
// V9 核心修复: 消除"中性带"
// 旧版 RangeMax=20, TrendMin=25 形成了 20-25 的中性带 → ADX 在此区间反复时永远 NEUTRAL → 不开仓
// V9 改用单一阈值: ADX≥InpADX_TrendMin → 趋势, 否则 → 震荡 (二元判定, 无中间带)
input ENUM_TIMEFRAMES InpRegimeTF  = PERIOD_M15; // 状态识别周期
input int    InpADX_Period         = 14;         // ADX 周期
input double InpADX_TrendMin       = 22.0;       // ★ V9: 单一阈值 (ADX≥此值=趋势, 否则=震荡)
input int    InpATR_Period         = 14;         // ATR 周期
input int    InpATR_AvgLookback    = 20;         // ATR 均值回看根数
input double InpATR_HighVolMult    = 2.5;        // ATR > 均值 × 此值 → 极端波动(冻结)
input int    InpRegimeMinHoldBars  = 2;          // ★ V9: 3→2 加速状态确认

input group "=== [N1] 新闻日历过滤 (V9 新增, 借鉴 GMarket.mq5) ==="
// 利用 MT5 内置经济日历 CalendarValueHistory API
// NFP/CPI/FOMC 等高重要性新闻前后会引发暴力波动, 这是黄金最大的爆仓杀手
// 提前规避新闻时段, 比追涨杀跌更聪明
input bool   InpEnableNewsFilter   = true;       // ★ 启用新闻日历过滤 (强烈建议保持开启)
input int    InpNewsBeforeMinutes  = 60;         // 新闻前暂停分钟数
input int    InpNewsAfterMinutes   = 60;         // 新闻后暂停分钟数
input bool   InpNewsHighImportance = true;       // 过滤高重要性新闻 (NFP/CPI/FOMC等)
input bool   InpNewsMediumImportance = false;    // 过滤中重要性新闻 (默认关, 否则过严)

input group "=== [D3] H1 大趋势偏好 (V9: 软参考, 不再硬过滤) ==="
// V9 改变: H1 偏好仅作为日志参考, 不再阻止 M15 入场
// 原因: V8.3 全年 0 笔, 主要就是 H1 硬过滤砍掉了所有逆势机会
//      实战上 H1 多头里的 M15 强空头回调, 往往是优质交易机会
input bool   InpEnableH1Bias       = true;       // 启用 H1 大趋势偏好 (仅诊断显示)
input bool   InpH1BiasHardFilter   = false;      // ★ V9: 是否硬过滤 (false=仅参考)
input ENUM_TIMEFRAMES InpH1_TF     = PERIOD_H1;  // 大趋势识别周期
input int    InpH1_FastEMA         = 50;         // 快线 EMA 周期
input int    InpH1_SlowEMA         = 200;        // 慢线 EMA 周期
input double InpH1_MinADX          = 20.0;       // H1 ADX 阈值 (仅诊断)
input int    InpH1_ADX_Period      = 14;         // H1 ADX 周期

input group "=== [E] 网格引擎 (震荡态) - V8.1 安全化重构 ==="
// Q4 决策: 默认不强制常开 (InpEnableGrid=false), 满足三重条件时运行时自动允许网格
input bool   InpGrid_AutoEnable    = true;       // Q4: 震荡+低点差+H1弱 时自动允许网格
input double InpGrid_AutoSpreadATR = 0.25;       // Q4/HC-08: S07/S09 spread/ATR 上限
input double InpGrid_AutoSpreadATR_Narrow = 0.20;// Q4: S08 窄幅震荡更严 spread/ATR 上限
input double InpGrid_AutoH1_ADXMax   = 20.0;     // Q4: H1 ADX 须低于此值 (大趋势酝酿则冻结)
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

input group "=== [F2] 突破引擎 - 模式 B: 趋势跟随 (V9 双模式入场) ==="
// V9 重要修复: 旧逻辑陷阱 - 强趋势时价格远离锚点, 永远等不到回调入场点
// 新逻辑: 两种入场方式择一, OR 关系
//   方式 A 「回调入场」: |价格-锚点| ≤ PullbackATR × ATR (理想情况, 价格回调到均线附近)
//   方式 B 「顺势追单」: PullbackATR < |价格-锚点| ≤ MaxChaseATR × ATR (趋势已展开, 顺势追)
input bool   InpBO_EnableTrendFollow = true;     // 启用趋势跟随入场
input double InpBO_TF_MinADX       = 28.0;       // ADX 达此值才认为趋势强 (V9: 30→28 放宽)
input double InpBO_TF_PullbackATR  = 1.5;        // 回调窗口 = ATR × 此值 (V9 改回 0.5→1.5)
input double InpBO_TF_MaxChaseATR  = 5.0;        // ★ V9 新增: 追单最大距离 = ATR × 此值 (Q6 自适应时作基线)

input group "=== [F2b] 自适应追单上限 (V10 Q6) ==="
input bool   InpAdaptiveMaxChase     = true;       // 启用自适应 MaxChase (§12.2)
input int    InpAdaptiveLookbackWeeks  = 20;       // 回看周数 (M15 ATR 序列)
input double InpBO_TF_BaseChase        = 5.0;      // 自适应基线/数据不足兜底
input double InpMaxChase_Lower         = 2.0;      // 自适应下限 (ATR 倍数)
input double InpMaxChase_Upper         = 8.0;      // 自适应上限 (ATR 倍数)

input group "=== [F2c] 出场 Profile (V10 P6, 按路由派发) ==="
// Profile A: 强趋势 BREAKOUT — 继承 V9.1 激进锁利
// Profile B: 弱趋势 TREND_FOLLOW — 更紧 BE/追踪
// Profile C: 网格 — 整篮 TP, 单笔无 BE/追踪 (ManageGridBasket 负责)
input double InpExitB_BE_TriggerATR  = 0.6;      // Profile B: BE 触发
input double InpExitB_TrailStartATR    = 1.2;      // Profile B: 追踪启动
input double InpExitB_TrailDistATR     = 0.4;      // Profile B: 追踪距离
input double InpExitB_TrailStepATR     = 0.15;     // Profile B: 追踪步长
input double InpExitLight_LotMult      = 0.5;      // BREAKOUT_LIGHT 手数系数
input double InpExitFollow_LotMult     = 0.6;      // TREND_FOLLOW 手数系数
input ENUM_TIMEFRAMES InpBO_TF_AnchorTF = PERIOD_M5; // 趋势跟随锚点周期
input int    InpBO_TF_AnchorMAPer  = 20;         // 锚点均线周期 (EMA)
input int    InpBO_TF_CooldownSec  = 180;        // 趋势跟随入场冷却(秒)

input group "=== [F3] 突破引擎 - 通用 (V9.1 激进快锁利) ==="
input int    InpBO_MaxSameSide     = 1;          // 同向突破最大持仓
// ★★★ V9.1 激进快锁利 (针对黄金高点差 300+ 环境)
// 旧 V8.2.1 设计 BE_Trigger=1.5 ATR 意味着浮盈达 5 美元才开始保本
//   → 在黄金 M15 经常浮盈 4 美元转身就回吐, 永远等不到锁利时机
// 新 V9.1 设计:
//   - BE_Trigger 1.5→0.8: 浮盈 ~2.5 美元立即保本, 不让任何赢家变输家
//   - TrailStart 2.5→1.5: 浮盈 ~5 美元启动追踪, 让趋势继续走
//   - TrailDist  0.8→0.5: 追踪距市价 ~1.6 美元, 紧贴市价锁利
//   - TrailStep  0.3→0.2: 追踪 SL 更新更敏感
// 目标: 把 44 美元浮盈这样的机会真正落袋
input double InpBO_SL_ATR_Mult     = 1.5;        // 初始止损 = ATR × 此值
input double InpBO_BE_TriggerATR   = 0.8;        // V9.1: BE 触发基线 (V10 SP-06 会动态抬升)
input bool   InpBO_BE_DynamicByATR = true;       // SP-06: 黄金高点差时动态抬升 BE 触发 = max(BE_TriggerATR, 2×spread_ATR)
input double InpBO_TrailStartATR   = 1.5;        // 浮盈 ~5 美元启动追踪
input double InpBO_TrailDistATR    = 0.5;        // 紧贴市价锁利
input double InpBO_TrailStepATR    = 0.2;        // ★ V9.1: 0.3→0.2 追踪更敏感
input int    InpBO_CooldownSec     = 120;        // Donchian 突破信号冷却(秒)

input group "=== [F4] 趋势期入场保护 (V9 放宽: 0=禁用) ==="
input int    InpTrendColdStartBars = 0;          // V9: 0=不冷启动 (V8.2 是 2, 太苛刻)
input int    InpMaxEntriesPerTrend = 10;         // V9: 10次 (V8.2 是 2, 太苛刻)

input group "=== [G] 通用过滤器 ==="
input double InpMaxSpreadPoints    = 500.0;      // SP-01: 最大允许点差 (OnInit 按品种自适应)
input bool   InpUseSessionFilter   = false;      // 启用交易时段过滤
input int    InpSessionStartHour   = 8;          // 时段开始 (服务器时间)
input int    InpSessionEndHour     = 22;         // 时段结束 (服务器时间)

input group "=== [G2] 点差护甲 SpreadGuard (V10 新增, 对应文档 §1.2) ==="
// V10 核心: 黄金 (XAUUSDm) 点差 200~400 点是常态, 必须用 spread_ATR (相对波动率) 双护甲
// 任何信号触发前先过 SpreadGuard, 不能赚回 ≥3× 点差的信号直接丢弃
input bool   InpEnableSpreadGuard  = true;       // 启用 SpreadGuard (强烈建议保持开启)
input double InpMaxSpreadATRRatio  = 0.35;       // SP-02: spread / ATR_M15 上限 (黄金 0.35, 外汇 0.10)
input double InpMinProfitSpreadMult = 3.0;       // SP-03: 预期盈利 ≥ N× 点差 才允许入场
input double InpGrid_MinTPSpreadMult = 2.0;      // SP-04: 网格篮 TP ≥ N× (点差 × 层数)
input bool   InpAsianSessionLooseSpread = true;  // Q2: 亚盘 23:00~04:00 GMT 放宽 SP-01 1.5 倍
input double InpAsianSpreadMult    = 1.5;        // Q2: 亚盘点差放宽倍数

input group "=== [H] 诊断与 UI ==="
input bool   InpEnableDiagnostic   = true;       // 启用诊断日志 (无仓时定时输出阻塞原因)
input int    InpDiagnosticIntervalSec = 30;      // 诊断日志间隔(秒)
input bool   InpShowControlPanel   = true;       // 显示右侧控制按钮面板
input bool   InpDashboardBackground = true;      // V10 P4: 左侧 dashboard 显示深色半透明背景框
input int    InpDashboardFontSize   = 10;        // V10 P4: 左侧 dashboard 字体大小 (推荐 10-12)

//==================================================================
// 枚举与全局结构
//==================================================================
// V10 P3+P4: 市场状态全 12 类完成
// 兼容旧值: REGIME_RANGE/TREND_UP/TREND_DOWN/HIGH_VOL 数值不变, 旧代码引用仍工作
// 详见 宙斯_开发文档.md §4 与 §12 Q3 决策
enum MarketRegime {
   REGIME_UNKNOWN      = 0,
   REGIME_RANGE        = 1,   // (S09 盘整, 默认兜底)
   REGIME_TREND_UP     = 2,   // (S03 强趋势↑ ADX≥28)
   REGIME_TREND_DOWN   = 3,   // (S04 强趋势↓ ADX≥28)
   REGIME_NEUTRAL      = 4,   // 保留兼容 (V10 不再产出)
   REGIME_HIGH_VOL     = 5,   // (S00) 高波动
   REGIME_RANGE_WIDE   = 6,   // (S07) 宽幅震荡 → 宽网格
   REGIME_NEWS_WINDOW  = 7,   // (S12) 新闻窗口 → FREEZE
   // V10 P4 新增 (剩余 5 类)
   REGIME_GAP          = 8,   // (S01) 缺口 → CLOSE_ONLY
   REGIME_PRE_BREAKOUT = 9,   // (S02) 爆发前夜 → 轻仓突破
   REGIME_TREND_UP_WK  = 10,  // (S05) 弱趋势↑ 22≤ADX<28 → 紧追踪
   REGIME_TREND_DN_WK  = 11,  // (S06) 弱趋势↓ 22≤ADX<28 → 紧追踪
   REGIME_RANGE_NARROW = 12,  // (S08) 窄幅震荡 → 高点差时 FREEZE
   REGIME_LOW_VOL      = 13,  // (S10) 低波动 → 极小网格或观望
   REGIME_REVERSAL     = 14   // (S11) 反转 → CLOSE_ONLY
};

// V10 P3+P4: 策略路由枚举 (状态 → 路由表的输出)
// 详见 宙斯_开发文档.md §5
enum StrategyRoute {
   ROUTE_FREEZE         = 0,  // 不开新仓, 仅管理存量 (S00/S08*/S10/S12)
   ROUTE_GRID_NARROW    = 1,  // 窄网格 (S09 盘整)
   ROUTE_GRID_WIDE      = 2,  // 宽网格 (S07 宽幅震荡)
   ROUTE_BREAKOUT       = 3,  // 突破 + 趋势跟随 (S03/S04 强趋势)
   ROUTE_CLOSE_ONLY     = 4,  // 仅平仓 (S01/S11)
   // V10 P4 新增
   ROUTE_BREAKOUT_LIGHT = 5,  // 轻仓突破 (S02 爆发前夜, 0.5× 仓位)
   ROUTE_TREND_FOLLOW   = 6   // 仅趋势跟随 (S05/S06 弱趋势, 0.6× 仓位 + 紧追踪)
};

// V10 P6: 出场 Profile (按路由派发, 详见 §5.4)
enum ExitProfile {
   EXIT_PROFILE_A = 0,  // 激进锁利 (强趋势 / 轻仓突破)
   EXIT_PROFILE_B = 1,  // 紧跟随 (弱趋势)
   EXIT_PROFILE_C = 2   // 网格整篮 (单笔无 BE/追踪)
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
// V9: 初始默认震荡态 (而非未知), 避免启动后 N 根K线内死锁不开仓
MarketRegime g_regime = REGIME_RANGE;
MarketRegime g_regimeCandidate = REGIME_RANGE;
int          g_regimeCandidateBars = 0;
datetime     g_lastRegimeBarTime = 0;

// V8.2 新增: 趋势期入场保护
datetime g_regimeEnterTime  = 0;  // 当前 regime 开始时间
int      g_entriesThisTrend = 0;  // 当前趋势期已入场次数

// V10 P2 新增: 状态切换历史 (HC-09 证据链 + REG-03 鞭打风险鉴别)
#define REGIME_HIST_SIZE 32
datetime     g_regimeSwitchTimes[REGIME_HIST_SIZE];   // 最近 N 次切换时间 (环形)
int          g_regimeSwitchIdx        = 0;            // 写入位置
int          g_regimeSwitchTotal      = 0;            // 累计切换次数
datetime     g_lastRegimeSwitchTime   = 0;            // 最近一次切换
string       g_lastRegimeSwitchReason = "";           // 最近一次切换文字证据
datetime     g_eaStartTime            = 0;            // EA 启动时间 (REG-01 检查用)
bool         g_firstRegimeProduced    = false;        // 是否已产出第一个状态 (REG-01)

// V10 P3 新增: 当前路由 (由 ResolveRoute_Zeus 每 tick 写入, 诊断面板可见)
StrategyRoute g_currentRoute       = ROUTE_FREEZE;
string        g_currentRouteReason = "(未初始化)";

// V9 新增: 新闻日历过滤器状态
bool     g_inNewsWindow = false;       // 当前是否在新闻时段
string   g_currentNewsTitle = "";      // 命中的新闻名称
datetime g_lastNewsCheckTime = 0;      // 上次检查时间 (节流, 避免每 tick 查询日历)
datetime g_nextNewsTime = 0;           // 下一个新闻的时间 (诊断用)
string   g_nextNewsTitle = "";         // 下一个新闻的名称 (诊断用)

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

// V10: 面板折叠状态 (默认展开)
bool g_panelCollapsed    = false;

// V10: 日盈利目标达成标记 (达成后 g_runPaused 同步置 true)
bool g_dailyTargetHit    = false;
datetime g_dailyTargetHitTime = 0;

// V10 Q6: 自适应追单状态
double   g_effectiveMaxChaseATR = 5.0;
datetime g_maxChaseRefreshWeek  = 0;   // 上次刷新所在周的周一 00:00

// V10 Q4: 网格三重激活 (运行时由 UpdateGridAutoAllowed_Zeus 刷新)
bool g_gridAutoAllowed = false;

// 诊断
datetime g_lastDiagTime = 0;
string   g_lastBlockReason = "";  // 最近一次拒单原因, 写入看板

//+------------------------------------------------------------------+
//| 日盈利计算 (与 GetDailyLossPct 对称, V10 新增)                    |
//| 返回值: 正数=今日盈利%, 负数=今日亏损%                            |
//+------------------------------------------------------------------+
double GetDailyProfitPct() {
   if(g_dailyStartEquity <= 0) return 0;
   double diff = accInfo.Equity() - g_dailyStartEquity;
   return diff / g_dailyStartEquity * 100.0;
}

//+------------------------------------------------------------------+
//| 日盈利金额 (USD)                                                  |
//+------------------------------------------------------------------+
double GetDailyProfitUSD() {
   if(g_dailyStartEquity <= 0) return 0;
   return accInfo.Equity() - g_dailyStartEquity;
}

//==================================================================
// UI 控制面板 (右上角, V10 重设计)
// 改动:
//   - 增加 [折叠/展开] 切换按钮 (始终显示)
//   - 移除手动买入/卖出按钮 (§0.5 反模式: 人工干预破坏策略一致性)
//   - 增加日盈利显示标签 (今日 ±X.XX% = ±USD)
//   - 增加日盈利目标达成提示
//==================================================================
#define UI_PREFIX "ZEUS_"
const int UI_BTN_W  = 140;
const int UI_BTN_H  = 26;
const int UI_LBL_H  = 20;
const int UI_BTN_X  = 8;   // 距右边距 (CORNER_RIGHT_UPPER)
const int UI_BTN_Y0 = 30;
const int UI_BTN_GAP= 4;

void CreateButton(const string id, const string text, int yPos, color bg, color fg = clrWhite) {
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
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yPos);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}

void CreatePanelLabel(const string id, const string text, int yPos, color fg, int fontSize = 9) {
   string name = UI_PREFIX + id;
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, UI_BTN_X + UI_BTN_W);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString (0, name, OBJPROP_FONT, "Microsoft YaHei");
   }
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yPos);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}

// 所有控件 ID (用于折叠/删除)
// V10: 日盈利显示已迁至左侧 dashboard, 此处仅留交互按钮
string g_panelButtonIDs[] = {"Toggle","Pause","Grid","Breakout","CloseGrid","CloseBO","CloseAll","Diag"};
string g_panelLabelIDs[]  = {};   // 已清空 (旧 LblTitle/LblPnL/LblTarget 删除)

void DeleteControlPanel() {
   for(int i = 0; i < ArraySize(g_panelButtonIDs); i++) ObjectDelete(0, UI_PREFIX + g_panelButtonIDs[i]);
   for(int i = 0; i < ArraySize(g_panelLabelIDs);  i++) ObjectDelete(0, UI_PREFIX + g_panelLabelIDs[i]);
}

// 隐藏面板内除 Toggle 外的所有控件 (折叠态)
void HideCollapsibleItems() {
   for(int i = 0; i < ArraySize(g_panelButtonIDs); i++) {
      if(g_panelButtonIDs[i] == "Toggle") continue;
      ObjectDelete(0, UI_PREFIX + g_panelButtonIDs[i]);
   }
   for(int i = 0; i < ArraySize(g_panelLabelIDs); i++) {
      ObjectDelete(0, UI_PREFIX + g_panelLabelIDs[i]);
   }
}

void CreateControlPanel() {
   if(!InpShowControlPanel) return;

   int y = UI_BTN_Y0;

   // [Toggle] 始终显示, 控制其余控件可见性
   CreateButton("Toggle",
                g_panelCollapsed ? "▼ 展开面板" : "▲ 折叠面板",
                y, g_panelCollapsed ? clrDarkSlateGray : clrSlateGray);
   y += UI_BTN_H + UI_BTN_GAP;

   if(g_panelCollapsed) {
      HideCollapsibleItems();
      ChartRedraw();
      return;
   }

   // 控制按钮 (V10: 日盈利标签已移至左侧 dashboard, 此处仅保留交互按钮)
   y += UI_BTN_GAP;
   CreateButton("Pause",     g_runPaused ? "▶ 恢复 EA" : "⏸ 暂停 EA",
                y, g_runPaused ? clrDarkGreen : clrDarkOrange);                              y += UI_BTN_H + UI_BTN_GAP;
   CreateButton("Grid",      g_runEnableGrid ? "🟢 网格 ON" : "⚪ 网格 OFF",
                y, g_runEnableGrid ? clrDarkGreen : clrDimGray);                             y += UI_BTN_H + UI_BTN_GAP;
   CreateButton("Breakout",  g_runEnableBreakout ? "🟢 突破 ON" : "⚪ 突破 OFF",
                y, g_runEnableBreakout ? clrDarkGreen : clrDimGray);                         y += UI_BTN_H + UI_BTN_GAP;
   CreateButton("CloseGrid", "✕ 平网格仓",      y, clrMaroon);                               y += UI_BTN_H + UI_BTN_GAP;
   CreateButton("CloseBO",   "✕ 平突破仓",      y, clrMaroon);                               y += UI_BTN_H + UI_BTN_GAP;
   CreateButton("CloseAll",  "✕✕ 平全部",        y, clrCrimson);                              y += UI_BTN_H + UI_BTN_GAP;
   CreateButton("Diag",      "📋 输出诊断日志", y, clrDarkSlateBlue);
}

//+------------------------------------------------------------------+
//| 日盈利显示文字与颜色 (V10 新增)                                   |
//+------------------------------------------------------------------+
string BuildDailyPnLText() {
   double pct = GetDailyProfitPct();
   double usd = GetDailyProfitUSD();
   string emoji = (pct > 0.01) ? "📈" : ((pct < -0.01) ? "📉" : "⊜");
   return StringFormat("%s 今日: %+.2f%% (%+.2f USD)", emoji, pct, usd);
}

color GetDailyPnLColor() {
   double pct = GetDailyProfitPct();
   if(pct >= InpDailyProfitTargetPct && InpEnableDailyProfitTarget) return clrLime;
   if(pct >= 0.5)                                                   return clrLightGreen;
   if(pct >  -0.5)                                                  return clrSilver;
   if(pct >  -InpDailyLossLimitPct * 0.5)                           return clrSandyBrown;
   return clrRed;
}

string BuildDailyTargetText() {
   double cur = GetDailyProfitPct();
   if(g_dailyTargetHit) {
      return StringFormat("✅ 已达标 %.2f%% @ %s",
                          InpDailyProfitTargetPct,
                          TimeToString(g_dailyTargetHitTime, TIME_MINUTES));
   }
   return StringFormat("🎯 目标 %.2f%% / 还差 %.2f%%",
                       InpDailyProfitTargetPct,
                       MathMax(0, InpDailyProfitTargetPct - cur));
}

color GetDailyTargetColor() {
   if(g_dailyTargetHit) return clrLime;
   return clrLightGray;
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

//+------------------------------------------------------------------+
//| V10 P3: Donchian 通道宽度 = (HH - LL) / Close × 100%               |
//|                                                                  |
//| 用于区分 S07 宽幅震荡 vs S09 盘整 (§4 文档定义):                  |
//|   - Donch_w > 1.5%  → S07 宽幅震荡 → ROUTE_GRID_WIDE              |
//|   - Donch_w ∈ [0.5%, 1.5%] → S09 盘整 → ROUTE_GRID_NARROW          |
//|   - Donch_w < 0.5% → S10 低波动 (P4 占位, 暂归 S09)               |
//|                                                                  |
//| 在 InpRegimeTF (默认 M15) 上计算, 与状态机同周期                  |
//+------------------------------------------------------------------+
double GetDonchianWidthPct() {
   if(InpDonch_Period <= 0) return 0.0;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpRegimeTF, 1, InpDonch_Period, r) < InpDonch_Period) return 0.0;
   double hh = r[0].high, ll = r[0].low;
   for(int i = 1; i < InpDonch_Period; i++) {
      if(r[i].high > hh) hh = r[i].high;
      if(r[i].low  < ll) ll = r[i].low;
   }
   double close = r[0].close;
   if(close <= 0) return 0.0;
   return (hh - ll) / close * 100.0;
}

//==================================================================
// V10 P4 状态识别辅助函数
//==================================================================

// S01 缺口检测: 当根开盘价 vs 上根收盘价的差异 (单位 ATR)
// 输出: 正数=向上跳空, 负数=向下跳空, 0=无明显缺口
double GetGapATR_Zeus() {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpRegimeTF, 0, 2, r) < 2) return 0.0;
   double atr = GetATR(g_hATR, 1);
   if(atr <= 0) return 0.0;
   double gap = r[0].open - r[1].close;
   return gap / atr;
}

// S02 爆发前夜: ATR_ratio 持续低 + 当前根反弹 → 蓄势爆发临界态
// 输出: true=满足前夜形态
bool IsPreBreakout_Zeus() {
   if(!InpEnableP4States) return false;
   if(InpPreBreakout_LowBars < 2) return false;
   double atrAvg = GetATR_Mean(g_hATR, InpATR_AvgLookback);
   if(atrAvg <= 0) return false;
   // 当前根 ATR_ratio 须反弹至阈值
   double atrNow = GetATR(g_hATR, 0);
   if(atrNow / atrAvg < InpPreBreakout_NowRatio) return false;
   // 之前 N 根 ATR_ratio 必须 < LowRatio
   for(int i = 1; i <= InpPreBreakout_LowBars; i++) {
      double a = GetATR(g_hATR, i);
      if(a <= 0) return false;
      if(a / atrAvg >= InpPreBreakout_LowRatio) return false;
   }
   return true;
}

// S11 反转检测: 之前是强趋势 (ADX≥强阈值), 当前 ADX 跌破 InpADX_TrendMin
//             且 DI 方向翻转 (上一根 +DI 主导, 当前 -DI 主导, 或反之)
// 输出: true=满足反转形态
bool IsReversal_Zeus() {
   if(!InpEnableP4States) return false;
   // 需要历史强趋势锚点 (g_regime 曾是 TREND_UP/DOWN)
   bool wasStrongTrend = (g_regime == REGIME_TREND_UP || g_regime == REGIME_TREND_DOWN ||
                          g_regime == REGIME_TREND_UP_WK || g_regime == REGIME_TREND_DN_WK);
   if(!wasStrongTrend) return false;
   double adxPrev = GetADX(1);
   double adxNow  = GetADX(0);
   // 之前强, 当前弱
   if(adxPrev < InpADX_TrendMin) return false;
   if(adxNow  >= InpADX_TrendMin) return false;
   // DI 方向翻转 (上一根方向与当前根方向相反)
   int dirPrev = GetADX_Direction(1);
   int dirNow  = GetADX_Direction(0);
   if(dirPrev * dirNow >= 0) return false;   // 同号或 0 → 无翻转
   return true;
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

//+------------------------------------------------------------------+
//| 亚盘时段判定 (Q2 决策: 23:00~04:00 GMT 放宽 SP-01)                |
//+------------------------------------------------------------------+
bool IsAsianSession_Zeus() {
   if(!InpAsianSessionLooseSpread) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);   // GMT 而非服务器时间, 避免经纪商时区差异
   return (dt.hour >= 23 || dt.hour < 4);
}

//+------------------------------------------------------------------+
//| SpreadGuard: V10 双护甲 (SP-01 绝对点差 + SP-02 spread/ATR 相对) |
//|                                                                  |
//| 返回 false 时 reason 已填好, 调用方直接走拒单分支。               |
//| - SP-01: 点数 ≤ MaxSpreadPoints (亚盘 × 倍数放宽)                 |
//| - SP-02: spread_price / ATR_M15 ≤ MaxSpreadATRRatio              |
//|                                                                  |
//| 注意: SP-03 (盈利倍数护甲) 需在具体子策略入口检查, 不在这里。     |
//+------------------------------------------------------------------+
bool PassesSpreadGuard_Zeus(string &reason) {
   if(!InpEnableSpreadGuard) return true;

   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   // SP-01: 绝对点差 (亚盘可放宽)
   double spreadCap = InpMaxSpreadPoints;
   bool asian = IsAsianSession_Zeus();
   if(asian) spreadCap *= InpAsianSpreadMult;

   if(InpMaxSpreadPoints > 0 && spreadPts > spreadCap) {
      reason = StringFormat("SP-01 spread %d > cap %.0f%s",
                            (int)spreadPts, spreadCap, (asian ? " (asian)" : ""));
      return false;
   }

   // SP-02: 相对点差 (spread / ATR_M15)
   double atrM15 = GetATR(g_hATR, 0);
   if(atrM15 > 0 && InpMaxSpreadATRRatio > 0) {
      double pt          = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double spreadPrice = spreadPts * pt;
      double spreadATR   = spreadPrice / atrM15;
      if(spreadATR > InpMaxSpreadATRRatio) {
         reason = StringFormat("SP-02 spread/ATR=%.2f > %.2f (spread=%.2f USD, ATR=%.2f USD)",
                               spreadATR, InpMaxSpreadATRRatio, spreadPrice, atrM15);
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| 取当前 spread_ATR (诊断面板与 SP-06 动态 BE 计算共用)             |
//+------------------------------------------------------------------+
double GetSpreadATRRatio_Zeus() {
   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double atrM15  = GetATR(g_hATR, 0);
   if(atrM15 <= 0) return 0.0;
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (spreadPts * pt) / atrM15;
}

//+------------------------------------------------------------------+
//| 通用过滤: 点差 (SpreadGuard) + 时段                              |
//+------------------------------------------------------------------+
bool PassesGlobalFilters(string &reason) {
   // SP-01 + SP-02 双护甲 (V10 核心)
   if(!PassesSpreadGuard_Zeus(reason)) return false;

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
      // V10: 跨日重置日盈利达标状态 (允许新的一天重新工作)
      if(g_dailyTargetHit) {
         PrintFormat("🌅 [跨日] 重置日盈利达标状态, 恢复正常运行");
         g_dailyTargetHit = false;
         g_dailyTargetHitTime = 0;
         // 若是因日盈利暂停的, 也恢复 (但不动用户手动暂停的)
         // 这里不主动恢复 g_runPaused, 避免覆盖用户意图
      }
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

   // 3) V10: 日盈利目标达成 → 自动停止开新仓
   //    设计哲学 §0.5 第 1 条: "不做"比"做"更重要 — 黄金 70% 时间应 FREEZE
   //    赢了就跑是风控的一部分, 不是怯懦
   if(InpEnableDailyProfitTarget && !g_dailyTargetHit) {
      double profitPct = GetDailyProfitPct();
      if(profitPct >= InpDailyProfitTargetPct) {
         g_dailyTargetHit = true;
         g_dailyTargetHitTime = TimeCurrent();
         g_runPaused = true;   // 暂停开新仓 (但 OnTick 仍会管理已有持仓的 SL/TP)
         PrintFormat("🎯 [日盈利达标] 今日盈利 %.2f%% ≥ 目标 %.2f%% (%+.2f USD)",
                     profitPct, InpDailyProfitTargetPct, GetDailyProfitUSD());
         PrintFormat("    暂停开新仓, 持仓继续管理. 跨日自动恢复.");
         if(InpDailyProfitForceClose) {
            int total = CountOurPositions(-1, ENG_NONE);
            if(total > 0) {
               CloseAllOurs(StringFormat("日盈利达标 %.2f%% → 强制全平落袋", profitPct));
            }
         }
         CreateControlPanel();  // 刷新面板显示达标
      }
   }
}

//--- 是否允许新开
bool CanOpenNew(string &reason) {
   if(g_circuitActive) { reason = "circuit breaker active"; return false; }
   // V9: 新闻日历过滤 (替代 V8.2 的鞭打过滤器)
   if(IsInNewsWindow(reason)) return false;
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
//+------------------------------------------------------------------+
//| P2: 状态切换历史工具                                              |
//+------------------------------------------------------------------+
void RecordRegimeSwitch_Zeus() {
   g_regimeSwitchTimes[g_regimeSwitchIdx] = TimeCurrent();
   g_regimeSwitchIdx = (g_regimeSwitchIdx + 1) % REGIME_HIST_SIZE;
   g_regimeSwitchTotal++;
   g_lastRegimeSwitchTime = TimeCurrent();
}

// 返回最近 windowSec 秒内的状态切换次数 (REG-03 鞭打风险鉴别)
int CountRegimeSwitches_Zeus(int windowSec) {
   if(windowSec <= 0) return 0;
   datetime cutoff = TimeCurrent() - windowSec;
   int cnt = 0;
   for(int i = 0; i < REGIME_HIST_SIZE; i++) {
      if(g_regimeSwitchTimes[i] >= cutoff) cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
//| 状态机核心 (P2 加固版)                                            |
//|                                                                  |
//| HC-05 严格二元化: ADX≥InpADX_TrendMin → 趋势, 否则震荡           |
//| HC-09 状态切换必 Print 证据链 (新旧状态/ADX/ATR/防抖根数)        |
//| REG-01 启动 ≤5 根 K 必产出第一个有效状态 (g_firstRegimeProduced) |
//| REG-03 ADX 横盘 200 根切换次数 ≤5 次 (CountRegimeSwitches_Zeus)  |
//+------------------------------------------------------------------+
void UpdateMarketRegime() {
   // 仅在 M15 K 线收盘后重新评估, 减少噪音
   datetime t[];
   ArraySetAsSeries(t, true);
   if(CopyTime(_Symbol, InpRegimeTF, 0, 1, t) < 1) return;
   if(t[0] == g_lastRegimeBarTime) return;  // 本根已评估
   // 注意: 这里允许在当前未收盘 K 线上做"试探性"识别, 用 shift=0
   // 但确认仍依赖 InpRegimeMinHoldBars 防抖

   double adx     = GetADX(0);
   int    dir     = GetADX_Direction(0);
   double atr     = GetATR(g_hATR, 0);
   double atrAvg  = GetATR_Mean(g_hATR, InpATR_AvgLookback);
   double donchPct = GetDonchianWidthPct();   // P3 新增: Donchian 宽度 %

   // V10 P3+P4 状态分类 (优先级从高到低, 同 §4 文档优先级)
   //  1. S12 新闻窗口   (与 ADX/ATR 独立)
   //  2. S00 高波动     (ATR > 均值×倍数)
   //  3. S01 缺口       (跳空 ≥ ATR×1.5) [P4]
   //  4. S11 反转       (前强趋势 + ADX跌破 + DI翻转) [P4]
   //  5. S02 爆发前夜   (ATR_ratio 多根低位 + 当前反弹) [P4]
   //  6. S03/S04 强趋势 (ADX ≥ InpADX_StrongTrend)
   //  7. S05/S06 弱趋势 (InpADX_TrendMin ≤ ADX < InpADX_StrongTrend) [P4]
   //  8. S10 低波动     (ATR_ratio ≤ InpLowVol_ATRRatio) [P4]
   //  9. S07 宽幅震荡   (Donch_w ≥ Wide)
   // 10. S08 窄幅震荡   (Donch_w ≤ Narrow) [P4]
   // 11. S09 盘整       (默认兜底)
   MarketRegime newRegime;
   string       classifyReason;

   // ATR_ratio 用于多个判定 (S02/S10)
   double atrRatio = (atrAvg > 0) ? atr / atrAvg : 1.0;

   if(InpEnableP3States && g_inNewsWindow) {
      newRegime = REGIME_NEWS_WINDOW;
      classifyReason = StringFormat("命中新闻 [%s] → FREEZE", g_currentNewsTitle);
   } else if(atrAvg > 0 && atr >= atrAvg * InpATR_HighVolMult) {
      newRegime = REGIME_HIGH_VOL;
      classifyReason = StringFormat("ATR=%.5f ≥ avg×%.2f (=%.5f) → 高波动 [S00]",
                                     atr, InpATR_HighVolMult, atrAvg * InpATR_HighVolMult);
   } else if(InpEnableP4States && MathAbs(GetGapATR_Zeus()) >= InpGap_ATR_Mult) {
      // S01 缺口
      double gapVal = GetGapATR_Zeus();
      newRegime = REGIME_GAP;
      classifyReason = StringFormat("跳空 %+.2f ATR (阈值 ±%.2f) → 缺口 [S01]",
                                     gapVal, InpGap_ATR_Mult);
   } else if(InpEnableP4States && IsReversal_Zeus()) {
      // S11 反转 (要早于普通趋势判定, 否则会被新趋势盖掉)
      newRegime = REGIME_REVERSAL;
      classifyReason = StringFormat("前强趋势 + ADX(%.1f→%.1f) + DI翻转 → 反转 [S11]",
                                     GetADX(1), adx);
   } else if(InpEnableP4States && IsPreBreakout_Zeus()) {
      // S02 爆发前夜
      newRegime = REGIME_PRE_BREAKOUT;
      classifyReason = StringFormat("ATR_ratio 持续%d根低于%.2f, 当前=%.2f → 爆发前夜 [S02]",
                                     InpPreBreakout_LowBars, InpPreBreakout_LowRatio, atrRatio);
   } else if(adx >= InpADX_TrendMin) {
      bool isStrong = (adx >= InpADX_StrongTrend);
      if(dir > 0) {
         newRegime = isStrong ? REGIME_TREND_UP : REGIME_TREND_UP_WK;
         classifyReason = StringFormat("ADX=%.1f, +DI 主导 → %s [%s]",
                                        adx, isStrong ? "强趋势↑" : "弱趋势↑",
                                        isStrong ? "S03" : "S05");
      } else if(dir < 0) {
         newRegime = isStrong ? REGIME_TREND_DOWN : REGIME_TREND_DN_WK;
         classifyReason = StringFormat("ADX=%.1f, -DI 主导 → %s [%s]",
                                        adx, isStrong ? "强趋势↓" : "弱趋势↓",
                                        isStrong ? "S04" : "S06");
      } else {
         newRegime = REGIME_RANGE;
         classifyReason = StringFormat("ADX=%.1f 但 DI 平局 → 退回盘整 [S09]", adx);
      }
   } else if(InpEnableP4States && atrRatio <= InpLowVol_ATRRatio) {
      // S10 低波动 (ADX 不足 + ATR_ratio 极低)
      newRegime = REGIME_LOW_VOL;
      classifyReason = StringFormat("ADX=%.1f < %.1f, ATR_ratio=%.2f ≤ %.2f → 低波动 [S10]",
                                     adx, InpADX_TrendMin, atrRatio, InpLowVol_ATRRatio);
   } else if(InpEnableP3States && donchPct >= InpDonchWideThresholdPct) {
      newRegime = REGIME_RANGE_WIDE;
      classifyReason = StringFormat("ADX=%.1f, Donch_w=%.2f%% ≥ %.2f%% → 宽幅震荡 [S07]",
                                     adx, donchPct, InpDonchWideThresholdPct);
   } else if(InpEnableP4States && donchPct <= InpDonchNarrowFloorPct) {
      // S08 窄幅震荡 (Donch_w 极窄)
      newRegime = REGIME_RANGE_NARROW;
      classifyReason = StringFormat("ADX=%.1f, Donch_w=%.2f%% ≤ %.2f%% → 窄幅震荡 [S08]",
                                     adx, donchPct, InpDonchNarrowFloorPct);
   } else {
      newRegime = REGIME_RANGE;
      classifyReason = StringFormat("ADX=%.1f, Donch_w=%.2f%% → 盘整 [S09]",
                                     adx, donchPct);
   }

   // P2 REG-01: 标记第一次有效产出状态 (启动 ≤5 根 K 内必须达成)
   if(!g_firstRegimeProduced) {
      g_firstRegimeProduced = true;
      int barsSinceStart = (int)((TimeCurrent() - g_eaStartTime) / 60); // 粗略 K 数 (M1)
      PrintFormat("✅ [REG-01] 启动后第 %d 分钟产出首个有效状态: %s | %s",
                  barsSinceStart, RegimeText(newRegime), classifyReason);
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

      // P2 HC-09: 状态切换完整证据链 (替代原单行日志)
      datetime now = TimeCurrent();
      int gapSec = (g_lastRegimeSwitchTime > 0) ? (int)(now - g_lastRegimeSwitchTime) : -1;
      int sw1h   = CountRegimeSwitches_Zeus(3600);
      int sw24h  = CountRegimeSwitches_Zeus(86400);

      PrintFormat("🔄 [状态切换 #%d] %s → %s",
                  g_regimeSwitchTotal + 1, RegimeText(oldRegime), RegimeText(newRegime));
      PrintFormat("   ├─ 量化证据: %s", classifyReason);
      PrintFormat("   ├─ 防抖确认: 连续 %d 根 K (阈值 %d)",
                  g_regimeCandidateBars, InpRegimeMinHoldBars);
      PrintFormat("   ├─ ATR=%.5f avg=%.5f ratio=%.2f | ADX=%.1f +DI/-DI dir=%d",
                  atr, atrAvg, (atrAvg > 0 ? atr/atrAvg : 0), adx, dir);
      if(gapSec > 0) {
         PrintFormat("   ├─ 距上次切换: %d 秒 (%.1f 分钟)", gapSec, gapSec / 60.0);
      }
      PrintFormat("   └─ 切换频率: 1h=%d 次 | 24h=%d 次 %s",
                  sw1h, sw24h,
                  (sw1h >= 4 ? "⚠ 鞭打风险!" : (sw24h >= 10 ? "⚠ 高频切换" : "✓ 健康")));

      g_lastRegimeSwitchReason = classifyReason;
      g_regime = newRegime;

      RecordRegimeSwitch_Zeus();   // P2: 写入历史环形缓冲区

      // V9: 重置趋势期入场计数器 + 记录入场时间
      g_regimeEnterTime = now;
      g_entriesThisTrend = 0;

      // 状态切换时清空陈旧拒单缓存, 避免诊断板显示旧状态的拒单
      g_lastBlockReason = "";

      // V8.1 关键修复: 从震荡切到趋势/高波动时, 强平网格
      bool exitFromRange = (oldRegime == REGIME_RANGE);
      bool intoTrend = (newRegime == REGIME_TREND_UP || newRegime == REGIME_TREND_DOWN ||
                         newRegime == REGIME_TREND_UP_WK || newRegime == REGIME_TREND_DN_WK ||
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
// V9: 经济日历新闻过滤器 (借鉴 GMarket.mq5 的 IsNewsTime 实现)
// 原理: 使用 MT5 内置 CalendarValueHistory 查询当前品种货币相关的日历事件
//      命中高重要性事件 (NFP/CPI/FOMC 等) 时, 暂停开新仓
//==================================================================
// 节流: 每 60 秒最多更新一次新闻状态 (CalendarValueHistory 调用昂贵)
#define NEWS_CHECK_THROTTLE_SEC 60

void UpdateNewsStatus() {
   if(!InpEnableNewsFilter) {
      g_inNewsWindow = false;
      g_currentNewsTitle = "";
      return;
   }
   datetime now = TimeCurrent();
   if(now - g_lastNewsCheckTime < NEWS_CHECK_THROTTLE_SEC) return;
   g_lastNewsCheckTime = now;

   datetime windowStart = now - InpNewsAfterMinutes * 60;
   datetime windowEnd   = now + InpNewsBeforeMinutes * 60;

   // 重置状态, 之后扫描窗口内事件命中则置位
   g_inNewsWindow = false;
   g_currentNewsTitle = "";
   g_nextNewsTime = 0;
   g_nextNewsTitle = "";

   MqlCalendarValue values[];
   // 同时查询品种基础货币和报价货币的事件 (NULL 表示全部国家)
   if(CalendarValueHistory(values, windowStart, windowEnd, NULL, NULL) <= 0) return;

   string base   = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string profit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);

   datetime nearestFutureNews = 0;
   string   nearestFutureTitle = "";

   for(int i = 0; i < ArraySize(values); i++) {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event)) continue;

      // 重要性过滤
      bool importanceMatch = false;
      if(InpNewsHighImportance   && event.importance == CALENDAR_IMPORTANCE_HIGH)     importanceMatch = true;
      if(InpNewsMediumImportance && event.importance == CALENDAR_IMPORTANCE_MODERATE) importanceMatch = true;
      if(!importanceMatch) continue;

      // 货币匹配 (与品种相关)
      MqlCalendarCountry country;
      string eventCurrency = "";
      if(CalendarCountryById(event.country_id, country)) {
         eventCurrency = country.currency;
      }
      if(StringFind(eventCurrency, base) < 0 && StringFind(eventCurrency, profit) < 0) {
         // 黄金 XAU/USD 的报价货币是 USD, 美国数据均会命中
         continue;
      }

      // 检查事件时间是否落在 [now-after, now+before] 窗口内
      datetime eventTime = values[i].time;
      if(eventTime >= windowStart && eventTime <= windowEnd) {
         // 命中当前新闻窗口
         g_inNewsWindow = true;
         g_currentNewsTitle = event.name;
      }
      // 记录最近的未来新闻 (用于诊断显示)
      if(eventTime > now && (nearestFutureNews == 0 || eventTime < nearestFutureNews)) {
         nearestFutureNews = eventTime;
         nearestFutureTitle = event.name;
      }
   }

   if(nearestFutureNews > 0) {
      g_nextNewsTime  = nearestFutureNews;
      g_nextNewsTitle = nearestFutureTitle;
   }
}

bool IsInNewsWindow(string &reason) {
   if(!InpEnableNewsFilter) return false;
   if(g_inNewsWindow) {
      reason = StringFormat("新闻时段(%s 前后 ±%d/%d 分钟暂停)",
                            g_currentNewsTitle,
                            InpNewsBeforeMinutes, InpNewsAfterMinutes);
      return true;
   }
   return false;
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
      case REGIME_RANGE:        return "盘整 [S09]";
      case REGIME_RANGE_WIDE:   return "宽幅震荡 [S07]";
      case REGIME_RANGE_NARROW: return "窄幅震荡 [S08]";
      case REGIME_TREND_UP:     return "强趋势↑ [S03]";
      case REGIME_TREND_DOWN:   return "强趋势↓ [S04]";
      case REGIME_TREND_UP_WK:  return "弱趋势↑ [S05]";
      case REGIME_TREND_DN_WK:  return "弱趋势↓ [S06]";
      case REGIME_HIGH_VOL:     return "高波动 [S00]";
      case REGIME_LOW_VOL:      return "低波动 [S10]";
      case REGIME_GAP:          return "缺口 [S01]";
      case REGIME_PRE_BREAKOUT: return "爆发前夜 [S02]";
      case REGIME_REVERSAL:     return "反转 [S11]";
      case REGIME_NEWS_WINDOW:  return "新闻窗口 [S12]";
      case REGIME_NEUTRAL:      return "(中性-兼容)";
      default:                  return "未知";
   }
}

string RouteText(StrategyRoute r) {
   switch(r) {
      case ROUTE_FREEZE:         return "FREEZE (冻结)";
      case ROUTE_GRID_NARROW:    return "GRID_NARROW (窄网格)";
      case ROUTE_GRID_WIDE:      return "GRID_WIDE (宽网格)";
      case ROUTE_BREAKOUT:       return "BREAKOUT (突破+跟随)";
      case ROUTE_BREAKOUT_LIGHT: return "BREAKOUT_LIGHT (轻仓突破)";
      case ROUTE_TREND_FOLLOW:   return "TREND_FOLLOW (仅跟随)";
      case ROUTE_CLOSE_ONLY:     return "CLOSE_ONLY (仅平仓)";
      default:                   return "未知";
   }
}

//+------------------------------------------------------------------+
//| V10 P5/P6/Q6: 路由 → 手数系数 / 出场 Profile / 自适应追单        |
//+------------------------------------------------------------------+
string ExitProfileText(ExitProfile p) {
   switch(p) {
      case EXIT_PROFILE_A: return "A (激进锁利)";
      case EXIT_PROFILE_B: return "B (紧跟随)";
      case EXIT_PROFILE_C: return "C (网格篮)";
      default:             return "?";
   }
}

ExitProfile GetExitProfileForRoute(StrategyRoute route) {
   switch(route) {
      case ROUTE_BREAKOUT:
      case ROUTE_BREAKOUT_LIGHT:
         return EXIT_PROFILE_A;
      case ROUTE_TREND_FOLLOW:
         return EXIT_PROFILE_B;
      case ROUTE_GRID_NARROW:
      case ROUTE_GRID_WIDE:
         return EXIT_PROFILE_C;
      default:
         return EXIT_PROFILE_A;  // 存量单默认 A
   }
}

double GetRouteLotMult() {
   switch(g_currentRoute) {
      case ROUTE_BREAKOUT_LIGHT: return InpExitLight_LotMult;
      case ROUTE_TREND_FOLLOW:   return InpExitFollow_LotMult;
      default:                   return 1.0;
   }
}

bool IsRegimeBullish(MarketRegime r) {
   if(r == REGIME_TREND_UP || r == REGIME_TREND_UP_WK) return true;
   if(r == REGIME_PRE_BREAKOUT) return (GetADX_Direction(0) > 0);
   return false;
}

bool IsRegimeBearish(MarketRegime r) {
   if(r == REGIME_TREND_DOWN || r == REGIME_TREND_DN_WK) return true;
   if(r == REGIME_PRE_BREAKOUT) return (GetADX_Direction(0) < 0);
   return false;
}

// 取当前有效追单上限 (ATR 倍数)
double GetEffectiveMaxChaseATR() {
   if(!InpAdaptiveMaxChase) return InpBO_TF_MaxChaseATR;
   return g_effectiveMaxChaseATR;
}

// Q6: 每周一刷新自适应 MaxChase (§12.2)
void RefreshAdaptiveMaxChase_Zeus() {
   if(!InpAdaptiveMaxChase) {
      g_effectiveMaxChaseATR = InpBO_TF_MaxChaseATR;
      return;
   }
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dow = dt.day_of_week;  // 0=周日
   datetime weekStart = TimeCurrent() - (dow == 0 ? 6 : dow - 1) * 86400;
   weekStart -= (weekStart % 86400);
   if(g_maxChaseRefreshWeek == weekStart) return;

   double oldVal = g_effectiveMaxChaseATR;
   double atrNow = GetATR(g_hATR, 0);
   if(atrNow <= 0) {
      g_effectiveMaxChaseATR = InpBO_TF_BaseChase;
      g_maxChaseRefreshWeek = weekStart;
      return;
   }

   int barsPerWeek = 96 * 5;  // M15 约 5 个交易日
   int needBars = MathMin(barsPerWeek * InpAdaptiveLookbackWeeks, 5000);
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   int copied = CopyBuffer(g_hATR, 0, 1, needBars, atrBuf);
   if(copied < barsPerWeek) {
      g_effectiveMaxChaseATR = InpBO_TF_BaseChase;
      PrintFormat("⚠ [Q6 REG-07] ATR 数据不足 (%d 根) → 退回基线 %.2f",
                  copied, InpBO_TF_BaseChase);
      g_maxChaseRefreshWeek = weekStart;
      return;
   }

   double sorted[];
   ArrayResize(sorted, copied);
   ArrayCopy(sorted, atrBuf, 0, 0, copied);
   ArraySort(sorted);
   int idx80 = (int)MathFloor(copied * 0.80);
   if(idx80 >= copied) idx80 = copied - 1;
   double p80 = sorted[idx80];
   double raw = (p80 / atrNow) * InpBO_TF_BaseChase;
   g_effectiveMaxChaseATR = MathMax(InpMaxChase_Lower, MathMin(InpMaxChase_Upper, raw));
   g_maxChaseRefreshWeek = weekStart;

   PrintFormat("📐 [Q6] 自适应 MaxChase 刷新: %.2f → %.2f ATR (p80=%.5f cur=%.5f 样本=%d)",
               oldVal, g_effectiveMaxChaseATR, p80, atrNow, copied);
}

// P6: 按 Profile 取 BE/追踪参数 (输出到引用参数)
void GetExitParamsForProfile(ExitProfile prof,
                             double &beTrig, double &trailStart,
                             double &trailDist, double &trailStep,
                             bool &useDynBE) {
   switch(prof) {
      case EXIT_PROFILE_B:
         beTrig      = InpExitB_BE_TriggerATR;
         trailStart  = InpExitB_TrailStartATR;
         trailDist   = InpExitB_TrailDistATR;
         trailStep   = InpExitB_TrailStepATR;
         useDynBE    = true;
         break;
      case EXIT_PROFILE_A:
      default:
         beTrig      = InpBO_BE_TriggerATR;
         trailStart  = InpBO_TrailStartATR;
         trailDist   = InpBO_TrailDistATR;
         trailStep   = InpBO_TrailStepATR;
         useDynBE    = InpBO_BE_DynamicByATR;
         break;
   }
}

//+------------------------------------------------------------------+
//| V10 Q4: 网格三重激活 + 引擎许可 (文档 §6.3 / §12 Q4)              |
//+------------------------------------------------------------------+
void UpdateGridAutoAllowed_Zeus() {
   g_gridAutoAllowed = false;
   if(!InpGrid_AutoEnable) return;
   if(InpGrid_HardDisable) return;

   bool rangeState = (g_regime == REGIME_RANGE || g_regime == REGIME_RANGE_WIDE ||
                      g_regime == REGIME_RANGE_NARROW);
   if(!rangeState) return;

   double sATR = GetSpreadATRRatio_Zeus();
   double spreadCap = (g_regime == REGIME_RANGE_NARROW)
                      ? InpGrid_AutoSpreadATR_Narrow
                      : InpGrid_AutoSpreadATR;
   if(sATR <= 0 || sATR > spreadCap) return;

   if(InpEnableH1Bias && g_h1AdxVal >= InpGrid_AutoH1_ADXMax) return;

   g_gridAutoAllowed = true;
}

bool IsGridEnginePermitted() {
   if(InpGrid_HardDisable) return false;
   if(!g_runEnableGrid) return false;
   if(InpEnableGrid) return true;
   if(InpGrid_AutoEnable && g_gridAutoAllowed) return true;
   return false;
}

string GridPermitStatusText() {
   if(InpGrid_HardDisable) return "硬禁用";
   if(!g_runEnableGrid) return "面板 OFF";
   if(InpEnableGrid) return "强制常开";
   if(g_gridAutoAllowed) return "Q4 自动 ON";
   if(!InpGrid_AutoEnable) return "自动未启用";
   double sATR = GetSpreadATRRatio_Zeus();
   double cap = (g_regime == REGIME_RANGE_NARROW)
                ? InpGrid_AutoSpreadATR_Narrow : InpGrid_AutoSpreadATR;
   if(sATR > cap)
      return StringFormat("等待 spread/ATR≤%.2f (现 %.2f)", cap, sATR);
   if(InpEnableH1Bias && g_h1AdxVal >= InpGrid_AutoH1_ADXMax)
      return StringFormat("等待 H1_ADX<%.1f (现 %.1f)", InpGrid_AutoH1_ADXMax, g_h1AdxVal);
   bool rangeState = (g_regime == REGIME_RANGE || g_regime == REGIME_RANGE_WIDE ||
                      g_regime == REGIME_RANGE_NARROW);
   if(!rangeState)
      return StringFormat("等待震荡态 (现 %s)", RegimeText(g_regime));
   return "等待 Q4 条件";
}

string GridFreezeReason_Zeus(double spreadATR) {
   if(InpGrid_HardDisable) return "网格硬禁用";
   if(!g_runEnableGrid) return "面板网格 OFF";
   if(IsGridEnginePermitted()) return "";
   double cap = (g_regime == REGIME_RANGE_NARROW)
                ? InpGrid_AutoSpreadATR_Narrow : InpGrid_AutoSpreadATR;
   if(spreadATR > cap)
      return StringFormat("spread_ATR=%.2f > %.2f (HC-08)", spreadATR, cap);
   if(InpEnableH1Bias && g_h1AdxVal >= InpGrid_AutoH1_ADXMax)
      return StringFormat("H1_ADX=%.1f ≥ %.1f (大趋势酝酿)", g_h1AdxVal, InpGrid_AutoH1_ADXMax);
   return StringFormat("Q4 未满足 (%s)", GridPermitStatusText());
}

//+------------------------------------------------------------------+
//| V10 P3: 策略路由表 — 核心函数                                     |
//|                                                                  |
//| 输入: 当前状态 g_regime + 全局上下文                              |
//| 输出: 该状态应执行的子策略路由                                    |
//|                                                                  |
//| 文档对应 §5.2 状态→路由 黄金默认表                                |
//| §5.5 反例索引: 每个分支都对应一个 V8/V9 历史失败的修复            |
//|                                                                  |
//| 注: 点差护甲已经在 CanOpenNew 拦截, 这里不重复; 但 FREEZE 状态    |
//|     是状态机层的拒绝, 即使点差通过也不开新仓                       |
//+------------------------------------------------------------------+
StrategyRoute ResolveRoute_Zeus(string &routeReason) {
   if(!InpEnableP3States) {
      // V9 兼容模式: RANGE→GRID, TREND→BREAKOUT, HIGH_VOL→FREEZE
      if(g_regime == REGIME_HIGH_VOL) { routeReason = "P3 关闭, HIGH_VOL → FREEZE"; return ROUTE_FREEZE; }
      if(g_regime == REGIME_TREND_UP || g_regime == REGIME_TREND_DOWN) {
         routeReason = "P3 关闭, TREND → BREAKOUT";
         return ROUTE_BREAKOUT;
      }
      routeReason = "P3 关闭, 默认 → GRID_NARROW";
      return ROUTE_GRID_NARROW;
   }

   // V10 P3 状态→路由分发
   switch(g_regime) {
      case REGIME_NEWS_WINDOW:
         routeReason = "S12 新闻窗口";
         return ROUTE_FREEZE;

      case REGIME_HIGH_VOL:
         routeReason = "S00 高波动 → 防爆 (反例: V8.1 -97% 灾难)";
         return ROUTE_FREEZE;

      case REGIME_TREND_UP:
      case REGIME_TREND_DOWN: {
         double adx = GetADX(0);
         routeReason = StringFormat("S03/S04 强趋势 (ADX=%.1f)", adx);
         return ROUTE_BREAKOUT;
      }

      // P4: 弱趋势 → 仅趋势跟随 (无 Donchian 突破), 紧追踪
      case REGIME_TREND_UP_WK:
      case REGIME_TREND_DN_WK: {
         double adx = GetADX(0);
         routeReason = StringFormat("S05/S06 弱趋势 (ADX=%.1f) → TREND_FOLLOW (紧追踪)", adx);
         return ROUTE_TREND_FOLLOW;
      }

      // P4: 缺口 → 仅平仓
      case REGIME_GAP:
         routeReason = "S01 缺口 → CLOSE_ONLY (反例: 周一开盘惯性追单)";
         return ROUTE_CLOSE_ONLY;

      // P4: 反转 → 仅平仓 (保护既有持仓)
      case REGIME_REVERSAL:
         routeReason = "S11 反转 → CLOSE_ONLY (DI翻转+ADX跌破)";
         return ROUTE_CLOSE_ONLY;

      // P4: 爆发前夜 → 轻仓突破 (0.5×, 紧 SL, BE 提前)
      case REGIME_PRE_BREAKOUT: {
         double sATR = GetSpreadATRRatio_Zeus();
         if(sATR > 0.40) {  // 前夜期对点差要求更严
            routeReason = StringFormat("S02 爆发前夜但 spread_ATR=%.2f >0.40 → FREEZE", sATR);
            return ROUTE_FREEZE;
         }
         routeReason = "S02 爆发前夜 → BREAKOUT_LIGHT (0.5×)";
         return ROUTE_BREAKOUT_LIGHT;
      }

      // P4: 低波动 → FREEZE (利润目标小于点差摩擦)
      case REGIME_LOW_VOL:
         routeReason = "S10 低波动 → FREEZE (利润目标小于摩擦)";
         return ROUTE_FREEZE;

      // P4: 窄幅震荡 → 高点差时 FREEZE, 低点差可窄网格
      case REGIME_RANGE_NARROW: {
         double sATR = GetSpreadATRRatio_Zeus();
         if(!IsGridEnginePermitted()) {
            routeReason = StringFormat("S08 窄幅 | %s", GridFreezeReason_Zeus(sATR));
            return ROUTE_FREEZE;
         }
         routeReason = StringFormat("S08 窄幅震荡 (spread_ATR=%.2f, Q4自动)", sATR);
         return ROUTE_GRID_NARROW;
      }

      case REGIME_RANGE_WIDE: {
         double sATR = GetSpreadATRRatio_Zeus();
         if(!IsGridEnginePermitted()) {
            routeReason = StringFormat("S07 宽幅 | %s", GridFreezeReason_Zeus(sATR));
            return ROUTE_FREEZE;
         }
         routeReason = StringFormat("S07 宽幅震荡 (spread_ATR=%.2f, Q4自动)", sATR);
         return ROUTE_GRID_WIDE;
      }

      case REGIME_RANGE: {
         double sATR = GetSpreadATRRatio_Zeus();
         if(!IsGridEnginePermitted()) {
            routeReason = StringFormat("S09 盘整 | %s", GridFreezeReason_Zeus(sATR));
            return ROUTE_FREEZE;
         }
         routeReason = StringFormat("S09 盘整 (spread_ATR=%.2f, Q4自动)", sATR);
         return ROUTE_GRID_NARROW;
      }

      default:
         routeReason = "未知状态 → FREEZE 防御";
         return ROUTE_FREEZE;
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
//    V9: 仅当 InpH1BiasHardFilter=true 时才阻止入场, 否则仅作日志参考
//    type=BUY → 需要 BIAS_LONG, type=SELL → 需要 BIAS_SHORT
bool IsAlignedWithH1Bias(ENUM_ORDER_TYPE type) {
   if(!InpEnableH1Bias) return true;        // 未启用 → 不阻止
   if(!InpH1BiasHardFilter) return true;    // V9: 软参考模式 → 不阻止
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

   // P2 HC-09 + REG-03: 状态切换证据链 (面板可见)
   {
      int sw1h  = CountRegimeSwitches_Zeus(3600);
      int sw24h = CountRegimeSwitches_Zeus(86400);
      string regHealth = (sw1h >= 4) ? "⚠鞭打风险" : ((sw24h >= 10) ? "⚠高频" : "✓健康");
      if(g_lastRegimeSwitchTime > 0) {
         int sinceMin = (int)((TimeCurrent() - g_lastRegimeSwitchTime) / 60);
         s += StringFormat("【状态稳定】最近切换=%s前 (累计 %d 次) | 1h=%d / 24h=%d %s\n",
                            (sinceMin < 60 ? StringFormat("%d 分钟", sinceMin)
                                           : StringFormat("%d 小时", sinceMin / 60)),
                            g_regimeSwitchTotal, sw1h, sw24h, regHealth);
      } else {
         s += StringFormat("【状态稳定】启动后未切换 (持续 %s) | 默认状态: %s\n",
                            (TimeCurrent() - g_eaStartTime < 3600
                              ? StringFormat("%d 分钟", (int)((TimeCurrent() - g_eaStartTime) / 60))
                              : StringFormat("%d 小时", (int)((TimeCurrent() - g_eaStartTime) / 3600))),
                            RegimeText(g_regime));
      }
   }
   // V10 P3: 当前路由 + Donch_w + P6 出场 / 手数系数 / Q6 追单
   {
      double donchPct = GetDonchianWidthPct();
      ExitProfile ep = GetExitProfileForRoute(g_currentRoute);
      s += StringFormat("【路由】%s | 手数×%.2f | 出场 %s\n",
                         RouteText(g_currentRoute), GetRouteLotMult(), ExitProfileText(ep));
      s += StringFormat("       └─ %s\n", g_currentRouteReason);
      s += StringFormat("【Donch_w】%.2f%% (宽≥%.2f%% 窄≤%.2f%%)\n",
                         donchPct, InpDonchWideThresholdPct, InpDonchNarrowFloorPct);
      if(InpAdaptiveMaxChase || g_currentRoute == ROUTE_TREND_FOLLOW)
         s += StringFormat("【追单上限】MaxChase=%.2f ATR (%s)\n",
                            GetEffectiveMaxChaseATR(),
                            InpAdaptiveMaxChase ? "auto" : "固定");
   }

   s += StringFormat("【运行】Paused=%s Grid=%s (%s) BO=%s\n",
                      g_runPaused ? "是" : "否",
                      IsGridEnginePermitted() ? "允许" : "禁止",
                      GridPermitStatusText(),
                      g_runEnableBreakout ? "开" : "关");

   string reason;
   bool canOpen = CanOpenNew(reason);
   s += StringFormat("【风控】可开新仓=%s%s\n", canOpen ? "是" : "否",
                      canOpen ? "" : (" 原因: " + reason));

   // V10: 日盈亏状态
   {
      double dpPct = GetDailyProfitPct();
      double dpUSD = GetDailyProfitUSD();
      string dpStatus;
      if(g_dailyTargetHit) {
         dpStatus = StringFormat("✅ 已达标 @ %s", TimeToString(g_dailyTargetHitTime, TIME_MINUTES));
      } else if(InpEnableDailyProfitTarget) {
         dpStatus = StringFormat("🎯 目标 %.2f%% / 还差 %.2f%%",
                                  InpDailyProfitTargetPct,
                                  MathMax(0.0, InpDailyProfitTargetPct - dpPct));
      } else {
         dpStatus = "(目标未启用)";
      }
      s += StringFormat("【今日盈亏】%+.2f%% (%+.2f USD) | %s\n", dpPct, dpUSD, dpStatus);
   }

   // 趋势期入场配额 (V9: 默认放宽到 10)
   if(g_regime == REGIME_TREND_UP || g_regime == REGIME_TREND_DOWN ||
      g_regime == REGIME_TREND_UP_WK || g_regime == REGIME_TREND_DN_WK ||
      g_regime == REGIME_PRE_BREAKOUT) {
      s += StringFormat("【趋势期】入场 %d/%d 笔 | 冷启动=%s\n",
                         g_entriesThisTrend, InpMaxEntriesPerTrend,
                         TrendCooldownOK() ? "已完成" : "进行中");
   }
   // H1 大趋势偏好 (V9: 软参考)
   if(InpEnableH1Bias) {
      s += StringFormat("【H1偏好】%s%s | FastEMA=%.5f SlowEMA=%.5f ADX=%.1f (需≥%.1f)\n",
                         BiasText(g_h1Bias),
                         InpH1BiasHardFilter ? " [硬过滤]" : " [软参考]",
                         g_h1FastVal, g_h1SlowVal,
                         g_h1AdxVal, InpH1_MinADX);
   }
   // V9: 新闻日历过滤器状态
   if(InpEnableNewsFilter) {
      string newsLine;
      if(g_inNewsWindow) {
         newsLine = StringFormat("🔴 新闻时段中: %s (±%d/%d 分钟暂停)",
                                  g_currentNewsTitle,
                                  InpNewsBeforeMinutes, InpNewsAfterMinutes);
      } else if(g_nextNewsTime > 0) {
         int minToNext = (int)((g_nextNewsTime - TimeCurrent()) / 60);
         newsLine = StringFormat("✓ 正常 | 下次新闻: %s 还有 %d 分钟 (%s)",
                                  TimeToString(g_nextNewsTime, TIME_MINUTES),
                                  minToNext, g_nextNewsTitle);
      } else {
         newsLine = "✓ 正常 (近期无高重要性新闻)";
      }
      s += StringFormat("【新闻过滤】%s\n", newsLine);
   }

   // V10 点差护甲诊断 (HC-10): 必须同时显示绝对点差和 spread/ATR
   {
      long spread       = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      double pt         = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double spreadUSD  = spread * pt;
      double spreadATR  = GetSpreadATRRatio_Zeus();
      bool   asian      = IsAsianSession_Zeus();
      double sp01Cap    = asian ? InpMaxSpreadPoints * InpAsianSpreadMult : InpMaxSpreadPoints;

      string spFlag = "✓";
      if(spread > sp01Cap)                      spFlag = "✗ SP-01 超限";
      else if(spreadATR > InpMaxSpreadATRRatio) spFlag = "✗ SP-02 超限";
      else if(spreadATR > 0.5)                  spFlag = "⚠ 接近上限";

      s += StringFormat("【点差护甲】%d 点 (%.2f USD) | spread/ATR=%.2f (≤%.2f) | SP-01 上限=%.0f%s | %s\n",
                         (int)spread, spreadUSD,
                         spreadATR, InpMaxSpreadATRRatio,
                         sp01Cap, (asian ? " [亚盘×" + DoubleToString(InpAsianSpreadMult,1) + "]" : ""),
                         spFlag);
      s += StringFormat("【市场】Bid=%.5f Ask=%.5f\n",
                         SymbolInfoDouble(_Symbol, SYMBOL_BID),
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   }

   // 突破引擎诊断 (强/弱/前夜趋势)
   if(IsRegimeBullish(g_regime) || IsRegimeBearish(g_regime) ||
      g_regime == REGIME_TREND_UP_WK || g_regime == REGIME_TREND_DN_WK) {
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

      // 模式 B: 趋势跟随 (V9 双模式诊断显示)
      if(InpBO_EnableTrendFollow && g_hTF_MA != INVALID_HANDLE) {
         double maArr[];
         ArraySetAsSeries(maArr, true);
         double anchor = 0;
         if(CopyBuffer(g_hTF_MA, 0, 0, 1, maArr) >= 1) anchor = maArr[0];
         double adx = GetADX(0);
         double pullbackDist = atr * InpBO_TF_PullbackATR;
         double maxChaseDist = atr * GetEffectiveMaxChaseATR();
         s += StringFormat("【趋势跟随】锚点EMA=%.5f ADX=%.1f 回调≤%.5f 追单≤%.5f (MaxChase=%.2f ATR)\n",
                            anchor, adx, pullbackDist, maxChaseDist, GetEffectiveMaxChaseATR());
         if(IsRegimeBullish(g_regime)) {
            double diff = ask - anchor;
            bool inPullback = (anchor > 0 && diff >= 0 && diff <= pullbackDist);
            bool inChase    = (anchor > 0 && diff > pullbackDist && diff <= maxChaseDist);
            string status = inPullback ? "是[回调]" : (inChase ? "是[追单]" : "否");
            s += StringFormat("           多头入场? %s (Ask=%.5f 距锚点 %.5f)\n",
                               status, ask, diff);
         } else if(IsRegimeBearish(g_regime)) {
            double diff = anchor - bid;
            bool inPullback = (anchor > 0 && diff >= 0 && diff <= pullbackDist);
            bool inChase    = (anchor > 0 && diff > pullbackDist && diff <= maxChaseDist);
            string status = inPullback ? "是[回调]" : (inChase ? "是[追单]" : "否");
            s += StringFormat("           空头入场? %s (Bid=%.5f 距锚点 %.5f)\n",
                               status, bid, diff);
         }
      }
   }
   // 网格引擎诊断 (Q4 三重激活)
   if(g_regime == REGIME_RANGE || g_regime == REGIME_RANGE_WIDE ||
      g_regime == REGIME_RANGE_NARROW) {
      double atr = GetATR(g_hATR_Exec, 0);
      double sATR = GetSpreadATRRatio_Zeus();
      double cap = (g_regime == REGIME_RANGE_NARROW)
                   ? InpGrid_AutoSpreadATR_Narrow : InpGrid_AutoSpreadATR;
      s += StringFormat("【网格】许可=%s | Auto=%s spread/ATR=%.2f/%.2f H1_ADX=%.1f/%.1f\n",
                         IsGridEnginePermitted() ? "是" : "否",
                         g_gridAutoAllowed ? "满足" : "未满足",
                         sATR, cap, g_h1AdxVal, InpGrid_AutoH1_ADXMax);
      s += StringFormat("       ATR=%.5f 间距=%.5f 多/空 %d/%d (max %d)\n",
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

   // P2 REG-01 兜底告警: 启动 ≥5 分钟仍未产出有效状态 → 异常
   if(!g_firstRegimeProduced && (TimeCurrent() - g_eaStartTime) > 300) {
      PrintFormat("❌ [REG-01 失败] 启动 %d 分钟后仍未产出有效状态 — 检查 InpRegimeTF=%s 数据是否充足!",
                  (int)((TimeCurrent() - g_eaStartTime) / 60),
                  EnumToString(InpRegimeTF));
   }

   Print("──────── 宙斯 V10 诊断 ────────\n", BuildDiagnosticReport(),
         "────────────────────────");
   g_lastDiagTime = TimeCurrent();
}

//==================================================================
// 网格引擎 (震荡态)
//==================================================================
void ManageGridEngine() {
   if(!IsGridEnginePermitted()) return;
   // V10 P3+P4: 兼容 S09 盘整 / S07 宽幅 / S08 窄幅震荡 (路由层已确保合规)
   if(g_regime != REGIME_RANGE && g_regime != REGIME_RANGE_WIDE &&
      g_regime != REGIME_RANGE_NARROW) return;

   string reason;
   if(!CanOpenNew(reason)) { g_lastBlockReason = "网格被拒: " + reason; return; }

   double atr = GetATR(g_hATR_Exec, 0);
   if(atr <= 0) return;

   // V10 P3: 宽网格使用 1.5× 的间距系数 (S07 → ROUTE_GRID_WIDE)
   double spacingMult = (g_currentRoute == ROUTE_GRID_WIDE) ? (InpGrid_SpacingATR * 3.0)
                                                            : InpGrid_SpacingATR;
   double spacing = atr * spacingMult;
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
// 突破引擎 (V10 P5: 按路由分发)
//==================================================================
void ManageBreakoutEngine() {
   if(!g_runEnableBreakout || !InpEnableBreakout) return;

   bool allowDonchian    = false;
   bool allowTrendFollow = false;

   switch(g_currentRoute) {
      case ROUTE_BREAKOUT:
         if(g_regime != REGIME_TREND_UP && g_regime != REGIME_TREND_DOWN) return;
         allowDonchian    = InpBO_EnableDonchian;
         allowTrendFollow = InpBO_EnableTrendFollow;
         break;
      case ROUTE_BREAKOUT_LIGHT:
         if(g_regime != REGIME_PRE_BREAKOUT) return;
         allowDonchian    = InpBO_EnableDonchian;   // 前夜仅 Donchian 轻仓
         allowTrendFollow = false;
         break;
      case ROUTE_TREND_FOLLOW:
         if(g_regime != REGIME_TREND_UP_WK && g_regime != REGIME_TREND_DN_WK) return;
         allowDonchian    = false;
         allowTrendFollow = InpBO_EnableTrendFollow;
         break;
      default:
         return;
   }

   string reason;
   if(!CanOpenNew(reason)) { g_lastBlockReason = "突破被拒: " + reason; return; }

   if(!TrendCooldownOK()) {
      g_lastBlockReason = StringFormat("趋势冷启动中 (需等 %d 根 %s K线)",
                                        InpTrendColdStartBars, EnumToString(InpRegimeTF));
      return;
   }
   if(!TrendEntryQuotaOK()) {
      g_lastBlockReason = StringFormat("本趋势期已入场 %d/%d 笔, 等下一段趋势",
                                        g_entriesThisTrend, InpMaxEntriesPerTrend);
      return;
   }

   double atr = GetATR(g_hATR_Exec, 0);
   if(atr <= 0) return;

   if(allowDonchian)    TryDonchianBreakout(atr);
   if(allowTrendFollow) TryTrendFollow(atr);
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

   if(IsRegimeBullish(g_regime) && ask > hh) {
      if(!IsAlignedWithH1Bias(ORDER_TYPE_BUY)) {
         g_lastBlockReason = StringFormat("Donchian多头被H1过滤: 大趋势=%s", BiasText(g_h1Bias));
      } else if(CountOurPositions(0, ENG_BREAKOUT) < InpBO_MaxSameSide &&
         TimeCurrent() - g_lastBOOpenBuy >= InpBO_CooldownSec) {
         PrintFormat("🚀 [Donchian] 多头突破 Ask=%.5f > HH=%.5f (H1=%s)", ask, hh, BiasText(g_h1Bias));
         OpenBreakoutPosition(ORDER_TYPE_BUY, atr);
      }
   }
   if(IsRegimeBearish(g_regime) && bid < ll) {
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
// V9 重写: 趋势跟随逻辑
// 旧逻辑陷阱: "价格必须距锚点 0~PullbackATR 内才入场"
//   → 强趋势时价格早跑出区间, 永远等不到回调点
//   → 黄金 ATR=4 时, 价格瞬间能跑 15 美元远离 EMA
//
// V9 新逻辑 (两种入场方式择一, OR 关系):
//   方式 A 「回调入场」: 价格回调至锚点 ± (PullbackATR × ATR) 范围内 → 顺势开仓
//   方式 B 「顺势追单」: 价格在锚点正确侧 且 距锚点 ≤ MaxChaseATR × ATR → 顺势开仓
//                       (用于趋势已确立但价格不再回调的"追单"场景)
void TryTrendFollow(double atr) {
   if(g_hTF_MA == INVALID_HANDLE) return;
   double adx = GetADX(0);
   double minAdx = (g_currentRoute == ROUTE_TREND_FOLLOW) ? InpADX_TrendMin : InpBO_TF_MinADX;
   if(adx < minAdx) return;

   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(g_hTF_MA, 0, 0, 1, ma) < 1) return;
   double anchor = ma[0];
   if(anchor <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pullbackDist = atr * InpBO_TF_PullbackATR;
   double maxChaseDist = atr * GetEffectiveMaxChaseATR();

   if(IsRegimeBullish(g_regime)) {
      double diff = ask - anchor;
      // 方式 A: 回调入场 (价格在锚点正上方且接近)
      bool inPullback = (diff >= 0) && (diff <= pullbackDist);
      // 方式 B: 顺势追单 (价格在锚点上方, 距离不超过 MaxChase)
      bool inChase    = (diff > pullbackDist) && (diff <= maxChaseDist);
      bool entrySignal = inPullback || inChase;
      string mode = inPullback ? "回调" : (inChase ? "追单" : "");

      if(entrySignal && !IsAlignedWithH1Bias(ORDER_TYPE_BUY)) {
         g_lastBlockReason = StringFormat("趋势跟随多头被H1过滤: 大趋势=%s", BiasText(g_h1Bias));
      } else if(entrySignal &&
         CountOurPositions(0, ENG_BREAKOUT) < InpBO_MaxSameSide &&
         TimeCurrent() - g_lastTFOpenBuy >= InpBO_TF_CooldownSec) {
         PrintFormat("🌊 [趋势跟随%s] 多头入场 Ask=%.5f Anchor=%.5f diff=%.5f ADX=%.1f H1=%s",
                     mode, ask, anchor, diff, adx, BiasText(g_h1Bias));
         if(OpenBreakoutPositionTF(ORDER_TYPE_BUY, atr)) {
            g_lastTFOpenBuy = TimeCurrent();
         }
      }
   }
   if(IsRegimeBearish(g_regime)) {
      double diff = anchor - bid;  // 正数表示 bid 在 anchor 下方
      bool inPullback = (diff >= 0) && (diff <= pullbackDist);
      bool inChase    = (diff > pullbackDist) && (diff <= maxChaseDist);
      bool entrySignal = inPullback || inChase;
      string mode = inPullback ? "回调" : (inChase ? "追单" : "");

      if(entrySignal && !IsAlignedWithH1Bias(ORDER_TYPE_SELL)) {
         g_lastBlockReason = StringFormat("趋势跟随空头被H1过滤: 大趋势=%s", BiasText(g_h1Bias));
      } else if(entrySignal &&
         CountOurPositions(1, ENG_BREAKOUT) < InpBO_MaxSameSide &&
         TimeCurrent() - g_lastTFOpenSell >= InpBO_TF_CooldownSec) {
         PrintFormat("🌊 [趋势跟随%s] 空头入场 Bid=%.5f Anchor=%.5f diff=%.5f ADX=%.1f H1=%s",
                     mode, bid, anchor, diff, adx, BiasText(g_h1Bias));
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
   double lots = CalcLotByRisk(slDist) * GetRouteLotMult();
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   lots = NormalizeLots(lots);
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
   double lots = CalcLotByRisk(slDist) * GetRouteLotMult();
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   lots = NormalizeLots(lots);

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

//--- 突破单分级动态止损: 保本 → ATR 追踪 (V10 P6 按路由 Profile)
void ManageBreakoutTrailing() {
   SyncBOStates();
   double atr = GetATR(g_hATR_Exec, 0);
   if(atr <= 0) return;

   ExitProfile prof = GetExitProfileForRoute(g_currentRoute);
   double beTrig, trailStart, trailDist, trailStep;
   bool useDynBE;
   GetExitParamsForProfile(prof, beTrig, trailStart, trailDist, trailStep, useDynBE);

   for(int i = 0; i < ArraySize(g_boStates); i++) {
      ulong tk = g_boStates[i].ticket;
      if(!PositionSelectByTicket(tk)) continue;
      ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openP = PositionGetDouble(POSITION_PRICE_OPEN);
      double curP  = (pType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitDist = (pType == POSITION_TYPE_BUY) ? (curP - openP) : (openP - curP);
      if(profitDist <= 0) continue;
      double profitATR = profitDist / atr;

      double beTrigger = beTrig;
      if(useDynBE) {
         double spreadATR = GetSpreadATRRatio_Zeus();
         double dynTrigger = 2.0 * spreadATR;
         if(dynTrigger > beTrigger) beTrigger = dynTrigger;
      }
      if(!g_boStates[i].beMoved && profitATR >= beTrigger) {
         double spreadBuf = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double be = (pType == POSITION_TYPE_BUY) ? openP + spreadBuf : openP - spreadBuf;
         if(ModifyPositionSL(tk, be)) {
            g_boStates[i].beMoved = true;
            PrintFormat("🛡 [BO/%s] ticket=%I64u 保本 @ %.5f (profitATR=%.2f trig=%.2f)",
                        ExitProfileText(prof), tk, be, profitATR, beTrigger);
         }
      }
      if(profitATR >= trailStart) {
         g_boStates[i].trailActive = true;
         if(profitATR > g_boStates[i].peakProfitATR) g_boStates[i].peakProfitATR = profitATR;
         double trailDistPrice = atr * trailDist;
         double newSL = (pType == POSITION_TYPE_BUY) ? curP - trailDistPrice : curP + trailDistPrice;
         double curSL = PositionGetDouble(POSITION_SL);
         double stepDist = atr * trailStep;
         bool shouldUpdate = false;
         if(curSL == 0) shouldUpdate = true;
         else if(pType == POSITION_TYPE_BUY  && newSL - curSL >= stepDist) shouldUpdate = true;
         else if(pType == POSITION_TYPE_SELL && curSL - newSL >= stepDist) shouldUpdate = true;
         if(shouldUpdate) {
            if(ModifyPositionSL(tk, newSL)) {
               PrintFormat("📈 [BO/%s] ticket=%I64u 追踪 SL→%.5f (peak %.2f ATR)",
                           ExitProfileText(prof), tk, newSL, g_boStates[i].peakProfitATR);
            }
         }
      }
   }
}

//==================================================================
// 图表显示 (简洁版)
//==================================================================
void CreateLabel(const string name, int y, const string text, color clr, int fontSize = 10) {
   // V10 P4: 用户可统一放大字体 (默认 10 → 可调到 12+)
   int effSize = (InpDashboardFontSize > 0) ? InpDashboardFontSize : fontSize;
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 14);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   // ★ 关键修复 v3: BACK 必须在每次调用都强制覆盖 (而非只在创建时设置)
   //               否则升级版本时, 残留的旧对象 BACK 属性永远是旧值, 导致文字被背景框盖住
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, effSize);
   ObjectSetString (0, name, OBJPROP_FONT, "Consolas");
}

// V10 P4: dashboard 背景框 (深色半透明), 让浅色 K 线下也能清晰阅读
// 修复 v3: BACK=true 必须每次强制覆盖
void EnsureDashboardBg(int totalHeight) {
   if(!InpDashboardBackground) {
      ObjectDelete(0, "V8_DashBg");
      return;
   }
   string nm = "V8_DashBg";
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 8);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 14);
      ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   }
   // ★ 关键修复 v3: 强制每帧覆盖 BACK/BGCOLOR/边框颜色, 避免旧对象残留
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);                // 必须在背景层
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, C'25,25,35');
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, 460);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, totalHeight);
}

// V10 P4: 用于一次性诊断 dashboard 创建是否被调用
bool g_dashFirstCallLogged = false;

void UpdateDashboard() {
   if(!g_dashFirstCallLogged) {
      g_dashFirstCallLogged = true;
      PrintFormat("🖼 [Dashboard] 首次调用 UpdateDashboard() | InpDashboardBackground=%s | FontSize=%d",
                  InpDashboardBackground ? "ON" : "OFF", InpDashboardFontSize);
   }
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
   CreateLabel("V8_Title", y, "宙斯 V10 (Zeus) — 状态路由", clrGold, 12); y += dy + 4;
   CreateLabel("V8_Regime", y,
               StringFormat("市场: %s | ADX %.1f | ATR %.5f (avg %.5f)",
                            RegimeText(g_regime), adx, atr, atrAvg),
               clrCyan); y += dy;
   // V10 P3: 当前路由 (策略路由表输出)
   color routeClr = (g_currentRoute == ROUTE_FREEZE) ? clrOrange
                  : (g_currentRoute == ROUTE_BREAKOUT) ? clrAqua
                  : clrLightGreen;
   CreateLabel("V8_Route", y,
               StringFormat("路由: %s | 手数×%.1f | %s",
                            RouteText(g_currentRoute), GetRouteLotMult(),
                            ExitProfileText(GetExitProfileForRoute(g_currentRoute))),
               routeClr); y += dy;
   CreateLabel("V8_Acct", y,
               StringFormat("权益 $%.2f | 回撤 %.2f%% | 日亏 %.2f%%",
                            accInfo.Equity(), GetDrawdownPct(), GetDailyLossPct()),
               clrWhite); y += dy;

   // V10: 日盈利显示 (左侧面板, 紧贴权益行)
   CreateLabel("V8_DailyPnL", y, BuildDailyPnLText(), GetDailyPnLColor(), 11); y += dy;
   if(InpEnableDailyProfitTarget) {
      CreateLabel("V8_DailyTarget", y, BuildDailyTargetText(), GetDailyTargetColor(), 10); y += dy;
   } else {
      ObjectDelete(0, "V8_DailyTarget");
   }
   y += 2;  // 视觉分隔

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
      string pauseTxt = g_dailyTargetHit
         ? StringFormat("🎯 已达日盈利目标, 自动暂停 @ %s",
                        TimeToString(g_dailyTargetHitTime, TIME_MINUTES))
         : "⏸ EA 已暂停";
      CreateLabel("V8_Pause", y, pauseTxt, g_dailyTargetHit ? clrLime : clrYellow); y += dy;
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
   // V10 P4: 最后调用一次背景框 (尺寸基于 y 累计高度), 让所有标签落在深色面板上
   EnsureDashboardBg(y + 6);
}

void DeleteDashboard() {
   string names[] = {"V8_Title","V8_Regime","V8_Route","V8_Acct","V8_DailyPnL","V8_DailyTarget",
                     "V8_Grid","V8_BO","V8_Halt","V8_Pause","V8_Reason","V8_DashBg"};
   for(int i = 0; i < ArraySize(names); i++) ObjectDelete(0, names[i]);
}

//==================================================================
// MQL5 生命周期
//==================================================================
//+------------------------------------------------------------------+
//| HC-01 品种自适应: 启动时根据 _Symbol 给出建议 set                  |
//|                                                                  |
//| 不直接覆盖用户参数 (避免回测时参数失效), 而是把建议值与实参对照,   |
//| 偏差过大时打印 WARN, 让用户决定是否调整。                          |
//+------------------------------------------------------------------+
void DetectSymbolProfile_Zeus() {
   string sym = _Symbol;
   bool isGold = (StringFind(sym, "XAU") >= 0);
   bool isJPY  = (StringFind(sym, "JPY") >= 0);

   // 当前实际点差
   long curSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   PrintFormat("┌──── 宙斯 V10 品种感知 (HC-01) ────");
   PrintFormat("│ 品种: %s | 当前点差: %d 点", sym, (int)curSpread);

   // 建议值 (与文档 §0.2 / §1 对应)
   double sugMaxSpread = 50.0;     // 外汇默认
   int    sugSlippage  = 20;
   double sugSpreadATR = 0.10;

   if(isGold) {
      sugMaxSpread = 500.0;        // §0.5 HC-01: 黄金 ≥400, 我们用 500 兼顾 Mini 账户
      sugSlippage  = 50;
      sugSpreadATR = 0.35;         // SP-02 黄金阈值
      PrintFormat("│ 类型: 黄金 (高点差环境)");
   } else if(isJPY) {
      sugMaxSpread = 30.0;
      sugSlippage  = 15;
      sugSpreadATR = 0.08;
      PrintFormat("│ 类型: JPY 货币对");
   } else {
      PrintFormat("│ 类型: 外汇主流");
   }

   PrintFormat("│ 建议 MaxSpreadPoints=%.0f  当前=%.0f %s",
               sugMaxSpread, InpMaxSpreadPoints,
               (MathAbs(InpMaxSpreadPoints - sugMaxSpread) > sugMaxSpread*0.3) ? "⚠ 偏差大" : "✓");
   PrintFormat("│ 建议 SlippagePoints=%d  当前=%d %s",
               sugSlippage, InpSlippagePoints,
               (MathAbs(InpSlippagePoints - sugSlippage) > sugSlippage) ? "⚠ 偏差大" : "✓");
   PrintFormat("│ 建议 MaxSpreadATRRatio=%.2f  当前=%.2f %s",
               sugSpreadATR, InpMaxSpreadATRRatio,
               (MathAbs(InpMaxSpreadATRRatio - sugSpreadATR) > 0.1) ? "⚠ 偏差大" : "✓");

   // 黄金特殊提示: Mini 账户提醒切 Raw (Q1 决策)
   if(isGold && curSpread > 100) {
      PrintFormat("│ ⚠ 当前点差 %d > 100, 怀疑为 Standard/Mini 账户", (int)curSpread);
      PrintFormat("│   §12 Q1 决策建议切 Raw/Zero 账户以降低点差成本");
   }

   PrintFormat("└──────────────────────────────────");
}

int OnInit() {
   // 仅支持对冲账户 (本 EA 同时持多空)
   if(accInfo.MarginMode() == ACCOUNT_MARGIN_MODE_RETAIL_NETTING) {
      Print("❌ 当前为 NETTING 账户, 不支持双向持仓, EA 退出");
      return INIT_FAILED;
   }

   DetectSymbolProfile_Zeus();

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

   // P2 REG-01 初始化: 记录 EA 启动时间, 用于 ≤5 根 K 状态产出自检
   g_eaStartTime = TimeCurrent();
   g_firstRegimeProduced = false;
   for(int i = 0; i < REGIME_HIST_SIZE; i++) g_regimeSwitchTimes[i] = 0;

   ArrayResize(g_boStates, 0);
   SyncBOStates();

   // 同步运行时开关: Q4 自动模式下面板默认 ON (用户可点 OFF 完全禁用网格)
   g_runEnableGrid     = !InpGrid_HardDisable && (InpEnableGrid || InpGrid_AutoEnable);
   g_runEnableBreakout = InpEnableBreakout;
   UpdateGridAutoAllowed_Zeus();
   g_runPaused         = false;

   CreateControlPanel();

   PrintFormat("✅ 宙斯 V10 (Zeus) 启动 | Symbol=%s Period=%s RegimeTF=%s Magic=%I64d",
               _Symbol, EnumToString(_Period), EnumToString(InpRegimeTF), InpMagic);
   PrintFormat("📊 风控: 单笔风险=%.2f%% | 回撤上限=%.2f%% | 日亏上限=%.2f%%",
               InpRiskPercent, InpMaxDrawdownPct, InpDailyLossLimitPct);
   PrintFormat("🛡 SpreadGuard: %s | SP-01=%.0f pts | SP-02 spread/ATR≤%.2f | 亚盘放宽×%.1f",
               (InpEnableSpreadGuard ? "ON" : "OFF"),
               InpMaxSpreadPoints, InpMaxSpreadATRRatio, InpAsianSpreadMult);
   if(InpEnableDailyProfitTarget) {
      PrintFormat("🎯 日盈利目标: %.2f%% (达成后自动暂停%s, 跨日恢复)",
                  InpDailyProfitTargetPct,
                  InpDailyProfitForceClose ? " 并强平持仓" : "");
   }
   if(InpEnableDiagnostic) {
      Print("📋 诊断已启用, 每 ", InpDiagnosticIntervalSec,
            " 秒在无仓时输出阻塞原因. 也可点[输出诊断日志]按钮立即查看.");
   }
   PrintFormat("🔭 状态机 (P2): %s 周期 | ADX 单阈值=%.1f | 防抖 %d 根 K | 二元化 ✓",
               EnumToString(InpRegimeTF), InpADX_TrendMin, InpRegimeMinHoldBars);
   PrintFormat("🧭 路由表 (P3+P4): %s | 强趋势≥%.1f | Wide≥%.2f%% | Narrow≤%.2f%% | %d 状态 → %d 路由",
               InpEnableP3States ? "ON" : "OFF",
               InpADX_StrongTrend, InpDonchWideThresholdPct, InpDonchNarrowFloorPct,
               12, 7);
   PrintFormat("🆕 P4 状态: %s | Gap≥%.1f ATR | LowVol≤%.2f | PreBreak %d根<%.2f → 当前>%.2f",
               InpEnableP4States ? "ON (S01/S02/S05/S06/S08/S10/S11)" : "OFF",
               InpGap_ATR_Mult, InpLowVol_ATRRatio,
               InpPreBreakout_LowBars, InpPreBreakout_LowRatio, InpPreBreakout_NowRatio);
   PrintFormat("🎯 P5/P6: 出场 Profile A/B/C | 手数 LIGHT×%.1f FOLLOW×%.1f | MaxChase %s",
               InpExitLight_LotMult, InpExitFollow_LotMult,
               InpAdaptiveMaxChase ? "自适应 ON" : "固定");
   PrintFormat("📊 Q4 网格: Auto=%s | spread≤%.2f/%.2f | H1_ADX<%.1f | 强制常开=%s | 硬禁=%s",
               InpGrid_AutoEnable ? "ON" : "OFF",
               InpGrid_AutoSpreadATR, InpGrid_AutoSpreadATR_Narrow,
               InpGrid_AutoH1_ADXMax,
               InpEnableGrid ? "是" : "否", InpGrid_HardDisable ? "是" : "否");
   Print("📖 设计规格: 宙斯_开发文档.md v0.9 | P0~P6 已完成");

   g_effectiveMaxChaseATR = InpAdaptiveMaxChase ? InpBO_TF_BaseChase : InpBO_TF_MaxChaseATR;
   RefreshAdaptiveMaxChase_Zeus();

   DeleteDashboard();
   UpdateDashboard();
   ChartRedraw(0);
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
   PrintFormat("👋 宙斯 V10 (Zeus) 停止 reason=%d", reason);
}

//==================================================================
// 按钮事件处理
//==================================================================
void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam) {
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(StringFind(sparam, UI_PREFIX) != 0) return;
   string btn = StringSubstr(sparam, StringLen(UI_PREFIX));

   if(btn == "Toggle") {
      g_panelCollapsed = !g_panelCollapsed;
      PrintFormat("📐 [按钮] 面板 %s", g_panelCollapsed ? "折叠" : "展开");
   }
   else if(btn == "Pause") {
      g_runPaused = !g_runPaused;
      // 用户手动恢复 → 清除日盈利达标标记 (尊重用户意图覆盖)
      if(!g_runPaused && g_dailyTargetHit) {
         PrintFormat("⚠ [用户覆盖] 日盈利已达标但用户手动恢复, 继续交易自行承担风险");
         g_dailyTargetHit = false;
      }
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

void OnTick() {
   // 1) 账户级监督 (最高优先级)
   UpdateRiskSupervisor();

   // 2) 市场状态识别
   UpdateMarketRegime();
   UpdateTrendBias();      // H1 大趋势偏好 (V9: 软参考)
   UpdateNewsStatus();     // V9: 经济日历新闻过滤器

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

   // 6) 熔断期间不开新仓
   if(g_circuitActive) {
      g_lastBlockReason = "账户熔断中";
      UpdateDashboard();
      PrintDiagnostic(false);
      return;
   }

   // 7) V10 P3+P5: 策略路由表分发
   RefreshAdaptiveMaxChase_Zeus();
   UpdateGridAutoAllowed_Zeus();
   string routeReason;
   g_currentRoute = ResolveRoute_Zeus(routeReason);
   g_currentRouteReason = routeReason;

   switch(g_currentRoute) {
      case ROUTE_FREEZE:
         g_lastBlockReason = StringFormat("路由=FREEZE | %s", routeReason);
         break;

      case ROUTE_GRID_NARROW:
      case ROUTE_GRID_WIDE:
         ManageGridEngine();
         break;

      case ROUTE_BREAKOUT:
         ManageBreakoutEngine();
         break;

      case ROUTE_BREAKOUT_LIGHT:
         ManageBreakoutEngine();
         break;

      case ROUTE_TREND_FOLLOW:
         ManageBreakoutEngine();
         break;

      case ROUTE_CLOSE_ONLY:
         if(CountOurPositions(-1, ENG_BREAKOUT) > 0)
            CloseEngine(ENG_BREAKOUT, StringFormat("路由=CLOSE_ONLY | %s", routeReason));
         g_lastBlockReason = StringFormat("路由=CLOSE_ONLY | %s", routeReason);
         break;
   }

   // 8) 刷新看板 + 诊断
   UpdateDashboard();
   PrintDiagnostic(false);
}
//+------------------------------------------------------------------+
