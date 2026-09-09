# Consolepilot Gate 0 实施前确认报告（已确认版 · 决策 D1–D8 已登记）

> 依据：[PLAN.md](PLAN.md)（《Consolepilot 重构、交付与严格验收实施计划》，已确认版 · 决策 D1–D8）第 4 节
> Gate 0 与第 7 节「实施授权前最终确认清单」。
>
> 本报告只做**实施前确认与可行性验证**，未修改任何生产代码、未删除任何数据、未改变 Git 仓库内容。
> 任何标为「需用户决策」或「未执行」的条目，在用户明确确认前均阻断 P0 生产代码变更。
>
> **更新（2026-09-09）**：用户已逐项确认 D1–D8（见 0.1 决策登记）。本文保留原始审计证据并登记决策。
> **P0 生产代码变更尚未开始**，动手前将先给出 P0 第 1 步落地清单。

- 日期：2026-09-09
- 执行环境：macOS 15.7.9 (24G830)，Apple Silicon (arm64)
- 对照计划：`Docs/PLAN.md`（已确认版 · 决策 D1–D8 已登记）；旧版计划 `Docs/Consolepilot_plan_v4.0.md` 为现状对照

---

## 0. 总览

| Gate 0 项 | 结论 | 说明 |
|---|---|---|
| 1. 工具链 / 签名 / 设备 / 测试账户 | ✅ 本机侧通过（D1–D3） | 本机工具链满足；Apple Development 证书已生成并验证生效；macOS 14 实机已提供；独立测试账户属验收矩阵开放项 |
| 2. TOML 解析器 spike | ✅ 本机通过（附约束） | 锁定版 TOMLDecoder 0.4.5 在 10k 合法 + 并发 + 非法语料下零崩溃；错误描述可定位（含行号），应用侧错误提取需小幅加强 |
| 3. SwiftUI 最小原型 | ✅ 已确认并入 P0 第 1 步（D4） | 不单独 spike；最小 SwiftUI 骨架（WindowGroup + Settings + 菜单栏 + 无焦点激活验证）列入 P0 Step 1 DoD |
| 4. Provider 契约 fixture | ✅ 本机侧通过（D5） | 接受现有 TransportTests（20 项）为契约证据；独立 fixture 脚本并入 P1「Provider 统一 stream contract」时建立；真实 Provider 凭据属验收矩阵开放项 |
| 5. 配置字段产品语义 | ✅ 审计完成，清单已确认（D6–D7） | 删除/新增/延后清单已定稿，见 0.1 决策登记与第 5 节 |
| 6. 数据清空 | ✅ 已决策：手动一次性清空（D8） | 不做 app 内清空/确认页；本机无 mvp 残留 → 按全新设计重构，无旧数据兼容负担 |
| 7. 汇总 | ✅ Gate 0 确认项全部闭环，可进入 P0 | D1–D8 全部确认；剩余仅验收矩阵资源项（凭据/测试账户/双机排期），不阻塞本机起步 |

**主要风险提示**：计划要求「删除旧 SwiftPM 体系、旧 AppKit 页面、废弃配置字段并清空既有本地 SQLite」。
仓库现状已有 77 项测试与大量已实现功能（详见第 8 节）。该破坏性范围已于 2026-09-09 获用户明确授权（D8）：
清空是**手动一次性动作、不做 app 内清空页**，且本机从未安装/使用过 mvp 版本 → **按全新设计重构，无需兼容旧设计及旧数据**。

---

## 0.1 用户决策登记 D1–D8（2026-09-09 已确认）

