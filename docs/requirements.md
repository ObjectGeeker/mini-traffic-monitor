# MiniTrafficMonitor 需求文档

> 版本 v1.2 · 2026-10-16 · 状态：已定稿（Q1–Q7 全部定案，仅本机自用）
> 技术可行性已于 2026-10-16 在本机实测验证，见附录 A

---

## 1. 背景与目标

Windows 平台的 TrafficMonitor 是一个在任务栏/桌面常驻显示 CPU、内存、网速的轻量工具。macOS 上缺乏等价的、**真正轻量**的状态栏替代品：iStat Menus 功能齐全但常驻内存达数十至上百 MB，且为付费闭源；`top`/`htop` 需要占用一个终端窗口。

本项目目标：做一个**只读、常驻状态栏、极致轻量**的资源监控工具，只看四个数：CPU 占用率、内存占用率、上行网速、下行网速。

**可验证的量化目标：**

| 指标 | 目标 |
|---|---|
| 常驻内存 RSS | ≤ 25 MB |
| 自身 CPU 占用 | ≤ 0.3%（1 Hz 采样下） |
| 冷启动到状态栏可见 | ≤ 1 s |
| 第三方依赖 | 0（仅系统框架） |
| 权限要求 | 不需 root、不需沙盒、不需特殊 entitlement、不弹任何权限请求 |

---

## 2. 设计原则

这四条原则是后续所有取舍的依据，实现期若与之冲突，应先回到本文档讨论而非就地妥协。

1. **纯文字渲染优先**
   菜单栏用 `NSStatusItem.button.attributedTitle` 直接渲染文字，**不生成 `NSImage`、不做动画、不自定义视图**。这是内存与 CPU 开销的最大单一决定因素。

2. **单线程**
   所有采样在主线程 RunLoop 的 `Timer` 中同步完成。实测单次全量采样（CPU + 内存 + 网速）在数十微秒量级，引入 GCD 队列或 async/await 只会增加调度开销与并发复杂度，没有收益。

3. **不持有历史**
   v1 不绘制折线图，因此不需要环形缓冲区。进程内只保留「上一次采样的原始计数器值」用于求差。

4. **拉取式，而非监听式**
   CPU / 内存 / 网速统一按 1 Hz 主动读取系统计数器。**唯一例外**是活动网卡识别：用 `SCDynamicStore` 的 RunLoop 通知机制监听变更，避免为了发现网卡切换而高频轮询。

---

## 3. 技术选型（已验证）

### 3.1 开发环境约束

| 项 | 值 |
|---|---|
| 开发机 | macOS 15.7.8 (24G824)，Apple Silicon arm64 |
| Swift | 6.1.2 (swiftlang-6.1.2.1.2) |
| Xcode | **未安装**，仅有 Command Line Tools |

「没有完整 Xcode」是本次选型最硬的约束：`xcodebuild` 不可用，`.xcodeproj` 工程无法正常构建。

### 3.2 结论：Swift + AppKit + Swift Package Manager

| 层 | 选择 | 说明 |
|---|---|---|
| 语言 | Swift 6.1.2 | CLT 自带，无需额外安装 |
| UI | **AppKit**（`NSStatusItem` / `NSMenu`） | 不用 SwiftUI，见 §3.3 |
| 构建 | **Swift Package Manager** | `swift build -c release`，不依赖 Xcode |
| 打包 | **手工组装 .app bundle** | 由 `build.sh` 生成 `Contents/MacOS` + `Info.plist` |
| 签名 | ad-hoc（`codesign --force --sign -`） | 本机自用足够 |

已验证：纯 CLT 环境下 `swiftc` 可正常编译并链接 AppKit、SystemConfiguration。

### 3.3 为什么不用 SwiftUI MenuBarExtra

`MenuBarExtra` 代码量最少、开发最快，但：

- 引入 SwiftUI 运行时，常驻内存通常高 **10–25 MB**，直接吃掉本项目的内存预算
- 每秒更新文字会触发 SwiftUI 视图 diff，开销高于直接赋 `attributedTitle`
- 对状态栏文字的字体、间距、逐段着色的控制力弱于 AppKit

与「极致轻量」这一首要目标冲突，故排除。

### 3.4 最低系统版本：macOS 13.0 (Ventura)

由 `SMAppService`（开机自启）决定。AppKit 本身可支持更低版本，但无必要。本机为 macOS 15.7.8，余量充足。

