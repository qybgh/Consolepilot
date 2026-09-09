# Consolepilot 配置

配置文件默认位置：`~/.config/consolepilot/config.toml`。也可以在 App 菜单中选择“设置…”直接编辑。保存后，Consolepilot 会校验 TOML；校验失败时保留上一份有效配置。

设置编辑器按纯文本模式工作，并已关闭智能引号等自动替换；TOML 字符串请使用 ASCII 双引号 `"`。

## 安全规则

- 不要把真实 API Key 或服务 token 写入 TOML、日志或 Git。
- 远程 Provider 的密钥使用 `${keychain:name}` 或 `${env:VARIABLE}` 引用。
- 本地 Mock Provider 可以使用空 `apiKey`。
- LocalServer 默认只监听 `127.0.0.1`，请求必须携带 `Authorization: Bearer <token>`。

## 配置分组

`[general]` 控制本地端口、主题/字体/透明度/置顶等显示参数（解析与校验已保留，界面接线随 P2 SwiftUI 迁移实现）、滚动缓冲行数与真实 Provider 开关；`[server]` 控制鉴权 token 引用及最大请求体；`[capture]` 控制文本捕获策略、剪贴板恢复和长度限制。

`[[profiles]]` 定义 Provider、Base URL、模型、密钥引用、生成参数和价格；`[[actions]]` 定义 Action 的提示词、输入来源、会话策略（`sessionMode`）、快捷键、超时与通知。日志尾随（`tails`）以及 `launchAtLogin`、`toggleHotkey`、`attachTo` 已按 D6/D7 决策移出本轮 schema，配置中出现旧字段会报明确错误，不再静默忽略。

`[server].authToken` 是可选的本地 CLI/HTTP 接口鉴权配置；留空即可关闭本地服务，不影响 App 内对话和真实 Provider。远程 Profile 的 API Key 会在 App 首次打开时预读取，以便一次性完成钥匙串授权。

Action 每个字段的完整示例见 `Sources/Infrastructure/Config/DefaultConfig.toml`（随 App/CLI 分发）。关键语义：

- `sessionMode`：本轮仅支持 `"dedicated"`——每次 Action 在独立后台会话执行，并按 `actionId + sourceApp` 复用最近一个空闲会话续写上下文；旧 `attachTo` 值会给出迁移报错（含行号），改为 `sessionMode = "dedicated"` 即可。
- `timeoutSec`（可选整数，> 0）：覆盖该 Action 所用 Profile 的 `timeoutSec`；未设置时回退 Profile 默认值。超时按请求超时处理并落为失败终态。
- `autoShow`：Action 完成并创建会话后是否显示主窗口（仅 `orderFront`，不抢占前台）。
- `notifyOnDone`：App 不在前台时，Action 完成/失败后发本地通知；通知只含 Action 名与状态。
- 非法配置（含 `nan`/`inf` 数值、旧字段）保存时校验报错，保留上一份有效配置不变。

Action 快捷键支持双击语法：`hotkey = "cmd+c*2"` 表示在约 420 毫秒内连续按两次 `Command+C` 才触发；不带 `*2` 时为单次触发。双击模式的第一次按键只用于计时，Action 捕获选区时会自行模拟 `⌘C`。

当 Action 使用 `input = "selection"` 时，Consolepilot 先尝试辅助功能直读；失败后会在原前台 App 中静默模拟一次 `⌘C`，并且只有确认剪贴板确实发生变化才接受结果，不会把上一次复制的旧内容当作当前选区。捕获后会恢复原剪贴板。`input = "clipboard"` 才会明确读取现有剪贴板。

## Profile 与 API Key 配置（按当前文件操作）

你当前配置中已有两个 Profile：

- `local-test`：`http://127.0.0.1:11434/v1`，本地地址，`apiKey = ""`，不会读取钥匙串，也不会消耗远程 API Token。
- `ChatAnywhere`：`https://api.chatanywhere.tech/v1`，远程 OpenAI 兼容服务，`apiKey = "${keychain:openai}"`，会从钥匙串账户 `openai` 读取密钥。

### 方式 A：使用钥匙串（推荐）

1. 打开“钥匙串访问”（Keychain Access）。
2. 新建“密码”项目：
   - 钥匙串：登录
   - 名称/账户：`openai`
   - 密码：你的 ChatAnywhere API Key
3. 保存后，在配置中保持：

```toml
apiKey = "${keychain:openai}"
```

4. 保存设置，等待状态栏显示热重载完成。
5. 从 App 菜单“切换 Profile”选择 `ChatAnywhere · openai`。
6. 发送一条短测试消息，确认助手返回；首次读取钥匙串时 macOS 可能弹出访问确认，选择“始终允许”。

### 方式 B：使用环境变量

1. 在终端设置环境变量（不要把真实值写入文件）：

```zsh
export CHATANYWHERE_API_KEY='你的 API Key'
```

2. 将 Profile 改为：

```toml
apiKey = "${env:CHATANYWHERE_API_KEY}"
```

3. 从同一个终端启动 App，或确保启动 App 的环境继承该变量：

```zsh
open /Users/luoran/Projects/Consolepilot/dist/Consolepilot.app
```

环境变量方式每次重新登录或从图形界面启动时可能失效；遇到“密钥不可用”提示时，优先改用钥匙串方式。

### 新增自定义 Profile 模板

复制以下块并修改 `id`、`provider`、`baseURL`、`model` 和 `apiKey`：

```toml
[[profiles]]
id = "my-provider"
provider = "openai" # 或 anthropic
baseURL = "https://你的服务地址/v1"
model = "你的模型名"
apiKey = "${keychain:my-provider-key}"
temperature = 0.3
maxTokens = 4096
timeoutSec = 120
```

然后在钥匙串中创建同名账户 `my-provider-key`，填入 API Key。`id` 必须唯一；保存成功后 Profile 菜单会立即刷新，无需重启 App。

注意：Anthropic Profile 的 `baseURL` 应指向 Anthropic Messages API 根地址，`provider = "anthropic"`；不要把 OpenAI 的 URL 和 Anthropic provider 混用。

## 环境变量降级

不希望访问钥匙串时，可将服务 token 设置为：

```toml
[server]
authToken = "${env:CONSOLEPILOT_SERVER_TOKEN}"
```

并在启动 App 和 CLI 前执行：

```zsh
export CONSOLEPILOT_SERVER_TOKEN='仅用于本机回环服务的随机 token'
```

环境变量只对当前 shell/session 生效；需要持久化时请使用 macOS 的登录项环境配置，而不是把 token 写入仓库。

## 变更生效

通用配置和 Provider 映射通过文件监听热重载。端口或服务 token 变更后，LocalServer 可能需要重启 App 才能重新绑定监听端口。设置窗口底部会显示保存状态；详细错误会保留在状态栏和日志中。

## 真实 Provider 开关

为避免验收时误消耗 API Token，Consolepilot 默认即使配置了远程 Profile 也使用本地 Mock。开关已放入 `[general]` 配置段，可在设置窗口直接修改：

```toml
allowRealProvider = false
```

保持 `false` 即为 Mock 安全模式。只有在你明确需要真实请求时，才改为 `true`，保存后重启 App：

```zsh
allowRealProvider = true
```

真实请求结束仍必须收到 `data: [DONE]`；缺少该终止帧会标记为连接异常，不会当作正常完成。测试完成后务必改回 `false`。
