# Consolepilot 编码规范（CODING-STYLE）

> 本文档是本仓库新增/重构代码的**唯一写法基准**，自 P0 实施起生效。
> 与之冲突的旧文件写法不作为新代码的例外依据；涉及存量文件的必要适配须保持最小 diff 并同步遵守本文档。
> 配套门禁：`make lint`（swift-format strict、SwiftLint strict、`xcodebuild analyze`、xcodeproj 漂移检查）。

## 1. 语言与并发

- Swift 6 严格并发；`SWIFT_VERSION=6` 以编译器为准，禁止用 `@unchecked Sendable` 绕过检查（特殊情况须在 PR 说明并留注释）。
- 共享可变状态一律用 `actor`；UI/协调器/窗口类用 `@MainActor final class`。
- 值类型优先：`Sendable struct` + `Equatable`；性能敏感路径遵循写时复制语义，避免无谓拷贝与重复分配。
- 每个启动的 `Task` 必须有：明确所有者、取消路径、终态处理与对应测试；禁止「fire-and-forget」后无人接管。
- 取消统一走现有协议（退出/会话删除/配置热重载/Action 取消/断网共用同一取消注册表）。

## 2. 命名

- 协议不加 `Protocol` 后缀：沿用 `AIProvider`、`CLIRouter` 风格，名称即角色。
- 一个文件一个主要类型：`<Type>.swift`；辅助私有类型可同文件。
- 类型/协议 UpperCamelCase；方法/属性/枚举 case lowerCamelCase；布尔属性用 `is`/`has`/`can` 前缀。
- 测试文件 `<Area>Tests.swift`；测试方法 `test...` 开头，命名描述行为与期望（如 `testTimeoutSecOverrideBeatsProfileDefault`）。
- UI 文案一律中文；可交互控件加稳定 `accessibilityIdentifier`。

## 3. 错误模型

- 错误沿用现有分层枚举风格（`AppError` 聚合 `ConfigError/CaptureError/TransportError/StorageError/ServerError`），并统一扩展出四要素：
  1. 稳定 `code: String`（可被测试/日志断言，不随文案变化）；
  2. `userMessage`：面向用户的直接可读文案（中文）；
  3. `recoverySuggestion`：下一步可执行建议（无则空串）；
  4. 脱敏诊断信息：只含类型/状态/脱敏上下文，**绝不包含密钥或捕获正文**。
- 错误必须 `Equatable` + `Sendable`，便于测试与跨 actor 传递。

## 4. 日志与隐私

- 一律走 `Infrastructure/Log.swift`（级别 + category，stderr）；生产路径禁 `print`（CLI 面向用户的输出除外）。
- 日志、诊断、测试 fixture 与错误信息中不得出现：Authorization 头、API 密钥、Token、捕获正文/剪贴板内容。
- 捕获审计只落元数据（来源 App、字符数、策略、耗时），不落内容（既有 `capture_log` 约定）。

## 5. 格式与静态检查

- swift-format：4 空格缩进、120 列宽（`.swift-format` 已配置）；提交前对改动文件执行 `swift-format format --in-place`。
- SwiftLint `strict`（含 `force_unwrapping`、`fatal_error_message`、自定义 no-print/no-force-try/no-todo 规则）：新增代码零违规、零 `disable` 注释。
- 生产代码禁止：强制解包、`fatalError`、`try!`、静默 `try?`、`[String: Any]` DTO、未持有的 Task、明文密钥。
- 删除任何废弃字段/模块/页面时，执行全仓库引用搜索（源码/测试/文档/默认配置/示例），保证零残留。
- XcodeGen：`project.yml` 是工程唯一编辑源；改工程先改 `project.yml` 再 `make xcodegen`；`make lint` 内含漂移检查（`xcodegen generate` 后 `git diff --exit-code`）。

## 6. 测试

- 框架 XCTest；`final class` + `test…` 命名；方法内按 Arrange / Act / Assert 空行分段。
- 用 fake/in-memory 实现；禁止真网络、真 Keychain、用户剪贴板、既有库/真实数据库依赖。
- 每个用例命名契约方向并固定其存在（空壳/协议占位同样配测试，防死代码门禁误报）。
- 性能敏感路径的回归护栏：见 PLAN §6.2（并行流隔离、取消、usage 无重复无丢失、fixture 矩阵等）。