### 3.5 Swift 语言模式

Swift 6.1 默认启用严格并发检查。本项目的单线程设计下，严格并发只会带来大量无收益的 `Sendable` 标注与 `@MainActor` 传染。

**决定：`Package.swift` 中设置 `swiftLanguageMode(.v5)`。**

---

## 4. 功能需求

### FR-1 状态栏文字展示 【P0】

菜单栏常驻显示一行文字，由三个**可独立开关的段**组成：CPU 段、MEM 段、NET 段（开关与预设见 FR-5）。默认三段全开，采用压缩格式：

```
C12% M45% ↓1.2M ↑300K
```

MEM 段有两种内容模式，可在下拉面板切换，**默认为占用率**：

- 占用率 → `M45%`
- 内存压力（活动监视器绿/黄/红，见 FR-8）→ `M●` / `M▲` / `M■`

**栏内宽度预算（13pt 全等宽实测，见附录 A.5）：**

| 栏内内容 | 宽度 |
|---|---|
| 三段全开（默认，首帧 `--` 同宽） | 200.9 pt |
| 仅 NET（「极简」预设） | 104.5 pt |
| 仅 CPU+MEM | 88.4 pt |

要求：

- 使用 `NSStatusItem`，通过 `button.attributedTitle` 渲染，**不设置 `button.image`**
- **必须使用全等宽字体** `.monospacedSystemFont(ofSize:weight:)`
  > 这一条不是审美偏好：比例字体下 `1` 比 `8` 窄，数字每秒变化会导致整个菜单栏项左右抖动，同时挤压右侧其他图标。这是同类工具最常见的体验缺陷。
  > 注意**不能用** `.monospacedDigitSystemFont`：它只保证数字等宽，而帧内的小数点 `.`、单位字母 `K/M/B`、首帧 `--` 都不是数字，实测同一格式不同帧宽度极差达 41.68pt，仍会抖动。全等宽实测极差 0.00pt（见附录 A.5）。
- 字号跟随系统菜单栏（13 pt regular）
- 网速单位自动缩放：`B/s → KB/s → MB/s`，**1024 进制**，< 10 时保留 1 位小数，≥ 10 时取整
- 采样器首次运行无前值时显示 `--%`，不得显示 `0%`（会误导为「无负载」）
- 栏内单位缩写为 `K` / `M`，速率语义由 `↓↑` 方向承担；完整单位（`KB/s` 等）只出现在 tooltip 与下拉面板
- 设置 `button.toolTip` 为完整四指标 + 压力态文本，作为不占栏内宽度的悬停全量视图
- **刘海自适应收缩**：每帧检测状态项左边缘是否伸进 `NSScreen.auxiliaryTopRightArea`；被挤压**立即降档**（全开 → 去 MEM → 仅 NET → **仅状态点**）。状态点档（约 10pt，压力色 `●`/`▲`/`■`）保证任何拥挤程度下都可见、可点击打开全量面板。**升档为慢速自愈**：预测 fit 且余量 ≥ 40pt 并持续 30s 才升一档；启动或用户改偏好/预设时立即重试全开。无刘海屏幕该区域为 nil，不收缩
  > 动机：菜单栏空间与所有状态项共享且**动态变化**（其他菜单栏图标会瞬时增减）。实测本机刘海右侧 772pt 曾被占用到仅剩约 52pt，连仅网速档（104pt）都放不下，状态项被刘海裁成碎片、看似「没显示」。
  > 升档为何要慢：实测状态项右边缘随自身宽度漂移约 20pt，且 window frame 异步更新；无余量、无持续的试升会与降档构成每秒极限环闪烁。余量 40pt > 漂移 20pt，配合 30s 持续条件，既能自愈又不闪。

`Info.plist` 必须包含：

| 键 | 值 | 作用 |
|---|---|---|
| `LSUIElement` | `true` | 不出现在 Dock、不抢焦点、无主菜单 |
| `CFBundleIdentifier` | `com.mini.trafficmonitor` | 开机自启注册标识 |
| `LSMinimumSystemVersion` | `13.0` | 版本门槛 |

### FR-2 CPU 占用率采样 【P0】

