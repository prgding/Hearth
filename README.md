# Hearth

macOS 菜单栏的轻量投资组合跟踪器。常驻菜单栏显示当日盈亏，点开弹窗管理多组合、多市场（A 股 / 美股）持仓，行情按市场自动路由到不同数据源并带兜底切换。

## 功能

- **多组合管理**：新建、重命名、删除组合；每个组合独立持仓清单。
- **A 股 + 美股**：A 股走腾讯，缺数据回落新浪；美股可选 Yahoo Finance 或新浪美股，互为兜底。
- **菜单栏即看**：状态栏直接显示两个钉选组合的当日盈亏（涨跌色 + 百分比）。
- **本地持久化**：基于 SwiftData，开机即用，无账号无云端。
- **可调刷新间隔**：5 / 10 / 30 / 60 秒切换。
- **行情提供方可扩展**：`QuoteProvider` 协议 + `QuoteRouter` 路由，加新数据源只动一处。

## 项目结构

```
Hearth/
├─ HearthApp.swift             # @main，挂 AppDelegate
├─ AppDelegate.swift           # NSStatusItem + NSPopover 宿主
├─ Models/                     # Portfolio / Holding / Market / Quote（SwiftData）
├─ Storage/                    # ModelContainer 构建
├─ Quotes/                     # QuoteProvider 协议 + 腾讯/新浪/Yahoo 实现 + Router
├─ ViewModels/                 # PortfolioStore、QuoteRefresher
├─ Views/                      # 菜单栏标签、弹窗、表单、设置
└─ Theme/                      # 涨跌配色
```

行情数据流：`QuoteRefresher`（定时器）→ `PortfolioStore.refresh` → `QuoteRouter.fetch` → 按市场拆分到各 `QuoteProvider` → 合并写回 store → SwiftUI 重绘。

## 运行

要求：macOS 14+，Xcode 15+（用到 SwiftData 与 `@Observable`）。

```bash
open Hearth.xcodeproj
```

在 Xcode 里选 `Hearth` scheme 跑即可。首次启动会在菜单栏出现一个空标签，点开新建组合并添加持仓。

## 数据源说明

| 市场 | 主 | 备 |
| --- | --- | --- |
| A 股 | 腾讯 | 新浪 |
| 美股 | Yahoo（可在设置切到新浪）| 另一方 |

所有请求都是匿名、只读、走 HTTPS，没有 API key。

## 状态

个人项目，按需迭代。代码结构稳定，但 UI 文案是中文，没有做本地化。
