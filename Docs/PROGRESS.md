# Consolepilot 开发进度

## P0/P1 阶段（XcodeGen 迁移 + 8-target 拆分 + Action 可靠性）

执行计划：`Docs/PLAN.md`（P0+P1 可直接执行版）；决策登记：`Docs/GATE0-CONFIRMATION.md`（D1–D8）；写法基准：`Docs/CODING-STYLE.md`。

### 状态

| 阶段 | 状态 | 证据 |
|---|---|---|
| Preflight（工具/基线/文档） | 完成 | 见下方基线记录 |
| P0-A 工程化（XcodeGen+Makefile+同构迁移） | 完成 | 见 P0-A 验收记录（2026-09-09） |
| P0-B 入口替换与最小 SwiftUI 骨架 | 完成 | 见 P0-B 验收记录（2026-09-09） |
| P0-C 协议/用例空壳与清理 | 完成 | 见 P0-C 验收记录（2026-09-09） |
| P1-A 8-target 拆分 | 进行中（前置：实体/记录分离完成） | 见 P1 前置记录（2026-09-09） |
| P1-B 领域与存储 | 进行中（实体纯化与 Records 落地；Repository 实现待续） | 见 P1 前置记录（2026-09-09） |
| P1-C 流与并发重建 | 未开始 | — |
| P1-D Provider 统一 contract + fixture | 未开始 | — |
| P1-E Action 生命周期与配置处置 | 未开始 | — |
| P1-F 死代码清理与收尾 | 未开始 | — |

### Preflight 基线记录（2026-09-09）

- 环境：macOS 15.7.9 arm64；Xcode 16.4 (16F6)；Swift 6.1.2；macOS SDK 15.5；部署目标 14.0。
- 工具：xcodegen 2.46.0（`brew install xcodegen` 安装）、swiftlint 0.65.1、periphery 3.8.0、swift-format（Xcode 工具链内，`xcrun --find swift-format`）均可用。
- 迁移基线：SwiftPM 结构 61 个 Swift 文件；`swift test --disable-sandbox` = **77 项：74 通过，3 项失败（受限 shell 已知项）**。
- lint 基线（P0-A 前置 chore 清理后）：swift-format 与 SwiftLint 全仓 **0 违规**；SwiftLint 规则与格式权威 swift-format 对齐（closure_parameter_position/opening_brace/trailing_comma 禁用），Tests 嵌套配置豁免 force 类与长度类规则（XCTest 惯用）。
- 已知失败 3 项（无 GUI/受限 shell 环境，GUI 会话须全绿）：
  1. `InfrastructureTests.testClipboardSnapshotRestoresStringRTFImageAndMultipleItems` — `XCTUnwrap failed: NSPasteboard`（受限 shell 无剪贴板服务）。
  2. `InfrastructureTests.testClipboardSnapshotRoundTripsOneHundredTimes` — 同上。
  3. `InfrastructureTests.testKeychainStoreRoundTripsAndDeletesOnlyTestAccount` — `KeychainError(status: 100001)`（受限 shell 无钥匙串访问）。
- 契约基线：`TransportTests` 20 项全绿，作为 Gate 0.4 Provider contract 证据（独立 fixture 脚本并入 P1-D 建立）。
- 测试明细（77 项分布）：TransportTests 20、ServerTests（含 HTTP/鉴权/CLI 语义）、DatabaseTests、InfrastructureTests（含上述 3 项受限失败）、HotkeyTests、RenderingTests。
- 工作区在此基线后进入 P0-A；后续阶段状态与证据随实施逐段更新。

---

### P0-A 验收记录（2026-09-09）

- 提交：`8d05410 refactor: migrate Consolepilot from SwiftPM to XcodeGen`；`8a775f7 chore: remove SwiftPM entry points and IntelliJ project files`。
- 工程化落地：`project.yml`（唯一编辑源）→ XcodeGen 生成 `Consolepilot.xcodeproj`（Core framework/App/CLI/Tests 5 target；GRDB 7.8.0 + TOMLDecoder 0.4.5 精确锁定，Xcode 侧 `Package.resolved` 已提交）；`Makefile` 为唯一命令入口（bootstrap/test/lint/build/release/clean/xcodegen/drift-check）。
- 构建配置：`Configs/Debug|Release.xcconfig`（Swift 6 严格并发、macOS 14.0、warnings-as-errors、ad-hoc 签名、版本变量）；`Resources/Info.plist` 真实文件，版本走 `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`。
- 同构迁移：61 文件按原目录迁入，业务代码未改；必要适配 = ConfigLoader 默认配置资源定位（Bundle.main → ConsolepilotCore bundle id → 已加载 bundle 兜底，适配 Xcode 资源阶段）；`Bundle.module`/`#if SWIFT_PACKAGE` 分支已随 SwiftPM 删除一并移除。
- 门禁证据（本机 GUI 会话）：
  - `make test`（xcodebuild test）：**77 项全部通过**（含基线 3 项受限 shell 失败项，GUI 会话全绿）。
  - Debug/Release `make build`：`** BUILD SUCCEEDED **`（App + CLI，DefaultConfig.toml 资源已入 App bundle）。
  - `make lint`：swift-format strict 0 违规、SwiftLint strict 0 违规、`xcodebuild analyze` 通过、密钥扫描 0 命中、xcodeproj 漂移检查通过、periphery 仅报告 P0-B/P1 待删旧 UI 层遗留（报告性，`|| true`，P1-F 清零）。
