# S4 · SSE 流式与取消

验证 C11–C12：UTF-8 跨 chunk、畸形 SSE、服务端断连和取消后的 TCP 关闭。

`mock_server.py` 提供本地 SSE 服务，正式实现前不得使用真实 Provider 替代断连测试。
