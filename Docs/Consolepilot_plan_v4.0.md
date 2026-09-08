# Consolepilot — macOS 终端风格 AI 副屏控制台
## 开发实施计划 v4.0 · 可直接实施版

**目标机器**：MacBook Air (M1) · macOS 14.8.8 · 主屏 + 小尺寸副屏
**部署形态**：本地构建，ad-hoc 签名 .app（不上架、不沙盒、不公证）
**本版目标**：把计划细化到"照着写就能实现"的程度 —— 全部类型签名、接口契约、文件职责、完成定义均已固定；全部代码写法不确定项均有可实机验证的确认方式。

## 执行前确认（v4.0 修订决策）

本计划按以下决策实施：

- 完整 Xcode 作为唯一构建工具链；Deployment Target 为 macOS 14.0，Release 产物为 arm64。
- 依赖使用 Swift Package Manager，版本在 `Package.resolved` 中锁定；正式代码依赖 GRDB.swift、TOML 解析库，快捷键库仅在 C15 Spike 证明 Carbon 不足时引入。
- LocalServer 增加 `[server]` 配置段，使用 `Authorization: Bearer <token>` 鉴权；token 通过 Keychain 或环境变量引用，绝不写入配置明文。
- 远程 Profile 禁止明文 API Key；仅允许 `${keychain:...}` 或 `${env:...}`。环回本地 Profile 可使用空字符串，仍不允许把真实密钥写入 TOML。
- `TransportError` 增加 `connectionLost`；S4、M5、T4 和实机验收统一使用该错误码。
- ad-hoc 为默认签名方案；S8 若验证 TCC/Keychain 不持久，则启用稳定 Bundle ID 的免费 Apple ID 本地签名；若 Keychain 仍不可用，保留 `${env:VAR}` 作为运行时降级路径。
- 缺失的 `SessionMeta`、`SyntaxPalette`、`CaptureLogEntry` 在 M1/M3/M4 的代码规格中补齐，不再允许“实现时自定”。

---

# 第 -1 部分 · 开工前置条件

以下条件满足后才能开始 S1–S9；完整 Xcode 未安装时禁止进入 M1。

## -1.1 本机工具链

1. 安装与启动完整 Xcode（不是仅 Command Line Tools），执行 `xcode-select` 指向 Xcode 的 Developer 目录，并接受许可。
2. 验证 `xcodebuild -version`、`swift --version`、`xcrun instruments` 均可用；Swift 版本须支持 Swift 6 `complete` 并发检查。
3. 安装 SwiftLint 与 Periphery；`swift-format` 优先使用 Xcode toolchain 中的 `xcrun --find swift-format`，找不到时安装与当前 Swift toolchain 匹配的 SwiftFormat 发布包；不得假定存在名为 `swift-format` 的 Homebrew formula。
4. 保留系统 `sqlite3` 用于验收调试；Python 3 用于 S4 mock server。

## -1.2 依赖与工程约束

| 依赖 | 用途 | 规则 |
|---|---|---|
| GRDB.swift | SQLite 数据层 | SPM 锁定具体版本，启用 WAL、外键和 busy timeout |
| TOML 解析库 | 配置解析 | SPM 锁定具体版本；若 C18 证明库不满足行号/原子替换要求，改用计划内极简子集解析器 |
| Carbon / AppKit | 快捷键、AX、窗口、剪贴板 | 优先使用系统框架，不额外引入快捷键库 |
| KeyboardShortcuts（可选） | C15 降级方案 | 仅当 Carbon Spike 未达标时加入，加入前更新依赖表和许可证记录 |

依赖版本、Checksum 和源地址必须提交到 `Package.resolved`；禁止在源码中依赖未锁版本的远程包。

## -1.3 实机与账号准备

- S1 的 15 个目标 App（Safari、Chrome、Xcode、VS Code、Terminal、iTerm2、Notes、Preview、Mail、Slack、Figma、微信、Word、Finder、Warp）至少准备 14 个可运行版本；缺失 App 必须在 `SPIKE-RESULTS.md` 记录并重新说明样本数与阈值。
- 准备主屏 + 副屏、中文拼音与五笔输入法，用于 S3/S5 和第 10 部分实机验收。
- 准备 OpenAI 与 Anthropic 测试凭据；只写入 Keychain 或本机环境变量，不得提交到仓库、配置文件或日志。
- 准备可执行辅助功能授权、网络断连、日志轮转、磁盘压力和 Gatekeeper 测试的 macOS 账户。

## -1.4 开工门禁

执行以下命令全部成功后，才可开始 S1：

```bash
xcodebuild -version
swift --version
xcrun --find swift-format
swiftlint version
periphery version
python3 --version
sqlite3 --version
```

若任一工具缺失，先修复环境，不以手工跳过门禁替代。

### 相对 v3.1 的补充
| 新增 | 说明 |
|---|---|
| 第 2 部分 | **代码写法确认项 C1–C18**，每项都有可实机运行的验证方法，Spike 阶段逐项锁定 |
| 第 3 部分 | **强制编码规范**，含 `../.swiftlint.yml` 全文、命名表、禁用清单、性能铁律 |
| 第 5 部分 | **代码规格（Code Spec）** —— 全部核心类型的确切 Swift 签名，实施时不再有设计决策 |
| 第 6 部分 | Spike S1–S9，每个含量化通过阈值与降级方案 |
| 第 7 部分 | Milestone 升级为**文件级交付清单 + 完成定义（DoD）** |
| 第 8 部分 | 交付脚本**全文给出**，非描述 |
| 第 9–10 部分 | D1–D8 工具门禁、R1–R24 人工审查、T1–T5 模拟测试、实机 100 步 |

---

# 第 0 部分 · 定位与风险

## 0.1 产品定义
常驻 macOS 的终端风格控制台，通常放在副屏。在任意应用中选中文字后按下快捷键，即按预设提示词模板向自选 AI 服务发起流式请求，结果实时渲染在副屏控制台，并可在控制台内继续追问。

## 0.2 通道设计
| 通道 | 说明 | v1 |
|---|---|---|
| **A · Action 触发** | 全局快捷键 + 选中文字/剪贴板 + 提示词模板 → 请求 AI → 副屏渲染 | **主通道** |
| B · 控制台直接输入 | 窗口内打字对话 | 必做 |
| C · CLI 伴生命令 | `consolepilot ask` / 管道输入 | 必做 |
| D · 文件尾随 | 监听日志文件增量显示 | 必做 |
| E · HTTP 推送 | 本机环回 `POST /v1/ingest/stream` | 必做 |
| ~~F · 透传代理~~ | ~~拦截外部调用方~~ | 不做，留档 `Docs/FUTURE-PROXY.md` |

## 0.3 两个可能推翻方案的风险
1. **跨 App 选中文字捕获**（S1）：AX API 干净但部分 App 不支持；模拟 ⌘C 通用但需处理剪贴板恢复与安全输入。门槛：目标 App 矩阵成功率 ≥ 90%、剪贴板零污染。
2. **ad-hoc 签名下的权限持久性**（S8）：无 Developer ID 即无稳定 designated requirement，辅助功能授权与 Keychain ACL 可能在每次重新构建后失效。

这两项必须在写正式代码前定论。

---

# 第 1 部分 · 决策记录（全部已锁定）

| # | 项目 | 决策 |
|---|---|---|
| A1 | 最低系统版本 | macOS 14.0（Deployment Target 14.0） |
| A2 | AI 供应商 | OpenAI 兼容协议 + Anthropic Messages 双支持，配置文件指定；OpenAI 兼容意味着中转站与本地 Ollama 亦可用 |
| A3 | 主通道 | A · Action 触发 |
| A4 | Key 存储 | Keychain 为主；配置支持 `${env:VAR}` / `${keychain:name}`，**永不明文存 Key** |
| A5 | 沙盒/上架 | 不沙盒、不上架 |
| A6 | 持久化 | SQLite + GRDB.swift |
| A7 | 渲染 | 自研 ANSI + Markdown → NSTextStorage 增量渲染 |
| A8 | 窗口 | 单窗口 + 会话侧边栏 + 小副屏紧凑模式 |
| A9 | 构建 | arm64 单架构 |
| A10 | 签名 | ad-hoc（`codesign -s -`），不公证 |
| A11 | 配置格式 | TOML |
| A12 | 文字捕获 | AX → 模拟 ⌘C → 剪贴板 → 手动输入 四级降级；辅助功能权限已确认可授予 |
| A13 | 用量统计 | v1 保留（`usage_record` + `/usage`） |
| A14 | 窗口呼出快捷键 | 默认不设（`toggleHotkey = ""`）；功能保留可自配 |
| A15 | Action 可自定义性 | 默认 5 个仅示例；数量与内容完全由配置文件决定 |
| A16 | LocalServer 鉴权 | 仅监听回环地址；`Authorization: Bearer <token>`，缺失/错误返回 401，非回环返回 403 |
| A17 | API Key 明文策略 | 远程 Profile 禁止明文；仅允许 Keychain/环境变量引用；环回本地 Profile 可为空 |
| A18 | 签名降级 | ad-hoc 默认；S8 失败时使用稳定 Bundle ID 的免费 Apple ID 本地签名；Keychain 失败时使用环境变量 |

## 1.1 关键选型依据（三项对比结论）

**配置格式** —— TOML 采纳：手写舒适、支持注释、`[[actions]]` 数组表天然适配、无缩进陷阱。YAML 否（缩进敏感、规范复杂）；JSON 否（无注释，仅保留作 `--json` 导出）。

**持久化** —— SQLite + GRDB 采纳：可聚合查询、迁移显式可控、WAL 并发安全、单文件易备份、`sqlite3` 可直接调试。SwiftData 否（迁移弱、复杂聚合受限、高频写入并发有坑）；JSONL 否（无索引、统计需全扫、删除要重写整文件）。

**渲染** —— 自研采纳（~800 行、内存最低、纯增量最优、输入法完全可控）。SwiftTerm 否（2 万行第三方，99% 功能为 PTY/光标寻址/alternate screen，我们不需要，且输入模型不匹配）；WKWebView + xterm.js 否（+150MB 内存基线、跨进程 IPC 增延迟、输入法集成困难）。

---

# 第 2 部分 · 代码写法确认项（C 系列 · 实施前必须全部锁定）

> 规则：每项都有**可实机运行**的验证方法。Spike 阶段逐项产出结论并写入对应 `SpikeN-*.md`。**任一项未锁定，禁止进入第 6 部分实施。**

## 2.1 确认项清单