- 清理：`Package.swift`/`Package.resolved`/`Scripts/*` 已删除（旧 SwiftPM 入口不再并存）；`.idea/`、`Consolepilot.iml` 已从工作区移除并 gitignore；README 已更新为 Makefile/XcodeGen 指引。
- 遗留：periphery 旧 UI 层报告项（ConsolepilotRootView/KeychainStore 未用符号/SecretResolver 冗余 public/Rendering 未用符号等）→ P0-B/P1 删除与清理范围；真实签名/notarization 仍按「P0 仅本机验证」策略不在此阶段处理。

---


### P0-B 验收记录（2026-09-09）

- 范围：删除 AppKit `@main`，`ConsolepilotApp: App`（`WindowGroup("main")` + `Settings` 场景）接管；旧根视图经 `RootHostView`（NSViewRepresentable）承载；设置编辑器迁入 SwiftUI `Settings` 场景；菜单栏/状态栏/用量窗口保留 AppKit 入口；`WindowActivationPolicy` 统一激活策略；删除 `ConsoleWindowController`/`DependencyContainer`。
- 引擎根视图生命周期：由 `MainWindowCoordinator` 持有（单例），主窗口关闭/重建不销毁引擎（会话/配置/流状态跨窗口存活）。
- 人工 QA 发现并已修复两项：
  1. **重复主窗口**：旧实现同时保留 AppKit「关闭=隐藏 + `applicationShouldHandleReopen`」与 SwiftUI 原生重建，Dock 重新唤起会出现两个同内容窗口。修复：移除 reopen 处理与关闭拦截，主窗口真正关闭，Dock 唤起由 SwiftUI 重建唯一窗口并重新挂载同一引擎根视图。本机验证：关闭主窗口后经 `open -a` 唤起连续 3+ 轮均只出现 1 个主窗口。
  2. **Settings 不适配窄屏**：竖屏副屏（540×960 逻辑点）下 Settings 以 880pt 理想宽度打开，右半（按钮/滚动条）落到屏外。修复：`SettingsWindowLayout` 收敛规则 + 屏幕感知 `intrinsicContentSize`（窗口挂载/成为 key/换屏时收敛到可见区域，顶部对齐保证标题栏可拖拽）。本机验证：内建屏打开=900×668；拖到 540 宽副屏自动收敛为 508×668 且完整可见；无抖动/循环。
- 门禁证据（本机 GUI 会话，2026-09-09）：
  - `make test`：**77 项全部通过**。
  - `make build`（Debug）：`** BUILD SUCCEEDED **`；`make lint`：swift-format/SwiftLint strict 0 违规、`xcodebuild analyze` 通过、漂移检查通过。
- 完成判定（2026-09-09）：两项修复已按原报告场景在本机 GUI 会话验证——Dock 重新唤起连续 3+ 轮均只出现 1 个主窗口；Settings 在 540×960 竖屏副屏自动收敛为 508×668 完整可用、拖拽跨屏无抖动。你的顺手复查并入 P1 暂停窗口，不再阻断后续阶段。

---

### P0-C 验收记录（2026-09-09）

- 提交：`144032f style: rename main window root view backing storage for strict lint`（P0-B 遗留 `_rootView` 标识符违反 SwiftLint strict，先行清理）；`4461e1f refactor: add domain/application contracts and placeholder use cases (P0-C)`。
- 契约空壳（不接线、不改变现有运行路径）：
  - `Sources/Domain/Repositories/`：`SessionRepository` / `UsageRepository` / `CaptureAuditRepository` / `ConfigurationRepository` 四个协议（Session/Message/UsageRecord/UsageSummary/CaptureLogEntry/AppConfig 均为既有领域类型）。
  - `Sources/Domain/UseCases/`：`ConversationUseCase`（send/cancelCurrent + `ConversationRequest/Response`）、`ActionExecutionUseCase`（run + `ActionExecutionRequest/Response`）协议与纯值类型。
  - `Sources/Application/`：`ConversationUseCasePlaceholder` / `ActionExecutionUseCasePlaceholder` 占位实现，一律抛 `AppError.notImplemented`。
  - `project.yml` 增加 `Sources/Application`（Core 过渡承载；P1-A 拆分独立 Application target）。
- 错误模型：`AppError` 新增 `.notImplemented(String)` 并按 CODING-STYLE §3 统一扩展四要素（稳定 `code` / `userMessage` / `recoverySuggestion` / 脱敏 `diagnostic`）；嵌套层错误仅保留既有 `userMessage`，逐层四要素补齐列入 P1。
- 契约测试（每空壳一条）：`Tests/UseCasePlaceholderTests.swift`（2 项，断言抛 `.notImplemented` 且 `code == "notImplemented"`）、`Tests/RepositoryContractTests.swift`（4 项，内存 fake 固定会话/消息生命周期与分页、用量聚合、仅元数据捕获审计、配置 reload 失败保留最后有效）。
- 门禁证据（本机 GUI 会话）：`make test` **83 项全部通过**（77 基线 + 6 新增）；`make build` `** BUILD SUCCEEDED **`；`make lint` 全绿（swift-format/SwiftLint strict 0 违规、analyze 通过、密钥扫描 0 命中、漂移检查通过；periphery 报告性项 `|| true`）。
- periphery 报告性遗留（P1 接线后自然消失，P1-F 清零）：四协议「未作为 existential 使用」、占位实现未用参数（占位为 P0-C 有意空壳，测试已固定其存在与契约方向）。
- 清理确认：`DependencyContainer` 无源码/工程引用（仅历史文档提及）；旧 SwiftPM `Package.swift`/`Scripts/` 无残留；无 `import ConsolepilotCore` 之外的旧模块引用。