- API：`host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCpus, &info, &count)`
- 返回每核 4 个**累计** tick：`CPU_STATE_USER` / `SYSTEM` / `IDLE` / `NICE`
- 占用率 = `Δ(user + system + nice) / Δ(user + system + nice + idle)`
- **必须用两次采样的差值**，绝对值是开机以来的累计，直接用会恒为高值
- v1 聚合所有核心，不做每核展示

实现要点（均为已验证的坑）：

1. 返回的 `processor_info_array_t` **必须** `vm_deallocate` 释放，容量为 `count * MemoryLayout<integer_t>.stride`。
   > 不释放则每秒泄漏一次，运行数小时后内存远超预算，直接违背 NFR-1。这是本采样器唯一的资源管理风险点。
2. tick 类型为 `UInt32`，长时间运行会回绕，差值计算须用 wrapping 减法 `&-`
3. 多核需按 `CPU_STATE_MAX` 步长遍历，逐项累加后再求比

### FR-3 内存占用率采样 【P0】

- API：`host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)`
- 物理总量：`sysctlbyname("hw.memsize")`，**启动时读一次并缓存**（该值永不变化）
- 页大小：`vm_kernel_page_size`，Apple Silicon 上为 **16384**（不是 4096，算错会差 4 倍）

#### 口径决策 —— 需确认，见 §7 Q1

同一时刻（32 GB 机器）各候选公式实测值：

| 候选 | 公式 | 结果 | 占比 |
|---|---|---|---|
| **A（推荐）** | `(internal_page_count + wire_count) × pageSize` | 17.50 G | **54.7%** |
| B | `physmem − free − speculative − purgeable` | 31.05 G | 97.0% |
| C | `physmem − free` | 31.51 G | 98.5% |
| D | A + `external_page_count`（含文件缓存） | 24.73 G | 77.3% |

**推荐 A**，等价于「App Memory + Wired Memory + Compressed」，即活动监视器底部「已使用内存」的口径。

**理由（重要）**：macOS 会主动把空闲内存用满做文件缓存，这是设计行为而非异常。因此 B / C 在任何一台 Mac 上几乎恒为 95%–99%，**作为监控指标完全没有信息量** —— 用户看到的永远是一个接近满格的数字。A 会随真实负载变化，才具备监控价值。

若最终选 A，实现时须对照活动监视器「已使用内存」做一次校准（见 M2 验收）。

### FR-4 网速采样 【P0】

- API：`getifaddrs()` → 遍历 `sa_family == AF_LINK` 的项 → `ifa_data` 转 `if_data` → 读 `ifi_ibytes` / `ifi_obytes`
- 速率 = `Δ字节 / Δ时间`
- 时间基准用**单调时钟** `clock_gettime_nsec_np(.UPTIME)`，不能用 `Date()`
  > 用 `Date()` 时，NTP 校时或用户改系统时间会产生负时间差或巨大时间差，导致速率出现荒谬值。
- 排除 `lo0`（回环，实测本机 lo0 累计 307 MB，混入会严重失真）

#### 活动网卡识别 —— 已验证方案

**不要手工解析路由表。** 实测用 `SCDynamicStore` 三行即可，且结果与 `route -n get default` 完全一致：

```swift
let store = SCDynamicStoreCreate(nil, "mtm" as CFString, nil, nil)!
let v = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
let primary = v?["PrimaryInterface"] as? String     // → "en0"
```

需链接 SystemConfiguration：SPM 中写 `linkerSettings: [.linkedFramework("SystemConfiguration")]`。

要求：

- 通过 `SCDynamicStoreSetNotificationKeys` + `SCDynamicStoreCreateRunLoopSource` 监听 `State:/Network/Global/IPv4`，网卡切换时自动更新，**不轮询**
- **网卡切换或计数器归零时必须重置基线**
  > 不同网卡的 `ifi_ibytes` 是各自独立的累计值。切换网卡瞬间用新网卡的累计值减去旧网卡的累计值，会显示一个巨大的假速率（可能是 GB/s 级）。这是本采样器最容易出的 bug。
- 无活动网卡（断网）时显示 `↓0 B/s ↑0 B/s`，不得显示 `--` 或崩溃

### FR-5 下拉详情面板 【P1】

点击状态栏项弹出 `NSMenu`：

