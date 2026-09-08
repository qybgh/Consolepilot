# Consolepilot 最终验收操作指南

本文针对当前版本（含菜单栏、快速提问、Profile 切换、输入历史和设置窄屏适配）。默认使用 Mock，不会消耗 API Token。

真实 Provider 默认被显式关闭。配置中的 `[general] allowRealProvider = false` 时，即使选择远程 Profile 也不会访问网络；只有明确改为 `true` 并重启后才会访问真实 API。

## 0. 构建与启动

```zsh
cd /Users/luoran/Projects/Consolepilot
./Scripts/build-local.sh
open -n /Users/luoran/Projects/Consolepilot/dist/Consolepilot.app
```

辅助功能权限请授予上述 `dist/Consolepilot.app`。不要用内部二进制的权限代替 App bundle 的权限；重新构建 ad-hoc 签名后若 macOS 再次询问，请在“系统设置 → 隐私与安全性 → 辅助功能”中删除旧 Consolepilot 条目，再添加最新的 `dist/Consolepilot.app`。

若系统拦截：在 Finder 中右键 `dist/Consolepilot.app` →“打开”。

## 1. 设置窗口窄屏验收

1. App 菜单 →“设置…”。
2. 将窗口拖窄到约 420pt，或点击绿色按钮进入全屏。
3. 确认配置正文自动换行；超长 URL/连续字符串可通过底部水平滚动条查看。
4. 滚动条应为深色 overlay 样式，不出现白色背景。
5. 任意点击文本中间编辑，执行复制、粘贴、撤销。
6. 点击“保存更改”，状态栏显示保存成功；窗口不崩溃。

## 2. 当前配置 Profile 验收

当前文件应包含：

- `local-test`：本地 Mock 配置，无需 API Key；
- `ChatAnywhere`：远程配置，`apiKey = "${keychain:openai}"`。

保存配置后，关闭并重新打开“切换 Profile”菜单，列表应立即包含两个 Profile；无需重启 App。

## 3. Keychain 配置

推荐在“钥匙串访问”中创建（最稳定的做法是让“账户”字段与配置引用完全一致）：

- 钥匙串：登录；
- 账户：`chatanywhere.free`（如果配置写的是 `${keychain:chatanywhere.free}`）；
- 密码：ChatAnywhere API Key。

配置文件只保留：

```toml
apiKey = "${keychain:openai}"
```

如果你的钥匙串条目账户是 `chatanywhere.free`，则配置必须写成：

```toml
apiKey = "${keychain:chatanywhere.free}"
```

账户字段、配置引用中的名称必须逐字符一致（包括大小写、点号和连字符）。修改配置后点击“保存更改”，等待状态栏热重载完成，再重新打开“切换 Profile”菜单。若仍提示不可用，可在钥匙串条目的“访问控制”中允许 Consolepilot 访问，或删除旧条目后按上述字段重新创建。

首次请求若出现钥匙串访问提示，选择“始终允许”。不要把 API Key 写入 TOML、日志或截图。

## 4. 核心场景：跨 App 选中文字 → 快捷键 → 预设 Action → 新会话

这是 Consolepilot 的主通道。先保持 `[general] allowRealProvider = false`，使用本地 Mock 完成整条链路，不消耗 API Token。

### 4.1 准备一个选中文字 Action

在设置窗口的 TOML 配置中加入以下内容。下面直接绑定你当前的 `ChatAnywhere` Profile；由于本段验收保持 `allowRealProvider = false`，即使它是远程地址，App 也会强制使用本地 Mock，不会访问网络或消耗 Token：

```toml
[[actions]]
id = "summarize-selection"
name = "总结选中文本"
hotkey = "cmd+shift+j"
profile = "ChatAnywhere"
userPrompt = "请用中文简洁总结以下选中内容：\n\n{{selection}}"
input = "selection"
attachTo = "newSession"
autoShow = true
notifyOnDone = false
```

保存后等待“配置已热重载”。如果系统提示辅助功能权限，打开“系统设置 → 隐私与安全性 → 辅助功能”，允许 Consolepilot。

### 4.2 手动验证主通道

1. 打开 Safari、Chrome、Notes、TextEdit 或 VS Code，输入并选中一段中英混排文字，包含一个 emoji。
2. 不要先点击 Consolepilot，保持选中文字的 App 位于前台。
3. 直接按 `⌘⇧J`，不需要预先手动按 `⌘C`。Consolepilot 会记录触发瞬间的原前台 App，并向该进程定向静默执行一次复制；完成后恢复剪贴板。
4. Consolepilot 应立即显示类似“正在执行 Action：summarize-selection · 捕获选中文字…”，随后新建一个“总结选中文本”会话；主屏上的原 App 不应被切走或出现 Consolepilot 窗口。
5. Action 会话默认隐藏底部对话输入框，工具栏保留一个展开按钮；点击展开按钮后可恢复手动输入。这样长题目和长答案可以获得完整的垂直显示空间。
6. 会话中应先出现助手 loading 状态，然后出现按配置模板生成的用户提问；提示词中应包含刚才选中的原文。
7. Mock 助手回复应逐块流式显示，完成后状态栏显示字符数、首字延迟、总耗时和 `finish_reason=stop`。
8. 切换到其他会话再切回来，用户提问和助手回复都应完整保留；普通会话的输入框应恢复显示，Action 会话仍保持收起状态。
9. 再次选中另一段文字触发同一快捷键，应新建第二个独立会话，不能串入上一会话。

