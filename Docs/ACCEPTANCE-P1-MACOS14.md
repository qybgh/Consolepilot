# P1 实机验收清单（macOS 14）

> 对象：P0+P1 里程碑产物 `dist/Consolepilot-0.2.0-p1.zip`（Consolepilot.app + consolepilot CLI + SHA256SUMS.txt）。
> 机器：macOS 14（Apple Silicon），建议使用**新建非管理员测试账户**执行，避免污染日常环境。
> 状态：`[ ]` 未验 / `[x]` 通过 / `[!]` 失败（附现象）/ `[-]` 不适用。
> 安全：全程使用本地 Mock，不访问真实 API；任何日志/截图不得包含密钥或正文内容。

## 0. 测试账户（一次性，用管理员在目标机执行）

```zsh
sudo sysadminctl -addUser consolepilot-test -password "仅测试用随机密码" -admin
# 若需删除：sudo sysadminctl -deleteUser consolepilot-test
```

## 1. 产物安装与校验

1. 将 `dist/Consolepilot-0.2.0-p1.zip` 传到 macOS 14（AirDrop/移动盘），解压。
2. `cd <解压目录> && shasum -a 256 -c SHA256SUMS.txt`
3. `codesign --verify --deep --strict --verbose=2 Consolepilot.app`；`codesign -dv Consolepilot.app` 应显示 `TeamIdentifier=3CSL8ZN3AN`、Authority 含 `Apple Development: 1217194271@qq.com (WCHFR3G7VB)`（开发者证书签名，非 ad-hoc）
4. 首次被 Gatekeeper 拦截时：右键 Consolepilot.app →“打开”，或
   `xattr -dr com.apple.quarantine Consolepilot.app`
5. 启动 App；如弹“辅助功能”权限提示，在 系统设置→隐私与安全性→辅助功能 授予本 App。

- [ ] 1.1 SHA-256 校验通过
- [ ] 1.2 codesign 校验通过
- [ ] 1.3 首次启动不崩溃，菜单栏出现 Consolepilot 图标

## 2. 基础入口

- [ ] 2.1 主窗口显示；Dock 图标存在
- [ ] 2.2 App 菜单“设置…”（`⌘,`）打开设置场景；窄到 ~420pt 不裁切、可编辑/保存
- [ ] 2.3 App 菜单“用量统计…”打开用量窗口
- [ ] 2.4 `./consolepilot --help` 输出正常；`ask/open/run` 子命令存在
- [ ] 2.5 关闭主窗口后点 Dock 图标，仅重建 1 个主窗口（连续 3 轮）

## 3. Mock Action 后台执行（不抢焦点）

1. 配置 `[general] allowRealProvider = false`，Profile 指向 `127.0.0.1`（Mock）。
2. 打开 TextEdit 输入一段文字并选中。
3. 通过菜单栏/CLI 触发一次 `input = "selection"` 的 Action。

- [ ] 3.1 源应用（TextEdit）保持前台，Consolepilot 不抢焦点
- [ ] 3.2 `autoShow = true` 时主窗口 `orderFront`（不激活）；`autoShow = false` 时窗口不出现
- [ ] 3.3 `notifyOnDone = true` 且 App 不在前台时仅收到本地通知（不含正文）
- [ ] 3.4 剪贴板在捕获后恢复；捕获失败不发送旧剪贴板内容

## 4. 非法配置与热重载

1. 在配置中把某 Action 改为 `attachTo = "newSession"` 并保存。
2. 再把某 Profile/General 数值改为 `opacity = nan` 并保存。

- [ ] 4.1 `attachTo` 报错含行号与 `sessionMode = "dedicated"` 改法
- [ ] 4.2 `nan/inf` 被拦截报错
- [ ] 4.3 报错后上一份有效配置保持不变，App 不崩溃、不覆盖文件

## 5. 连续/并发 Action 与会话

- [ ] 5.1 同一 Action 连续执行复用同一独立会话（`actionId + sourceApp`），两轮对话上下文正确
- [ ] 5.2 不同 Action/不同源应用会话互不串线
- [ ] 5.3 流式中可取消（`/stop`/⌃C），已收前缀保留

## 6. 退出/重启检查点

- [ ] 6.1 流式中 `⌘Q` 退出 → 重启后该会话已收内容可见（checkpoint）
- [ ] 6.2 卸载/清理只删除 App 自身文件：运行仓库 `./uninstall.sh --yes` 后确认 `~/.config/consolepilot`、`~/Library/Application Support/Consolepilot` 与偏好域已清空（钥匙串密钥默认保留）

## 7. 真实 Provider（待凭据，暂缓）

- [ ] 7.1 使用你提供的低权限测试凭据补跑 PLAN §6 第 5 步动网子集（归档到 PROGRESS）

## 反馈模板

逐项记录：`状态` + 版本号（App 菜单“关于”或 `defaults read` bundle version）+ 现象/截图（去敏）+ 日志（`~/Library/Logs/Consolepilot` 或 stderr，去敏）。
