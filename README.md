# Hearth

macOS 菜单栏的轻量投资组合跟踪器。常驻菜单栏显示当日盈亏，点开弹窗管理多组合、多市场（A 股 / 美股）持仓，行情按市场自动路由到不同数据源并带兜底切换。

## 功能

- **多组合管理**：新建、重命名、删除组合；每个组合独立持仓清单。
- **持仓编辑**：右键持仓行 → 编辑，可改股数和成本价。
- **A 股 + 美股**：A 股走腾讯，缺数据回落新浪；美股可选 Yahoo Finance 或新浪美股，互为兜底。
- **菜单栏即看**：状态栏直接显示两行钉选组合的当日盈亏金额。文字走 template image，跟随系统菜单栏 active/inactive 自动 tint 和变淡，跟原生时钟/电池一致。
- **本地持久化**：组合和持仓走 SwiftData；行情缓存进 UserDefaults，重启后立即显示上次拉取的数字。启动时强制再拉一次（绕过开盘时间过滤），确保收盘后任何时候打开看到的都是当天收盘价。
- **可调刷新间隔**：5 / 10 / 30 / 60 秒切换。
- **行情提供方可扩展**：`QuoteProvider` 协议 + `QuoteRouter` 路由，加新数据源只动一处。

## 安装

> **仅支持 Apple Silicon**。Intel Mac 走方式二自行编译，并把构建 architecture 改成 universal。

### 方式一：下载 .app

去 [Releases](https://github.com/prgding/Hearth/releases) 下载最新 `Hearth.app.zip`，解压把 `Hearth.app` 拖进 `/Applications`。

因为没经过 Apple notarization，首次打开会被 Gatekeeper 拦截（提示「无法验证开发者」）。任选一种方式绕过：

- **系统设置**：双击触发拦截后，打开「系统设置 → 隐私与安全性」，拉到底点「仍要打开」
- **命令行一次性清掉 quarantine 属性**：
  ```bash
  xattr -d com.apple.quarantine /Applications/Hearth.app
  ```

### 方式二：从源码编译

要求：macOS 26.5+，对应版本的 Xcode。

```bash
git clone https://github.com/prgding/Hearth.git
cd Hearth
open Hearth.xcodeproj
```

Xcode 里选 `Hearth` scheme，⌘R 直接跑；要出 Release 包：Product → Archive。

首次启动菜单栏会出现一个图表图标，点开新建组合并添加持仓。

## 项目结构

```
Hearth/
├─ HearthApp.swift             # @main，挂 AppDelegate
├─ AppDelegate.swift           # NSStatusItem + NSPopover 宿主、全局鼠标 monitor
├─ Models/                     # Portfolio / Holding / Market / Quote（SwiftData）
├─ Storage/                    # ModelContainer 构建
├─ Quotes/                     # QuoteProvider 协议 + 腾讯/新浪/Yahoo 实现 + Router
├─ ViewModels/                 # PortfolioStore（含 quote 缓存）、QuoteRefresher
├─ Views/                      # MenuBarRenderer、弹窗、表单、设置
└─ Theme/                      # PnLFormatter（金额/百分比格式化）
```

行情数据流：`QuoteRefresher`（定时器，首次 tick 强制拉取）→ `PortfolioStore.refresh` → `QuoteRouter.fetch` → 按市场拆分到各 `QuoteProvider` → 合并写回 store + 缓存到 UserDefaults → `MenuBarRenderer` 监听变化重绘 template image。

## 数据源说明

| 市场 | 主 | 备 |
| --- | --- | --- |
| A 股 | 腾讯 | 新浪 |
| 美股 | Yahoo（可在设置切到新浪）| 另一方 |

所有请求都是匿名、只读、走 HTTPS，没有 API key。

## 状态

个人项目，按需迭代。代码结构稳定，但 UI 文案是中文，没有做本地化。