| # | 决策项 | 用户结论（原文要点） | 对实施的影响 |
|---|---|---|---|
| D1 | 开发者证书 | 已在本机生成开发者证书：`Apple Development: 1217194271@qq.com (WCHFR3G7VB)`；`security find-identity -v -p codesigning` 已可查到该身份（SHA-1 `660E631A9EAC4C48F1424C3C0D87919CCBD13B13`） | Gate 0.1 签名身份由「仅 ad-hoc」更新为「有 Apple Development 证书」：本机安装/真机调试可签名。**2026-09-09 验收修订：发布形态默认改用本证书签名（Team `3CSL8ZN3AN`，稳定 designated requirement，辅助功能/钥匙串授权跨重建保留），ad-hoc 仅作无证书环境回退**；不引入 Developer ID / 公证 / 沙盒 |
| D2 | 实机测试 | 另有一台 **macOS 14** 电脑可用于实机测试 | macOS 15 轮次用本机（macOS 15.7.9 arm64）、macOS 14 轮次用该设备；两代双机物理条件具备 |
| D3 | 命令环境准备 | 需提前安装的命令环境由**用户自行安装**，只给安装命令 | 交付 `brew install swiftlint`、`brew install periphery`（备用 `brew install peripheryapp/periphery/periphery`）；swift-format 已随 Xcode 就绪无需安装；不代为执行安装 |
| D4 | Gate 0.3 方式 | **不单独做 Gate 0.3 临时 spike**；在 **P0 第 1 步建 Xcode 工程时**先搭最小 SwiftUI App 骨架（WindowGroup + Settings + 菜单栏 + 无焦点激活验证）作为该阶段 DoD 的一部分 | Gate 0.3 结项为「并入 P0 Step 1 DoD」；最小骨架验证点进入 P0 第 1 步验收 |
| D5 | Gate 0.4 契约证据 | 接受以现有 TransportTests **20 项**作为 Gate 0.4 的契约证据；独立 fixture 脚本并入 P1「Provider 统一 stream contract」工作时一并建立 | Gate 0.4 本机侧结项；fixture 脚本列为 P1 工作项 |
| D6 | tails / UI 字段 / toggleHotkey | `tails` **整体移出本轮**；`theme` 等 6 个 UI 字段（theme/fontName/fontSize/compactFontSize/opacity/alwaysOnTop）**随 P2 SwiftUI 迁移实现**；`toggleHotkey` **本轮删除** | 本轮 schema/默认配置/设置/README 不暴露 tails 与 toggleHotkey；6 个 UI 字段列入 P2 实现清单（含接线与测试） |
| D7 | launchAtLogin / attachTo / sessionMode / timeoutSec | 确认按计划：**删除 `launchAtLogin`**、**废弃 `attachTo`**、**新增 `sessionMode`** + Action 级 **`timeoutSec`** | Gate 0.5 删除/新增清单定稿；`attachTo` 旧值在配置迁移时报错 |
| D8 | 破坏性范围与数据清空 | 接受「SwiftPM→Xcode、删旧 AppKit 页、删废弃字段、升级首次启动清空既有本地 SQLite」，但**清空是手动一次性动作，不需要 app 内设计相关功能**；本机从未安装/使用过 mvp 版本 → **按全新设计重构，无需兼容旧设计及旧数据** | Gate 0.6 关闭：不实现升级确认页/清空页；P0 无旧数据迁移与兼容负担；残留清理走外部一次性命令 |

**结论**：D1–D8 全部确认。Gate 0 所有确认项具备推进条件 → **可进入 P0**。
仍属验收矩阵、不阻塞本机 P0 起步的开放项：真实 Provider 低权限测试凭据、独立测试账户、macOS 14/15 双机人手排期（见第 9 节）。

---

## 1. Gate 0.1 工具链 / 签名 / 系统权限 / 测试账户 —— ✅ 本机侧通过（D1–D3）

### 本机实测结果（2026-09-09）