---

### P1 前置记录（2026-09-09）：Domain 纯度前置——实体与 GRDB record 分离

- 提交：`68588a8 refactor: split domain entities from GRDB records (P1-A purity foundation)`。
- 背景：P1-A 的目标拆分要求 `ConsolepilotDomain` 纯净（禁 GRDB/AppKit），但 Session/Message/Usage/CaptureLog 四模型当时是 GRDB record，且 P0-C 的 Repository 协议引用这些实体——因此目标拆分（A）与「实体迁入 Domain、record 只存 Infrastructure」（B）在物理上必须交织执行，先完成本前置。
- 落地：
  - `Sources/Domain/Models/`：`Session`/`Message`/`Usage`（原 `UsageRecord` 更名）/`CaptureLogEntry` 现为纯值类型（Identifiable+Sendable+Equatable，无 GRDB）；`ProviderKind`、`CaptureStrategy` 从 `Infrastructure/Config/ConfigSchema.swift` 迁入 Domain。
  - `Sources/Infrastructure/Database/Records/`：新增 `SessionRecord`/`MessageRecord`/`UsageRecord`/`CaptureLogRecord`（GRDB FetchableRecord+MutablePersistableRecord，含 Columns/`init(_ entity:)`/`entity` 映射）。
  - 消费者适配：`SessionStore`/`UsageStore`/`CaptureLogStore` 与 `StreamCoordinator` 经 record 持久化、以实体对外；`UsageRepository` 协议参数改为 `Usage`。
- 门禁证据（本机 GUI 会话）：`make test` **83 项全部通过**（行为与数量不变）；`make build` 通过；`make lint` 全绿（含漂移检查）。
- 待续：P1-A 目标创建与文件归位（含 import 方向扫描）、P1-B 四个 Repository 的 SQLite 实现 + AppConfig 迁 Domain。

---

### 更新日期与继续执行

本文件是 `Consolepilot_plan_v4.0.md` 的执行看板。状态只按里程碑 DoD 判断：文件存在不等于完成，缺少测试、实机证据或门禁时统一标为“部分完成”。

## 当前结论