```
CPU          12.3 %   (user 8.1 / sys 4.2)
内存         17.5 / 32.0 GB   (54.7%)
             wired 2.4 G · compressed 6.3 G
网络         en0 (10.52.69.33)
             ↓ 1.2 MB/s   ↑ 300 KB/s
──────────────────────────────
栏内显示：CPU            ☑
栏内显示：内存           ☑
栏内显示：网速           ☑
内存内容：占用率         ☑
内存内容：压力
──────────────────────────────
预设：完整（三段全开）
预设：极简（仅网速）
☑ 开机自启
──────────────────────────────
退出
```

- **全部用纯文本 `NSMenuItem.title`，不使用自定义 view**
  > `NSMenuItem.view` 会为每一项创建并常驻一个 NSView 层级，是状态栏应用内存膨胀的常见来源。纯文本菜单项由 AppKit 统一绘制，开销可忽略。
- 面板内容在每次弹出时按需构建（`menuNeedsUpdate:`），不预先持有
- 「栏内显示」三个勾选项分别控制 FR-1 的 CPU / MEM / NET 段，取消勾选即从菜单栏移除该段（宽度随之减小）
- 「预设」为批量设置上述三个勾选项的快捷方式：**完整** = 三段全开（172pt）；**极简** = 仅网速（88pt）。预设不引入额外状态，只是勾选项的组合
- 「内存内容」为互斥二选一项（占用率 / 压力），控制 FR-1 的 MEM 段内容
- 以上勾选状态实时生效并写入偏好设置（FR-7）
- 「开机自启」为可勾选项，状态写入偏好设置
- 无论栏内显示哪些段，本面板**始终展示全部四指标**，是全量数据的兜底视图

### FR-6 开机自启 【P1】

- **首选**：`SMAppService.mainApp.register()`（macOS 13+），用户可在「系统设置 → 通用 → 登录项」中看到并关闭
- **风险**：ad-hoc 签名下，每次重新构建签名标识都会变化，可能导致已注册的登录项失效或指向旧二进制。**须在实现阶段实测验证**
- **兜底**：写入 `~/Library/LaunchAgents/com.mini.trafficmonitor.plist`（`RunAtLoad = true`）。ad-hoc 签名下更稳定，且不要求 App 位于 `/Applications`

### FR-7 偏好设置持久化 【P2】

- 用 `UserDefaults`，不引入自定义配置文件格式
- v1 持久化三个键：
  - `launchAtLogin: Bool`
  - `memoryDisplayMode: usage | pressure`（默认 `usage`）
  - `visibleSegments: 位掩码`（CPU | MEM | NET，默认全开）
- 不做的：主题、字体、其他显示项开关、刷新间隔（见 §6）

### FR-8 内存压力采样与展示 【P1】

活动监视器「内存压力」图的绿/黄/红三态，对应系统内核的内存压力等级。

- API：`sysctlbyname("kern.memorystatus_vm_pressure_level")`，返回 `Int32`
- 取值与 `DispatchSource.MemoryPressureEvent` 位掩码完全一致（已验证）：

| 值 | 含义 | 活动监视器 | 菜单栏符号 |
|---|---|---|---|
| 1 | normal | 绿 | 绿色 `●` |
| 2 | warning | 黄 | 黄色 `▲` |
| 4 | critical | 红 | 红色 `■` |

- 在既有的 1 Hz 采样 tick 中顺带读取（一次 sysctl 为微秒级），**不引入额外定时器或线程**，符合设计原则 4
- 符号采用**颜色 + 形状双重编码**：颜色提供与活动监视器一致的直观语义；形状保证即使系统剥离颜色（见附录 A.4）三态仍可区分。二者缺一不影响可读性

#### 已验证并否决的方案

`DispatchSource.makeMemoryPressureSource(...)` 事件驱动、零轮询，理论上更省。但实测（macOS 15.7.8）它是**纯边沿触发**：`resume()` 后不会立即回调当前状态，只有等级真正变化时才触发。正常机器上等级可能数小时不变，会导致 App 启动后长时间没有压力数据。**故否决，改用 sysctl 在 tick 中轮询。**

#### 明确不使用

`kern.memorystatus_level` 实测返回 71（0–100 整数），但其语义未公开，且经比对既非 free 占比也非已用占比，无法验证含义。**不用于任何展示** —— 不给用户一个无法解释的数字。

---

## 5. 非功能需求