| 项 | 结果 | 结论 |
|---|---|---|
| macOS | 15.7.9 (24G830)，Apple Silicon arm64 | ✅ 满足「Apple Silicon」平台约束 |
| Xcode | 16.4 (16F6)，`xcode-select` 指向 `/Applications/Xcode.app/Contents/Developer` | ✅ 可建 Xcode 工程 |
| Swift | 6.1.2（swift-driver 1.120.5） | ✅ 满足 Swift 6 要求 |
| macOS SDK | `xcodebuild -showsdks` 仅列出 **macOS 15.5** | ⚠️ 本机无 macOS 14 SDK；Xcode 16.4 支持设置 macOS 14 部署目标并以 15.5 SDK 构建，但**在 macOS 14 真机上的运行验证**需用户提供设备 |
| swift-format | 位于 XcodeDefault toolchain，可用 | ✅ 满足 `make lint` 的格式化部分 |
| SwiftLint | **未安装** | ⚠️ P0 `make lint` / P3 CI 前置缺失，进入 P0 前需安装（Homebrew：`swiftlint`） |
| Periphery | **未安装** | ⚠️ 同上（若 P0/P1 静态门禁要求死代码检测） |
| 签名身份 | `security find-identity -v -p codesigning` → **1 valid identity**：`660E631A9EAC4C48F1424C3C0D87919CCBD13B13 "Apple Development: 1217194271@qq.com (WCHFR3G7VB)"` | ✅ 用户已生成并验证 Apple Development 证书（D1）：本机安装/真机调试可签名；发布形态仍按计划以 ad-hoc ZIP/CLI 为主，不引入 Developer ID / 公证 / 沙盒 |
| 真实测试设备 / 测试账户 | macOS 14 实机已提供（D2） | ✅ macOS 14 设备可用于实机测试；macOS 15 轮次以本机（15.7.9 arm64）执行。**独立低权限测试账户仍未闭环** → 验收矩阵开放项 |

### 需用户决策（已确认 D1–D3）
- [x] 开发者证书：已生成并验证生效（D1）；用于本机/真机安装与调试签名。
- [x] 实机：提供 macOS 14 电脑用于实机测试（D2）；macOS 15 用本机。
- [ ] 独立低权限测试账户：**未提供** → 列为验收矩阵开放项，不阻塞本机 P0 起步。
- [x] 发布形态：接受 ad-hoc 签名 ZIP/CLI（与计划第 1 节一致，不引入 Developer ID）；Apple Development 证书仅用于安装调试，不替代该决策。

---

## 2. Gate 0.2 TOML 解析器 spike —— ✅ 本机通过（附约束）

### 验证对象
- 锁定版本：`Package.resolved` → TOMLDecoder **0.4.5**（revision `a2bbd279…`，MIT 许可证，已在 `.build/checkouts/TOMLDecoder/LICENSE.md` 确认）。
- 注意：`Sources/Infrastructure/Config/ConfigLoader.swift` 等处的注释仍写「TOMLDecoder 0.3 …force-unwrap」，**注释与锁版不符，属陈旧注释**，实施时应清理；本次 spike 针对的是实际锁定的 0.4.5 源码副本。

### 验证方法（独立 spike，位于 `/private/tmp/toml-spike-g0/`，不入库）
- 从 `.build/checkouts/TOMLDecoder` 拷贝源码（15 个 Swift 文件），`swiftc -O` 独立编译 + 手写 spike main。
- 语料覆盖计划要求：合法 corpus（CJK / emoji / 三引号多行字符串 / 数字字面量 `1_000_000`、hex、oct、bin / datetime / inline table）与非法 corpus（15 种，含未闭合三引号、重复键、空键、未闭合 table/array、裸词 int、尾随垃圾、**越界 int**、字符串当 int、坏 bool、nan float、非法 float、未知枚举值）。

### 结果（`spike` 二进制实测输出）
| 阶段 | 结果 |
|---|---|
| PHASE1 合法 10,000 次（单线程） | `ok=10000 err=0`，约 377 ms |
| PHASE3 并发 8 线程 × 1,250 | `ok=10000 err=0`，约 174 ms |
| PHASE2 非法语料 15 种 × 200 次 | 语法类 12 种全部稳定报错（`err=200`），**零崩溃** |

### 错误可定位性（本次新增证据）
- TOMLDecoder 0.4.5 的错误描述普遍携带行号，例如：
  - 语法错误：`(Line 1) Syntax error: unterminated triple-d-quote.`
  - 数值/类型错误：`(Line 2) Invalid integer value for key 'port': …`
  - 布尔错误：`(Line 2) Invalid boolean value for key 'alwaysOnTop'.`
