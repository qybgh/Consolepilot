# Consolepilot 重构、交付与严格验收实施计划（当前执行计划 · 已确认版 · 决策 D1–D8）

> **文档状态（2026-09-09）**：本文件为**当前唯一执行计划**，已并入 Gate 0 验证结论与全部实施前决策（D1–D8）。
> Gate 0 证据与逐项结论见 `Docs/GATE0-CONFIRMATION.md`（已确认版）；与旧文档冲突时以本文件为准。
> 版本沿革：`abc4d36`（mvp version）→ 2026-09-09 待确认版 → 2026-09-09 已确认版（登记 D1–D8、并入 Gate 0 结论、按决策修订本轮范围）。

## 0. 实施前决策登记（2026-09-09 用户已确认，覆盖下文相应条款）

> 登记依据：`Docs/GATE0-CONFIRMATION.md`（已确认版 · 决策 D1–D8）。下列决策为当前权威口径；
> 与正文冲突处以本登记为准；正文相应条款在 P0 落地时按本登记执行并同步修订。

| # | 决策 | 对本计划的覆盖 |
|---|---|---|
| D1 | Apple Development 证书已在本机生成并验证生效（`1217194271@qq.com` / WCHFR3G7VB） | 本机安装与真机调试可签名；**2026-09-09 验收修订：交付签名默认使用本证书（`make build`/`make release`，`SIGN_IDENTITY=-` 回退 ad-hoc）**，不引入 Developer ID / 公证 / 沙盒 |
| D2 | 提供一台 macOS 14 电脑用于实机测试 | §6 实机验收：macOS 15 轮次用本机、macOS 14 轮次用该设备 |
| D3 | 需提前安装的命令环境由用户自行安装，仅需安装命令 | `brew install swiftlint`、`brew install periphery`；swift-format 已随 Xcode 就绪 |
| D4 | 不单独做 Gate 0.3 临时 spike | §4 Gate 0 第 3 项改为并入 **P0 第 1 步**（建 Xcode 工程）DoD：先搭最小 SwiftUI App 骨架（WindowGroup + Settings + 菜单栏 + 无焦点激活验证） |
| D5 | 接受现有 TransportTests 20 项作为 Gate 0.4 契约证据 | §4 Gate 0 第 4 项本机侧通过；独立 fixture 脚本并入 P1「Provider 统一 stream contract」工作时建立 |
| D6 | `tails` 整体移出本轮；`theme` 等 6 个 UI 字段随 P2 SwiftUI 迁移实现；`toggleHotkey` 本轮删除 | §3.4 tails 条款不暴露；6 UI 字段列入 P2 实现清单；toggleHotkey 从 schema/默认/设置/测试删除 |
| D7 | 删除 `launchAtLogin`、废弃 `attachTo`（旧值迁移报错）、新增 `sessionMode` + Action 级 `timeoutSec` | §3.4 按此执行 |
| D8 | 接受破坏性范围；清空 mvp 残留是**手动一次性动作**，不需要 app 内设计相关功能；本机无 mvp 使用史 → 按全新设计重构，无旧兼容负担 | 覆盖第 1 节「数据」、§3.4「升级首次启动确认页」与 §6 第 2 步：**取消 app 内升级清空/确认页设计** |

## 1. 已锁定的目标与边界