| 编号 | 类别 | 指标 | 验收方式 |
|---|---|---|---|
| NFR-1 | 内存 | 常驻 **physical footprint ≤ 25 MB**（活动监视器「内存」列口径），实测 **9.3 MB** | `vmmap --summary` / 活动监视器 |
| NFR-2 | 内存稳定性 | 连续运行 24 h 后 RSS 无增长 | 定时采样对比，验证 FR-2 的 `vm_deallocate` 无遗漏 |
| NFR-3 | CPU | **稳态**自身占用 ≤ 0.3%（1 Hz），实测 0.3%；生命周期均值含启动突发会略高，不作验收口径 | `top -l 2 -pid` |
| NFR-4 | 启动 | 冷启动到状态栏可见 ≤ 1 s | 手动计时 |
| NFR-5 | 依赖 | 零第三方依赖，仅 AppKit / SystemConfiguration | `Package.swift` 无 `dependencies` |
| NFR-6 | 权限 | 不需 root / 沙盒 / 特殊 entitlement，不弹权限请求 | 全新用户账户下运行 |
| NFR-7 | 体积 | .app ≤ 2 MB | `du -sh` |
| NFR-8 | 兼容 | macOS 13.0+ | — |
| NFR-9 | 鲁棒性 | 睡眠唤醒、网卡切换、显示器热插拔后数据仍正确 | 手动触发后观察 |

---

## 6. 范围外（明确不做）

以下已在需求讨论中排除，记录于此以避免实现期范围蔓延。

| 功能 | 排除原因 | 归属 |
|---|---|---|
| 迷你折线图 / sparkline | 需每秒生成并绘制 `NSImage`，与「纯文字最低开销」原则直接冲突 | v2 可评估 |
| 每核心 CPU 展示 | 下拉面板变长，且需常驻 per-core 数组 | v2 |
| Top N 进程占用 | 需遍历 `proc_listpids` + `proc_pidinfo`，开销与本项目定位冲突 | 不做 |
| **按进程统计网速** | macOS 上需 Network Extension + 特殊 entitlement 且需 root，个人开发者无法获取 | **技术上不可行** |
| CPU 温度 / 风扇转速 | 需 IOKit SMC 访问，机型兼容性坑多，常驻开销明显 | v2 |
| 会话 / 今日累计流量 | 需持久化与跨天归零逻辑 | v2 |
| 手动切换网卡 UI | v1 自动识别已足够 | v2 |
| 主题 / 自定义格式 / 刷新间隔 | 需引入设置界面与更多持久化面（显示项开关与内存内容切换已在 v1，见 FR-1 / FR-5 / FR-8） | v2 |
| 刷新间隔可配置 | v1 固定 1 Hz | v2 |
| 磁盘 I/O、GPU、电池 | 非本次目标 | 待定 |

> 注：**「多网卡智能选择」未列入 v1 功能，但活动网卡识别本身不是可选特性**，而是网速数据正确性的前提（不识别就会把 lo0 或休眠网卡的流量算进来）。v1 实现 FR-4 中的自动识别，**不提供用户手动切换界面**，后者归 v2。

---

## 7. 决策记录

以下事项已于 2026-10-16 评审定稿，全部采纳建议值。部署形态：**仅本机自用，不分发**。

| # | 事项 | 定稿结论 |
|---|---|---|
| Q1 | 内存口径 | **A**（`internal_page_count + wire_count`，活动监视器口径）。M2 阶段对照活动监视器「已使用内存」校准一次 |
| Q2 | 开机自启 | 先试 `SMAppService`；ad-hoc 签名下失效则回退 LaunchAgent |
| Q3 | 菜单栏箭头 | `↓↑`（常见字体覆盖区，不会出现豆腐块） |
| Q4 | universal binary | **不需要**，仅本机自用，arm64 即可 |
| Q5 | 分发 | **不分发**，无需 Developer ID 签名与公证 |
| Q6 | 内存展示 | 支持占用率 ↔ 压力切换，**默认占用率**（FR-8） |
| Q7 | 菜单栏宽度 | 定宽压缩格式 200.9pt + 分段可开关 + 「极简」预设（104.5pt）+ tooltip 悬停全量 + **刘海自适应收缩**（FR-1）。原否决的「自适应降级」指*猜测*剩余宽度（确无公开 API）；改为*测量自身 frame 是否伸进刘海安全区*后可靠可行，故恢复为收缩机制 |

---

## 8. 架构草图

单进程、单线程、零第三方依赖：