| # | 不确定的写法 | 候选方案 | 验证方法（实机） | 归属 |
|---|---|---|---|---|
| C1 | 读取其它 App 选中文字 | `AXUIElementCopyAttributeValue(kAXSelectedTextAttribute)` / `kAXSelectedTextRangeAttribute`+`kAXStringForRangeParameterizedAttribute` | 15 App 矩阵逐个实测，记录成功率与耗时 | S1 |
| C2 | 合成 ⌘C 按键 | `CGEvent(keyboardEventSource:)` + `.maskCommand` / `AXUIElementPerformAction(kAXPressAction)` / AppleScript `keystroke` | 三方案在同矩阵实测；比较成功率、耗时、是否触发权限弹窗 | S1 |
| C3 | 剪贴板完整快照与恢复 | 遍历 `pasteboardItems` 全 type / 仅 `string` / `NSPasteboardWriting` 归档 | 复制富文本、图片、多 item 后往返 diff 每个 type 的 data | S1 |
| C4 | 检测安全输入态 | `IsSecureEventInputEnabled()`（Carbon） | 聚焦密码框时调用，验证返回 true 且我们正确跳过 | S1 |
| C5 | 判定辅助功能权限 | `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions(prompt:)` | 未授权与已授权两态各测；验证撤销授权后能否**运行时**检测到变化 | S1 |
| C6 | 高频文本追加不触发全量重排 | TextKit2 `NSTextStorage.append` / TextKit1（`usesTextKit2=false`）/ 自绘 CALayer | 200 token/s×60s，Instruments 看 Hitch p99 与 layout 耗时 | S2 |
| C7 | scrollback 裁剪写法 | `deleteCharacters(in:)` 批量 / `NSTextStorage` 整体替换 | 10 万行下裁剪 5000 行的耗时与是否引起滚动跳动 | S2 |
| C8 | 流式未闭合代码块回溯上色 | `setAttributes(_:range:)` 回溯 / 删除重插 / 延迟到闭合再渲染 | 逐字符喂入含未闭合 ``` 的文本，观察是否跳动、最终样式是否正确 | S2 |
| C9 | 键盘事件拦截 | SwiftUI `.onKeyPress` / `NSView.keyDown` / `NSEvent.addLocalMonitorForEvents` | `^C` `^L` `Tab` `⇧⏎` 四键逐个测，含被系统吞掉的情况 | S3 |
| C10 | 输入法组合态判定 | `NSTextInputClient.hasMarkedText()` / `NSTextView.hasMarkedText()` | 拼音与五笔输入中途按 `⏎`，必须上屏而非发送 | S3 |
| C11 | SSE 流式读取 | `URLSession.bytes(for:)` AsyncSequence / `URLSessionDataDelegate` | 中途 kill 服务端，验证抛错类型；验证 UTF-8 中文跨 chunk 切断不乱码 | S4 |
| C12 | 取消流并真正断开 TCP | `Task.cancel()` 传播 / `URLSessionTask.cancel()` 显式调用 | `^C` 后用 `lsof`/`netstat` 确认连接已关闭，非空转 | S4 |
| C13 | 自定义标题栏 + 半透明 + 置顶 | `titlebarAppearsTransparent` + `NSVisualEffectView` + `NSWindow.level` | 浅/深色 × 主/副屏 × Stage Manager 目视检查黑边、撕裂、圆角 | S5 |
| C14 | 窗口关闭不退出 App 且可重开 | `NSWindowDelegate.windowShouldClose` 返回 false + orderOut / `NSApp.setActivationPolicy` | `⌘W` 后从菜单栏图标与 Dock 各重开 10 次 | S5 |
| C15 | 多组全局快捷键注册 | `KeyboardShortcuts` 库 / Carbon `RegisterEventHotKey` / `NSEvent.addGlobalMonitor` | 同时注册 6+ 组；测是否需输入监控权限；热重载重注册 100 次查泄漏 | S6 |
| C16 | 空快捷键跳过注册 | 空字符串直接 return / Optional 建模 | 配 `toggleHotkey = ""` 启动，必须无异常无报错 | S6 |
| C17 | ad-hoc 签名下 TCC 与 Keychain 持久性 | ad-hoc / 免费 Apple ID 本地签名 / 加密文件存 Key | 重新构建替换 .app 后，验证辅助功能授权与 Keychain 是否失效 | S8 |
| C18 | TOML 解析与热重载 | `TOMLDecoder` 库 / 自研极简子集解析器 | 解析我们的完整默认配置；测编辑器原子写（`mv`）是否丢监听、错误行号是否准确 | S9 |

## 2.2 锁定流程
1. 执行 Spike，逐项填写下表并写入 `SpikeN-*.md`
2. 全部 18 项状态为「已锁定」后，才可开始 M1

**结论记录模板**（每项必填）
```
C编号：
选定写法：
实测数据：
被否方案及原因：
边界与已知限制：
对应正式代码位置：
```

---

# 第 3 部分 · 强制编码规范

> 目标：无遗漏、无残留、无冗余、可维护、最佳性能。以下为**硬性规则**，由工具闸门 + 人工审查双重强制。

## 3.1 `../.swiftlint.yml`（全文，直接使用）
```yaml
strict: true

included:
  - Sources
excluded:
  - Sources/Generated

analyzer_rules:
  - unused_declaration
  - unused_import

opt_in_rules:
  - array_init
  - closure_end_indentation
  - closure_spacing
  - collection_alignment
  - contains_over_filter_count
  - contains_over_first_not_nil
  - convenience_type
  - discouraged_optional_boolean
  - empty_collection_literal
  - empty_count
  - empty_string
  - explicit_init
  - fallthrough
  - fatal_error_message
  - first_where
  - flatmap_over_map_reduce
  - force_unwrapping
  - implicit_return
  - joined_default_parameter
  - last_where
  - legacy_multiple
  - literal_expression_end_indentation
  - lower_acl_than_parent
  - modifier_order
  - multiline_arguments
  - multiline_parameters
  - operator_usage_whitespace
  - overridden_super_call
  - prefer_self_type_over_type_of_self
  - private_action
  - private_outlet
  - prohibited_super_call
  - reduce_into
  - redundant_nil_coalescing
  - redundant_type_annotation
  - sorted_first_last
  - static_operator
  - toggle_bool
  - unavailable_function
  - unneeded_parentheses_in_closure_argument
  - unowned_variable_capture
  - untyped_error_in_catch
  - vertical_parameter_alignment_on_call
  - yoda_condition

disabled_rules:
  - todo          # 我们用 custom_rules 直接禁止，报错更明确

line_length:
  warning: 120
  error: 140
  ignores_comments: false
  ignores_urls: true

file_length:
  warning: 350
  error: 400

type_body_length:
  warning: 200
  error: 250

function_body_length:
  warning: 35
  error: 40

function_parameter_count:
  warning: 5
  error: 6

cyclomatic_complexity:
  warning: 8
  error: 10

nesting:
  type_level: 2
  function_level: 3

identifier_name:
  min_length: 2
  excluded: [id, db, ax, ui, x, y]

custom_rules:
  no_todo_markers:
    name: "禁止遗留标记"
    regex: "(TODO|FIXME|XXX|HACK|WIP)"
    message: "提交前必须清除遗留标记"
    severity: error

  no_print:
    name: "禁止 print"
    regex: "(?<!\\.)\\b(print|debugPrint|dump)\\s*\\("
    message: "使用 Log 而非 print"
    severity: error

  no_force_try:
    name: "禁止 try!"
    regex: "try!"
    message: "禁止 try!，显式处理错误"
    severity: error

  no_force_cast:
    name: "禁止 as!"
    regex: "as!\\s"
    message: "禁止 as!，用 as? 并处理 nil"
    severity: error

  no_commented_code:
    name: "禁止注释掉的代码"
    regex: "^\\s*//\\s*(let|var|func|if|for|while|return|guard|import)\\s"
    message: "删除而非注释代码"
    severity: error

  no_empty_catch:
    name: "禁止空 catch"
    regex: "catch\\s*\\{\\s*\\}"
    message: "catch 必须有明确处理"
    severity: error

  no_main_async_patch:
    name: "禁止 DispatchQueue.main.async 补丁"
    regex: "DispatchQueue\\.main\\.async"
    message: "用 @MainActor 而非手动派发"
    severity: error

  no_secret_in_log:
    name: "禁止密钥入日志"
    regex: "Log\\.[a-z]+\\([^)]*(apiKey|secret|token|password)"
    message: "禁止将密钥写入日志"
    severity: error
```

## 3.2 命名统一表（全仓强制一致，禁止混用同义词）
| 概念 | 唯一用词 | 禁止使用 |
|---|---|---|
| 流式片段 | `delta` | chunk、piece、fragment |
| 合帧后的批次 | `TokenBatch` | buffer、group、packet |
| 会话 | `Session` | conversation、thread、chat |
| 单条消息 | `Message` | entry、record、item |
| 模型端点配置 | `Profile` | endpoint、provider config、preset |
| 快捷键动作 | `Action` | command、task、shortcut |
| 文字捕获结果 | `CaptureResult` | grabbed、picked、snippet |
| 提示词模板 | `promptTemplate` | template、format、pattern |

## 3.3 架构铁律（越界即审查不通过）
1. `Presentation` 不 import `Transport`；`Transport` 不 import `SwiftUI`/`AppKit`
2. `Capture` 不持有也不修改 `Domain` 状态，只返回 `CaptureResult`
3. `StreamCoordinator` 是**唯一**的「流 → UI」汇聚点，五个通道无旁路
4. 依赖注入统一走 `DependencyContainer`，禁止散落单例（`Log` 除外）
5. UI 与 Domain 全部 `@MainActor`；Transport 全部 `actor`
6. 跨 actor 只传 `Sendable` 值类型；禁止 `@unchecked Sendable`
7. 所有非继承 `class` 必须 `final`
8. 可见性最小化：能 `private` 不 `internal`，能 `internal` 不 `public`

## 3.4 性能铁律（违反即红线不达标）
1. **只增量**：`textStorage.append(_:)`，禁止任何重建全文 `AttributedString` 的路径
2. **必合帧**：Transport 侧 16.6ms 时间窗聚合成 `TokenBatch` 才发 UI；禁止逐 delta 通知 UI
3. **流中零落库**：流式进行中不写 SQLite，仅 `done`/`interrupted` 时一次写入
4. **批量裁剪**：scrollback 超限时每次裁 5000 行，禁止逐行删除
5. **先反馈后等待**：Action 路径必须先渲染 user 消息与 streaming 占位，再发起网络请求
6. **仅重绘光标行**：闪烁光标不得触发整个 textView 重绘

## 3.5 错误处理规范
1. 每个 `catch` 必须：映射为 `AppError` → 记 `Log` → 必要时呈现用户可读文案。三者缺一不可
2. 禁止 raw error 直出到 UI
3. 所有边界（用户输入、配置文件、网络响应、剪贴板内容）必须校验；内部调用信任类型系统，不做冗余防御
4. 不为不可能发生的场景写兜底分支

## 3.6 注释规范
1. 只解释**为什么**，不复述代码做了什么
2. 每个非平凡算法（ANSI 状态机、合帧、剪贴板恢复、SSE 增量解析）必须有一段说明设计意图与边界
3. 禁止文件头版权注释块、禁止 `// MARK: -` 之外的装饰性分隔
4. 公开类型必须有一行用途说明

---

# 第 4 部分 · 配置契约

## 4.1 位置与热重载
- 主路径：`~/.config/consolepilot/config.toml`
- 兼容路径：`~/Library/Application Support/Consolepilot/config.toml`（主路径不存在时使用）
- 首次运行自动生成带完整注释的默认配置
- 热重载：`DispatchSource` 监听 vnode；保存即生效
- **失败策略**：解析或校验失败时**保留上一份有效配置**，控制台显示带行号的错误，绝不因配置错误让 App 失能

## 4.2 默认配置模板（原样内嵌于 `DefaultConfig.swift`）
```toml
# ============================================================
# Consolepilot 配置文件
# 保存后自动生效。语法错误时会保留上一份有效配置并在控制台提示。
# 密钥请勿明文写在这里，用 ${keychain:名称} 或 ${env:变量名} 引用。
# ============================================================

[general]
port            = 8765          # CLI / HTTP 推送监听端口（仅 127.0.0.1）
theme           = "tokyo-night" # tokyo-night | solarized-dark | nord | mono
opacity         = 0.92          # 0.75 – 1.0
alwaysOnTop     = true
fontName        = "SF Mono"
fontSize        = 13
compactFontSize = 11            # 小副屏紧凑模式字号
scrollbackLines = 100000
launchAtLogin   = false

# 呼出 / 隐藏控制台的全局快捷键。
# 默认留空 = 不注册，窗口手动打开即可。
# 想用就填，例如 "cmd+shift+space" 或 "ctrl+`"
toggleHotkey    = ""