- 当前阶段：Mock 核心对话链路、LocalServer/CLI、配置菜单与 Keychain 行为已通过人工验收，进入 M11 收尾与最终门禁准备。
- 当前可用：App 启动、会话持久化/切换/删除/清空、本地 Mock 流式输出、中断入口、历史恢复、左右聊天气泡、基础 Markdown、深色副屏 UI。
- 当前不可视为交付：真实 Provider 实机复核、跨 App Action 实机矩阵、Onboarding、完整门禁与干净账户交付复核。
- 自动化现状：`swift test` 73 项通过；Release 构建和 ad-hoc 签名通过。SwiftLint/format/periphery/覆盖率/性能门禁尚未全绿。
- 2026-08-28 性能修复：消息改为每页 12 条、上滚加载更早页面；流式 UI 以 50ms 批次刷新；Markdown 仅终态渲染；气泡尺寸与 Markdown 结果缓存。实机采样进一步确认超长 CJK 回复的 `NSTextField/NSTextLayer` 整块重绘是残余热点，正文已改为支持增量 TextKit 存储的 `NSTextView`。新版 Release 空闲采样未出现旧热点，RSS 约 70MB、physical footprint 约 35MB；A17/A18 仍等待用户交互复测，不据此自动判定通过。
- 2026-08-28 气泡高度回归修复：用户实测发现切换会话或长回复完成后气泡残留大面积空白。根因是 CoreText 预测高度与 TextKit 实际布局不一致，以及跨气泡复用高度缓存时新 `NSTextView` 尚未在最终宽度完成布局。现统一使用各气泡自身 TextKit `usedRect` 测量，测量前按最终宽度失效并重排；保留 Markdown 富文本缓存、取消跨视图高度缓存。已动态验证 `/long` 生成中、完成态、重启恢复及离开后切回四条路径，A17 仍等待用户确认。
- 2026-08-28 气泡宽度规则优化：只有真实宽度能放入单行的短消息按内容收缩；含换行或单行宽度超过上限的消息使用对话区完整可用宽度，再由 TextKit 计算实际高度。副屏隐藏/展开侧栏和 `/code` 长短气泡已截图复核，新增宽度策略回归测试；自动化现为 33 项通过。
- 2026-08-28 流式检查点与切换恢复修复：流式助手消息使用固定消息 ID 定期 upsert 到数据库，Control+C、窗口切换和退出前均保留已接收内容；切换活动会话时从历史列表排除该检查点，只渲染唯一的内存活动草稿，避免出现截断回复与实时回复重复显示。会话列表按 `updatedAt + id` 稳定排序。A19/A20 待人工复测。
- 2026-08-28 早期中断竞态修复：`Control+C` 现在先同步 flush/checkpoint 再取消 provider；若流在未发出 `.finished` 前正常结束，也按 `interrupted` 保存已接收前缀。A19/A20 人工复测通过。
- 2026-08-28 M2 配置基础门禁：启动时解析并校验配置；非法 reload 保留上一份有效配置；文件监听对编辑器原子替换事件做合并重载并自动重绑 inode。新增 20 次原子替换测试，自动化现为 37 项通过。配置生命周期已接入 App 启动，后续可接主题、快捷键和 LocalServer。
- 2026-08-28 聊天体验优化：Mock 普通助手回复不再重复回显用户输入；每个聊天气泡右下角新增快捷复制按钮，复制内容保留原始 Markdown（适合代码块直接粘贴），点击后显示短暂已复制反馈。新增 Mock 文案回归测试，自动化现为 38 项通过。
- 2026-08-28 复制按钮交互优化：复制按钮改为鼠标悬停手型光标，并叠加在气泡底部内边距中，不再单独占用一行；正文高度同步收紧，避免额外留白。
- 2026-08-28 复制按钮遮挡修复：正文 TextKit 增加底部安全内边距并调整气泡高度，最后一行即使铺满整行也不会与右下角复制按钮重叠；按钮仍保持悬浮、不单独占行。
- 2026-08-28 复制按钮布局二次修复：将按钮占用区域纳入正文 TextKit 的有效宽度计算，长行会在按钮左侧自动换行；移除可能导致溢出的额外文本 inset，并增加真实 tracking area，悬停即显示手型光标。
- 2026-08-28 M5/M6 本地校验增强：OpenAI/Anthropic 共用 HTTP 状态码映射；Anthropic 请求改用 `x-api-key`/`anthropic-version`；超时、取消、网络错误不再笼统归为断连；Provider 对畸形 SSE JSON 发出 typed decoding failure；缺失终止帧（OpenAI `[DONE]`、Anthropic `message_stop`）视为断连；新增 1000 delta 合帧零丢字断言。真实 API、TCP 断开 `lsof` 证据仍待用户授权和实机批次验收。
- 2026-08-28 M6 trace/中断门禁增强：AppDatabase 支持可注入 SQL trace；新增断言确保流式期间无 INSERT/UPDATE，终态才写入；Control+C 中断压力测试确认多段前缀完整落库且状态为 `interrupted`。M6 仍缺真实长流 trace 采样与更广泛压力基线。
- 2026-08-28 M2 校验矩阵增强：新增核心 V1–V23 规则组合测试（重复 ID、引用/快捷键冲突、范围、主题、捕获、服务鉴权、远程密钥策略与无 AX 警告）；模板引擎支持 `appBundleId/time/datetime/lang` 及 `env:` 占位符，并对缺失环境变量在校验期报错。完整 V1–V23 fixture 文件与 Keychain 实机持久性仍待补齐。
- 2026-08-29 侧栏竖线修复：确认黑线来自隐藏侧栏后 AppKit 仍绘制旧 divider；新增 `SidebarSplitView` 仅在隐藏状态跳过 divider 绘制，不改 divider position、pane frame 或宽度持久化，避免再次破坏收起/展开状态。已通过全量测试、Release 构建和签名校验，待用户实机确认视觉效果。
- 2026-08-29 M2 安全/热重载门禁增强：Keychain 唯一临时账号读写、更新、删除回归测试并自动清理；补充缺失 Keychain 引用、toggle 冲突/空值、tail 父目录和“仅有效 reload 触发 onChange”测试。当前 M2 仍缺独立 V1–V23 fixture、配置 UI 与签名环境下的 Keychain 持久性证据。
- 2026-08-29 M8 Action 链路增强：新增配置 overrides 范围校验；完成配置 → 模板渲染 → ActionRunner → Mock Provider → StreamCoordinator → SQLite 的端到端回归测试；新增选中文字模板与新会话回归测试。真实跨 App 捕获仍待用户实机验收。
- 2026-08-29 M8 运行时接线：App 现已启用 Carbon 全局 Action 快捷键注册；快捷键触发后执行真实 `ActionRunner`，捕获选区、渲染预设提示词、创建新会话、前台展示并流式回复；配置热更新会原子替换快捷键注册表。跨 App 与权限仍需实机验收。
- 2026-08-29 选区捕获回归修复：模拟 `⌘C` 现在必须检测剪贴板 changeCount 变化，避免目标 App 不响应时误用历史剪贴板；`input = "selection"` 不再降级到普通 clipboard 策略，失败时明确提示而不提交错误上下文。新增 stale clipboard 回归测试。
- 2026-08-29 Action 静默捕获增强：模拟复制改为带 12ms 键间隔的真实 Carbon `⌘C` 按键对，并在捕获完成后恢复剪贴板；Action 不再激活 Consolepilot，保持原前台 App 和主屏安静，输出仅更新已打开的副屏窗口。
- 2026-08-29 定向复制增强：记录快捷键触发瞬间的前台进程并用 `CGEvent.postToPid` 定向投递 `⌘C`，等待窗口至少 500ms；捕获日志仅记录 PID、changeCount 和字符数，便于诊断而不记录正文。
- 2026-08-29 M7 捕获链路增强：TextCaptureService 支持可注入策略并验证配置顺序 fallback、截断元数据、安全输入提前阻断与无权限错误保留；FrontmostAppObserver 在具备 AX 权限时读取窗口标题；新增 CaptureLogStore，只落 App/Bundle ID/字数/策略/耗时等元数据，数据库无正文列。跨 App 15 项矩阵仍待用户实机验收。
- 2026-08-29 M3 性能门禁增强：新增 10,000 条消息最新页查询 P95 < 20ms 回归测试，验证分页索引路径不会全量加载历史。
- 2026-08-29 M7/M8 运行时增强：捕获链路保留具体权限/安全输入/排除应用错误并提供稳定用户文案；Action 可记录捕获元数据；RuntimeBindings 支持 Carbon 全局注册、统一注销和退出清理；无快捷键配置时不会注册任何组合键。
- 2026-08-29 M3/M10 门禁增强：新增 10,000 条消息分页查询性能回归；CaptureLogStore 接入元数据写入；CLI 继续保持安全的 Mock/占位行为，避免在真实 Provider 和本地服务未完成前产生网络或副作用。
- 2026-08-29 运行时安全与接线修复：ActionRunner 支持通过 provider resolver 读取热重载后的 Provider 映射；新增辅助功能权限提示入口；修复配置环境变量错误文案与存储/服务错误的稳定用户提示；SwiftPM App 产品名与发布二进制统一为 `Consolepilot`。Release 构建、签名及 73 项测试通过。
- 2026-08-29 M10 IPC 首次接线：LocalServer 支持注入闭包路由和已解析 token；App 在数据库与 Mock Runtime 初始化后按配置尝试启动回环服务，提供 `/ask`、`/open`、`/push` 基础路由；CLI `ask/open/run/tail` 改为通过 Bearer 鉴权请求 LocalServer，缺少 token 时安全提示并保留 `open` fallback。默认配置未写入 token，因此默认不会启动服务或访问网络；Release 构建与签名通过。
- 2026-08-29 M10 功能链路补齐：App LocalServer 增加 `/run` action 执行与 `/tail` 文件尾随路由；CLI 从已验证配置读取 Keychain token（环境变量仍可作为降级），tail 行进入独立日志会话，退出时停止 watcher/server。Mock Provider 保持默认，完整测试 66 项通过，Release 产物已重新签名。
- 2026-08-29 M9 命令入口补齐：控制台输入支持 `/help`、`/new`、`/clear`、`/stop`、`/sessions`，命令在本地处理并不触发网络请求；命令执行与普通对话路径隔离。全量测试 66 项通过。
- 2026-08-29 P8 回归修复：CLI/HTTP 创建的会话现在会立即切换到主界面；`run` action 执行后自动显示新会话；Tail 同一路径复用单一日志会话，避免每行创建会话；`/code` 与 `/long` 保留为 Mock 对话命令而非 slash 管理命令；LocalServer 启动成功/失败会在状态栏明确反馈。Release、签名及 66 项测试通过。
- 2026-08-29 完成状态可追溯：Mock 与真实流结束后，状态栏按会话保留最终字符数和 `finish_reason`，切换会话不会被“就绪”状态覆盖；下一轮生成开始时清除旧完成状态。`MockAIProvider` 发送 `finishReason("stop")`，并通过 71 项测试与 Release 构建。
- 2026-08-29 状态栏指标补充：完成状态增加首字延迟与总耗时，格式保持单行简洁并随会话持久保留；首字延迟由首个 delta 记录，总耗时由流协调器统一计时。
- 2026-08-29 P8 真实链路回归：修复 CLI/Action 会话切换时序、Tail 行会话复用及 `/long`/`/code` 命令误判；LocalServer 改为等待 NWListener ready/failed 状态后报告启动结果，增加 loopback HTTP 鉴权集成测试，测试总数 67 项通过。
- 2026-08-29 P8 Action UI 回归修复：`run ask`/Action 创建会话后立即建立助手气泡，流式 Mock 增量可在当前会话实时显示；此前仅用户气泡可见但数据库已写入的问题已覆盖。新增 App 菜单“设置…”与“打开辅助功能设置”，移除侧栏权限按钮；设置窗口直接编辑现有 TOML，保存后由 ConfigStore 校验并热重载。LocalServer 启动复用已解析 token，避免服务启动阶段重复读取 Keychain；新写入 Keychain 项目使用 `kSecAttrAccessibleAfterFirstUnlock`。
- 2026-08-29 人工验收确认：A22–A29、P8 全部通过，复制按钮、Action 助手实时回复、设置菜单、辅助功能菜单及 Keychain 行为完成实机复测。
- 2026-08-29 M11 收尾启动：补齐 CONFIG、SHORTCUTS、TROUBLESHOOTING、FUTURE-PROXY、PERF-BASELINE 文档，并更新 README 的 Mock 默认、安全配置和诊断入口。自动化测试/Release 签名保持通过；D1–D8、长稳运行、真实 Provider、Carbon 快捷键与干净账户交付仍待最终门禁。
- 2026-08-29 设置编辑器优化：移除无效的左侧说明栏，将中文字段说明和 Profile/Action/Tail 全字段示例放入 TOML 注释；设置窗口使用标准 NSTextView 编辑/选择/撤销和可滚动文档，增加未保存状态、保存更改/放弃更改/重新读取按钮，并在保存前执行 TOML 与配置规则校验。旧配置首次打开会自动追加高级配置参考注释，不覆盖原有有效值。
- 2026-08-29 设置操作栏尺寸修复：保存更改、放弃更改、重新读取统一为 116pt 固定宽度，避免保存状态切换或状态文字变化造成按钮跳变。
- 2026-08-29 设置保存崩溃修复：从用户 DiagnosticReports 确认 TOMLDecoder 在非法整数（如 `port` 被编辑为空/非数字）路径中发生强制解包。ConfigLoader 增加整数配置项预检，设置保存现在会显示校验错误并保持 App 运行，不再进入 TOMLDecoder 崩溃路径。
- 2026-08-29 设置合法保存二次修复：最新崩溃报告显示 TOMLDecoder 0.3 的 `UInt16` 解码器即使读取合法端口也会触发内部 force unwrap。`RawGeneral.port` 改为先解码 `Int`，完成范围校验后转换为 `UInt16`，绕开第三方库的崩溃实现。
- 2026-08-29 设置保存崩溃三次修复：最新报告仍落在 TOMLDecoder `Token.unpackInteger` 的 `withContiguousStorageIfAvailable` 强制解包，确认 NSTextView 桥接字符串触发该库缺陷。解析入口和设置保存入口现在都通过 `String(decoding: text.utf8, as: UTF8.self)` 规范化原生 UTF-8，再进入 TOMLDecoder；合法值与错误值均应转为可显示错误而非进程崩溃。
- 2026-08-29 设置保存最终验收：用户确认合法修改保存不再崩溃，A34 关闭。新增编辑器样式字符串解析回归测试，防止 TOMLDecoder 桥接字符串问题复发。
- 2026-08-29 M11 门禁首轮：`swift test` 增至 69 项并通过；`swift build`、Release 打包、签名校验和差异检查通过。SwiftLint 当前报告 186 项历史格式告警，Periphery 因上游归档不可用，D4/格式门禁继续保留为交付前清理项。
- 2026-08-29 M10 尾随错误处理：`/tail` 现在在启动 watcher 前验证文件存在，不存在路径返回 HTTP 422 并在 CLI 显示错误，不再先返回 accepted 后静默失败；新增缺失文件回归测试。
- 2026-08-29 M9 用量入口：新增 App 菜单“用量统计…”及原生统计窗口，展示今日/近 7 天/全部请求数、输入输出 Token 和费用，可手动刷新；复用现有 UsageStore，不改变流式链路。
- 2026-08-29 用量窗口视觉修复：用量窗口强制跟随 Consolepilot 深色外观，内容区域增加深色背景并提升文字对比度，修复系统浅色外观下统计文字几乎不可见的问题。
- 2026-08-29 用量报告范围调整：按产品核心需求移除 UI 中金额统计，仅保留今日/近 7 天/全部请求次数及输入/输出 Token；费用不再作为产品报告或验收指标。后续开发重心回到真实 Provider、跨 App 捕获、全局快捷键和稳定性核心验收。
- 2026-08-29 核心 Provider 接线：RuntimeBindings 现在按 Profile 的 Base URL 区分本地 Mock 与远程 Provider；回环地址继续使用 Mock，非回环 OpenAI/Anthropic Profile 自动绑定真实 SSE Provider。默认配置行为不变，真实请求仍需用户配置安全密钥并进行实机授权验收。
- 2026-08-29 验收前收尾：补齐菜单栏 Consolepilot 常驻入口、快速提问面板、Profile 菜单切换和输入历史（Option+↑/↓，最近 100 条持久化）；控制台发送路径按所选 Profile 解析安全密钥并绑定对应 Provider。`swift test` 70 项通过，Release 构建与签名通过。
- 2026-08-29 CLI 安装脚本修复：安装前自动创建 `/usr/local/bin`，避免全新 macOS 环境因目标目录不存在而失败；脚本语法检查和 66 项测试通过。
- 2026-08-29 验收问题修复：设置窗口增加窄屏最小尺寸、自动换行和水平滚动兜底；配置热重载后立即刷新 Profile 菜单，新增 `Docs/ACCEPTANCE-GUIDE.md`，包含当前配置、Keychain/API Key 对应关系及完整人工验收步骤。70 项测试与 Release 构建签名通过。
- 2026-08-29 真实 SSE 流式修复：OpenAI/Anthropic Provider 改为直接消费 `URLSession.AsyncBytes`，按字节/换行即时解析 SSE，避免 `bytes.lines` 额外缓冲；ChatTranscriptView 移除全量 TextKit 布局失效和额外 50ms 二次缓冲，长回复按合帧即时渲染。请求补齐 `top_p`/频率惩罚参数。70 项测试与 Release 构建签名通过，待 ChatAnywhere 实机复测。
- 2026-08-29 Mock/安全开关增强：Mock 对 `/long`、3000 字和“10 段”提示生成 24 段可控长流，支持滚动/中断/恢复验收；新增 `[general].allowRealProvider`（默认 `false`）作为真实 API 唯一开关，移除隐藏环境变量依赖。`[DONE]` 终止帧回归测试保留，71 项测试通过。
- 2026-08-29 首字节可观测性：流协调器记录并显示 Provider 连接、等待首字节和首字节延迟；助手气泡增加“正在连接 Provider…”占位，避免高 TTFT 时看起来卡死。最新 71 项测试与 Release 构建签名通过。
- 2026-08-29 Loading 占位修复：首个真实 delta 到达时清除助手气泡中的“正在连接 Provider…”占位文本，避免 Mock/真实流式回复把状态文案误显示为正文。71 项测试与 Release 构建签名通过。