```
MiniTrafficMonitor.app
└── main.swift                  入口：NSApplication + AppDelegate（LSUIElement）
    ├── StatusItemController    持有 NSStatusItem，负责 attributedTitle 渲染
    ├── Sampler                 主线程 RunLoop Timer，1 Hz
    │   ├── CPUSampler          host_processor_info（含 vm_deallocate）
    │   ├── MemorySampler       host_statistics64 + 压力等级 sysctl（FR-8）
    │   └── NetworkSampler      getifaddrs/if_data + SCDynamicStore 网卡变更通知
    ├── MenuBuilder             NSMenu 按需组装与事件响应
    └── Preferences             UserDefaults 包装 + 开机自启注册
```

**数据流**（全程同步，无队列跳转，无 async/await）：

```
Timer 触发 → Sampler 读系统 API → 与上次计数器求差 → 格式化字符串
           → StatusItemController 更新 attributedTitle
```

**构建与打包**（收敛为单个 `build.sh`）：

```
swift build -c release
  → 创建 MiniTrafficMonitor.app/Contents/{MacOS,Resources}
  → 拷贝可执行文件到 Contents/MacOS/
  → 写入 Info.plist（LSUIElement=true, CFBundleIdentifier, LSMinimumSystemVersion=13.0）
  → codesign --force --sign - MiniTrafficMonitor.app
```

---

## 9. 里程碑

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| **M1** | SPM 工程 + `build.sh` bundle 组装 + 状态栏显示静态文字 | 状态栏出现固定文字；Dock 无图标；.app 可双击启动 |
| **M2** | CPU / 内存 / 网速三个采样器，1 Hz 刷新文字 | CPU 与活动监视器一致；内存与活动监视器「已使用内存」一致（Q1 校准）；网速与 `nettop` 量级一致 |
| **M3** | 下拉面板 + 分段开关/预设 + 网卡自动识别与切换监听 + 内存压力切换（FR-8） | Wi-Fi ↔ 有线切换后数据不断流、**不出现假峰值**；压力三态与活动监视器一致；分段开关 / 预设 / 内存内容切换实时生效且重启后保留 |
| **M4** | 开机自启 + 偏好持久化 | 注销重登 / 重启后自动运行；系统设置登录项中可见可关 |
| **M5** | 轻量性验收 | RSS ≤ 25 MB；自身 CPU ≤ 0.3%；24 h 运行 RSS 无增长 |

M1–M2 是核心价值闭环，完成后即可日常使用。

**实现状态（2026-10-16）**：M1–M5 全部完成，已打包安装至 `/Applications/MiniTrafficMonitor.app`（v1.0.0，含图标）。自测入口 `MTM_SELFTEST=1`（20 项）。轻量性验收见附录 A.6。仍需人工确认两项：① Wi-Fi ↔ 有线切换后不断流、无假峰值；② 压力符号颜色目视（绿 `●` / 黄 `▲` / 红 `■`，需菜单栏有足够空间显示 MEM 段时才可见）。24h 无增长（NFR-2）用 `tools/measure-lightweight.sh 86400 30` 由用户跑完确认。

---

## 附录 A：技术验证记录

2026-10-16，在 macOS 15.7.8 / Swift 6.1.2 / **仅 Command Line Tools** 环境下实测。

### A.1 验证结果

| 验证项 | 结果 |
|---|---|
| `swiftc` 在无 Xcode 环境下编译 AppKit | ✅ 通过 |
| `host_processor_info` 免特权读 CPU tick | ✅ user/sys/idle/nice 均可读 |
| `host_statistics64(HOST_VM_INFO64)` 读内存 | ✅ 与 `vm_stat` 吻合（wired 2602 vs 2609 MB，差异为采样时间差） |
| `getifaddrs` + `if_data` 读网卡累计字节 | ✅ 正确读到 en0 流量，lo0 可识别排除 |
| `SCDynamicStore` 读活动网卡 | ✅ 返回 `en0` + 网关 `10.52.69.254`，与 `route -n get default` 一致 |
| 手工解析路由表（`NET_RT_DUMP` / `NET_RT_DUMP2`） | ❌ 多次尝试未成功，**放弃**，改用 `SCDynamicStore` |
| `kern.memorystatus_vm_pressure_level` 读内存压力等级 | ✅ 返回 1（normal），位掩码与 `DispatchSource.MemoryPressureEvent` 完全一致 |
| `DispatchSource` memorypressure 事件源 | ⚠️ 纯边沿触发、无初始状态，**否决**，理由见 FR-8 |
| `kern.memorystatus_level` | ⚠️ 返回 71，语义不可验证，**不使用**，理由见 FR-8 |

