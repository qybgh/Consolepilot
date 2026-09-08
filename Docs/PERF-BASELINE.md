# Consolepilot 性能基线

本文件记录 M11 前的自动化基线；真实 Instruments 截图和长稳运行数据需要在目标 Mac 上完成后补入。

## 已有自动化数据（2026-08-29）

| 指标 | 结果 | 依据 |
|---|---:|---|
| XCTest 总数 | 67 通过 / 0 失败 | `swift test` |
| 10,000 条消息最新页查询 P95 | < 20 ms | `DatabaseTests.testTenThousandMessageLatestPageQueryStaysWithinPlanThreshold` |
| 1,000 delta 流式合帧 | 零丢字，更新次数受限 | `TransportTests` / `StreamCoordinator` 回归测试 |
| 流式期间 SQLite 写入 | 0 次旁路写入 | trace 回归测试 |
| Release 构建 | 通过 | `Scripts/build-local.sh` |
| ad-hoc 签名校验 | 通过 | `codesign --verify --deep --strict` |

## 待实机记录

- Instruments Leaks/Zombies：连续 2 小时、100 次 Action。
- 长会话切换、Markdown 终态渲染、滚动跟随的主线程采样。
- 10 万行终端/长消息内存峰值与滚动帧率。
- 睡眠唤醒、网络断连和强制退出后的恢复时间。

采样时不得使用真实用户剪贴板正文或生产 API 密钥；截图应隐藏路径中的用户名和敏感信息。