## 里程碑看板

| 里程碑 | 状态 | 已有能力 | 达到 DoD 仍缺 |
|---|---|---|---|
| M1 工程骨架 | 部分完成 | SwiftPM App/CLI、基础设施、构建测试脚本、可启动窗口 | `Consolepilot.xcodeproj`、完整依赖容器接线、Swift 6 complete 与全部 G1–G3 证据 |
| M2 配置系统 | 部分完成 | Schema、Loader、Validator、Store、默认配置、Secret/Keychain 基础代码、核心 V1–V23 组合测试、环境占位符校验、TOML 设置窗口 | 完整 V1–V23 独立 fixture、首次生成证据、签名环境下 Keychain 持久性实测 |
| M3 数据层 | 部分完成 | SQLite/GRDB、迁移、WAL、会话/消息/用量持久化、消息分页与上滚加载、1 万条最新页查询 P95 < 20ms 回归测试 | Store 完整测试、最终 schema/迁移审查 |
| M4 渲染引擎 | 部分完成 | ANSI/Markdown、聊天气泡、增量追加/scrollback、深色输出、Mock 长文本可视 | 完整 CommonMark 覆盖、S2 性能阈值、10 万行内存、光标局部重绘证据、Renderer 回归测试 |
| M5 Transport | 部分完成 | SSE 解码、请求构建、OpenAI/Anthropic 基础实现、本地 Mock、统一错误映射、超时/取消语义、畸形 JSON/缺失终止帧回归测试 | 真实调用、取消 TCP 断开 `lsof` 证据、真实断连 fixture、完整畸形 SSE 行计数 |
| M6 StreamCoordinator | 部分完成 | 17ms 合帧、终态落库、用量记录、Mock 延迟集成测试、1000 delta 零丢字/更新计数回归测试、SQLite trace 与中断前缀完整性测试 | 真实长流压力基线、架构审查确认无旁路 |
| M7 文本捕获 | 部分完成 | AX/模拟复制/剪贴板快照/权限/安全输入、fallback/截断/权限测试、窗口标题、仅元数据捕获日志 | S1 跨 App 实机矩阵、运行时撤权检测、可点击权限提示、App Action 实机链路 |
| M8 Action/快捷键 | 部分完成 | TemplateEngine、ActionRunner、HotkeySpec/Registry 基础测试、配置到 Mock Provider 端到端链路、overrides 校验、RuntimeBindings 热更新接线、Carbon 运行时注册 | 跨 App 捕获实机矩阵、冲突/撤权/稳定性验收、反馈先于网络 |
| M9 窗口与 UI | 部分完成 | 主窗口、可调/可隐藏侧栏、紧凑模式、聊天气泡、会话切换/删除/清空、Cmd+Q/W、窗口重开、设置/辅助功能/用量菜单入口、TOML 配置编辑器、菜单栏、QuickAsk、输入历史、Profile 菜单切换 | Onboarding、命令面板、副屏位置恢复 |
| M10 LocalServer/CLI | 部分完成 | LocalServer/FileTailWatcher 基础实现与部分测试、可注入闭包路由、CLI 产品、基础帮助/命令占位 | App 自动启动服务、IPC 鉴权接线、ask/open/run/tail 全功能、轮转端到端 |
| M11 交付 | 未完成 | build/bootstrap/sign/install 脚本雏形、README/SPIKE 文档雏形 | 全部交付文档、D1–D8、R1–R24、T1–T5、P1–P10、Instruments、干净账户验收 |