[server]
# LocalServer 仅监听 127.0.0.1。首次启动会生成随机 token 并写入 Keychain；
# 也可改为 ${env:CONSOLEPILOT_SERVER_TOKEN}。请求必须携带 Authorization: Bearer <token>。
authToken       = "${keychain:consolepilot-server}"
maxBodyBytes    = 1048576      # 1 MiB – 10 MiB；超限返回 HTTP 413

[capture]
strategy          = ["accessibility", "simulatedCopy", "clipboard"]
simulatedCopyWait = 120         # 模拟 ⌘C 后等待剪贴板更新的毫秒数
restoreClipboard  = true        # 模拟 ⌘C 后恢复原剪贴板（强烈建议 true）
maxInputChars     = 40000       # 超长选中内容截断上限
excludeBundleIds  = [
  "com.apple.keychainaccess",
  "com.agilebits.onepassword7",
]

[[profiles]]
id          = "gpt"
provider    = "openai"
baseURL     = "https://api.openai.com/v1"
model       = "gpt-4o-mini"
apiKey      = "${keychain:openai}"
temperature = 0.3
maxTokens   = 4096
timeoutSec  = 120
priceInput  = 0.15   # 美元 / 百万 token，仅用于本地成本估算
priceOutput = 0.60

[[profiles]]
id          = "claude"
provider    = "anthropic"
baseURL     = "https://api.anthropic.com"
model       = "claude-sonnet-4"
apiKey      = "${keychain:anthropic}"
temperature = 0.3
maxTokens   = 8192
timeoutSec  = 180
priceInput  = 3.00
priceOutput = 15.00

# 本地模型示例（OpenAI 兼容协议，无需 Key）
# [[profiles]]
# id       = "local"
# provider = "openai"
# baseURL  = "http://127.0.0.1:11434/v1"
# model    = "qwen2.5:14b"
# apiKey   = ""

[[actions]]
id           = "explain"
name         = "解释这段内容"
hotkey       = "cmd+shift+e"
profile      = "gpt"
input        = "selection"
systemPrompt = "你是一位善于把复杂概念讲清楚的老师。用简洁中文回答，不要客套。"
userPrompt   = """
请解释下面这段来自 {{app}} 的内容：

{{input}}
"""
attachTo     = "newSession"
autoShow     = true
notifyOnDone = false

[[actions]]
id         = "translate"
name       = "翻译为中文"
hotkey     = "cmd+shift+t"
profile    = "gpt"
input      = "selection"
userPrompt = "把下面内容翻译成自然流畅的简体中文，只输出译文：\n\n{{input}}"

[[actions]]
id           = "review"
name         = "代码审查"
hotkey       = "cmd+shift+r"
profile      = "claude"
input        = "selection"
systemPrompt = "你是严谨的资深工程师。指出真实问题，不要泛泛而谈，不要夸奖。"
userPrompt   = """
审查这段代码，按「严重问题 / 可改进 / 可忽略」三级列出，并给出修改建议：

{{input}}
"""

[[actions]]
id         = "ask"
name       = "自由提问"
hotkey     = "cmd+shift+a"
profile    = "gpt"
input      = "prompt"
userPrompt = "{{input}}"

[[actions]]
id         = "summarize"
name       = "总结要点"
hotkey     = "cmd+shift+s"
profile    = "gpt"
input      = "selection"
userPrompt = "用不超过 5 条要点总结下面内容，每条一行：\n\n{{input}}"

[[tails]]
path    = "~/ai-logs/*.log"
enabled = false
format  = "text"    # text | jsonl
fromEnd = true
```

## 4.3 模板占位符（`TemplateEngine` 支持的全集）
| 占位符 | 含义 |
|---|---|
| `{{input}}` | 捕获到的文字（按 action 的 `input` 来源） |
| `{{selection}}` | 强制取选中文字 |
| `{{clipboard}}` | 强制取剪贴板 |
| `{{app}}` | 前台 App 名称 |
| `{{appBundleId}}` | 前台 App bundle id |
| `{{windowTitle}}` | 前台窗口标题（AX 可得时，否则空串） |
| `{{date}}` `{{time}}` `{{datetime}}` | 本地时间 |
| `{{lang}}` | 系统语言（如 `zh-Hans`） |
| `{{env:NAME}}` | 环境变量（缺失则校验期报错） |

未知占位符在**配置校验期**报错并指出行号，运行期不会遇到。

## 4.4 校验规则（`ConfigValidator` 逐条实现，全部错误一次性列出并带行号）
| # | 规则 | 错误码 |
|---|---|---|
| V1 | `profile.id` 全局唯一 | `duplicateProfileId` |
| V2 | `action.id` 全局唯一 | `duplicateActionId` |
| V3 | `action.profile` 必须存在于 profiles | `unknownProfileRef` |
| V4 | `hotkey` 语法合法（`(cmd\|ctrl\|alt\|shift)+…+key`） | `invalidHotkeySyntax` |
| V5 | 各 `action.hotkey` 互不重复 | `duplicateHotkey` |
| V6 | `action.hotkey` 不与非空 `toggleHotkey` 冲突 | `hotkeyConflictWithToggle` |
| V7 | `toggleHotkey` 为空字符串是**合法值**，表示不注册 | — |
| V8 | `userPrompt`/`systemPrompt` 占位符全部已知 | `unknownPlaceholder` |
| V9 | `baseURL` 是合法 URL 且 scheme 为 http/https | `invalidBaseURL` |
| V10 | 远程 `apiKey` 必须是可解析的 `${keychain:...}` 或 `${env:...}` 引用；明文禁止；空串仅当 `baseURL` 为环回地址时允许 | `unresolvableSecret` |
| V11 | `opacity` ∈ [0.75, 1.0] | `valueOutOfRange` |
| V12 | `temperature` ∈ [0, 2] | `valueOutOfRange` |
| V13 | `maxTokens` > 0；`timeoutSec` > 0；`scrollbackLines` ≥ 1000 | `valueOutOfRange` |
| V14 | `port` ∈ [1024, 65535] | `valueOutOfRange` |
| V15 | `theme` 属于已注册主题名 | `unknownTheme` |
| V16 | `capture.strategy` 元素属于 `{accessibility, simulatedCopy, clipboard}` 且非空 | `invalidStrategy` |
| V17 | `capture.maxInputChars` ∈ [100, 1_000_000] | `valueOutOfRange` |
| V18 | `action.input` 属于 `{selection, clipboard, prompt, none}` | `invalidInputSource` |
| V19 | `action.attachTo` 属于 `{newSession, currentSession}` | `invalidAttachMode` |
| V20 | `tails.format` 属于 `{text, jsonl}`；`path` 展开后父目录存在 | `invalidTailConfig` |
| V21 | `provider` 属于 `{openai, anthropic}` | `unknownProvider` |
| V22 | `input = "selection"` 且无辅助功能权限 → **警告**（非错误），说明将降级 | `warnNoAXPermission` |
| V23 | `server.authToken` 必须是 `${keychain:...}` 或 `${env:...}`；禁止明文；`maxBodyBytes` ∈ [1 KiB, 10 MiB] | `invalidServerAuth` |

---

# 第 5 部分 · 代码规格（Code Spec）

> 本部分给出全部核心类型的**确切 Swift 签名**。实施阶段照此实现，不再做设计决策。
> 标注 `[待 Cn 锁定]` 的实现细节由对应 Spike 决定，但**签名不变**。

## 5.1 Infrastructure

### `Log.swift`
```swift
enum Log {
    static func debug(_ message: String, category: Category = .app)
    static func info(_ message: String, category: Category = .app)
    static func warn(_ message: String, category: Category = .app)
    static func error(_ message: String, category: Category = .app)

    enum Category: String {
        case app, config, capture, transport, render, domain, server, hotkey
    }
}
```
约束：底层用 `os.Logger(subsystem: "com.local.consolepilot", category:)`。**禁止**记录对话正文与密钥。

### `AppError.swift`
```swift
enum AppError: Error, Equatable {
    case config(ConfigError)
    case capture(CaptureError)
    case transport(TransportError)
    case storage(StorageError)
    case server(ServerError)

    /// 面向用户的可读文案，UI 只呈现这个
    var userMessage: String { get }
    /// 是否建议用户重试
    var isRetryable: Bool { get }
}
```

### `ConfigSchema.swift`
```swift
struct AppConfig: Sendable, Equatable {
    let general: GeneralConfig
    let server: ServerConfig
    let capture: CaptureConfig
    let profiles: [Profile]
    let actions: [Action]
    let tails: [TailConfig]

    func profile(id: String) -> Profile?
    func action(id: String) -> Action?
}

struct ServerConfig: Sendable, Equatable {
    /// 未解析的 Bearer token 引用；空值仅用于首次引导，服务未完成鉴权配置前不得启动
    let authTokenRef: String
    let maxBodyBytes: Int
}

struct GeneralConfig: Sendable, Equatable {
    let port: UInt16
    let theme: String
    let opacity: Double
    let alwaysOnTop: Bool
    let fontName: String
    let fontSize: Double
    let compactFontSize: Double
    let scrollbackLines: Int
    let launchAtLogin: Bool
    /// 空 = 不注册（A14）
    let toggleHotkey: String
}

struct CaptureConfig: Sendable, Equatable {
    let strategy: [CaptureStrategy]
    let simulatedCopyWait: Duration
    let restoreClipboard: Bool
    let maxInputChars: Int
    let excludeBundleIds: Set<String>
}

enum CaptureStrategy: String, Sendable, CaseIterable {
    case accessibility, simulatedCopy, clipboard
}

struct Profile: Sendable, Equatable, Identifiable {
    let id: String
    let provider: ProviderKind
    let baseURL: URL
    let model: String
    /// 未解析的引用形式，如 "${keychain:openai}"
    let apiKeyRef: String
    let temperature: Double
    let maxTokens: Int
    let timeoutSec: Int
    let priceInput: Double?
    let priceOutput: Double?
}

enum ProviderKind: String, Sendable, CaseIterable {
    case openai, anthropic
}

struct Action: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let hotkey: String?
    let profileId: String
    let systemPrompt: String?
    let userPrompt: String
    let input: InputSource
    let attachTo: AttachMode
    let autoShow: Bool
    let notifyOnDone: Bool
    let overrides: ParamOverrides?
}

enum InputSource: String, Sendable { case selection, clipboard, prompt, none }
enum AttachMode: String, Sendable { case newSession, currentSession }

struct ParamOverrides: Sendable, Equatable {
    let temperature: Double?
    let maxTokens: Int?
    let model: String?
}

struct TailConfig: Sendable, Equatable {
    let path: String
    let enabled: Bool
    let format: TailFormat
    let fromEnd: Bool
}

enum TailFormat: String, Sendable { case text, jsonl }
```

### `ConfigLoader.swift`
```swift
struct ConfigLoader {
    /// 解析 TOML 文本 → AppConfig。不做语义校验，仅结构解析
    /// [待 C18 锁定：TOMLDecoder 库 or 自研子集解析器]
    func parse(_ text: String) throws -> AppConfig

    /// 定位配置文件；不存在则写入默认模板后返回
    func resolveConfigURL() throws -> URL