- 产品定位：个人生产力工具；首要目标是跨应用后台 Action 的可靠性，AI 对话与 CLI/HTTP 为同一业务能力的不同入口。
- 平台：Apple Silicon，macOS 14 与 macOS 15；发布包仅构建和验收 arm64，不宣称 Intel 支持。
- UI：迁移至完整 SwiftUI 生命周期；允许保留 AppKit/Carbon/Accessibility 作为系统能力适配层，不保留 AppKit 页面实现。
- 架构：MVVM + Use Cases；View 不直接访问数据库、Provider、Keychain、Capture 或 LocalServer。
- 交付：Xcode 工程为唯一权威构建入口，Makefile 为唯一命令入口；本机 Apple Development 证书签名 ZIP 和 CLI（稳定签名身份，授权跨重建保留；无证书环境 `SIGN_IDENTITY=-` 回退 ad-hoc），不引入 Developer ID、公证、自动更新或 App Store 沙盒。
- 数据：允许一次性清空已有本地 SQLite 会话、消息、用量与捕获元数据。~~升级界面必须显式提示并要求用户确认，未确认则不删除、不迁移、不启动新版本数据层~~（0.0 决策 D8 取代：**不做 app 内确认页**；清空为手动一次性外部动作，新数据层全新建库）。
- UI 标准：功能等价并小幅优化，保留终端风格、聊天、会话、设置、用量、菜单栏和后台 Action 的核心体验。
- 隐私：配置仅允许 Keychain/环境变量密钥引用；日志、测试 fixture、诊断和数据库捕获日志不得保存 API 密钥或捕获正文。

### 1.1 执行环境与前置工具（Gate 0.1 实测，2026-09-09）

| 项 | 实测 / 决策 | 状态 |
|---|---|---|
| 本机 | macOS 15.7.9 (24G830)，Apple Silicon arm64 | ✅ |
| Xcode / Swift | Xcode 16.4 (16F6)；Swift 6.1.2；SDK 仅 macOS 15.5（部署目标可设 macOS 14，实机验证用 D2 设备） | ✅ |
| swift-format | 随 XcodeDefault toolchain 就绪 | ✅ 无需安装 |
| SwiftLint | 未安装 → 用户执行 `brew install swiftlint`（D3） | ⏳ 用户安装 |
| Periphery | 未安装 → 用户执行 `brew install periphery`（D3；formula 已 deprecated，失败时备用 `brew install peripheryapp/periphery/periphery`） | ⏳ 用户安装 |
| 签名身份 | Apple Development 证书已生成并验证（`1217194271@qq.com` / WCHFR3G7VB / Team `3CSL8ZN3AN`）；**发布形态默认本证书签名，ad-hoc 仅作回退（D1 修订 2026-09-09）** | ✅ |
| 实机 | macOS 14 电脑已提供；macOS 15 轮次用本机（D2） | ✅ |
| 测试基线 | `swift test --disable-sandbox`：77 项执行 / 74 通过 / 3 失败（NSPasteboard、Keychain 沙箱环境件，GUI 会话可跑） | ✅ 基线已记录 |
| 测试凭据 / 账户 | 真实 Provider 低权限凭据、独立测试账户未提供 | ⬜ 验收矩阵开放项 |

## 2. 当前审查结果与必须整改项

