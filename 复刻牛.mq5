//+------------------------------------------------------------------+
//|                                        太极·爱牛 Ultra V7.mq5    |
//|                                  根据参数面板复刻的多引擎策略      |
//+------------------------------------------------------------------+
#property copyright "太极·爱牛 Ultra V7"
#property version   "1.00"
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
input double MaxRiskPercent = 95.0;        // 极限追击比例 (%)

//+------------------------------------------------------------------+
//| === [B] 纯物理空间观察雷达 (0惯后防爆盾) ===                        |
//+------------------------------------------------------------------+
input group "=== [B] 纯物理空间观察雷达 (0惯后防爆盾) ==="
input double M1_Candle_Range_Limit = 999.0; // M1单根K线轻量标幅判定 (绝巧计差基金)
input int Range_Freeze_Minutes = 15;        // K线振幅超限后冻结开仓时长(分钟)
input int ADX_Period = 14;                  // 宏观趋势强度(ADX)
input int ATR_Period = 14;                  // 宏观波动基(ATR)
input int Tick_Speed_Limit = 25;            // 备用 Tick 狂暴滤速 (Tick/秒)

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
input double Qinglong_Structure_SL = 0.2;   // 结构止损线缓冲点差(美金)
input double Qinglong_Hard_SL = 5.0;        // 备用物理硬止损(美金)

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
};
QinglongPosition qinglongPos;

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
int trendDirection = 0;             // 趋势方向：1=只开多，-1=只开空，0=双向

// 指标句柄
int handleADX;
int handleATR;
int handleM5_MA;
int handleM5_MACD;