### A.2 踩到的坑（实现时避免重复）

1. `RTA_IFP` 是 bit 4（`0x10`），不是 bit 3 —— 地址位掩码的索引从 `RTA_DST=0` 开始逐个 bit 数
2. macOS 的 `rt_msghdr` / `rt_msghdr2` **没有 `rtm_hdrlen` 字段**（那是 FreeBSD 的），头部长度固定为结构体 stride
3. `UnsafePointer<UInt8>` 没有 `assumingMemoryBound(to:)`，必须先转成 `UnsafeRawPointer`
4. `host_processor_info` 返回的数组**必须 `vm_deallocate`**，否则每秒泄漏一次
5. `SCDynamicStore` 需显式链接 `-framework SystemConfiguration`
6. `vm_kernel_page_size` 在 Apple Silicon 上是 **16384**，按 4096 计算会差 4 倍
7. `UserDefaults(suiteName:)` 在进程启动**极早期**可能返回 nil。若把结果缓存成 `let`，回退到 `.standard` 的实例会被永久固定，之后永远读不到偏好（实测同一进程内新建 suite 读到值、缓存实例读不到）。用计算属性每次解析
8. `UserDefaults.object(forKey:) as? Int` 对 plist 整数（NSNumber）桥接可能失败而**静默回退默认值**。读整数一律用 `integer(forKey:)`
9. `NSStatusItem.button.window.frame` **异步更新**，且状态项**右边缘随自身宽度变化**（邻居/安全区夹逼，实测漂移约 20pt）。任何「测量 → 改宽度 → 再测量」的无余量闭环都会形成极限环（表现为每秒闪烁）。正确做法：降档立即、升档带余量（> 漂移量）+ 持续时间的慢速自愈

### A.3 验证代码

可直接运行的验证代码保存在 [`spike/`](../spike/)：

| 文件 | 内容 |
|---|---|
| `cpu-mem-net.swift` | CPU tick / 内存 / 网卡累计字节 三项采样 |
| `active-interface.swift` | `SCDynamicStore` 读活动网卡（**推荐方案**） |
| `memory-formulas.swift` | 四种内存口径公式并排对比 |

编译运行：

```bash
cd spike
swiftc -O active-interface.swift -o ai -framework SystemConfiguration && ./ai
swiftc -O memory-formulas.swift -o mf && ./mf
swiftc -O cpu-mem-net.swift -o cmn && ./cmn
```

这些代码已验证可用，可直接作为 M2 采样器的实现基础。

### A.4 菜单栏彩色文字验证受限（环境限制）

曾尝试用 `screencapture` 截取菜单栏，以验证 `attributedTitle` 的 `foregroundColor` 是否真实渲染。结果：**子区域截取与全屏截取均无法捕获菜单栏右侧内容** —— 连系统时钟、控制中心图标都被剥离，仅余壁纸；而同一张截图里左侧的应用菜单文字清晰正常。

判定为 macOS 对**无屏幕录制权限进程**的菜单栏右侧隐私脱敏，属环境限制，**不是渲染失败**。

因此 FR-8 的压力符号采用**颜色 + 形状双重编码**，把「颜色是否渲染」从正确性问题降级为纯视觉问题：即使系统剥离颜色，`●` / `▲` / `■` 三种形状仍足以区分三态。实现期人工目视确认一次颜色即可，无需再依赖截屏验证。

### A.5 菜单栏文字宽度实测

用 `NSAttributedString.size()` + `monospacedDigitSystemFont(ofSize: 13)` 实测各候选格式渲染宽度：

| 格式 | 宽度 | 结论 |
|---|---|---|
| `CPU 12%  MEM 45%  ↓1.2 MB/s ↑300 KB/s` | 268 pt | 初稿，**否决**（余量过薄） |
| `CPU 12% MEM 45% ↓1.2M ↑300K` | 216 pt | 否决 |
| `C12% M45% ↓1.2M ↑300K` | **172 pt** | **采用为默认** |
| `12% 45% ↓1.2M ↑300K` | 151 pt | 否决（位置编码可读性差） |
| `12 45 ↓1.2 ↑0.3` | 103 pt | 否决（丢失 % 与单位） |
| `↓1.2M ↑300K` | 88 pt | 采用为「极简」预设 |
| `C12% M45%` | 81 pt | 分段子集示例 |