    /// 读取 + 解析 + 校验，全部通过才返回
    func loadValidated() throws -> AppConfig
}
```

### `ConfigValidator.swift`
```swift
struct ConfigValidator {
    /// 执行 4.4 全部规则。返回值同时含错误与警告
    /// 错误非空 → 调用方必须拒绝该配置
    func validate(_ config: AppConfig, sourceText: String) -> ValidationReport
}

struct ValidationReport: Equatable {
    let errors: [ConfigIssue]
    let warnings: [ConfigIssue]
    var isAcceptable: Bool { errors.isEmpty }
}

struct ConfigIssue: Equatable {
    let code: ConfigErrorCode
    let line: Int?
    let message: String
}

enum ConfigErrorCode: String {
    case duplicateProfileId, duplicateActionId, unknownProfileRef
    case invalidHotkeySyntax, duplicateHotkey, hotkeyConflictWithToggle
    case unknownPlaceholder, invalidBaseURL, unresolvableSecret
    case valueOutOfRange, unknownTheme, invalidStrategy
    case invalidInputSource, invalidAttachMode, invalidTailConfig
    case unknownProvider, invalidServerAuth, parseFailure
    case warnNoAXPermission
}
```

### `ConfigStore.swift`（热重载的唯一入口）
```swift
@MainActor @Observable
final class ConfigStore {
    /// 当前生效配置。解析失败时保持上一份有效值不变
    private(set) var current: AppConfig
    /// 最近一次校验结果，供 UI 显示错误
    private(set) var lastReport: ValidationReport

    init(loader: ConfigLoader, validator: ConfigValidator) throws

    /// 开始监听文件变化（含原子写 mv 场景）[待 C18 锁定]
    func startWatching()
    func stopWatching()
    /// 手动重载（/reload 与 CLI reload 用）
    func reload()
}
```
**铁律**：`reload()` 内部若校验不通过，**只更新 `lastReport`，绝不改 `current`**。

### `SecretResolver.swift`
```swift
struct SecretResolver {
    /// 解析 "${keychain:name}" / "${env:VAR}" / 空串；远程 Profile 禁止明文
    /// 返回的密钥禁止进入 Log、DB、导出文件
    func resolve(_ reference: String) throws -> String
    /// 仅检查可解析性，不返回明文（供校验期使用）
    func canResolve(_ reference: String) -> Bool
}
```

### `KeychainStore.swift`
```swift
struct KeychainStore {
    /// service 固定 "com.local.consolepilot"，account 为 name
    func read(name: String) throws -> String
    func write(name: String, value: String) throws
    func delete(name: String) throws
    func exists(name: String) -> Bool
    /// 清除全部数据功能用
    func deleteAll() throws
}
```

### `Database.swift` / `Migrations.swift`
```swift
final class Database {
    init(url: URL) throws
    /// 执行全部未应用迁移
    func migrate() throws
    var reader: DatabaseReader { get }
    var writer: DatabaseWriter { get }
}

enum Migrations {
    /// 注册 v1；后续版本只增不改
    static func register(in migrator: inout DatabaseMigrator)
}
```
配置：`journal_mode = WAL`、`foreign_keys = ON`、`busy_timeout = 5000`。

### `HotkeyRegistry.swift`
```swift
@MainActor
final class HotkeyRegistry {
    /// 全量替换注册表：先注销旧的，再注册新的。热重载调用此方法
    /// 空字符串或 nil 的 hotkey 直接跳过（C16）
    func replaceAll(actions: [Action], toggleHotkey: String?, onAction: @escaping (String) -> Void, onToggle: @escaping () -> Void)
    func unregisterAll()
    /// 解析 "cmd+shift+e" → 修饰键与键码 [待 C15 锁定]
    static func parse(_ spec: String) -> HotkeySpec?
}

struct HotkeySpec: Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
}
```
**铁律**：`replaceAll` 必须先完整注销再注册，禁止增量补丁式更新（避免泄漏与重复触发）。

## 5.2 Capture

### `CaptureResult.swift`
```swift
struct CaptureResult: Sendable, Equatable {
    let text: String
    let strategy: CaptureStrategy
    let sourceApp: String?
    let sourceBundleId: String?
    let windowTitle: String?
    let wasTruncated: Bool
    let originalLength: Int
    let elapsed: Duration
}

enum CaptureError: Error, Equatable {
    case noPermission
    case allStrategiesFailed
    case emptySelection
    case excludedApp(String)
    case secureInputActive
}
```

### `TextCaptureService.swift`
```swift
@MainActor
final class TextCaptureService {
    init(config: CaptureConfig, permission: PermissionChecker, frontmost: FrontmostAppObserver)

    /// 按 config.strategy 顺序尝试；全部失败抛 allStrategiesFailed
    /// 无论成功失败，走过 simulatedCopy 就必须已恢复剪贴板
    func capture() async throws -> CaptureResult

    /// /capture test 用：返回各策略当前可用性
    func diagnose() -> [CaptureStrategy: Bool]
}
```

### `AccessibilityCapture.swift`
```swift
struct AccessibilityCapture {
    /// [待 C1 锁定：kAXSelectedTextAttribute 直读 or Range+StringForRange]
    func selectedText() throws -> String
    func focusedWindowTitle() -> String?
}
```

### `SimulatedCopyCapture.swift`
```swift
@MainActor
struct SimulatedCopyCapture {
    /// 1. 快照剪贴板 2. 合成 ⌘C 3. 轮询 changeCount 4. 取值 5. defer 恢复
    /// [待 C2 锁定：CGEvent or AXPerformAction or AppleScript]
    /// 铁律：任何路径（含抛错）都必须恢复剪贴板
    func copyAndRead(wait: Duration, restore: Bool) async throws -> String
}
```

### `ClipboardSnapshot.swift`
```swift
struct ClipboardSnapshot {
    /// 捕获 pasteboard 全部 item 的全部 type 与 data [待 C3 锁定]
    static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot
    /// 完整还原。changeCount 会变化，但内容需逐 type 一致
    func restore(to pasteboard: NSPasteboard)
    /// 测试用：逐 type 比较
    func isContentEqual(to other: ClipboardSnapshot) -> Bool
}
```

### `SecureInputDetector.swift` / `PermissionChecker.swift`
```swift
struct SecureInputDetector {
    /// IsSecureEventInputEnabled() [C4]
    static var isActive: Bool { get }
}

struct PermissionChecker {
    /// AXIsProcessTrusted() [C5]
    static var hasAccessibility: Bool { get }
    /// 弹系统授权提示
    static func requestAccessibility()
    /// 打开系统设置对应页
    static func openAccessibilitySettings()
}
```

### `FrontmostAppObserver.swift`
```swift
@MainActor
final class FrontmostAppObserver {
    /// 触发 action 瞬间记录，避免窗口切换后信息失真
    func snapshot() -> FrontmostInfo
}

struct FrontmostInfo: Sendable, Equatable {
    let appName: String?
    let bundleId: String?
    let windowTitle: String?
}
```

## 5.3 Rendering

### `Theme.swift`
```swift
struct Theme: Sendable, Equatable {
    let name: String
    let background: NSColor
    let foreground: NSColor
    let cursor: NSColor
    let ansi: [NSColor]           // 16 色
    let roleColors: [MessageRole: NSColor]
    let channelColors: [SessionChannel: NSColor]
    let codeBackground: NSColor
    let syntax: SyntaxPalette

    static let registry: [String: Theme]   // tokyo-night / solarized-dark / nord / mono
}

struct SyntaxPalette: Sendable, Equatable {
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let type: NSColor
    let function: NSColor
}
```
**铁律**：全仓禁止硬编码颜色，一律经 `Theme`。

### `ANSIParser.swift`
```swift
/// 增量状态机：跨 batch 调用时状态自动延续
struct ANSIParser {
    /// 转义序列可能被 batch 边界切断，未完成的序列缓存在内部
    mutating func consume(_ text: String) -> [ANSISpan]
    /// 流结束时调用，冲出残留缓冲
    mutating func flush() -> [ANSISpan]
}

struct ANSISpan: Equatable {
    let text: String
    let attributes: ANSIAttribute
}

struct ANSIAttribute: Equatable, Sendable {
    var foreground: Int?
    var background: Int?
    var bold: Bool
    var italic: Bool
    var underline: Bool
    static let `default`: ANSIAttribute
}
```

### `MarkdownStyler.swift` / `PendingBlockState.swift`
```swift
/// 流式 Markdown 上色。核心难点：代码块可能未闭合
struct MarkdownStyler {
    /// 返回增量 AttributedString 与需要回溯上色的范围
    /// [待 C8 锁定：setAttributes 回溯]
    mutating func style(_ increment: String, theme: Theme) -> StyleOutput
    mutating func flush(theme: Theme) -> StyleOutput
}

struct StyleOutput {
    let increment: NSAttributedString
    /// 代码块闭合时，回溯上色已追加内容的范围（相对全文）
    let retroactive: [(range: NSRange, attributes: [NSAttributedString.Key: Any])]
}

/// 未闭合块的状态机
struct PendingBlockState: Equatable {
    enum Kind: Equatable { case none, fencedCode(language: String?), list, quote }
    var kind: Kind
    var startOffset: Int
}
```
**关键测试断言**：逐字符喂入的最终 `NSAttributedString` 必须与一次性喂入完全相等。

### `TerminalRenderer.swift`
```swift
@MainActor
final class TerminalRenderer {
    init(textView: TerminalNSTextView, theme: Theme, scrollbackLines: Int)

    /// 唯一的追加入口。只做增量 append，绝不重建全文
    func append(_ batch: TokenBatch)
    /// 消息头（时间戳、角色、模型、来源 App）
    func appendHeader(_ header: MessageHeader)
    /// 流结束标记；interrupted 时渲染 ⚠
    func finishStream(state: MessageState)
    func clear()
    /// 超限时批量裁剪 5000 行 [待 C7 锁定]
    func trimIfNeeded()
    /// 主题切换：唯一允许的全量重绘场景
    func applyTheme(_ theme: Theme)
    /// 用户是否在底部，决定是否自动跟随滚动
    var isPinnedToBottom: Bool { get }
}
```

### `TerminalNSTextView.swift` / `TerminalTextView.swift`
```swift
/// [待 C6 锁定：TextKit2 or TextKit1]
final class TerminalNSTextView: NSTextView {
    /// 仅重绘光标所在行（性能铁律 6）
    func setStreamingCursorVisible(_ visible: Bool)
    /// [待 C9/C10 锁定：keyDown 拦截 + hasMarkedText 判定]
    override func keyDown(with event: NSEvent)
    var onKeyCommand: ((TerminalKeyCommand) -> Void)?
}

enum TerminalKeyCommand: Equatable {
    case interrupt          // ^C
    case clear              // ^L
    case historyPrev        // ↑
    case historyNext        // ↓
    case complete           // Tab
    case submit             // ⏎（非 IME 组合态）
    case newline            // ⇧⏎
}

struct TerminalTextView: NSViewRepresentable { /* 桥接 */ }
```

## 5.4 Transport

### `StreamEvent.swift` / `TokenBatch.swift`
```swift
enum StreamEvent: Sendable, Equatable {
    case started(model: String)
    case delta(String)
    case usage(input: Int, output: Int)
    case finished
    case failed(TransportError)
}

/// 16.6ms 合帧后的批次（性能核心）
struct TokenBatch: Sendable, Equatable {
    let sessionId: String
    let text: String
    let deltaCount: Int
}
```

### `TransportError.swift`
```swift
enum TransportError: Error, Equatable {
    case unauthorized
    case rateLimited(retryAfter: Duration?)
    case serverError(status: Int)
    case network(URLError.Code)
    case decoding(String)
    case cancelled
    case interrupted
    case connectionLost
    case configInvalid(String)

