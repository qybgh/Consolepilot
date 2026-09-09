# Consolepilot

macOS 上的本地 AI 控制台工具：捕获选中文本/剪贴板，通过本地或远程 OpenAI-compatible/Anthropic 服务执行问答，支持全局快捷键、菜单栏与 Action 后台执行。

> 状态：P0（XcodeGen 工程化 + 同构迁移）完成；P1（8-target 拆分 + Provider/Action 可靠性）实施中。执行计划见 `Docs/PLAN.md`，进度见 `Docs/PROGRESS.md`，编码规范见 `Docs/CODING-STYLE.md`。

## 工程结构

- `project.yml`：工程唯一编辑源（XcodeGen）。改工程先改它，再执行 `make xcodegen`。
- `Consolepilot.xcodeproj`：由 XcodeGen 生成并提交，`make lint` 内含漂移检查。
- `Sources/`：源码（App/CLI/Domain/Application/Infrastructure/Rendering/Transport；Domain 内含 `Models/Stores/Repositories/UseCases`）。
- `Tests/`：XCTest 测试（经 Xcode scheme 运行）。
- `Resources/`：`Info.plist`（版本号走 xcconfig 变量）与 entitlements。
- `Configs/`：Debug/Release `.xcconfig`（Swift 6 严格并发、warnings-as-errors）。
- `Makefile`：唯一命令入口。

## 开发命令（统一走 Makefile）

```sh
make bootstrap   # 校验 Xcode/工具链/依赖/架构（一次性）
make test        # 全量测试：xcodebuild test -scheme Consolepilot（GUI 会话须全绿）
make lint        # 门禁：swift-format + SwiftLint strict + analyze + 密钥扫描 + periphery + xcodeproj 漂移检查
make build       # Debug arm64 构建 App + CLI（产物在 build/）
make release VERSION=0.2.0-p1   # Release + ad-hoc 签名 + ZIP + SHA-256 manifest（dist/）
make clean       # 清理构建产物；make distclean 深度清理（含 .build）
```

## 配置

首次运行会在 `~/.config/consolepilot/config.toml` 生成默认配置（模板随 App/CLI bundle 分发）。字段说明见 `Docs/CONFIG.md`；本地密钥引用走 `${env:VAR}` 或 Keychain，禁止明文写入配置文件。

## 安装/卸载

- 安装：解压 `dist/Consolepilot-<version>.zip`，将 `Consolepilot.app` 拖入 `/Applications`，CLI 放任意 PATH 目录即可。
- 卸载：删除 App 与 CLI，并清理 `~/.config/consolepilot/`、`~/Library/Application Support/Consolepilot/`（如有残留）。
