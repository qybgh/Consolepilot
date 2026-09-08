# Consolepilot

macOS 14+ 终端风格 AI 副屏控制台。

开发顺序：先执行 `Scripts/bootstrap.sh`，再按 M1–M11 实施。当前 Mock 核心、LocalServer/CLI 和配置菜单已完成，正在进行 M11 收尾。

本地快速验证：

```bash
./Scripts/bootstrap.sh
swift test -j 1
./Scripts/build-local.sh
swift run consolepilot --help
```

构建产物位于 `dist/`：`Consolepilot.app`、`Consolepilot-0.1.0.zip`、`consolepilot` 和 `config.example.toml`。默认使用本地 Mock Provider，不消耗 API Token；启用 LocalServer 时请将 token 放入 Keychain 或环境变量，不要把真实密钥写入 TOML、日志或 Git。

更多配置和诊断信息见 [CONFIG.md](CONFIG.md)、[SHORTCUTS.md](SHORTCUTS.md)、[TROUBLESHOOTING.md](TROUBLESHOOTING.md) 和 [FUTURE-PROXY.md](FUTURE-PROXY.md)。

最终人工验收请按 [ACCEPTANCE-GUIDE.md](ACCEPTANCE-GUIDE.md) 执行；其中包含窄屏设置、Profile/API Key、菜单栏和稳定性验收步骤。

说明：Periphery 已被上游归档，且部分 arm64 Homebrew 环境没有可用 bottle。开发阶段脚本会警告但继续；最终 D4 门禁前必须安装可用版本或记录经确认的替代方案。