    var userMessage: String { get }
    var isRetryable: Bool { get }   // 仅 rateLimited 与 5xx 为 true
}
```

### `SSEDecoder.swift`
```swift
/// 纯增量解析器：零网络依赖，100% 可单测
/// 必须正确处理 UTF-8 多字节字符被 chunk 边界切断的情况
struct SSEDecoder {
    mutating func consume(_ bytes: some Sequence<UInt8>) -> [SSEFrame]
    mutating func flush() -> [SSEFrame]
}

struct SSEFrame: Equatable {
    let event: String?
    let data: String
}
```

### `AIProvider.swift`
```swift
protocol AIProvider: Sendable {
    /// 发起流式请求。取消 Task 必须真正断开 TCP [C12]
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error>
}

struct ChatRequest: Sendable, Equatable {
    let profile: Profile
    let apiKey: String
    let systemPrompt: String?
    let messages: [ChatMessage]
    let overrides: ParamOverrides?
}

struct ChatMessage: Sendable, Equatable {
    let role: MessageRole
    let content: String
}

enum MessageRole: String, Sendable, CaseIterable {
    case system, user, assistant, external
}
```

### `OpenAICompatibleProvider.swift` / `AnthropicProvider.swift` / `RequestBuilder.swift`
```swift
actor OpenAICompatibleProvider: AIProvider { init(session: URLSession) }
actor AnthropicProvider: AIProvider { init(session: URLSession) }

struct RequestBuilder {
    /// 参数优先级：overrides > profile
    func buildOpenAI(_ request: ChatRequest) throws -> URLRequest
    func buildAnthropic(_ request: ChatRequest) throws -> URLRequest
}
```

### `LocalServer.swift` 及路由
```swift
actor LocalServer {
    /// 仅绑 127.0.0.1；端口占用时自动 +1 试 5 次后抛错
    init(config: ServerConfig, port: UInt16, cli: CLIRouter, push: PushRouter, secrets: SecretResolver)
    func start() throws
    func stop()
    var actualPort: UInt16 { get }
}

enum ServerError: Error, Equatable {
    case portUnavailable(tried: [UInt16])
    case nonLoopbackRejected
    case payloadTooLarge
    case tooManyConnections
    case unauthorized
}
```
**安全红线**：非 `127.0.0.1`/`::1` 来源一律 403；缺少或不匹配 `Authorization: Bearer <token>` 一律 401；请求体超过 `maxBodyBytes` 返回 413；以上均必须有测试证明。

### `FileTailWatcher.swift`
```swift
actor FileTailWatcher {
    init(config: TailConfig, onLine: @escaping @Sendable (String) -> Void)
    func start() throws
    func stop()
    /// inode 变化（日志轮转）时自动重开；文件删除时暂停并上报
}
```

## 5.5 Domain

### `Session.swift` / `Message.swift` / `UsageRecord.swift`
```swift
struct Session: Identifiable, Sendable, Equatable {
    let id: String
    var title: String
    let channel: SessionChannel
    let actionId: String?
    let profileId: String?
    let provider: ProviderKind?
    let model: String?
    let sourceApp: String?
    let createdAt: Date
    var updatedAt: Date
    var archived: Bool
}

struct SessionMeta: Sendable, Equatable {
    let actionId: String?
    let profileId: String?
    let provider: ProviderKind?
    let model: String?
    let sourceApp: String?
}

enum SessionChannel: String, Sendable, CaseIterable {
    case action, console, cli, push, tail
}

struct Message: Identifiable, Sendable, Equatable {
    let id: String
    let sessionId: String
    let role: MessageRole
    var content: String
    var state: MessageState
    let createdAt: Date
}

enum MessageState: String, Sendable {
    case complete, interrupted, failed
}

struct MessageHeader: Sendable, Equatable {
    let timestamp: Date
    let role: MessageRole
    let channel: SessionChannel
    let model: String?
    let sourceApp: String?
}

struct UsageRecord: Identifiable, Sendable, Equatable {
    let id: String
    let sessionId: String?
    let actionId: String?
    let profileId: String
    let provider: ProviderKind
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double?
    let ttfb: Duration?
    let total: Duration?
    let createdAt: Date
}

struct CaptureLogEntry: Identifiable, Sendable, Equatable {
    let id: String
    let sourceApp: String?
    let sourceBundleId: String?
    let characterCount: Int
    let strategy: CaptureStrategy
    let elapsed: Duration
    let createdAt: Date
}
```

### `TemplateEngine.swift`
```swift
struct TemplateEngine {
    /// 渲染模板。未知占位符已在配置校验期拦截，此处不会遇到
    func render(_ template: String, context: TemplateContext) -> String
    /// 校验期用：返回模板中出现的全部占位符名
    static func placeholders(in template: String) -> Set<String>
    static let knownPlaceholders: Set<String>
}

struct TemplateContext: Sendable {
    let input: String
    let selection: String?
    let clipboard: String?
    let frontmost: FrontmostInfo
    let now: Date
    let language: String
}
```

### `StreamCoordinator.swift`（性能核心）
```swift
/// 唯一的「流 → UI」汇聚点。五个通道全部经此
@MainActor
final class StreamCoordinator {
    init(renderer: TerminalRenderer, sessionStore: SessionStore, usageStore: UsageStore)

    /// 消费任意来源的事件流。内部做 16.6ms 合帧
    func consume(_ events: AsyncThrowingStream<StreamEvent, Error>, into sessionId: String) async
    /// ^C：取消当前流，标记 interrupted [C12]
    func interruptCurrent()
    var isStreaming: Bool { get }
}
```
**铁律**：合帧窗口 16.6ms；1000 个 delta 触发的 UI 更新必须 < 100 次；拼接结果与原始序列完全一致（零丢字）。

### `ActionRunner.swift`
```swift
@MainActor
final class ActionRunner {
    init(config: ConfigStore, capture: TextCaptureService, secrets: SecretResolver,
         providers: [ProviderKind: AIProvider], coordinator: StreamCoordinator,
         sessionStore: SessionStore)

    /// 严格按 4.2 时序：捕获 → 渲染 user 消息 → 再发起网络
    /// 捕获失败不静默：抛错并由 UI 呈现明确提示
    func run(actionId: String, overrideInput: String?) async throws
}
```

### `SessionStore.swift` / `UsageStore.swift` / `ConversationEngine.swift` / `CommandRouter.swift`
```swift
@MainActor @Observable
final class SessionStore {
    private(set) var sessions: [Session]
    private(set) var currentId: String?
    private(set) var messages: [Message]      // 仅当前会话

    func create(channel: SessionChannel, title: String, meta: SessionMeta) -> Session
    func select(_ id: String)
    func rename(_ id: String, to title: String)
    func delete(_ id: String)                 // 级联删除 messages
    /// 流结束时一次性落库（性能铁律 3）
    func appendMessage(_ message: Message)
    func search(_ query: String) -> [Message]
}

@MainActor @Observable
final class UsageStore {
    func record(_ usage: UsageRecord)
    func summary(period: UsagePeriod) -> UsageSummary
}

enum UsagePeriod: String { case today, week, all }

struct UsageSummary: Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double
    let requestCount: Int
    let byModel: [String: UsageSummary]
}

@MainActor
final class ConversationEngine {
    /// 控制台内直接发送与追问；复用 action 会话上下文
    func send(_ text: String, in sessionId: String) async throws
}

@MainActor
final class CommandRouter {
    /// 解析并执行 slash 命令
    func execute(_ line: String) async -> CommandOutcome
    static func completions(for prefix: String) -> [String]
}

