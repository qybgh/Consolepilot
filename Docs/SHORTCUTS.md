# Consolepilot 快捷键

## App 与窗口

- `⌘Q`：退出 App，并在退出前保存活动流检查点。
- `⌘W`：隐藏主窗口，不退出 App。
- `⌘,`：打开设置窗口。
- `⌘0`：显示主窗口。

## 控制台输入

- `Enter`：提交当前输入。
- `Shift+Enter`：插入换行（由输入控件处理）。
- `Control+C`：中断当前会话的流式生成，保留已收到内容。

## 内置 slash 命令

```text
/help       显示命令帮助
/new        新建会话
/clear      清空当前显示
/stop       中断当前生成
/sessions   显示会话数量
```

`/code` 和 `/long` 属于 Mock 对话输入，不是管理命令。

## 全局快捷键

Consolepilot 使用 Carbon 注册配置中的 Action 快捷键；未配置快捷键时不会注册任何组合键。Action 触发后会在原前台 App 中静默模拟一次 `⌘C`（仅用于读取选区），然后恢复剪贴板，不激活或抢占 Consolepilot 主屏窗口。窗口呼出使用 Dock、菜单栏图标或 App 菜单快捷键（`⌘0`/`⌘,`）；原 `general.toggleHotkey` 全局呼出热键已随本轮删除。Action 捕获选区仍需要辅助功能权限。

Action 支持双击快捷键语法，例如 `hotkey = "cmd+c*2"` 表示在约 420 毫秒内连续按两次 `Command+C` 才触发；Consolepilot 会将按键转发给原前台 App，因此其它 App 的普通复制仍然有效；当 Consolepilot 自身位于前台时则直接调用标准复制响应链。第二次按键完成后才执行 Action，捕获选区时还会确认剪贴板变化并恢复原内容。普通单击快捷键不带 `*2`，例如 `cmd+shift+k`。

Action 也可以配置为 `hotkey = "ctrl+c"`，但这是全局组合键：在 Terminal/iTerm2 中会覆盖通常的 `Control+C`（发送 SIGINT），在 Consolepilot 自身窗口中也可能与“中断当前流式生成”冲突。使用该组合键作为选区 Action 时，建议通过 `/stop` 中断生成；如果仍需保留原生 Control+C，改用 `ctrl+alt+c` 或其他不冲突组合键。
