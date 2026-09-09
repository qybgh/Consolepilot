# Consolepilot 卸载说明（无残留清理）

> 目标：把 `Consolepilot.app` 与 `consolepilot` CLI 移入废纸篓后，应用在系统里
> **不留用户数据**。一键清理：`./uninstall.sh`（或 `make uninstall`）。

## 1. 卸载后有哪些残留（现状盘点）

macOS 对非 App Store 应用没有系统级“卸载”接口——把 `.app` 拖进废纸篓只删除
应用本体。Consolepilot（非沙盒）会在以下位置写数据：

| 位置 | 内容 | 是否残留 |
|---|---|---|
| `~/Library/Application Support/Consolepilot/` | SQLite 数据库（会话/消息/用量/捕获元数据）+ `-wal`/`-shm`；备用配置 | ⚠️ 残留 |
| `~/.config/consolepilot/` | 主配置文件 `config.toml`（首次运行自动生成） | ⚠️ 残留 |
| `~/Library/Preferences/`（`com.consolepilot.Consolepilot` 域） | 侧栏可见性/宽度、输入历史等 | ⚠️ 残留 |
| `~/Library/Caches/com.consolepilot.Consolepilot/` | 缓存（如存在） | ⚠️ 残留 |
| `~/Library/Logs/Consolepilot/` | 日志文件（当前版本日志走 stderr，通常无文件） | 视情况 |
| 钥匙串（Keychain） | `${keychain:账户}` 引用的 API Key 条目 | 默认保留（见 §3） |
| 系统“辅助功能”授权（TCC） | 曾授予本应用的辅助功能权限 | 系统管理，脚本用 `tccutil` 重置 |
| LaunchServices / 最近使用 | 系统自动维护 | 删除 App 后自动消失 |

## 2. 一键清理

```zsh
./uninstall.sh            # 逐项确认
./uninstall.sh --yes      # 直接执行
./uninstall.sh --dry-run  # 仅预览将删除的路径
make uninstall            # 等价于 ./uninstall.sh
```

脚本会：退出正在运行的应用 → 删除上表目录/偏好域 → `tccutil reset
Accessibility com.consolepilot.Consolepilot` → 给出钥匙串处理提示。
**不会**删除钥匙串密钥、其他应用数据或用户文档。

## 3. 钥匙串与 TCC 的取舍（行业惯例）

- **钥匙串**：`${keychain:name}` 引用的是你在“钥匙串访问”里自己创建的密码项目，
  属于你的秘密，可能同时被其他工具使用。卸载器默认**不删除**；需要彻底删除时：

  ```zsh
  security delete-generic-password -s com.local.consolepilot -a <账户名>
  ```

- **辅助功能授权**：由系统 TCC 数据库管理，应用无法自我删除。`tccutil reset
  Accessibility com.consolepilot.Consolepilot` 在多数情况下可重置；若系统拒绝，
  在“系统设置 → 隐私与安全性 → 辅助功能”中手动移除即可。

## 4. 业内规范参考

- Apple《File System Basics》：应用数据应放在
  `~/Library/Application Support/<bundle-id>`、`Caches`、`Logs`、`Preferences`
  等标准子目录，卸载时按这些目录清理即可覆盖全部残留：
  https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html
- Apple《The App Bundle》：`.app` 是自包含 bundle，删除它即删除程序本体：
  https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html
- Apple `UserDefaults` 文档：偏好设置写入
  `~/Library/Preferences/<bundle-id>.plist`：
  https://developer.apple.com/documentation/foundation/userdefaults
- macOS 没有面向第三方应用的“卸载 API”，业界通行做法即“删除 bundle +
  按 Library 标准目录清理”（AppCleaner 等工具同理）；App Store 应用删除后
  `~/Library/Containers/<bundle-id>` 数据同样不会自动清除，需手动删除。
  本仓库的 `uninstall.sh` 把上述清理固化为一条命令，达到“卸载无残留”。

## 5. 说明

- 若你曾把配置文件放在 `~/Library/Application Support/Consolepilot/config.toml`
  （旧版备用路径），脚本会连同该目录一并清理。
- 卸载后重装属于全新安装：首次运行会用随包分发的默认配置重新生成
  `~/.config/consolepilot/config.toml`——不含旧字段与重复示例，文末以整段注释附上默认关闭的 Profile/Action 示例。