| 优先级 | 发现 | 风险 | 完整改法 |
|---|---|---|---|
| P0 | `ConsolepilotRootView` 约 1,250 行，承担装配、UI、任务、IPC、流式、会话与状态 | 任何改动都会跨层回归；无法可靠迁移 SwiftUI | 删除该根视图职责，按 App / Presentation / Application / Domain / Infrastructure / System Integration 重建边界 |
| P0 | Action、聊天、CLI 各自编排会话、请求、Task、UI 切换 | 取消、错误、状态恢复与统计存在旁路 | 统一为 Conversation 与 Action 两个用例及单一 Stream 生命周期服务 |
| P0 | `attachTo`、`autoShow`、`notifyOnDone`、`launchAtLogin`、部分 tail 字段仅解析或校验，未完整兑现 | 配置文档与实际行为不一致 | 每个保留字段都必须实现、测试并写入 README；无法实现的字段从 schema、默认配置、设置说明与测试中彻底删除（处置细节见 §3.4 与 §0 决策登记 D6/D7） |
| P0 | Action 结果可能影响当前 UI 会话；后台与前台任务状态分散在多个字典 | 打断用户工作、会话串线、取消不完整 | Action 固定写入独立后台 Action 会话；`autoShow` 只影响窗口可见性，`notifyOnDone` 只触发通知 |
| P1 | Core target 同时包含领域、GRDB、Provider、AppKit 和系统 API | 编译边界与可测性差 | 建立独立 Xcode targets 和显式依赖方向，禁止反向 import |
| P1 | Provider 使用无类型 JSON 和重复 SSE 消费逻辑 | 协议变动、错误与 usage 解析难维护 | 以 Provider DTO、协议事件转换器、共享 SSE transport 和错误映射替换 |
| P1 | `TOMLDecoder` 已出现已知崩溃规避代码 | 设置编辑器仍有依赖风险 | Gate 0.2 已于 2026-09-09 通过（锁版 0.4.5 零崩溃 / 错误可定位 / MIT，见 GATE0-CONFIRMATION.md §2）；实现期仍需 preflight + validator 兜底 |
| P1 | 当前构建脚本内联 Info.plist、固定 arm64 路径、删除 `dist/` | 版本、签名、产物与开发环境不可复现 | 改为 Xcode 配置、真实 Info.plist、受控产物目录、版本校验及 Makefile 任务 |
| P1 | 根 README 近乎为空，文档分散且进度文档混入历史实现细节 | 新用户无法安装、验证或维护 | 重写根 README；新增独立架构/实施计划；`PROGRESS.md` 仅保留索引和实时状态 |
| P2 | 无 CI；SwiftLint 尚有历史豁免；无 UI/发布产物门禁 | “本机能跑”不能代表可交付 | 引入严格静态、单元、集成、UI、性能、构建、签名与人工验收门禁 |

## 3. 目标工程结构与代码写法规范

### 3.1 Xcode 工程与模块

新增 `Consolepilot.xcodeproj`，移除 `Package.swift`、`Package.resolved` 与旧 SwiftPM 构建脚本作为权威入口，避免双构建体系残留。工程由以下 targets 组成：

| Target | 责任 | 禁止依赖 |
|---|---|---|
| `ConsolepilotDomain` | 实体、值对象、领域错误、业务协议、纯规则 | SwiftUI、AppKit、GRDB、Network、Keychain |
| `ConsolepilotApplication` | Conversation/Action/Session/Config 用例、命令处理、事务编排 | SwiftUI、AppKit、具体 Provider/数据库实现 |
| `ConsolepilotInfrastructure` | GRDB、SQLite migration、Keychain、文件、TOML、HTTP/SSE Provider | SwiftUI、Presentation |
| `ConsolepilotSystemIntegration` | Accessibility、Carbon hotkey、通知、菜单栏、LocalServer、窗口激活桥接 | SwiftUI View、GRDB 细节 |
| `ConsolepilotPresentation` | SwiftUI View、`@Observable` ViewModel、导航和可访问性标识 | 具体 Infrastructure 类型 |
| `ConsolepilotApp` | `@main App`、composition root、WindowGroup、Settings、生命周期桥接 | 业务实现细节 |
| `consolepilot` | CLI 参数解析和 Application use case 调用 | SwiftUI、AppKit 页面 |
| `ConsolepilotTests` / `ConsolepilotUITests` | 单元、集成、UI、性能和发布验收自动化 | 生产私有实现细节 |

依赖方向固定为：`Presentation / CLI / SystemIntegration → Application → Domain`，以及 `App composition root → 全部实现 target`。Infrastructure 只通过 Domain/Application 定义的协议被注入。

### 3.2 SwiftUI 生命周期与系统桥接

- `ConsolepilotApp: App` 负责 Scene 声明：主窗口、设置窗口、用量窗口。
- 使用 `NSApplicationDelegateAdaptor` 仅桥接菜单栏、终止前 checkpoint、Carbon/Accessibility 生命周期等不可由 SwiftUI 原生实现的系统行为。
- 主界面由 `AppShellView` 承担导航；会话列表、对话记录、输入器、状态栏、设置、统计各自为独立 SwiftUI View。
- 每个可交互控件提供稳定 accessibility identifier，供 UI 测试和人工验收定位。
- 迁移期间以功能切片替换旧 AppKit 界面；某切片被 SwiftUI 替代并通过验收后，立即删除相应 AppKit View、Controller、回调和测试桩，禁止双实现长期共存。