## 当前人工验收窗口

只验收已经实现的 Mock 子集；未实现项不要求用户操作。

1. 普通 Mock 流式：发送普通中文，确认逐块出现且完成后恢复输入。
2. 富文本边界：发送 `/code`，确认代码块、CJK、English、emoji 可见且无乱码。
3. 长输出与滚动：发送 `/long`，确认停在底部时持续跟随；主动上翻时不抢滚动。
4. 中断：发送 `/long` 后按 Control+C，确认快速停止、已收内容保留、输入恢复。
5. 多轮：同一会话连续三轮，消息顺序正确。
6. 会话：新建第二会话、来回切换，内容互不串线。
7. 恢复：Command+Q 后重开，历史与当前会话恢复。
8. UI：新建按钮清晰、会话标题左对齐、滚动条无白色轨道、侧栏可调和隐藏。

验收结果记录在 `Docs/ACCEPTANCE.md`。A1–A12 已全部通过；用户补充的会话删除/清空与聊天式 Markdown 展示正在实施，完成后开发自动进入 M2–M8 补齐阶段。

## 下一实施顺序

1. 完成 M11 交付文档与性能基线：CONFIG、SHORTCUTS、TROUBLESHOOTING、PERF-BASELINE，并补齐 README 安装/升级/卸载说明。
2. 运行 D1–D8、R1–R24、T1–T5 门禁，修复 SwiftLint/format/periphery 与覆盖率缺口。
3. 完成真实 Provider 可配置接线；默认继续使用 Mock，真实调用前由用户明确授权。
4. 完成跨 App 捕获与 Carbon 全局快捷键实机注册验收。
5. 完成 Onboarding、用量/命令面板、菜单栏、QuickAsk 与窗口状态恢复。
6. 执行 P9 稳定性、权限持久性、睡眠唤醒、强制退出恢复测试。
7. 在干净用户账户完成 P10 全量交付复核，生成最终 zip 与安装指引。