enum CommandOutcome: Equatable {
    case handled(message: String?)
    case notACommand
    case failed(String)
}
```

## 5.6 Presentation 关键约束
```swift
@MainActor
final class ConsoleWindowController: NSWindowController, NSWindowDelegate {
    /// ⌘W 隐藏而非退出 App（C14）
    func windowShouldClose(_ sender: NSWindow) -> Bool   // 返回 false + orderOut
    /// 菜单栏图标 / Dock / CLI open 的统一入口，必须可靠
    func showWindow()
    /// 宽度 < 700pt 自动紧凑模式
    func updateLayoutMode(for width: CGFloat)
}
```
| 视图 | 唯一职责 |
|---|---|
| `ConsoleRootView` | 布局侧边栏 + 终端 + 输入栏，不含业务逻辑 |
| `TerminalTextView` | 桥接 `TerminalNSTextView`，不做样式计算 |
| `InputBarView` | 输入与键盘命令派发，不直接调 Transport |
| `QuickAskPanel` | `input="prompt"` 的浮层，提交后即销毁 |
| `SessionSidebarView` | 只读 `SessionStore`，操作走方法 |
| `CommandPaletteView` | 搜索并执行 action / slash 命令 |
| `UsagePanelView` | 只读 `UsageStore` |
| `ConfigEditorView` | 编辑 TOML + 显示 `ValidationReport` |
| `OnboardingScene` | 权限 → Key → 配置 → 试跑 四步 |

---

# 第 6 部分 · Spike 验证阶段（S1–S9）

原则：**Spike 全部通过之前不写一行正式代码。** 每个 Spike 是独立可运行的小工程（`Spikes/Sn-*/`），产出一份 `RESULT.md` 填入 第 2 部分 的结论记录表。任一 Spike 不达标 → 走该项的降级方案并回写 A 决策，再继续。

| Spike | 锁定项 | 目标 | 形态 | 预计文件数 |
|---|---|---|---|---|
| S1 | C1–C5 | 跨 App 取选中文字 | 命令行 + 最小 App（需辅助功能权限） | 6 |
| S2 | C6–C8 | 高频文本追加与裁剪性能 | SwiftUI App + 压测按钮 | 5 |
| S3 | C9–C10 | 键盘拦截与输入法 | SwiftUI App | 3 |
| S4 | C11–C12 | SSE 流式与取消 | 命令行 + 本地 mock server | 4 |
| S5 | C13–C14 | 窗口外观与生命周期 | AppKit App | 3 |
| S6 | C15–C16 | 多组全局快捷键 | AppKit App | 3 |
| S7 | 端到端时延 | 快捷键→首字节→首帧 | 复用 S1+S4 | 2 |
| S8 | C17 | ad-hoc 签名下 TCC/Keychain 持久性 | 脚本 + S1 产物 | 2 |
| S9 | C18 | TOML 解析与热重载 | 命令行 | 3 |

## 6.1 S1 · 跨 App 文本捕获（最高风险）
**测试矩阵（15 个 App）**：Safari、Chrome、Xcode、VS Code、Terminal、iTerm2、Notes、Preview(PDF)、Mail、Slack、Figma、WeChat、Word、Finder(文件名)、Warp。

**每个 App 记录 5 列**：AX 直读成功/失败、AX 耗时 ms、⌘C 兜底成功/失败、⌘C 耗时 ms、剪贴板往返是否等价。

**通过阈值（全部满足）**
1. 三条链路合计成功率 ≥ 90%（≥14/15）。
2. AX 直读单次耗时 P95 < 30ms；⌘C 兜底 P95 < 150ms。
3. 剪贴板往返 100 次后 `isContentEqual` 全等价，且富文本/图片/多 item 场景不丢 type。
4. 聚焦密码框时 `IsSecureEventInputEnabled()` 必须为 true，且此时不执行 ⌘C 合成。
5. 运行时在系统设置里撤销辅助功能权限，程序能在 1s 内检测到并给出 `.noPermission`，不崩溃。

**不达标降级（按序）**：① 仅 AX 直读，失败即提示手动复制后按快捷键；② 引导用户改用「先复制再按快捷键」的 `input="clipboard"` 模式作为默认；③ 该 App 列入已知不支持清单写进 README。

## 6.2 S2 · 渲染性能
**压测脚本**：以 50 / 200 / 500 token/s 三档，各持续 60s，token 平均 4 字符，含 30% 中文、10% emoji、含 3 个未闭合代码块。

**通过阈值**
1. 200 token/s 时主线程 CPU < 25%，掉帧（Hitches）时长占比 < 1%。
2. 1000 个 delta 触发的 UI 更新次数 < 100（合帧生效证据）。
3. 输出 10 万行后内存 < 300MB；裁剪至 5000 行单次耗时 < 50ms 且不产生可见跳动。
4. 零丢字：把渲染文本与输入文本做 diff 必须完全相等（含 emoji、组合字符）。
5. 未闭合代码块闭合瞬间回溯上色耗时 < 16ms。

**不达标降级**：TextKit1 → 自绘 CALayer 文本层（仅在 TextKit 两方案均不达标时启用，需重估 M4 工期）。

## 6.3 S3 · 键盘与输入法
**通过阈值**
1. ⏎ 发送 / ⇧⏎ 换行 / ⌘K 清屏 / ⌘L 定位输入 / ⌥↑↓ 历史 / ⌃C 中断 全部生效且不与系统冲突。
2. 拼音与五笔在候选窗打开（`hasMarkedText() == true`）时按 ⏎ **必须**只上屏候选词，不触发发送，20 次连续测试 0 次误发。
3. 流式输出中按 ⌃C，UI 在 100ms 内显示中断标记。

## 6.4 S4 · SSE 流式与取消
**mock server**：本地 Python 脚本，可配置首字节延迟、token 间隔、故意在中途切断连接、发送畸形 SSE 行、把一个 UTF-8 中文字符拆到两个 chunk。

**通过阈值**
1. UTF-8 跨 chunk 拆分不产生乱码（含 4 字节 emoji）。
2. `data: [DONE]`、空行、注释行、`event:` 行处理正确；畸形行跳过并计数，不中断流。
3. 服务端中途断连 → 抛 `TransportError.connectionLost`，已收文本保留并落库。
4. `Task.cancel()` 后用 `lsof -p <pid> -i` 确认 TCP 连接 1s 内消失（不是仅停止读取）。
5. OpenAI 与 Anthropic 两种响应格式各跑通一次真实调用。

## 6.5 S5 · 窗口
**通过阈值**：透明标题栏 + 毛玻璃 + 可切换置顶正常；⌘W 隐藏且 App 不退出；从菜单栏图标、Dock 图标、`consolepilot open` 三条路径重新唤出窗口各 10 次全成功；副屏拔插后窗口不丢失（回落主屏或记住上次屏幕）。

## 6.6 S6 · 全局快捷键
**通过阈值**：同时注册 5 组快捷键全部触发；`toggleHotkey = ""` 时不注册且无报错；热重载后旧快捷键完全失效、新的立即生效（先注销后注册验证）；与系统/其它 App 冲突时给出明确报错而非静默失败。

## 6.7 S7 · 端到端时延
**通过阈值**：按下快捷键 → 控制台出现「已捕获 N 字」反馈 < 120ms；→ 首个 token 渲染 = 网络首字节 + < 50ms。

## 6.8 S8 · 签名与权限持久性
**步骤**：ad-hoc 签名构建 → 授予辅助功能权限 → 写入 Keychain → 修改一行代码重新构建 → 检查权限与 Keychain 是否仍有效。重复 3 次。

**通过阈值**：权限与 Keychain 至少其一保持；若两者都失效，启用降级：① 免费 Apple ID 本地签名（稳定 Bundle ID + 稳定签名身份）；② Keychain 不可用时改用 `${env:VAR}` 或 macOS 加密文件方案。**此 Spike 的结论直接决定 第 8 部分 的签名脚本形态。**

## 6.9 S9 · 配置解析与热重载
**通过阈值**：默认模板完整往返解析正确；写入非法配置后 `current` 保持上一份有效配置且 `lastReport` 含准确错误码与行号；连续保存 20 次（含编辑器原子替换导致的 inode 变化）监听不丢失；V1–V23 每条规则各有一个失败样例被正确捕获。

---

# 第 7 部分 · 实施里程碑（M1–M11，含文件级交付清单与 DoD）

每个里程碑的 DoD（Definition of Done）统一附加三条**全局门禁**，下文不再重复：
- G1：`../Scripts/lint.sh` 通过（SwiftLint `--strict` 零告警 + `periphery scan --strict` 零无用声明 + `swift-format lint` 通过）。
- G2：`../Scripts/test.sh` 通过（本里程碑新增代码行覆盖率 ≥ 80%，Domain/Infrastructure 层 ≥ 90%）。
- G3：本里程碑不留 `TODO`/`FIXME`/注释掉的代码/未使用的文件（由 `no_todo_markers`、`no_commented_code`、periphery 强制）。

## M1 · 工程骨架与基础设施
**交付文件**
```
Consolepilot.xcodeproj
Sources/App/ConsolepilotApp.swift
Sources/App/DependencyContainer.swift
Sources/Infrastructure/Log.swift
Sources/Infrastructure/AppError.swift
Sources/Infrastructure/Clock.swift
Tests/InfrastructureTests/LogTests.swift
.swiftlint.yml  .swift-format  Scripts/lint.sh  Scripts/test.sh
```
**DoD**：空窗口可启动；`DependencyContainer` 已定义全部依赖属性（可为 stub）；Swift 6 `complete` 并发检查零告警；`Log` 支持分级与 `no_secret_in_log` 检查；CI 脚本本地可跑。

## M2 · 配置系统
**交付文件**
```
Sources/Infrastructure/Config/ConfigSchema.swift
Sources/Infrastructure/Config/ConfigLoader.swift
Sources/Infrastructure/Config/ConfigValidator.swift
Sources/Infrastructure/Config/ConfigStore.swift
Sources/Infrastructure/Config/DefaultConfig.toml   (bundle resource)
Sources/Infrastructure/Secrets/SecretResolver.swift
Sources/Infrastructure/Secrets/KeychainStore.swift
Tests/ConfigTests/ (ValidatorTests, LoaderTests, HotReloadTests, SecretResolverTests)
Fixtures/Config/invalid-*.toml   (V1–V23 各一个)
```
**DoD**：首次启动自动生成默认配置；V1–V23 全部有单测；热重载 20 次不丢监听；校验失败保留旧配置；Keychain 读写通过；配置中不出现明文密钥（单测断言）。

## M3 · 数据层
**交付文件**
```
Sources/Infrastructure/Database/Database.swift
Sources/Infrastructure/Database/Migrations.swift
Sources/Domain/Models/{Session,Message,UsageRecord,CaptureLogEntry}.swift
Sources/Domain/Stores/{SessionStore,UsageStore}.swift
Tests/DatabaseTests/{MigrationTests,SessionStoreTests,UsageStoreTests}.swift
```
**DoD**：WAL 开启；迁移可从空库跑到最新版且幂等；`capture_log` 只存元数据（单测断言无内容字段）；1 万条消息查询 P95 < 20ms。

## M4 · 终端渲染引擎
**交付文件**
```
Sources/Rendering/Theme.swift
Sources/Rendering/ANSIParser.swift
Sources/Rendering/MarkdownStyler.swift
Sources/Rendering/TerminalRenderer.swift
Sources/Rendering/TerminalNSTextView.swift
Sources/Rendering/ScrollbackTrimmer.swift
Tests/RenderingTests/{ANSIParserTests,MarkdownStylerTests,RendererTests}.swift
Tests/PerformanceTests/RenderThroughputTests.swift
```
**DoD**：S2 全部阈值在 XCTest Metrics 中复现并纳入回归基线；纯增量追加（代码审查确认无全量重设）；裁剪批量执行；光标闪烁只重绘所在行（Instruments 截图为证）。

## M5 · Transport 与 Provider
**交付文件**
```
Sources/Transport/SSEDecoder.swift
Sources/Transport/StreamEvent.swift
Sources/Transport/TransportError.swift
Sources/Transport/RequestBuilder.swift
Sources/Transport/Providers/{OpenAIProvider,AnthropicProvider}.swift
Tests/TransportTests/{SSEDecoderTests,ProviderTests,CancelTests}.swift
Fixtures/SSE/*.txt   (含畸形、跨 chunk、断连样本)
```
**DoD**：S4 全部阈值通过；取消后 TCP 断开有 `lsof` 证据；两家 Provider 各有一条真实调用记录；错误分类完整（超时/401/429/5xx/断连/畸形）。

## M6 · StreamCoordinator（合帧核心）
**交付文件**
```
Sources/Domain/StreamCoordinator.swift
Sources/Domain/TokenBatch.swift
Tests/DomainTests/StreamCoordinatorTests.swift
Tests/PerformanceTests/CoalescingTests.swift
```
**DoD**：1000 delta → UI 更新 < 100 次（单测断言计数）；零丢字 diff 断言；流式期间 SQLite 写入次数 = 0（用 GRDB trace 断言）；中断后已收内容完整落库；这是**唯一**的流聚合点（架构审查确认无旁路）。

## M7 · 文本捕获
**交付文件**
```
Sources/Capture/CaptureResult.swift
Sources/Capture/TextCaptureService.swift
Sources/Capture/AccessibilityCapture.swift
Sources/Capture/SimulatedCopyCapture.swift
Sources/Capture/ClipboardSnapshot.swift
Sources/Capture/SecureInputDetector.swift
Sources/Capture/PermissionChecker.swift
Sources/Capture/FrontmostAppObserver.swift
Tests/CaptureTests/{ClipboardSnapshotTests,FallbackChainTests,PermissionTests}.swift
```
**DoD**：S1 结论落地为代码；剪贴板往返单测 100 次全等价；安全输入态直接返回错误不合成按键；无权限时给出可点击跳转系统设置的提示。

## M8 · Action 系统与快捷键
**交付文件**
```
Sources/Domain/TemplateEngine.swift
Sources/Domain/ActionRunner.swift
Sources/Infrastructure/Hotkey/HotkeyRegistry.swift
Sources/Infrastructure/Hotkey/HotkeySpec.swift
Tests/DomainTests/{TemplateEngineTests,ActionRunnerTests}.swift
Tests/HotkeyTests/RegistryTests.swift
```
**DoD**：S6 通过；`replaceAll` 先注销后注册（单测断言旧键失效）；空 `toggleHotkey` 不注册；占位符未知即报错；**反馈先于网络**（单测断言 UI 反馈时间戳早于请求发起时间戳）。

## M9 · 窗口与 UI
**交付文件**
```
Sources/Presentation/ConsoleWindowController.swift
Sources/Presentation/ConsoleRootView.swift
Sources/Presentation/TerminalTextView.swift
Sources/Presentation/InputBarView.swift
Sources/Presentation/QuickAskPanel.swift
Sources/Presentation/SessionSidebarView.swift
Sources/Presentation/CommandPaletteView.swift
Sources/Presentation/UsagePanelView.swift
Sources/Presentation/ConfigEditorView.swift
Sources/Presentation/MenuBarController.swift
Sources/Presentation/OnboardingScene.swift
Sources/Domain/{ConversationEngine,CommandRouter}.swift
```
**DoD**：S3、S5 通过；**因为没有默认呼出快捷键**，菜单栏图标、Dock 图标、`consolepilot open` 三条唤出路径各 10 次全成功且有测试记录；⌘W 隐藏不退出；副屏拔插不丢窗口；紧凑模式在 700pt 以下正确切换；Onboarding 四步可完整走通。

## M10 · 兜底通道（环回 HTTP + 文件尾随）与 CLI
**交付文件**
```
Sources/Transport/LocalServer.swift
Sources/Infrastructure/FileTailWatcher.swift
Sources/CLI/main.swift   (consolepilot 可执行文件)
Scripts/install-cli.sh
Tests/ServerTests/{LoopbackTests,AuthTests}.swift
Tests/TailTests/RotationTests.swift
```
**DoD**：非回环来源返回 403；缺失/错误 Bearer token 返回 401；超大请求体返回 413（均有单测）；`consolepilot ask/open/run/tail` 四条子命令可用并有 `--help`；日志轮转与截断时尾随不丢行、不重复。

## M11 · 收尾（打包、文档、加固）
**交付文件**
```
Scripts/{build-local.sh,bootstrap.sh,sign.sh}
Docs/{README.md,CONFIG.md,SHORTCUTS.md,TROUBLESHOOTING.md,FUTURE-PROXY.md,SPIKE-RESULTS.md}
Docs/ACCEPTANCE.md   (第 10 部分 的可勾选版本)
```
**DoD**：第 8 部分 的全部产物齐备（含 `../Resources/Consolepilot.entitlements` 与 `Package.resolved`）；第 9 部分/10 全部通过；`periphery` 零无用声明；Instruments Leaks/Zombies 零泄漏。

---

# 第 8 部分 · 产物交付流程（脚本全文）

## 8.1 产物清单（14 项）
| # | 产物 | 路径 | 说明 |
|---|---|---|---|
| 1 | 应用包 | `../dist/Consolepilot.app` | ad-hoc 签名，可直接拖入「应用程序」 |
| 2 | 压缩包 | `dist/Consolepilot-<version>.zip` | 分发用 |
| 3 | CLI | `../dist/consolepilot` | 安装到 `/usr/local/bin` |
| 4 | 默认配置 | `../dist/config.example.toml` | 与 bundle 内一致 |
| 5 | 构建脚本 | `../Scripts/build-local.sh` | 一键出包 |
| 6 | 安装脚本 | `../Scripts/install-cli.sh` | 装 CLI + 建配置目录 |
| 7 | 引导脚本 | `../Scripts/bootstrap.sh` | 新机环境准备 |
| 8 | 门禁脚本 | `../Scripts/lint.sh` `../Scripts/test.sh` | 见 第 9 部分 |
| 9 | Spike 结论 | `SPIKE-RESULTS.md` | 第 2 部分 结论表填写完成版 |
| 10 | 文档集 | `Docs/*.md` | README/CONFIG/SHORTCUTS/TROUBLESHOOTING |
| 11 | 验收清单 | `ACCEPTANCE.md` | 可勾选，含实机 90 步 |
| 12 | 性能基线 | `Docs/PERF-BASELINE.md` | XCTest Metrics 与 Instruments 截图 |
| 13 | 签名权限声明 | `../Resources/Consolepilot.entitlements` | 非沙盒 App 所需的辅助功能/网络声明，随 target 固定 |
| 14 | 依赖锁定 | `Package.resolved` | SPM 依赖版本、revision 与 checksum 锁定 |

## 8.2 `../Scripts/bootstrap.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
command -v xcodebuild >/dev/null || { echo "需要安装 Xcode"; exit 1; }
SWIFT_VER=$(swift --version | head -1)
echo "toolchain: $SWIFT_VER"
for t in swiftlint swift-format periphery; do
  command -v "$t" >/dev/null || { echo "缺少工具 $t，请按 README 安装与 Swift/Xcode 匹配的版本"; exit 1; }
done
mkdir -p "$HOME/.config/consolepilot"
echo "bootstrap 完成"
```

## 8.3 `../Scripts/lint.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "==> swift-format lint"
swift-format lint --recursive --strict Sources Tests
echo "==> swiftlint (strict)"
swiftlint lint --strict --config .swiftlint.yml
echo "==> swiftlint analyze (需先 build 产生编译日志)"
xcodebuild -scheme Consolepilot -destination 'platform=macOS' \
  -derivedDataPath .build/dd build 2>&1 | tee .build/xcodebuild.log >/dev/null
swiftlint analyze --strict --compiler-log-path .build/xcodebuild.log
echo "==> periphery (无用声明)"
periphery scan --strict --quiet
echo "LINT PASS"
```

## 8.4 `../Scripts/test.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild test -scheme Consolepilot -destination 'platform=macOS' \
  -derivedDataPath .build/dd -enableCodeCoverage YES | tee .build/test.log
xcrun xccov view --report --only-targets .build/dd/Logs/Test/*.xcresult
echo "TEST PASS（覆盖率阈值需人工核对：Domain/Infrastructure ≥90%，整体 ≥80%）"
```

## 8.5 `../Scripts/sign.sh`
```bash
#!/usr/bin/env bash
# 由 S8 结论决定 IDENTITY：ad-hoc 用 "-"，免费 Apple ID 用证书名
set -euo pipefail
APP="$1"
IDENTITY="${CONSOLEPILOT_SIGN_IDENTITY:--}"
codesign --force --deep --options runtime \
  --entitlements Resources/Consolepilot.entitlements \
  -s "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "signed with: $IDENTITY"
```

## 8.6 `../Scripts/build-local.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
rm -rf dist .build/archive
xcodebuild -scheme Consolepilot -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .build/dd \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO build
mkdir -p dist
cp -R ".build/dd/Build/Products/Release/Consolepilot.app" dist/
cp ".build/dd/Build/Products/Release/consolepilot" dist/
cp Sources/Infrastructure/Config/DefaultConfig.toml dist/config.example.toml
./Scripts/sign.sh dist/Consolepilot.app
(cd dist && ditto -c -k --keepParent Consolepilot.app "Consolepilot-${VERSION}.zip")
echo "产物就绪：dist/  版本 ${VERSION}"
```

## 8.7 `../Scripts/install-cli.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="/usr/local/bin/consolepilot"
[ -f dist/consolepilot ] || { echo "先运行 build-local.sh"; exit 1; }
sudo install -m 0755 dist/consolepilot "$BIN"
CFG="$HOME/.config/consolepilot/config.toml"
if [ ! -f "$CFG" ]; then
  mkdir -p "$(dirname "$CFG")"
  cp dist/config.example.toml "$CFG"
  echo "已生成配置：$CFG"
fi
echo "安装完成：$BIN"
```

## 8.8 首次使用流程（写入 README）
1. `../Scripts/bootstrap.sh` → 2. `../Scripts/build-local.sh` → 3. 拖 `../dist/Consolepilot.app` 到应用程序 → 4. 首次启动首右键打开绕过 Gatekeeper → 5. Onboarding 授予辅助功能权限 → 6. 存入 API Key 与 LocalServer token（写 Keychain）→ 7. 编辑 `~/.config/consolepilot/config.toml` → 8. `../Scripts/install-cli.sh` → 9. 选中文字按快捷键试跑。

---

# 第 9 部分 · 验收阶段一：深度审查 + 模拟测试

## 9.1 工具门禁（必须全绿，任一失败即验收不通过）
| 门 | 命令 | 通过标准 |
|---|---|---|
| D1 | `swift-format lint --strict` | 零告警 |
| D2 | `swiftlint lint --strict` | 零告警（含 8 条自定义规则） |
| D3 | `swiftlint analyze --strict` | 零无用声明/无用 import |
| D4 | `periphery scan --strict` | 零无用代码 |
| D5 | Swift 6 `complete` 并发 | 零告警 |
| D6 | `xcodebuild` Release | 零 warning |
| D7 | 覆盖率 | 整体 ≥80%，Domain/Infra ≥90% |
| D8 | `git grep -nE "TODO|FIXME|XXX|HACK"` | 无结果 |

## 9.2 人工深度审查清单（逐条签字，共 24 条）
**架构（8 条）**
- R1 每个文件的 import 不跨越 第 3 部分 的分层规则。
- R2 StreamCoordinator 是唯一流聚合点，无旁路直连 Renderer。
- R3 所有依赖经 DependencyContainer 注入，无全局单例。
- R4 UI/Domain 全 `@MainActor`，Transport 为 `actor`，跨界仅传 `Sendable`。
- R5 所有 class 为 `final`，可见性取最小。
- R6 命名与 第 3 部分 统一表完全一致，无禁用同义词（`git grep` 逐个验证）。
- R7 无「以后可能用到」的预留接口。
- R8 每个 第 5 部分 签名都已实现且无额外公开 API。

**性能（6 条）**
- R9 渲染仅 `NSTextStorage.append`，无全量 `setAttributedString`。
- R10 合帧窗口 16.6ms 生效，有计数断言。
- R11 流式期间零 SQLite 写入，有 trace 断言。
- R12 scrollback 批量裁剪，非逐行删除。
- R13 Action 路径 UI 反馈先于网络请求。
- R14 光标闪烁不触发全文重绘。

**正确性与安全（10 条）**
- R15 无 `try!` / `as!` / 强解包（lint 已覆盖，人工确认无绕过）。
- R16 无空 catch，所有错误转为 `AppError` 并有用户可读文案。
- R17 API Key 不出现在任何日志/DB/配置明文中（`git grep` + 运行时日志抽查）。
- R18 `capture_log` 无内容字段。
- R19 LocalServer 非回环 403、缺失或错误 Bearer token 401、超大请求体 413。
- R20 剪贴板恢复在所有异常路径上都执行（`defer` 审查）。
- R21 安全输入态下不合成按键。
- R22 配置校验失败绝不覆盖 `current`。
- R23 `HotkeyRegistry.replaceAll` 先注销后注册。
- R24 取消流后 TCP 真正断开。

## 9.3 模拟测试 T1–T5
**T1 单元测试**：ANSIParser、MarkdownStyler、SSEDecoder、TemplateEngine、ConfigValidator（V1–V23）、ClipboardSnapshot、HotkeySpec.parse、CommandRouter。要求边界样例：空串、超长（1MB）、纯 emoji、混合 CJK、畸形 ANSI、嵌套代码块。

**T2 集成测试**：mock server + 假捕获源，跑「Action 触发 → 模板渲染 → 请求 → 流式 → 渲染 → 落库 → 用量统计」全链路 5 个场景（正常 / 断连 / 取消 / 401 / 429 重试）。断言 DB 最终状态与 UI 文本一致。

**T3 性能测试（XCTest Metrics，纳入回归基线）**
| 指标 | 阈值 |
|---|---|
| 200 token/s 主线程 CPU | < 25% |
| 1000 delta 的 UI 更新次数 | < 100 |
| 10 万行内存 | < 300MB |
| 裁剪 5000 行耗时 | < 50ms |
| 首帧延迟（首字节后） | < 50ms |
| Action 反馈延迟 | < 120ms |
| 1 万条消息查询 P95 | < 20ms |

**T4 故障注入**：网络中途断开、DNS 失败、超时、返回非 JSON、返回空流、`[DONE]` 缺失、配置文件被删除、配置文件写入非法内容、Keychain 拒绝访问、辅助功能权限运行时撤销、磁盘写满（DB 写失败）、剪贴板被其它程序抢占。每项要求：不崩溃 + 有明确用户提示 + 状态可恢复。

**T5 内存与生命周期**：Instruments Leaks + Zombies 跑 30 分钟混合操作（100 次 Action、50 次窗口开关、20 次热重载、10 次取消流），要求零泄漏、零 zombie；窗口关闭后 `ConsoleWindowController` 之外的视图对象全部释放（`deinit` 日志断言）。

---

# 第 10 部分 · 验收阶段二：实机验收 100 步（核心必过 90 步）

环境：MacBook Air M1 / macOS 14.8.8 / 主屏 + 小尺寸副屏。每步记录「通过 / 失败 + 实测数据」，任一失败必须修复后从该组开头重跑。

## P1 安装与首次启动（步 1–8）
1. 干净机（或删除 `~/.config/consolepilot`、`~/Library/Application Support/Consolepilot`）执行 `../Scripts/bootstrap.sh`，无报错。
2. 执行 `../Scripts/build-local.sh`，`../dist` 出现产物清单中的 1–4 项。
3. `codesign --verify --deep --strict dist/Consolepilot.app` 通过。
4. 拖入「应用程序」，双击被 Gatekeeper 拦截（预期），右键→打开成功启动。
5. Onboarding 第一步提示辅助功能权限，点击可直接跳转系统设置对应面板。
6. 授权后返回 App，权限状态在 2s 内自动变为已授权（无需重启）。
7. Onboarding 第二步输入 API Key，保存后 `~/.config/consolepilot/config.toml` 中**不含**明文 Key。
8. Onboarding 第四步「试跑」成功收到流式回复。

## P2 配置系统（步 9–20）
9. `config.toml` 首次自动生成，内容与 `config.example.toml` 一致。
10. 修改 `theme` 并保存，控制台配色在 1s 内变化，无需重启。
11. 写入重复 `profile.id`，App 报 `duplicateProfileId` 并附行号，界面仍用旧配置正常工作。
12. 写入未知 `profile` 引用，报 `unknownProfileRef`。
13. 写入非法快捷键语法，报 `invalidHotkeySyntax`。
14. 两个 action 使用同一快捷键，报 `duplicateHotkey`。
15. 模板中使用未知占位符，报 `unknownPlaceholder`。
16. `baseURL` 填非 URL，报 `invalidBaseURL`。
17. `${keychain:notexist}` 报 `unresolvableSecret`。
18. `temperature = 5`，报 `valueOutOfRange`。
19. 删除配置文件，App 不崩溃并提示，重建后恢复。
20. 用 VS Code 保存 20 次（原子替换改变 inode），热重载每次都生效。

## P3 文本捕获（步 21–37）
21–35. 依次在 Safari、Chrome、Xcode、VS Code、Terminal、iTerm2、Notes、Preview(PDF)、Mail、Slack、Figma、WeChat、Word、Finder、Warp 中选中一段中英混排文字（含 emoji），按 Action 快捷键，记录：是否捕获成功、走的哪条链路、捕获字数是否正确。**要求 ≥14/15 成功。**
36. 全过程结束后按 ⌘V 到文本编辑器，确认剪贴板仍是测试前手动放入的内容（零污染）。
37. 未选中任何文字时按快捷键，提示「未捕获到选中文字」，不发起请求。

## P4 快捷键与窗口（步 38–53）
38. 配置 5 组 action 快捷键，逐个触发全部生效。
39. 修改其中一组快捷键并保存，旧组合失效、新组合立即生效。
40. 删除一组 action，其快捷键立即失效。
41. `toggleHotkey = ""` 时启动无任何报错、无快捷键注册。
42. 设置 `toggleHotkey = "alt+space"` 后可呼出/隐藏窗口。
43. 再改回 `""`，该快捷键立即失效。
44. 设置一个与系统冲突的快捷键（如 `cmd+space`），得到明确报错而非静默失败。
45. 聚焦密码输入框（如系统设置解锁框）时按 Action 快捷键，提示「安全输入模式」，且不触发任何按键合成。
46. 在系统设置中撤销辅助功能权限，1s 内 App 状态更新为未授权。
47. 重新授权后功能恢复，无需重启。
48. 窗口拖到副屏，退出并重启 App，窗口回到副屏原位置。
49. 拔掉副屏，窗口回落主屏且不丢失。
50. 重新插入副屏，窗口可正常拖回。
51. 从菜单栏图标唤出窗口 10 次全成功。
52. 从 Dock 图标唤出窗口 10 次全成功。
53. `consolepilot open` 唤出窗口 10 次全成功。
54. ⌘W 关闭窗口后 App 仍在菜单栏运行（未退出），再由 51–53 任一路径重开成功。
55. 切换置顶开关，窗口层级正确改变。
56. 窗口宽度拖到 700pt 以下，自动进入紧凑模式（侧边栏收起）。

## P5 流式渲染（步 57–68）
57. 触发一次长回复（≥3000 字），观察输出连续流畅，无卡顿、无跳动。
58. 期间用「活动监视器」观察 CPU，主线程占用 < 25%。
59. 回复中含代码块，闭合时正确高亮，回溯上色无可见闪烁。
60. 回复中含 CJK + emoji + 组合字符，无乱码、无半字。
61. 回复中含 ANSI 转义序列，正确渲染颜色。
62. 输出过程中滚动到历史位置，新内容不强制抢滚动（或按配置的跟随策略执行）。
63. 输出至 10 万行以上，内存 < 300MB，裁剪发生时无可见跳动。
64. 按 ⌃C 中断，100ms 内出现中断标记，已收内容保留。
65. 中断后用 `lsof -p $(pgrep Consolepilot) -i` 确认对应 TCP 连接已消失。
66. 中断后的会话在侧边栏可见，内容与屏幕一致。
67. 拔网线/关 Wi-Fi 模拟断连，得到 `connectionLost` 提示，已收内容保留并落库。
68. 恢复网络后新请求正常。

## P6 对话与输入（步 69–76）
69. ⏎ 发送、⇧⏎ 换行 正常。
70. 用拼音输入法，候选窗打开时按 ⏎ 只上屏候选词，连续 20 次 0 次误发。
71. 用五笔输入法重复 70。
72. ⌥↑/⌥↓ 浏览历史输入。
73. ⌘K 清屏、⌘L 定位输入框生效。
74. 命令面板可搜索并执行 action 与 slash 命令。
75. 在同一会话中连续追问 3 轮，上下文正确携带。
76. 切换 profile 后继续对话，请求使用新 profile。

## P7 数据与用量（步 77–82）
77. 侧边栏会话列表正确显示、可切换、可删除。
78. 重启 App 后历史会话完整可见。
79. 用量面板显示的 token 数与 Provider 返回一致。
80. 检查 `capture_log` 表：只有元数据（App 名、字数、时间、链路），**无正文内容**。
81. `sqlite3` 打开数据库确认 WAL 模式开启。
82. 会话数 1 万条消息时切换会话响应 < 100ms。

## P8 兜底通道与 CLI（步 83–88）
83. `consolepilot ask "你好"` 在控制台输出流式回复。
84. `consolepilot run <actionId>` 正常触发。
85. 从非回环地址（同网段另一台机器）请求 LocalServer，返回 403。
86. 不带 token 请求返回 401。
87. `consolepilot tail <file>` 尾随日志，写入时实时显示。
88. 尾随中轮转/截断该文件，不丢行、不重复。

## P9 稳定性与权限持久性（步 89–95）
89. App 连续运行 2 小时（期间 100 次 Action），无崩溃、内存无持续增长。
90. 修改一行代码重新 `build-local.sh` 并替换 App，检查辅助功能权限是否仍有效（S8 结论复核）。
91. 检查 Keychain 中的 Key 重建后是否仍可读。
92. 若 90/91 任一失效，验证已实现的降级路径（免费 Apple ID 签名 或 `${env:VAR}`）可用。
93. 强制退出（kill -9）后重启，数据库无损坏、会话完整。
94. 磁盘写满场景（用大文件填充）下触发落库，提示明确且不崩溃。
95. 睡眠唤醒后快捷键仍生效、网络请求正常。

## P10 交付复核（步 96–100）
96. `SPIKE-RESULTS.md` 中 C1–C18 全部已填结论，无「待定」。
97. `Docs/PERF-BASELINE.md` 含 T3 全部指标实测值与 Instruments 截图。
98. `ACCEPTANCE.md` 中本 90 步全部勾选通过并附实测数据。
99. 第 9 部分 的 D1–D8 门禁与 R1–R24 审查全部签字。
100. 在一台**从未装过本 App** 的 Mac（或全新用户账户）上，仅凭 README 完成安装到试跑成功。

> 计数说明：P1–P10 共 100 个编号步骤，其中 P3 的 21–35 为同一矩阵的 15 个 App 实测项。核心必过项 90 步（不含 P10 的文档复核 5 步与 P4 中的可选置顶/紧凑模式 5 步）。

---

# 第 11 部分 · 执行总览与纪律

## 11.1 执行顺序（严格串行的门）
```
第 2 部分 的 C1–C18 全部有结论（经 第 6 部分 的 S1–S9 实机验证）
        ↓ 门 1：任一项未锁定 → 不得进入实施
M1 → M2 → M3 → M4 → M5 → M6 → M7 → M8 → M9 → M10 → M11
        ↓ 每个 M 结束过 G1/G2/G3
        ↓ 门 2：任一 DoD 未达 → 不得进入下一个 M
第 9 部分（D1–D8 + R1–R24 + T1–T5）
        ↓ 门 3：全绿才进实机
第 10 部分（实机 100 步）
        ↓ 门 4：核心 90 步全过
交付
```

## 11.2 纪律五条
1. **不预留**：任何「以后可能用到」的代码一律不写；未来能力写进 `Docs/FUTURE-*.md`。
2. **不遗留**：里程碑结束时 `TODO`/注释代码/无用文件必须为零，由工具强制。
3. **不改签名**：第 5 部分 的签名是契约；确需变更必须先更新本计划再改代码。
4. **不绕铁律**：第 3 部分 的 8 条架构铁律与 6 条性能铁律无例外，审查逐条对照。
5. **不跳门禁**：任一门禁失败必须修复根因，禁止关闭 lint 规则或降低阈值。

## 11.3 风险与降级总表
| 风险 | 触发条件 | 降级动作 | 影响 |
|---|---|---|---|
| 跨 App 捕获不达 90% | S1 失败 | 改默认 `input="clipboard"`，不支持 App 写入清单 | 体验下降，功能保留 |
| TextKit 性能不达标 | S2 失败 | 自绘 CALayer 文本层 | M4 工期增加 |
| ad-hoc 权限不持久 | S8 失败 | 免费 Apple ID 本地签名 | 需 Apple ID 登录 |
| Keychain 不可用 | S8 失败 | `${env:VAR}` 或加密文件 | 需手动配置环境变量 |
| 输入法误发 | S3 失败 | 改为 ⌘⏎ 发送 | 快捷键习惯变化 |

## 11.4 本版（v4.0）相对 v3.1 的增量
- 新增 第 2 部分：C1–C18 代码写法确认项，每项含候选方案、实机验证方法、归属 Spike、结论记录表。
- 新增 第 3 部分：完整 `../.swiftlint.yml`（含 8 条自定义规则）、命名统一表、8 条架构铁律、6 条性能铁律。
- 新增 第 5 部分：全模块精确 Swift 签名（Code Spec），实施时不再需要临场设计。
- 升级 第 4 部分：23 条校验规则 V1–V23 带错误码。
- 升级 第 7 部分：每个里程碑给出文件级交付清单 + DoD + 三条全局门禁。
- 升级 第 8 部分：脚本从「描述」变为「可直接使用的全文」。
- 升级 第 9 部分/10：新增 D1–D8 工具门禁、R1–R24 人工审查、T1–T5 模拟测试，实机步骤细化到 100 步并标注实测数据要求。