### 3.3 业务与并发规则

- `ConversationUseCase` 负责人工对话、CLI ask 和 HTTP ask；`ActionExecutionUseCase` 负责捕获、模板渲染、后台会话和通知。`TailIngestionUseCase` 因 D6（tails 整体移出本轮）**本轮不建立**，后续轮次恢复时按同一用例规范补建。
- 所有请求创建统一 `RequestExecution`，其状态仅为 `queued / capturing / connecting / streaming / completed / failed / cancelled`；状态、时间、错误、usage 和持久化 checkpoint 都由它维护。
- 所有流式输出只经 `StreamCoordinator`；Provider、UI、CLI 禁止直接写入消息 Store。
- 使用 actor 管理请求注册表、流式合帧和并发会话；UI/ViewModel 必须是 `@MainActor`。不得以散落的 `Task {}`、全局单例、通知字符串或闭包链管理生命周期。
- 每个启动的 Task 必须有所有者、取消路径、终态和测试；应用退出、会话删除、配置热重载、Action 取消、网络断开均走同一取消协议。
- Provider 请求以强类型 DTO 编码/解码；禁止生产代码使用 `[String: Any]`、静默 `try?`、`fatalError`、强制解包或吞没错误。
- 错误使用可展示的错误码、原因、恢复建议和底层安全诊断字段；用户正文、Token、Authorization header 不得进入日志。
- 配置热重载必须先解析、校验、构造候选依赖图，再原子替换；失败时保留最后有效配置和运行中任务。

### 3.4 配置、Action 与数据规则

- `attachTo = currentSession` 将废弃，避免其与“后台独立会话”决策冲突；迁移时明确报错并要求用户改为新字段。
- 新 Action 配置采用明确语义：
  - `sessionMode = dedicated`：Action 固定独立会话，按 `actionId + sourceApp` 复用最近可用会话。
  - `autoShow`：仅决定 Action 启动时是否显示主窗口；默认 `false`，后台任务不得抢焦点。
  - `notifyOnDone`：仅在窗口未前台且结果完成/失败时发本地通知；通知不包含捕获正文。
  - `timeoutSec`：从捕获完成进入网络请求开始计时；超时写入 `.failed` checkpoint 并显示可重试错误。
- `launchAtLogin`：首轮不实现；从 schema、默认 TOML、设置说明和验证器中删除。
- `tails`：仅保留已实现且经验证的 `text/jsonl`、轮转和启动配置；否则整体移至后续能力，不在本轮 UI/文档中暴露。（0.0 决策 D6：**整体移出本轮**，本轮不暴露、不补 Action 隔离与 jsonl 校验）
- ~~版本升级首次启动时显示“清空历史数据”确认页~~（0.0 决策 D8 取代：**不做 app 内清空/确认页**）。清空 mvp 残留为**手动一次性动作**，由外部命令删除 Consolepilot SQLite 主文件、`-wal`、`-shm`（精确路径实施时列出），不进 app 代码；新 schema 全新创建。
- 所有旧 schema、旧配置别名、废弃 Action 字段、旧 Store API 和迁移兼容分支在数据清空版本发布后删除，确保无死代码与无长期兼容负担。

## 4. 实施顺序与逐阶段 Definition of Done

### Gate 0：实施前确认与可行性验证 —— ✅ 已完成（2026-09-09）

> 本阶段未写生产代码；完整证据、实测输出与逐项结论见 `Docs/GATE0-CONFIRMATION.md`（已确认版）。