- 应用侧 `ConfigLoader.userFacingParseError` 的正则只对 `Line N … Syntax error: …` 形态提取行号（实测可命中，输出「第 N 行：TOML 语法错误」）；对 `Invalid integer/boolean value` 等**非语法形态会落入通用文案**（无行号）。
- 结论：**解析器本身满足「错误可定位」**；应用侧错误展示需在 P1 配置工作时把行号提取扩展到非语法错误（或让 preflight / validator 报行号），这是实现期小改动，不构成「不通过」。

### 已知宽容行为（需应用层兜底，已兜底或需补）
- TOML 规范本身允许 `nan / inf / -inf` 作为合法浮点：`opacity = nan` 会被 TOMLDecoder 接受；`ConfigValidator` 的 `0.75…1` 范围比较对 `nan` 恒为 false，**不会拦截** → 实现期需在 validator 增加「有限数」检查。
- `theme = "未知值"` 等字符串类：解析通过，由 `ConfigValidator` 白名单（`tokyo-night/solarized-dark/nord/mono`）拦截（已有测试覆盖）。
- 越界/畸形 int：TOMLDecoder 会以 `valueNotFound(Int)` 等报错而非崩溃；应用层 `preflightNumericFields`（配置编辑保存前扫描 `port/scrollbackLines/maxBodyBytes/simulatedCopyWait/maxInputChars/maxTokens/timeoutSec`）在进入 decoder 前拦截，测试 `testConfigLoaderRejectsMalformedIntegerBeforeTOMLDecoder` 已绿。
- 结论：**「库容忍宽松、应用必须套 preflight + validator」是采用 TOMLDecoder 的可接受前提**；锁版 0.4.5 未复现代码注释中所说的 force-unwrap 崩溃路径。

### Gate 0.2 结论
- [x] 零崩溃（合法 10k、并发 10k、非法 3k 次解析均无崩溃）
- [x] 错误可定位（解析器错误带 `(Line N)`；应用展示层小幅加强列入 P1）
- [x] 许可证可接受（MIT）
- [ ] 无阻塞项 → **Gate 0.2 本机通过**

---

## 3. Gate 0.3 SwiftUI 最小原型 —— ✅ 已确认：并入 P0 第 1 步（D4）

计划要求的最小原型范围：多窗口、菜单栏、Settings Scene、终止回调、窗口不抢焦点、后台流式 UI 刷新、Accessibility/Carbon 桥接。

- 本机已具备执行条件（Xcode 16.4 / Swift 6.1.2 / arm64），但建原型工程属「准实现」活动，且原型代码在 P0 重建后不会直接复用。
- 现状证据（供原型对照）：
  - `Sources/App/AppMain.swift:14`、`ConsoleWindowController.swift:59`、`SettingsWindowController.swift:133`、`UsageWindowController.swift:60`、`ConsolepilotRootView.swift:755` 均调用 `activate(ignoringOtherApps: true)` → 与 P0「后台 Action 不抢焦点」冲突源，原型需验证替代方案。
  - 当前为 AppKit AppDelegate 生命周期 + 启动即建主窗口，非 SwiftUI `@main App`。

### 需用户决策（已确认：方式 A，D4）
- [x] 方式 A（已确认）：不单独做 Gate 0.3 临时 spike，在 **P0 第 1 步建 Xcode 工程时**先搭最小 SwiftUI App 骨架（WindowGroup + Settings + 菜单栏 + 无焦点激活验证）作为该阶段 DoD 的一部分。
- [ ] 方式 B（不采用）：先在 `/private/tmp` 建独立临时原型工程。

---

## 4. Gate 0.4 Provider 契约 fixture —— ✅ 本机侧通过（D5）

### 已有契约测试证据（本次基线复跑）
- `Tests/TransportTests.swift`（465 行）本次执行 **20 项全部通过**，覆盖：
  - 分块 SSE 合帧、`[DONE]` / `message_stop` 收尾、1000 delta 无丢失无重复（StreamCoordinator 跨会话隔离测试通过）；
  - 取消、超时、401 / 429 / 5xx 映射（`testTransportHTTPStatusMappingIsSharedAcrossProviders` 等）；
  - 畸形帧、早期前缀持久化、完成时机与 finishReason。