// 账户初始状态
double initialEquity = 0;

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
   
   Print("✅ 太极·夔牛 Ultra V7 初始化成功");
   Print("📊 初始权益: $", DoubleToString(initialEquity, 2));
   Print("🔧 毒蛇网格: ", Enable_DuShe_Grid ? "开启" : "关闭");
   Print("🔧 牛龟突击: ", Enable_NiuGui_Squad ? "开启" : "关闭");
   Print("🔧 青龙波段: ", Enable_QingLong_Squad ? "开启" : "关闭");
   
   if(Enable_Trend_Filter) {
      Print("🎯 趋势过滤器: 已启用 (MA", M5_MA_Period, " + MACD)");
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
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
   ObjectDelete(0, "EA_Protocol");
   
   IndicatorRelease(handleADX);
   IndicatorRelease(handleATR);
   IndicatorRelease(handleM5_MA);
   IndicatorRelease(handleM5_MACD);
   Print("太极·夔牛 Ultra V7 已停止");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // 更新持仓信息
   UpdatePositions();
   
   // 检查趋势过滤器（M5 K线收盘前1秒）
   if(Enable_Trend_Filter) {
      CheckTrendFilter();
   }
   
   // 检查K线振幅防爆盾
   CheckCandleRangeShield();
   
   // 检查沙盒状态
   CheckSandboxStatus();
   
   // 主引擎：毒蛇网格
   if(Enable_DuShe_Grid) {
      ManageGridSystem();
   }
   
   // 辅引擎：牛龟突击（朱雀）
   if(Enable_NiuGui_Squad) {
      ManageZhuqueEngine();
   }
   
   // 辅引擎：青龙波段
   if(Enable_QingLong_Squad) {
      ManageQinglongEngine();
   }
   
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
            if(positionInfo.Symbol() == _Symbol && 
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
   CreateLabel("EA_Title", 10, yPos, "太极·夔牛 Ultra V7 智能交易系统", clrGold, 14);
   yPos += lineHeight + 5;
   
   // 环境雷达 - 青色
   CreateLabel("EA_Env", 10, yPos, 
               StringFormat("环境雷达: %s | ADX(%.1f) ATR(%.2f)", _Symbol, adx[0], atr[0] / _Point),
               clrCyan, 10);
   yPos += lineHeight + 3;
   
   // 分隔线
   CreateLabel("EA_Line1", 10, yPos, "━━━━━━━━━━━━━━━━━━━━━━━━", clrDimGray, 10);
   yPos += lineHeight;
   
   // 资金中枢 - 白色
   CreateLabel("EA_Money", 10, yPos,
               StringFormat("资金中枢: 净值 $%.2f | 可用 $%.2f", 
                           accountInfo.Equity(), accountInfo.FreeMargin()),
               clrWhite, 10);
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
                           buyGridCount, Grid_Max_Levels, buySign, buyGridProfit, buyTrailing),
               buyColor, 10);
   yPos += lineHeight;
   
   // 主网格(空) - 绿色或红色
   color sellColor = (sellGridProfit >= 0) ? clrLime : clrRed;
   string sellSign = (sellGridProfit >= 0) ? "+" : "";
   string sellTrailing = (sellGridProfit > 5.0) ? " [🔒追踪]" : "";
   CreateLabel("EA_GridSell", 10, yPos,
               StringFormat("[主]网格(空): %d/%d | 盈 %s$%.2f%s", 
                           sellGridCount, Grid_Max_Levels, sellSign, sellGridProfit, sellTrailing),
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
   
   // 更新青龙持仓
   if(latestQinglongTicket > 0) {
      if(qinglongPos.ticket != latestQinglongTicket) {
         qinglongPos.ticket = latestQinglongTicket;
         qinglongPos.openPrice = latestQinglongOpenPrice;
         qinglongPos.type = latestQinglongType;
      }
      CheckQinglongStop();
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
   // 获取M5 K线数据
   MqlRates m5Rates[];
   ArraySetAsSeries(m5Rates, true);
   if(CopyRates(_Symbol, PERIOD_M5, 0, 1, m5Rates) < 1) return;
   
   datetime currentM5BarTime = m5Rates[0].time;
   
   // 如果是新的M5 K线，重置检查标记
   static bool hasCheckedThisBar = false;
   if(currentM5BarTime != lastM5BarTime) {
      lastM5BarTime = currentM5BarTime;
      hasCheckedThisBar = false;  // 新K线，允许检查
   }
   
   // 如果本K线已经检查过，直接返回
   if(hasCheckedThisBar) return;
   
   // 计算距离K线收盘的时间（秒）
   datetime currentTime = TimeCurrent();
   datetime nextM5BarTime = currentM5BarTime + 5 * 60; // M5 = 5分钟 = 300秒
   int secondsToClose = (int)(nextM5BarTime - currentTime);
   
   // 只在K线收盘前1秒检查
   if(secondsToClose != 1) return;
   
   // 标记本K线已检查
   hasCheckedThisBar = true;
   
   // 获取MA数据（需要2根K线：当前和前一根）
   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(handleM5_MA, 0, 0, 2, ma) < 2) return;
   
   // 计算MA斜率
   double maSlope = ma[0] - ma[1];
   
   // 获取MACD数据
   double macdMain[], macdSignal[];
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   if(CopyBuffer(handleM5_MACD, 0, 0, 2, macdMain) < 2) return;    // MACD主线
   if(CopyBuffer(handleM5_MACD, 1, 0, 2, macdSignal) < 2) return;  // 信号线
   
   // 判断MACD金叉/死叉
   bool macdGoldenCross = (macdMain[1] <= macdSignal[1]) && (macdMain[0] > macdSignal[0]); // 金叉
   bool macdDeadCross = (macdMain[1] >= macdSignal[1]) && (macdMain[0] < macdSignal[0]);   // 死叉
   
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
   CheckBatchCloseConditions();
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
      if(direction == 0) {
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
void CheckGridTrailingStop(int index) {
   return;
}

//+------------------------------------------------------------------+
//| 管理朱雀引擎                                                       |
//+------------------------------------------------------------------+
void ManageZhuqueEngine() {
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
   if(CopyRates(_Symbol, PERIOD_M1, 0, 1, rates) < 1) return;
   if(lastZhuqueSignalBarTime == rates[0].time) {
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
         lastZhuqueSignalBarTime = rates[0].time;
      }
   }
}

//+------------------------------------------------------------------+
//| 检测朱雀突破信号                                                   |
//+------------------------------------------------------------------+
int DetectZhuqueSignal() {
   // 获取ATR
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 3, atr) < 3) return 0;
   
   // 获取K线数据
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M1, 0, 5, rates) < 5) return 0;
   
   // 当前K线实体
   double currentBody = MathAbs(rates[0].close - rates[0].open);
   
   // 前3根K线最高价和最低价
   double highestHigh = rates[1].high;
   double lowestLow = rates[1].low;
   for(int i = 2; i <= 3; i++) {
      if(rates[i].high > highestHigh) highestHigh = rates[i].high;
      if(rates[i].low < lowestLow) lowestLow = rates[i].low;
   }
   
   // 做多信号
   if(currentBody > atr[0] * 0.5 &&           // 饱满实体
      rates[0].close > rates[0].open &&       // 阳线
      rates[0].close > highestHigh) {         // 突破前高
      return 1; // BUY
   }
   
   // 做空信号
   if(currentBody > atr[0] * 0.5 &&           // 饱满实体
      rates[0].close < rates[0].open &&       // 阴线
      rates[0].close < lowestLow) {           // 突破前低
      return -1; // SELL
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
   if(!CheckRiskLimit(Zhuque_Base_Lot, orderType)) return false;
   
   double price = (signal > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDistance = CashToPriceDistance(Zhuque_Hard_SL, Zhuque_Base_Lot);
   double sl = (signal > 0) ? price - slDistance : price + slDistance;
   sl = NormalizeDouble(sl, _Digits);

   string comment = (signal > 0) ? "ZhuQue_B" : "ZhuQue_S";
   if(trade.PositionOpen(_Symbol, orderType, Zhuque_Base_Lot, price, sl, 0, comment)) {
      zhuquePos.ticket = FindLatestPositionTicketByComment(comment);
      zhuquePos.openPrice = price;
      zhuquePos.maxProfit = 0;
      zhuquePos.type = (signal > 0) ? 0 : 1;
      lastZhuqueSignalTime = TimeCurrent();
      
      string direction = (signal > 0) ? "做多" : "做空";
      Print("🦅 [朱雀出击] 饱满真突破！", direction, "！止损设于动能原点防线。");
      return true;
   }
   return false;
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
      Print("🦅 [朱雀撤退] 触发硬止损: $", DoubleToString(currentProfit, 2));
      return;
   }
   
   // 检查移动止盈
   if(zhuquePos.maxProfit >= Zhuque_TP_Trigger) {
      double drawback = zhuquePos.maxProfit - currentProfit;
      double drawbackRatio = drawback / zhuquePos.maxProfit;
      
      if(drawbackRatio >= Zhuque_Drawback_Ratio) {
         CloseTrackedPosition(zhuquePos.ticket);
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
         if(positionInfo.Symbol() == _Symbol && 
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
   if(adx[0] > ADX_Period && currentPrice > highest) {
      return 1; // BUY
   }
   
   // 下跌趋势：ADX强势 + 跌破支撑
   if(adx[0] > ADX_Period && currentPrice < lowest) {
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
   if(!CheckRiskLimit(Qinglong_Base_Lot, orderType)) return false;
   
   double price = (signal > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0;
   double slDistance = CashToPriceDistance(Qinglong_Hard_SL, Qinglong_Base_Lot);
   sl = (signal > 0) ? price - slDistance : price + slDistance;
   sl = NormalizeDouble(sl, _Digits);

   string comment = (signal > 0) ? "QingLong_B" : "QingLong_S";
   if(trade.PositionOpen(_Symbol, orderType, Qinglong_Base_Lot, price, sl, 0, comment)) {
      qinglongPos.ticket = FindLatestPositionTicketByComment(comment);
      qinglongPos.openPrice = price;
      qinglongPos.addTimes = 0;
      qinglongPos.type = (signal > 0) ? 0 : 1;
      
      string direction = (signal > 0) ? "做多" : "做空";
      Print("🐉 [青龙波段] 宏观趋势确认！", direction, "！");
      return true;
   }
   return false;
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
   int signal = DetectQinglongSignal();
   if(signal == (qinglongPos.type == 0 ? 1 : -1)) {
      // 趋势方向一致，加仓
      double price = (qinglongPos.type == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                                                SymbolInfoDouble(_Symbol, SYMBOL_BID);
      ENUM_ORDER_TYPE orderType = (qinglongPos.type == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!CheckRiskLimit(Qinglong_Base_Lot, orderType)) return;
      
      if(trade.PositionOpen(_Symbol, orderType, Qinglong_Base_Lot, price, 0, 0, "QingLong_Add")) {
         qinglongPos.addTimes++;
         lastQinglongAddBarTime = currentBarTime;
         lastQinglongActionTime = TimeCurrent();
         Print("🐉 [青龙加仓] 第", qinglongPos.addTimes, "次加仓");
      }
   }
}

//+------------------------------------------------------------------+
//| 检查青龙止损                                                       |
//+------------------------------------------------------------------+
void CheckQinglongStop() {
   if(!PositionSelectByTicket(qinglongPos.ticket)) return;
   
   double currentProfit = PositionGetDouble(POSITION_PROFIT);
   
   // 硬止损
   if(currentProfit <= -Qinglong_Hard_SL) {
      BatchCloseByCommentPrefix("QingLong");
      Print("🐉 [青龙止损] 触发硬止损: $", DoubleToString(currentProfit, 2));
      return;
   }
   
   // 结构破位止损（简化：反向信号）
   int signal = DetectQinglongSignal();
   if(signal == (qinglongPos.type == 0 ? -1 : 1)) {
      BatchCloseByCommentPrefix("QingLong");
      Print("🐉 [青龙止损] 结构破位");
   }
}

//+------------------------------------------------------------------+
//| 检查资金风险限制                                                   |
//+------------------------------------------------------------------+
bool CheckRiskLimit(double lots, ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY) {
   double balance = accountInfo.Balance();
   double margin = accountInfo.Margin();
   double freeMargin = accountInfo.FreeMargin();
   
   // 计算新订单所需保证金
   double requiredMargin = 0;
   double marginPrice = (orderType == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(!OrderCalcMargin(orderType, _Symbol, lots, marginPrice, requiredMargin)) {
      return false;
   }
   
   // 检查是否超过极限追击比例
   double maxAllowedMargin = balance * MaxRiskPercent / 100.0;
   if(margin + requiredMargin > maxAllowedMargin) {
      Print("⚠️ 资金风险限制：已使用", DoubleToString(margin, 2), 
            " 新增", DoubleToString(requiredMargin, 2),
            " 超过限制", DoubleToString(maxAllowedMargin, 2));
      return false;
   }
   
   // 检查可用保证金
   if(requiredMargin > freeMargin) {
      Print("⚠️ 可用保证金不足");
      return false;
   }
   
   return true;
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
   return NormalizeDouble(BaseLotSize * MathPow(Grid_Multiplier, level - 1), 2);
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

   int existingCount = CountGridOrdersByDirection(direction);
   if(existingCount >= Grid_Max_Levels) {
      return false;
   }

   int newLevel = existingCount + 1;
   double lots = GetGridLotByLevel(newLevel);
   ENUM_ORDER_TYPE orderType = (direction == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!CheckRiskLimit(lots, orderType)) {
      return false;
   }

   double price = (direction == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string comment = GetGridComment(direction, isSniper, existingCount);

   if(!trade.PositionOpen(_Symbol, orderType, lots, price, 0, 0, comment)) {
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
   
   Print("🐂 [夔牛布阵] ", role, " ", directionText, " ", comment, 
         " | 手数:", DoubleToString(lots, 2),
         " | 价格:", DoubleToString(price, _Digits),
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

   // 沙盒狙击使用独立层级，从第1层开始
   double lots = GetGridLotByLevel(sniperLevel);
   ENUM_ORDER_TYPE orderType = (direction == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!CheckRiskLimit(lots, orderType)) {
      return false;
   }

   double price = (direction == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string comment = (direction == 0) ? "Grid_B_Sniper" : "Grid_S_Sniper";

   if(!trade.PositionOpen(_Symbol, orderType, lots, price, 0, 0, comment)) {
      return false;
   }

   lastGridOrderTime = currentTime;
   if(direction == 0) {
      lastGridBuyOrderTime = currentTime;
   } else {
      lastGridSellOrderTime = currentTime;
   }
   
   string directionText = (direction == 0) ? "多单" : "空单";
   Print("🐂 [夔牛布阵] 沙盒狙击 ", directionText, " ", comment, 
         " | 手数:", DoubleToString(lots, 2),
         " | 价格:", DoubleToString(price, _Digits),
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
         if(positionInfo.Symbol() == _Symbol && positionInfo.Comment() == comment) {
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
   if(trade.PositionClose(ticket)) {
      return true;
   }

   uint retcode = trade.ResultRetcode();
   if(retcode != TRADE_RETCODE_CLOSE_ORDER_EXIST) {
      UnmarkClosingTicket(ticket);
   }
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
         if(positionInfo.Symbol() == _Symbol && StringFind(positionInfo.Comment(), prefix) == 0) {
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
//| 检查批量平仓条件                                                   |
//+------------------------------------------------------------------+
void CheckBatchCloseConditions() {
   // 统计多空单数量和盈利
   int buyCount = 0, sellCount = 0;
   double buyProfit = 0, sellProfit = 0;
   
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(!PositionSelectByTicket(gridOrders[i].ticket)) continue;
      
      double profit = PositionGetDouble(POSITION_PROFIT);
      if(gridOrders[i].type == 0) { // BUY
         buyCount++;
         buyProfit += profit;
      } else { // SELL
         sellCount++;
         sellProfit += profit;
      }
   }
   
   // 削峰自救：当同方向订单数≥阈值时，平掉首尾2个订单
   if(buyCount >= Grid_Profit_Orders_Threshold) {
      CheckPeakCutForDirection(0); // 多单削峰
   }
   
   if(sellCount >= Grid_Profit_Orders_Threshold) {
      CheckPeakCutForDirection(1); // 空单削峰
   }
}

//+------------------------------------------------------------------+
//| 检查指定方向的削峰自救                                             |
//+------------------------------------------------------------------+
void CheckPeakCutForDirection(int direction) {
   // 找到首尾订单（最早和最晚开仓的）
   ulong firstTicket = 0, lastTicket = 0;
   datetime firstTime = 0, lastTime = 0;
   double firstProfit = 0, lastProfit = 0;
   
   for(int i = 0; i < ArraySize(gridOrders); i++) {
      if(gridOrders[i].type != direction) continue;
      if(!PositionSelectByTicket(gridOrders[i].ticket)) continue;
      
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double profit = PositionGetDouble(POSITION_PROFIT);
      
      // 找最早的订单
      if(firstTime == 0 || openTime < firstTime) {
         firstTime = openTime;
         firstTicket = gridOrders[i].ticket;
         firstProfit = profit;
      }
      
      // 找最晚的订单
      if(lastTime == 0 || openTime > lastTime) {
         lastTime = openTime;
         lastTicket = gridOrders[i].ticket;
         lastProfit = profit;
      }
   }
   
   // 如果首尾是同一个订单，不处理
   if(firstTicket == 0 || lastTicket == 0 || firstTicket == lastTicket) return;
   
   // 计算首尾2个订单的净盈利
   double netProfit = firstProfit + lastProfit;
   
   // 如果净盈利≥目标利润，平掉这2个订单
   if(netProfit >= Grid_Hedge_Target_Profit) {
      if(CloseTrackedPosition(firstTicket) && CloseTrackedPosition(lastTicket)) {
         string directionText = (direction == 0) ? "多单" : "空单";
         Print("✂️ [削峰自救] ", directionText, " 首单盈利$", DoubleToString(firstProfit, 2),
               " 尾单盈利$", DoubleToString(lastProfit, 2),
               " 净盈利$", DoubleToString(netProfit, 2), " 平掉首尾2单");
      }
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