| # | 原确认项 | 结论 | 依据 / 决策 |
|---|---|---|---|
| 1 | 工具链 / 签名 / 设备 / 测试账户 | ✅ 本机侧通过 | Xcode 16.4 / Swift 6.1.2 / arm64（见 1.1）；Apple Development 证书已验证（D1）；macOS 14 实机已提供（D2）；独立测试账户为验收矩阵开放项 |
| 2 | TOML 解析器 spike | ✅ 通过（附约束） | 锁版 TOMLDecoder 0.4.5：合法 10k + 并发 10k + 非法 3k 次解析零崩溃、错误带 `(Line N)`、MIT；应用层 preflight + validator（含有限数检查）与错误行号提取加强列入 P1 |
| 3 | SwiftUI 最小原型 | ✅ 并入 P0 第 1 步（D4） | 不单独 spike；最小 SwiftUI App 骨架（WindowGroup + Settings + 菜单栏 + 无焦点激活验证）列入 P0 Step 1 DoD |
| 4 | Provider 契约 fixture | ✅ 本机侧通过（D5） | 现有 TransportTests 20 项全绿作为契约证据；独立 fixture 脚本并入 P1「Provider 统一 stream contract」 |
| 5 | 配置字段产品语义 | ✅ 清单已确认（D6–D7） | tails 移出本轮、toggleHotkey 删除、launchAtLogin 删除、attachTo 废弃为 sessionMode、6 个 UI 字段随 P2、Action 级 timeoutSec 新增 |
| 6 | 数据清空交互 | ✅ 改为手动一次性（D8） | 不做 app 内清空/确认页；新 schema 全新建库 |
| 7 | 授权前确认 | ✅ 2026-09-09 全部确认 | 见 §7 逐项回执 |

**剩余开放项（验收矩阵，不阻塞本机 P0 起步）**：真实 Provider 低权限测试凭据、独立测试账户、macOS 14/15 双机人手排期。

### P0：工程基线与干净替换骨架

**前置（Gate 0.1 + D3）**：Xcode 16.4 / Swift 6.1.2 / swift-format 已就绪；swiftlint、periphery 由用户按 D3 命令安装（见 1.1）；Apple Development 证书（D1）与 macOS 14 实机（D2）用于调试与后续验收。

1. 创建 Xcode 工程、Debug/Release `.xcconfig`、真实 `Info.plist`、entitlements、target membership 和 Xcode Swift Package 依赖。
   - **D4（原 Gate 0.3 范围，并入本步 DoD）**：本步同时搭出最小 SwiftUI App 骨架——`ConsolepilotApp: App`（`@main`）+ `WindowGroup` 主窗口 + `Settings` Scene + 菜单栏占位 + 「后台 Action 不抢焦点」激活验证；骨架验证通过后再继续本步其余内容。
2. 新增根 `Makefile`：
   - `make bootstrap`：校验 Xcode、swiftlint/periphery、格式化工具、依赖解析和本机架构。
   - `make test`：运行全部 XCTest、UI test 与性能测试。
   - `make lint`：执行 swift-format、SwiftLint、编译器 warnings-as-errors、静态 analyze、依赖与密钥扫描。
   - `make build`：Debug arm64 App + CLI。
   - `make release VERSION=x.y.z`：Release arm64 App + CLI、Apple Development 证书签名（`SIGN_IDENTITY=-` 回退 ad-hoc）、验证、ZIP、SHA-256 manifest。
   - `make clean`：仅删除明确的 DerivedData/Build/Release 临时产物，不删除用户数据或源码。
3. 重建 Domain/Application 协议和 use case 空壳，将现有行为以测试固定下来。
4. 建立统一 composition root；删除未接线的 `DependencyContainer`，不保留“未来可能使用”的容器。
5. 删除旧 SwiftPM 发布脚本、内联 Info.plist 生成、固定 `.build/arm64-*` 复制逻辑和重复脚本。

**完成条件：** Xcode Debug/Release 可构建；Makefile 五个核心命令可重复执行；旧/新构建入口不并存；静态门禁零 warning、零 lint 违规、零明文密钥命中；最小 SwiftUI 骨架（WindowGroup + Settings + 菜单栏）可启动，且外部触发时不调用 `activate(ignoringOtherApps:)` 抢焦点（D4 验证点，DoD 必过）。