- OpenAI-compatible 与 Anthropic 的解析在既有单测中均以本地 fixture（字符串/文件）验证，**不依赖真实网络**。

### 缺口
- 没有独立的「Provider fixture spike」目录/可重复脚本（现为单测内联 fixture）。
- 计划验收矩阵第 5 节要求「真实 Provider 短请求/流式/取消/401/429/5xx/断网/超时」在**专用低权限测试 Key** 下验证 → 本机无法闭环，需用户提供测试凭据。

### 需用户决策（已确认 D5；凭据为验收矩阵开放项）
- [x] 已接受：以现有 TransportTests 20 项作为 Gate 0.4 的契约证据；独立 fixture 脚本并入 P1「Provider 统一 stream contract」工作时一并建立。
- [ ] （验收矩阵开放项，不阻塞 P0 起步）真实 Provider 低权限测试凭据（OpenAI-compatible + Anthropic），用于验收矩阵第 5 节动网验证。

---

## 5. Gate 0.5 配置字段产品语义审计 —— ✅ 审计完成，删除/实现清单需确认

审计方法：对 `ConfigSchema.swift / ConfigLoader.swift / ConfigValidator.swift / DefaultConfig.toml / SettingsWindowController.swift / ConsolepilotRootView.swift / RuntimeBindings.swift / Transport / App` 做逐字段引用矩阵 grep（本次会话重新验证），未改动代码。

### 5.1 已接线、语义完整（保留）

| 字段 | 运行证据 |
|---|---|
| `capture.strategy / restoreClipboard / excludeBundleIds / simulatedCopyWait / maxInputChars` | `TextCaptureService(config:)`、捕获回退与元数据测试全绿（`testTextCaptureFallbackUsesConfiguredOrderAndMetadata` 等） |
| `server.authToken / maxBodyBytes` | LocalServer / Bearer 鉴权 / body 限长 |
| `profiles.*（baseURL/model/temperature/maxTokens/priceInput/priceOutput）` | Transport / RequestBuilder / Usage |
| `profiles.timeoutSec` | **profile 级**网络超时（RequestBuilder、ConsolepilotRootView），validator 范围检查 |

### 5.2 仅解析/校验、运行时未接线或语义冲突（进入「删除或实现」清单）

| 字段 | 现状证据 | 计划语义（PLAN 3.2/3.4） | 建议 |
|---|---|---|---|
| `launchAtLogin` | 仅 ConfigSchema/Loader；全仓库**无 SMAppService / LoginItem / SMLoginItem 引用** | 首轮不实现，从 schema/默认/设置/测试删除 | **删除**（随计划执行） |
| `attachTo = newSession/currentSession` | 仅模型 + validator；`ActionRunner` 不按其分支（一律新会话） | `currentSession` 废弃，改为 `sessionMode = dedicated`（按 `actionId+sourceApp` 复用） | **删除 `attachTo`，新增 `sessionMode`**，迁移时对旧值明确报错 |
| `sessionMode` | 当前不存在 | 新字段 | **新增** |
| `autoShow` | 仅模型 + Settings UI 文案；所有 Action 都会展示到主窗口会话 | 仅决定启动时是否显示主窗口，默认 false；后台任务不抢焦点 | **实现**（P1 Action 生命周期） |
| `notifyOnDone` | 仅模型 + Settings UI 文案；运行时不发通知 | 仅窗口非前台且完成/失败时发通知，不含正文 | **实现** |
| `timeoutSec`（Action 级） | **无 Action.timeoutSec 字段**（现仅 profile 级） | 从捕获完成进入网络请求开始计时，超时写 `.failed` checkpoint | **新增 Action.timeoutSec**（与 profile 级区分或统一） |
| `tails` | 基础已实现：FileTailWatcher 轮转、CLI/HTTP `/tail`、UI push；但内容**直接 append 到 UI transcripts**（无 Action 会话隔离），jsonl 元数据/校验不足 | 本轮不补 Action 隔离与 jsonl 校验 | **整体移出本轮（D6）**：schema/默认/设置/UI 不暴露，留待后续轮次 |
| `toggleHotkey` | 仅解析 + validator（语法/冲突）；`RuntimeBindings` 只注册 `actions` 的 hotkey，**无全局 toggle 呼出注册** | 已具备 `actions[].hotkey` 承担快捷键能力 | **本轮删除（D6）**：从 schema/默认/设置/测试移除 |
| `fontName / fontSize / compactFontSize / opacity / alwaysOnTop / theme` | 仅 schema/loader/validator；`ConsolepilotRootView` 硬编码 `Theme.registry["tokyo-night"]`、固定字号、固定 `scrollbackLines: 100_000`，不读 `config.general`（grep 无 `config.general` 引用） | UI 字段须在 SwiftUI 迁移中落地 | **随 P2 SwiftUI 迁移实现（D6）**：theme/fontName/fontSize/compactFontSize/opacity/alwaysOnTop 六字段列入 P2 实现清单 |