## 进度维护规则

- 每次功能合入同步更新本文件的状态和缺口。
- 每个里程碑只有 DoD 与 G1–G3 全部满足后才标记“完成”。
- 人工验收失败记录具体步骤、截图/日志与修复版本，不用口头“看起来通过”代替证据。
- 真实 API 调用、系统权限授予、断网/拔屏、干净账户和 Instruments 等必须由用户实机配合的项目，集中成批请求，不零散打断开发。

### P1-A S1 记录（ConsolepilotDomain 提取，2026-09-09）

- 提交：`68588a8`（实体/记录分离前置）、`64e0c30`（记录）、`b803d05 refactor: extract ConsolepilotDomain module with pure config/models and migrated AppError/Log/HotkeySpec/TemplateEngine`。
- ConsolepilotDomain target（静态 framework）建立：Sources/Domain/{Models,Repositories,UseCases,Config} + TemplateEngine/AppError/Log/HotkeySpec；Domain 纯值类型/协议/错误全部 public 化（跨模块访问所需；P1-E 清理废弃字段后按需回收可见性）。
- 纯化：FrontmostInfo/UsageSummary 移入 Domain；UsageStore 不再定义 UsagePeriod/UsageSummary；GRDB record（*Record.swift）留在 Infrastructure 并与实体分离。
- 门禁：`make test` 83 项全绿；swift-format strict / SwiftLint strict / xcodebuild analyze / 密钥扫描全过；xcodegen 漂移幂等。
- 遗留（后续 slice）：Domain 目录下 ActionRunner/StreamCoordinator/Stores 因依赖 AppKit/GRDB 暂编入实现层，P1-C/E 重写时归位。