### P1：领域、存储、Provider 与 Action 可靠性

1. 将 Session、Message、Usage、Capture metadata 和 Config 迁至 Domain model；GRDB record 与领域实体分离，Repository 映射只存在于 Infrastructure。
2. 实现 `SessionRepository`、`UsageRepository`、`CaptureAuditRepository`、`ConfigurationRepository` 协议及 SQLite/文件实现。
3. 重建 StreamCoordinator、RequestExecution actor、取消注册表和 usage/checkpoint 写入策略；确保每个会话并行流互不污染。
4. 将 OpenAI-compatible、Anthropic、Mock Provider 统一为同一 stream contract；抽取 SSE decoder、HTTP 状态映射、重试资格和安全日志；同步建立独立 Provider fixture 脚本（D5，原 Gate 0.4 补充项）。
5. 实现 Action 生命周期：快捷键触发时捕获前台 PID、捕获策略回退、独立会话、模板渲染、后台执行、可选窗口展示、可选通知、终态持久化和失败反馈。
6. 按 §3.4 与决策 D6/D7 删除或实现配置字段：删除 `launchAtLogin`、`toggleHotkey`，`attachTo` 旧值迁移报错；新增 `sessionMode` 与 Action 级 `timeoutSec`；更新默认 TOML 与严格 validator（含 TOML 有限数检查，见 GATE0-CONFIRMATION.md §2），配置更改原子生效。

**完成条件：** Action、聊天、CLI、HTTP 不存在旁路写库；每条任务有取消与终态；所有现有配置字段均有运行时测试；捕获失败不会发送历史剪贴板正文；真实 Provider 默认关闭。

### P2：完整 SwiftUI UI 迁移

1. 实现 `AppShellView`、`SessionSidebarView`、`ConversationView`、`ComposerView`、`StatusView`、`SettingsView`、`UsageView` 和 `ActionStatusView`。
   - SettingsView 需落地 D6 指定的 6 个 UI 字段接线：`theme` / `fontName` / `fontSize` / `compactFontSize` / `opacity` / `alwaysOnTop`（读取 `config.general` 并实时生效）。
2. 建立 `ConversationViewModel`、`SessionListViewModel`、`SettingsViewModel`、`UsageViewModel`；它们只调用 use case 并消费状态快照。
3. 保留功能等价：会话分页与删除、流式增量、历史恢复、取消、输入历史、Profile 切换、快捷键、菜单栏、快速提问、LocalServer/CLI。~~日志尾随~~（D6：tails 整体移出本轮，本轮 UI 不暴露）。
4. 优化而不扩大范围：VoiceOver 标签、键盘导航、窄窗口布局、明确加载/失败/取消状态、后台 Action 不抢焦点。
5. 当 SwiftUI 页面完成并验收后，删除对应 AppKit View、WindowController、SettingsWindowController、UsageWindowController、重复 renderer glue 与回调。

**完成条件：** 不再存在 AppKit 页面控制器；SwiftUI 通过 UI 自动化；后台 Action 在主屏或其他应用前台时不激活 Consolepilot；会话与流式渲染无重复或丢字。

### P3：交付文档、CI 与可安装产物

1. 新增 `Docs/ARCHITECTURE-REVIEW-AND-IMPLEMENTATION.md`：包含本审查表、已确认决策、阶段状态、Gate 结果、风险、证据链接与未通过项。
2. 更新 `Docs/PROGRESS.md`：只保留该计划链接、当前阶段、通过门禁和待办摘要。
3. 重写根 `README.md`：安装、系统要求、权限、配置、常用 Action、CLI、构建、测试、发布、隐私、故障处理，以及数据目录说明与 mvp 残留**手动清理指引**（一次性外部命令，D8；无 app 内清空页）。
4. 增加 CI：每次 PR 执行 `make lint`、`make test`、`make build`；release tag 执行 `make release` 并上传 ZIP、CLI、checksum manifest、测试报告。
5. 发布包内容固定为：`Consolepilot.app`、`consolepilot`、`config.example.toml`、`README`、版本与 SHA-256 manifest；签名与 ZIP 内容均由自动校验确认。

