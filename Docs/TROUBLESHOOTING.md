# Consolepilot 故障排查

## App 没有窗口

```zsh
open -n /Users/luoran/Projects/Consolepilot/dist/Consolepilot.app
```

`open` 启动的是 App bundle，终端不会显示 App 日志。跨 App 选区捕获的辅助功能权限应授予这个 bundle：`/Users/luoran/Projects/Consolepilot/dist/Consolepilot.app`。重新构建并替换 ad-hoc 签名后，macOS 可能要求重新授权。

需要同时观察并保存日志时，另开一个终端运行：

```zsh
cd /Users/luoran/Projects/Consolepilot
./dist/Consolepilot.app/Contents/MacOS/Consolepilot 2>&1 | tee /tmp/consolepilot-capture.log
```

该终端会被 App 占用；再开一个终端执行筛选。系统未安装 `rg` 时使用 macOS 自带的 `grep`：

```zsh
grep -E "模拟复制|capture|Action 触发" /tmp/consolepilot-capture.log
tail -f /tmp/consolepilot-capture.log
```

直接启动内部二进制仅适合诊断，不要与 App bundle 同时运行；两者在 macOS 辅助功能权限中可能被视为不同对象。

若 App 已运行但窗口隐藏，执行：

```zsh
/usr/local/bin/consolepilot open
```

也可以从 App 菜单选择“显示主窗口”。

## CLI 报鉴权错误

如果 `[server].authToken` 留空，本地 CLI/HTTP 服务处于关闭状态，不影响 App 内对话。只有启用该服务时，才需要配置 `${keychain:...}` 或 `${env:CONSOLEPILOT_SERVER_TOKEN}`。

## 钥匙串重复提示

App 启动时会预读取远程 Profile 的 API Key，授权提示应集中在首次打开阶段，不再等到发起会话时才出现。当前本地 Release 使用 ad-hoc 签名，重建并替换 App 后 macOS 可能视为新的钥匙串访问者，再次提示；最终稳定 Apple ID 签名后会改善。`consolepilot-server` 不再是默认配置项。

## 设置保存后没有生效

先在设置窗口点击“重新加载”，确认 TOML 语法和枚举值正确。非法配置不会替换当前有效配置。若修改了 LocalServer 端口或 token，退出并重新打开 App 让监听器重新建立。

设置编辑器已关闭智能引号、智能破折号、自动替换和自动纠错；TOML 字符串中的引号会保持 ASCII `"`。从外部富文本编辑器粘贴内容时，仍应确认使用直引号而不是 `“`/`”`。

## CLI 未安装

```zsh
cd /Users/luoran/Projects/Consolepilot
./Scripts/build-local.sh
sudo ./Scripts/install-cli.sh
```

脚本会创建 `/usr/local/bin`（需要管理员权限）并安装 `consolepilot`。

## 获取诊断信息

保留终端错误文本、App 状态栏提示和 `Docs/ACCEPTANCE.md` 中对应步骤。不要提交配置文件中的密钥、剪贴板正文或捕获内容。