### P1-A 验收记录（多模块拆分完成，2026-09-09）

- 提交：`b803d05`（Domain 提取）、`e045c8e`（Application 提取）、`25774ed`（Infrastructure/LegacyUI 拆分，溶解 ConsolepilotCore）、`c9bd6e7`（测试 import 清理）、docs 本段。
- 最终 target 集（7 个，Presentation/UITests 留 P2）：
  1. `ConsolepilotDomain`：Sources/Domain（Models/Repositories/UseCases/Config + TemplateEngine/AppError/Log/HotkeySpec），纯值类型/协议，禁 UI/GRDB/Network/Keychain。
  2. `ConsolepilotApplication`：Sources/Application（两个用例占位实现，P1-C/E 前不接线）。
  3. `ConsolepilotInfrastructure`：Sources/Infrastructure + Sources/Transport + Sources/Infrastructure/Stores；GRDB 记录/Stores/配置/捕获/密钥/HTTP+SSE Provider；ActionRunner 与 StreamCoordinator 因仍耦合 AppKit/GRDB/Transport，作为过渡文件居于此模块，P1-C/E 重写后归位 Application。
  4. `ConsolepilotLegacyUI`：Sources/LegacyUI（原 Infrastructure/Presentation + Rendering 共 10 文件），遗留 AppKit UI + 渲染过渡组，P2 删除。
  5. `Consolepilot`（App composition root + SwiftUI 生命周期）；6. `consolepilot` CLI；7. `ConsolepilotTests`。
- 关键实现决策（本次新增、已按「干净/可测试」落地）：
  - 跨模块可见性统一 `package`（project.yml base `OTHER_SWIFT_FLAGS = -package-name Consolepilot`），避免扩大 public API；Domain 早期 public 化保留至 P1-E 清理废弃字段时再回收。
  - 遗留 UI 不放进 App 可执行模块：Xcode 可执行模块不可被 hosted 单测 `@testable import`（实测 `no such module`，DEFINES_MODULE/SWIFT_EMIT_MODULE 无效），故遗留组单独成框架 `ConsolepilotLegacyUI` 保证 RenderingTests 可测；P2 删除该模块即完成过渡。
  - `make lint` 新增 `Scripts/check-imports.py` 依赖方向门禁：逐文件校验 Consolepilot 模块族 import 不得向上/越层（当前 0 违规）。
- 门禁证据：`make test` 83 项全绿；`make build` Debug 全 target 通过；`make lint` 全绿（drift/swift-format/SwiftLint/analyze/密钥扫描/import 方向零违规；periphery 报告仅 `|| true` 记录——因 `package` 跨模块引用 periphery 误报为未使用，P1-F 清零时按真实引用复核）。
- 残留（明确归属后续阶段）：Transport `[String: Any]` DTO → P1-D 强类型化；ActionRunner/StreamCoordinator 过渡居所 → P1-C/E；periphery 误报清单 → P1-F；旧 SwiftPM 模块名 `ConsolepilotCore` 全仓库 grep 为 0。

### P1-B 验收记录（Repository 实现，2026-09-09）

- 提交：`d4babc2 feat: implement SQLite/file repositories on Domain contracts (P1-B)`。
- 新增 `Sources/Infrastructure/Repositories/`：
  - `SQLiteSessionRepository`（fetchSessions/fetchSession/fetchMessages 最新在前分页/search/save/delete 级联）。
  - `SQLiteUsageRepository`（record + fetchSummary 按 today/week/all 周期过滤聚合）。
  - `SQLiteCaptureAuditRepository`（只落元数据，无正文列）。
  - `FileConfigurationRepository`（解析+校验通过才原子替换 current；失败抛 ConfigError 且保留最后有效配置；无文件监听，UI 热重载仍由 ConfigStore 负责）。
- `UsageAggregator` 抽为 Stores 与 Repository 共用，消除汇总规则重复。
- 门禁：新增 `Tests/SQLiteRepositoryTests.swift` 7 项（temp-file SQLite 每次隔离=内存库语义、WAL journal 断言、分页边界、重开持久化 checkpoint、用量周期聚合、审计仅元数据、配置 last-good）；**90 项全绿**。
- 依赖门禁加强：`Scripts/check-imports.py` 现同时禁止 Domain/Application import GRDB/AppKit/SwiftUI/Security/Network/Carbon/TOMLDecoder/Observation/CoreText/Combine（纯净层约束），当前 0 违规。