**完成条件：** 从干净 checkout 到发布包只需一个命令；README 可让新用户独立完成安装和首个 Mock Action；CI 不允许 warning、跳过或“历史问题豁免”。

## 5. 自动化质量门禁

### 深度代码审查门禁

- 逐 target 检查 import 方向；Presentation 不得引用 GRDB、Keychain、Network 或 Capture 实现。
- 搜索并禁止：生产代码中的强制解包、`fatalError`、未持有的 Task、无类型 JSON、明文密钥、日志正文、无使用代码、废弃字段、旧 AppKit 页面。
- 执行 `xcodebuild analyze`、Swift strict concurrency、warnings-as-errors、swift-format、SwiftLint；全部必须零错误、零警告、零忽略。
- 逐文件人工审查：并发隔离、取消语义、资源释放、错误传播、配置一致性、内存所有权、隐私与可访问性。
- 对每个删除项执行全仓库引用搜索，确认没有 source、测试、文档、构建脚本或 target membership 残留。

### 单元与模拟测试门禁

- Domain：模板、配置规则、Action 语义、错误分类、会话状态机、全新建库 schema 版本与数据目录契约（D8：无 app 内清空确认状态）。
- Application：聊天、Action、CLI、HTTP 均使用 fake repository/provider/system bridge 验证成功、取消、超时、重试资格、并行和恢复（tail 用例本轮移出，D6）。
- Infrastructure：SQLite schema、删除/重建、WAL、分页、checkpoint、Keychain、文件轮转、配置热重载。
- Provider：URLProtocol/SSE fixture 覆盖逐字节分块、空行、UTF-8 边界、`[DONE]`、`message_stop`、损坏 JSON、401、429、5xx、断连、超时和取消。
- Capture：AX 成功/拒绝、模拟复制、剪贴板恢复、changeCount 不变、安全输入、排除 bundle、输入截断和 PID 定向投递。
- UI：XCUITest 覆盖窗口启动、会话创建/删除、流式状态、取消、设置校验、Profile 选择、后台 Action 状态、菜单栏与键盘操作。
- 回归：同一用例至少运行 20 次；测试顺序随机化，不允许依赖真实网络、真实 Keychain 条目、用户剪贴板正文或既有数据库。

### 性能与稳定性门禁

- 10,000 条消息加载最新页 P95 小于 20 ms，且无全量历史加载。
- 10,000 SSE delta 无丢失、无重复；UI 刷新上限为 60 Hz，取消后不再接收可见增量。
- 100 个串行 Action 与 10 个并发模拟会话完成后，请求注册表为空、无残留 task、无重复 usage、无数据库锁错误。
- 2 小时 Mock 长稳运行：持续流式、会话切换、设置热重载（tail 轮转随 D6 移出本轮），记录 CPU、内存、句柄和崩溃数据；相对基线回归超过 10% 即失败。
- Instruments 使用 Leaks、Allocations、Time Profiler 和 Main Thread Checker；所有 retain cycle、泄漏、主线程 I/O 和超预算热点必须修复或有明确、已确认的豁免。

## 6. 严格实机验收步骤

每次均在独立测试账户、无生产密钥、已安装 release ZIP 的条件下执行；macOS 14 Apple Silicon 与 macOS 15 Apple Silicon 各完成一轮，并保存去敏截图、版本号、日志摘要与结果。

1. **安装与启动**
   - 解压发布 ZIP，校验 SHA-256 manifest。
   - 执行 `codesign --verify --deep --strict --verbose=2`。
   - 首次启动，确认版本、arm64 架构、菜单栏、主窗口、设置窗口、用量窗口与 CLI 帮助可用。
   - 验证未配置真实 Provider 时只使用 Mock，且不访问外网。