选区 Action 不会把剪贴板中的历史内容当作选区：如果目标 App 不支持 AX 直读，模拟 `⌘C` 还必须确认剪贴板发生了变化才接受结果。因此不需要、也不应先手动按 `⌘C`；若捕获失败，App 应明确提示并不创建错误上下文的请求。调试时可查看 `[capture]` 日志中的 PID、changeCount 和字符数，但不会记录选中文本。

### 4.3 捕获失败时的预期

- 未选中文字：提示“无法捕获选中文字：当前没有选中文本”，不应创建请求会话。
- 当前应用在排除列表中：提示已排除，不应读取剪贴板或发起请求。
- 密码框/安全输入：提示“当前窗口启用了安全输入”，不应模拟 `⌘C`。
- 没有辅助功能权限：提示需要权限；可在“打开辅助功能设置”菜单中授权后重试。
- 辅助功能不支持的应用：App 会按 `strategy` 顺序尝试静默模拟复制；只有剪贴板确认发生变化才接受结果，完成后恢复原剪贴板内容。若模拟复制也不被该 App 支持，应明确提示失败，不会误用剪贴板历史内容。

## 5. 菜单栏、快速提问、Profile

1. 点击菜单栏 Consolepilot 图标，验证隐藏/显示主窗口。
2. App 菜单 →“快速提问…”，输入问题并发送，确认当前会话流式回复。
3. App 菜单 →“切换 Profile”，选择 `local-test`，发送消息，确认本地 Mock 回复。
4. 选择远程 Profile 前，确认 Keychain 中对应账户存在；否则预期显示“密钥不可用”，且不发起请求。

如果某个 Action 使用 `hotkey = "ctrl+c"`，请注意它是全局快捷键，会覆盖 Terminal/iTerm2 的 SIGINT 行为，并可能占用 Consolepilot 自身的 Control+C 中断操作。验收该 Action 时使用 `/stop` 中断流式请求，或将 Action 改为 `ctrl+alt+c`。

双击快捷键验收：将目标 Action 的 `hotkey` 设置为 `cmd+c*2`，在其它 App 选中文字后连续按两次 `Command+C`（两次间隔不超过约 420 毫秒）。第一次按键只用于计时，第二次完成后 Consolepilot 才触发 Action；Action 随后会自行模拟 `⌘C` 获取选区；只按一次或间隔过长不应触发。

## 6. 输入历史

1. 发送“第一条”“第二条”“第三条”。
2. 输入框中按 `Option+↑`/`Option+↓` 浏览历史。
3. 退出并重启后再次按 `Option+↑`，确认历史仍存在。

## 7. 核心 Mock 验收

- 普通消息：逐块流式输出，完成后输入框恢复；
- `/code`：Markdown 标题、行内代码、围栏代码块正确；
- `/long`：底部自动跟随，上翻后不抢位置；
- `Control+C`：中断标记出现，已收内容保留；
- 多轮对话：上下文和消息顺序正确；
- 会话切换/删除/清空：互不串线；
- 重启：历史和未完成检查点可恢复；
- 复制按钮：复制原始 Markdown 内容；
- 用量统计：仅显示请求次数、输入 Token、输出 Token。

完成后请留意状态栏：新版会显示类似“回复完成 · N 字符 · 首字 0.42s · 总耗时 8.31s · finish_reason=stop”。该结果按会话保留，切换到其他会话再切回来仍应显示，直到该会话开始下一轮生成；不依赖几秒钟的临时提示。`stop` 表示 Provider 正常结束；`length` 表示达到 `maxTokens`，不是 App 丢失尾部。若没有 `finish_reason` 或没有 `[DONE]`，应记录为 Provider/网络异常。

Mock 验收期间请不要设置 `CONSOLEPILOT_ENABLE_REAL_PROVIDER=1`。需要测试真实 ChatAnywhere 时再单独开启，测试完成后关闭 App 并从普通方式重新启动即可回到 Mock。

## 8. CLI/LocalServer

```zsh
sudo ./Scripts/install-cli.sh
consolepilot --help
consolepilot ask "CLI 测试"
consolepilot open
consolepilot run ask "Action 测试"
consolepilot tail /tmp/consolepilot-test.log
```

缺失日志文件应返回 HTTP 422，不创建空会话。LocalServer 请求必须带正确 Bearer token。

## 9. 其它计划内人工验收

- 辅助功能权限和撤权/重新授权；
- Safari、Chrome、Xcode、VS Code、Terminal、iTerm2、Notes、Preview、Mail、Slack、Figma、微信、Word、Finder、Warp 的文本捕获；
- Carbon 全局快捷键注册；
- 真实 OpenAI/Anthropic Provider；
- 副屏拔插、睡眠唤醒、2 小时稳定性；
- `kill -9`、磁盘写满、Keychain 持久性；
- 全新用户账户安装。

每项记录“通过/失败、实际步骤、截图或日志”。
