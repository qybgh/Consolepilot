# Consolepilot

macOS 上的本地 AI 控制台工具：捕获选中文本/剪贴板，通过本地或远程 OpenAI-compatible/Anthropic 服务执行问答，支持全局快捷键、菜单栏与 Action 后台执行。

> 状态：P0（XcodeGen 工程化 + 同构迁移 + SwiftUI 入口）完成；P1-A…F 完成（8-target 拆分、领域/存储、流与并发重建、Provider 统一 contract、Action 生命周期与配置处置、死代码收尾），P1 DoD 全绿，待 macOS 14 实机验收。执行计划见 `Docs/PLAN.md`，进度见 `Docs/PROGRESS.md`，编码规范见 `Docs/CODING-STYLE.md`。

## 工程结构

- `project.yml`：工程唯一编辑源（XcodeGen）。改工程先改它，再执行 `make xcodegen`。
- `Consolepilot.xcodeproj`：由 XcodeGen 生成并提交，`make lint` 内含漂移检查。
- `Sources/`：按 target 分层（依赖只能向下）：
  - `Sources/Domain` → `ConsolepilotDomain`（纯模型/配置值对象/错误/协议/用例契约，禁 UI/GRDB/Network/Keychain）。
  - `Sources/Application` → `ConsolepilotApplication`（Use Case 实现，P1-C/E 前为占位）。
  - `Sources/Infrastructure` + `Sources/Transport` → `ConsolepilotInfrastructure`（GRDB/存储/配置/捕获/密钥/HTTP+SSE Provider；`StreamCoordinator` 为唯一流汇聚与取消注册表，`ActionRunner` 为 `ActionExecutionUseCase` 真实实现）。
  - `Sources/LegacyUI` → `ConsolepilotLegacyUI`（遗留 AppKit UI + Rendering，P2 删除）。
  - `Sources/App` → `Consolepilot`（App composition root + SwiftUI 生命周期）；`Sources/CLI` → `consolepilot`。
- 跨模块可见性统一用 `package`（`OTHER_SWIFT_FLAGS = -package-name Consolepilot`），不扩大 public API；`make lint` 内含 `Scripts/check-imports.py` 依赖方向门禁。
- `Tests/`：XCTest 测试（经 Xcode scheme 运行）。
- `Resources/`：`Info.plist`（版本号走 xcconfig 变量）与 entitlements。
- `Configs/`：Debug/Release `.xcconfig`（Swift 6 严格并发、warnings-as-errors）。
- `Makefile`：唯一命令入口。

## 开发命令（统一走 Makefile）

```sh
make bootstrap   # 校验 Xcode/工具链/依赖/架构（一次性）
make test        # 全量测试：xcodebuild test -scheme Consolepilot（GUI 会话须全绿）
make lint        # 门禁：swift-format + SwiftLint strict + analyze + import 方向 + 残留扫描 + 密钥扫描 + periphery + xcodeproj 漂移检查
make build       # Debug arm64 构建 App + CLI（产物在 build/）
make release VERSION=0.2.0-p1   # Release + ad-hoc 签名 + ZIP + SHA-256 manifest（dist/）
make clean       # 清理构建产物；make distclean 深度清理（含 .build）
```

## 配置

首次运行会在 `~/.config/consolepilot/config.toml` 生成默认配置（模板随 App/CLI bundle 分发）。字段说明见 `Docs/CONFIG.md`；本地密钥引用走 `${env:VAR}` 或 Keychain，禁止明文写入配置文件。

## 安装/卸载

- 安装：解压 `dist/Consolepilot-<version>.zip`，将 `Consolepilot.app` 拖入 `/Applications`，CLI 放任意 PATH 目录即可。
- 卸载：删除 App 与 CLI，并清理 `~/.config/consolepilot/`、`~/Library/Application Support/Consolepilot/`（如有残留）。