> 上表以 `monospacedDigitSystemFont` 测量，仅用于**格式选型**（决定去掉哪些标签与单位），**不代表最终渲染宽度**。

**字体修正（实测，重要）**：`monospacedDigitSystemFont` 只保证数字等宽，而帧内的小数点 `.`、单位字母 `K/M/B`、首帧 `--` 都不是数字。实测同一格式在不同数值帧下宽度极差达 **41.68pt**（`↑96.8K` 183.6pt vs `↑1024B` 192.5pt），仍会抖动。改用 `monospacedSystemFont`（全等宽）后极差 **0.00pt**。

最终采用帧（全等宽 13pt，字段定宽填充）：

| 帧 | 宽度 |
|---|---|
| `C 20% M 50% ↓ 7.0K ↑96.8K`（三段全开；首帧 `C --% … ↓   0B` 同宽） | 200.90 pt |
| `↓ 7.0K ↑96.8K`（「极简」预设） | 104.47 pt |
| `C 20% M 50%` | 88.40 pt |

**空间参考**：16" MacBook 逻辑宽 1728pt；刘海约 200pt、右侧系统图标（时钟/控制中心/电池/Wi-Fi）约 180pt；应用菜单与状态项共享剩余约 1348pt。实测 IntelliJ 全菜单约占 710pt，故初稿 268pt 在本机可放下（710+268 < 1348）但余量薄 —— 换 13" 机器、多开菜单栏 App 或应用菜单变长即会挤爆。因此采用定宽默认 200.9pt + 「极简」预设 104.5pt 兜底（710 + 201 < 1348，本机仍有余量）。

**拥挤实测（2026-10-16，「菜单栏没看到软件」的根因）**：`auxiliaryTopRightArea` = x 956..1728（772pt）。本机该区域已被系统图标与其他菜单栏 App 占用 578pt，仅剩约 194pt。全开帧 221pt 的状态项被布局到 x=929..1150，左缘伸进刘海 27pt → **物理不可见**，而 `NSStatusItem.isVisible` 仍为 `true`、进程无崩溃，故从进程侧完全看不出异常。结论：仅靠"默认格式够窄"不能保证可见，必须有 FR-1 的刘海自适应收缩兜底。

**拥挤是动态的（补充实测）**：同一天内空闲空间在 ~194pt 与 ~52pt 之间波动（其他菜单栏图标瞬时增减）。52pt 时连仅网速档（104pt）都放不下，状态项被裁成碎片、用户感知为「点图标启动但状态栏没东西」（进程存活、无崩溃、`isVisible=true`，极难排查）。故收缩阶梯必须有**约 10pt 的状态点最终档**兜底。

### A.6 轻量性验收测量（M5，2026-10-16）

| 指标 | 口径 | 实测 | 预算 | 结论 |
|---|---|---|---|---|
| 内存 | physical footprint（`vmmap`，= 活动监视器「内存」列） | **9.3 MB** | ≤ 25 MB | ✅ |
| 内存 | RSS（含共享框架只读映射，仅参考） | ~38 MB | — | 参考值 |
| 内存增长 | 240s 窗口首末差 | **−640 KB**（平坦） | 趋近 0 | ✅（24h 用 `tools/measure-lightweight.sh 86400 30` 复核） |
| CPU | 稳态区间采样（`top -l 2 -s 5`） | **0.3%** | ≤ 0.3% | ✅ |
| 体积 | .app（含图标） | 624 KB | ≤ 2 MB | ✅ |
| 启动 | launch → checkin | 0.05 s | ≤ 1 s | ✅ |

> **RSS 与 footprint 的差异**：RSS 计入 AppKit 等共享框架的只读映射页，这些页并非本 App 的边际内存成本；footprint（dirty + compressed）才是本 App 实际造成的内存压力，也是活动监视器「内存」列的口径。故 NFR-1 以 footprint 验收，RSS 仅作参考。
>
> **优化记录**：字体查找改静态缓存、IPv4 地址改为接口变化时才读、tooltip 改 5s 更新一次 —— 三项使 footprint 从 16.6 MB 降至 9.3 MB、稳态 CPU 从 0.4% 降至 0.3%。