### 5.3 产品语义（已确认 D6–D7）
- [x] `tails`：**整体移出本轮**（本轮 schema/UI/文档不暴露，不补 Action 会话隔离与 jsonl 校验，留待后续轮次）。
- [x] `toggleHotkey`：**本轮删除**（已有 `actions[].hotkey` 承担快捷键能力）；`theme` 等 6 个 UI 字段（theme/fontName/fontSize/compactFontSize/opacity/alwaysOnTop）**随 P2 SwiftUI 迁移实现**。
- [x] 确认按计划：删除 `launchAtLogin`、废弃 `attachTo`（迁移对旧值报错）、新增 `sessionMode` + Action 级 `timeoutSec`。

---

## 6. Gate 0.6 数据清空 —— ✅ 已决策：手动一次性清空（D8）

> 计划 3.4 原设计「升级首次启动确认页 + 删除 SQLite + 重建 schema」经 D8 决策**不再作为 app 内功能成立**。

- 用户结论（D8）：接受破坏性范围，但**清空 mvp 版本残留数据/文件是手动执行的一次性动作，不需要 app 内设计相关功能**。
- 本机从未安装/使用过 mvp 版本 → 无既有数据与文件需要迁就，**当作一次设计重构，无需兼容旧设计及旧数据**。
- 落地约定：
  - 本轮**不实现**升级确认页/清空页/迁移页（该项原设计删除）。
  - 若本机数据目录存在 mvp 残留（SQLite 主文件 + `-wal` + `-shm`，会话/消息/用量/捕获元数据），由**手动一次性命令**删除（届时给出精确路径与命令），不进 app 代码。
  - 新 Store 以全新 schema 建库，版本号从新基线开始。

---

## 7. Gate 0.7 汇总结论（2026-09-09 更新）

| 判定 | 条目 |
|---|---|
| ✅ 本机通过 | Gate 0.2 TOML spike（零崩溃、可定位、MIT） |
| ✅ 决策已确认 | Gate 0.1 工具链/证书/设备（D1–D3）；Gate 0.3 方式 A 并入 P0 Step 1（D4）；Gate 0.4 TransportTests 20 项契约证据（D5）；Gate 0.5 删除/新增清单（D6–D7）；Gate 0.6 手动一次性清空（D8） |
| ⬜ 验收矩阵开放项（不阻塞 P0 起步） | 真实 Provider 低权限测试凭据；独立低权限测试账户；macOS 14/15 双机人手排期；开发证书/ad-hoc 产物在 macOS 14 上的打开与 quarantine 处理指引 |
| ❌ 不通过 | 无 |

**结论（更新）**：D1–D8 全部确认，破坏性范围已获授权（D8）。按计划第 7 节的前提已满足 → **可进入 P0**。
P0 属生产代码变更，动手前先给出 P0 第 1 步落地清单。

---

## 8. 附：现状基线证据（本次会话实测）