2. **数据清空确认（0.0 决策 D8 修订）**
   - 本机从未安装/使用过 mvp 版本 → 无旧数据兼容负担，本步骤以**全新安装**场景执行（首次启动即全新 schema）。
   - 若验收环境存在 mvp 残留，由**手动一次性外部命令**删除目标 SQLite、`-wal`、`-shm`（路径列入验收指引），不进 app 代码、无 app 内确认页。
   - 确认新 schema 正常创建、无旧代码兼容分支报错、无死代码残留。

3. **SwiftUI 功能等价**
   - 创建会话、连续三轮对话、分页加载历史、切换会话、删除单个会话和清空会话。
   - 使用 `/long` 或等价 Mock 长输出，检查流式增量、滚动跟随、上翻不抢滚、取消、恢复、重启后 checkpoint。
   - 调整窗口至窄屏与多显示器，验证布局、字体、侧栏、键盘导航和 VoiceOver 标签。
   - 编辑合法与非法配置，确认非法配置不覆盖最后有效配置，合法配置原子生效。

4. **跨应用后台 Action**
   - 在 TextEdit、Notes、Safari 网页文本中分别选中文本并执行 Action；确认正确捕获、源应用保持前台、Consolepilot 不抢焦点。
   - 在无选区、辅助功能未授权、权限运行时撤销、安全输入、排除应用、模拟复制失败下执行；确认不发送旧剪贴板内容，错误文案明确且可恢复。
   - 连续触发、同时触发两个不同 Action、切换显示器、休眠唤醒后重复执行；确认会话隔离、任务可取消、无重复通知与无资源残留。
   - 分别验证 `autoShow = false/true`、`notifyOnDone = false/true`，确认窗口与通知严格符合配置，通知不包含正文。

5. **真实 Provider 与本地集成**
   - 在专用低权限测试 Key 下分别验证 OpenAI-compatible 与 Anthropic 短请求、流式请求、取消、401、429、5xx、断网和超时。
   - 验证请求、日志、数据库、截图中均无密钥或正文泄漏。
   - 使用 CLI 和 LocalServer 的 ask/open/run，验证 Bearer 鉴权、无 token、错误 body、超限 body 和 app 未启动时的失败行为（tail 命令随 D6 移出本轮）。

6. **退出、恢复与卸载**
   - 在捕获中、流式中、配置热重载中分别退出和强制结束；重启后确认状态符合设计、无损坏数据库、无悬挂端口（tail 运行中退出项随 D6 移出本轮）。
   - 运行清理/卸载流程，确认仅删除明确的 Consolepilot 应用、CLI、配置与数据；不删除用户其他文件或 Keychain 项。
   - 完成最终深度代码审查、CI 全绿、性能报告、实机证据归档后，才可标记本计划完成。

## 7. 实施授权前最终确认清单 —— 已确认（2026-09-09）

> 以下各项已于 2026-09-09 由用户逐项确认（决策与证据见 §0 及 `Docs/GATE0-CONFIRMATION.md` §9）。

- ✅ Gate 0 全部通过：TOML 解析器 spike（GATE0 §2）、SwiftUI 桥接验证并入 P0 Step 1（D4）、Provider fixture 以 TransportTests 20 项为契约证据（D5）、数据清空改为手动一次性（D8）。
- ✅ Xcode、签名身份（Apple Development，D1）、macOS 14 实机（D2）可用；独立测试账户仍为验收矩阵开放项，不阻断本机 P0 起步。
- ✅ 破坏性范围（删除旧 SwiftPM 体系、旧 AppKit 页面、废弃配置字段与清空本地数据）已被接受（D8）。
- ✅ P0/P1/P2/P3 功能、测试阈值与实机验收矩阵的未决产品语义已清零（D4–D8）；本轮范围不含 tails、toggleHotkey、launchAtLogin 与 app 内清空页。
- ✅ 本文档即**当前执行计划**；实施中发现任何新增未确定项，立即停止该项工作、补充计划并再次确认。
