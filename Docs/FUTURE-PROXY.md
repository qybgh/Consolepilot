# 真实 Provider 与代理接入说明

当前默认使用本地 Mock Provider，不消耗 API Token。真实 OpenAI/Anthropic 请求只有在配置远程 Profile 且用户明确完成密钥授权后才启用。

远程 Profile 必须使用 `${keychain:name}` 或 `${env:VARIABLE}` 引用密钥；禁止把明文 API Key 写入配置。请求通过 Provider 的 SSE 流式解码器进入唯一的 `StreamCoordinator`，终态或中断检查点写入 SQLite。

后续启用真实 Provider 前，需要完成：

1. 在目标账户中配置密钥引用并确认网络访问范围。
2. 对 OpenAI 与 Anthropic 各执行一次短请求，记录 HTTP 状态、首 token 延迟和取消行为。
3. 验证 401、429、5xx、超时、断连和畸形 SSE 的用户提示。
4. 不在日志、截图、测试 fixture 中保留密钥或完整请求正文。

代理、企业网关或本地兼容服务只需提供与对应 Provider 相容的 Base URL；仍然必须使用安全的密钥引用和用户授权流程。