### 8.1 测试基线
- 命令：`swift test --disable-sandbox`（沙箱内裸 `swift test` 会被 SwiftPM `sandbox-exec` 阻断，需 `--disable-sandbox`）。
- 结果：**77 项执行，74 通过，3 失败**；失败均为沙箱环境件，非产品回归：
  - `testClipboardSnapshotRestoresStringRTFImageAndMultipleItems`、`testClipboardSnapshotRoundTripsOneHundredTimes`：`XCTUnwrap failed: … "NSPasteboard"`（沙箱内剪贴板不可用，GUI 会话可跑）；
  - `testKeychainStoreRoundTripsAndDeletesOnlyTestAccount`：`KeychainError(status: 100001)`（沙箱对 securityd 访问被拒）。
- 配置相关测试全绿：`testConfigLoaderRejectsMalformedIntegerBeforeTOMLDecoder`、`testConfigLoaderReportsConciseMultilineStringError`、`testConfigLoaderRejectsUnknownEnumValues`、`testConfigStoreNotifiesOnlyAfterValidReload` 等。

### 8.2 仓库结构现状（对应 PLAN 审查表）
- 单一 SwiftPM package：无 `Consolepilot.xcodeproj`、无 Makefile；`Sources/` 合并一个 Core target（Domain / Infrastructure / Transport / Rendering / App 同 target）。
- `Sources/Infrastructure/Presentation/ConsolepilotRootView.swift`：**1249 行** AppKit NSView，承担装配/UI/任务/IPC/流式/会话/状态。
- `Sources/App/DependencyContainer.swift`：存在但无引用（未被组合使用）。
- 构建：`Scripts/build-local.sh` 内联 Info.plist、固定 `.build/arm64-apple-macosx/…/ConsolepilotAppBinary`、`rm -rf dist`；无受控产物目录。
- 依赖：GRDB.swift 7.8.0、TOMLDecoder 0.4.5（均已缓存 checkout）。
- 文档差异：`Docs/SPIKE-RESULTS.md` 标记 S1–S9 未执行，但仓库代码已实现 S2–S6/S8/S9 大部分能力；`Docs/PLAN.md` 为新增未跟踪文件。

### 8.3 证据位置（便于复核）
- TOML spike：`/private/tmp/toml-spike-g0/`（src/main.swift、errdump、TOMLDecoderSrc、二进制 spike / errdump-bin；不入库）。
- 测试输出：本报告 8.1 的命令可复现。
- 配置字段引用矩阵：本报告第 5 节，可对 `Sources/` 重跑 grep 复核。

---

## 9. 授权前待确认清单 —— 逐项回执（2026-09-09 全部答复）

1. **破坏性范围** ✅ 接受（D8）：SwiftPM → Xcode 工程、删除旧 AppKit 页面、删除废弃字段、清空既有本地 SQLite。本机从未安装/使用过 mvp → **按全新设计重构，无兼容旧设计及旧数据的负担**。
2. **数据清空定稿** ✅ 修改定稿（D8）：**不做** app 内清空/确认页；清空是**手动一次性动作**，由外部命令删除 `Consolepilot.sqlite` + `-wal` + `-shm`（精确路径实施时列出），不进 app 代码。
3. **tails** ✅ **整体移出本轮**（D6）：本轮 schema/UI/文档不暴露，不补 Action 隔离与 jsonl 校验。
4. **未接线 UI 字段 / toggleHotkey** ✅（D6）：`toggleHotkey` 本轮删除；`theme/fontName/fontSize/compactFontSize/opacity/alwaysOnTop` 六字段随 P2 SwiftUI 迁移实现。
5. **Gate 0.3 方式** ✅ **方式 A**（D4）：不单独 spike，最小 SwiftUI 骨架并入 P0 第 1 步建工程时实现并列入该步 DoD。
6. **测试资源** ✅ 部分提供 / 部分开放：macOS 14 实机已提供（D2），macOS 15 用本机；**独立测试账户、真实 Provider 低权限凭据、双机人手排期仍未闭环** → 验收矩阵第 5–6 节前补齐，不影响本机 P0 起步。
7. **附加** ✅ 接受（与计划一致，ad-hoc 发布、不引入 Developer ID）；Apple Development 证书（D1）用于本机/真机安装调试。

**结论**：确认项全部答复完毕（D1–D8），Gate 0 前提具备 → **可进入 P0**。
