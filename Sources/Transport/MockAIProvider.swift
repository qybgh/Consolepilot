import ConsolepilotDomain
import Foundation

/// A deterministic local streaming provider used for end-to-end acceptance without API credentials.
package struct MockAIProvider: AIProvider {
    let delay: Duration

    package init(delay: Duration = .milliseconds(28)) {
        self.delay = delay
    }

    package func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        let response = Self.response(for: request.messages.last?.content ?? "")
        let inputCount = request.messages.last?.content.count ?? 0
        let delay = delay
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                continuation.yield(.started(model: "mock-stream-v1"))
                do {
                    for chunk in Self.chunks(response, size: 3) {
                        try Task.checkCancellation()
                        continuation.yield(.delta(chunk))
                        try await Task.sleep(for: delay)
                    }
                    continuation.yield(
                        .usage(
                            input: max(1, inputCount / 4),
                            output: max(1, response.count / 4)))
                    continuation.yield(.finishReason("stop"))
                    continuation.yield(.finished)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: CancellationError())
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func longParagraph(index: Int) -> String {
        let head =
            "第\(index)段：这是 Consolepilot 本地 Mock 的长流式测试内容，用来验证连续 delta、长文本排版、滚动跟随、中断恢复和数据库检查点。"
        let tail = "每个段落会拆成多个小块逐步发送，确保界面不会等待完整响应后才显示。中文、English、emoji 🚀 都会被保留。\n"
        return head + tail
    }

    private static func response(for prompt: String) -> String {
        if prompt == "/long" || prompt.contains("3000") || prompt.contains("10 段") || prompt.contains("10段") {
            let paragraphs = (1...24).map { Self.longParagraph(index: $0) }
            return paragraphs.joined()
        }
        if prompt == "/code" {
            return """
                这是本地 Mock 的代码块响应：

                ```swift
                struct Consolepilot {
                    let mode = "mock"
                }
                ```

                中文、English 与 emoji 🚀 均由本机生成，不消耗 API Token。
                """
        }
        return """
            这是 Consolepilot 本地 Mock Provider 的流式响应。当前请求没有访问互联网，也没有消耗任何 API Token。
            可输入 /code 测试代码块，输入 /long 测试长回复。
            """
    }

    private static func chunks(_ text: String, size: Int) -> [String] {
        var result: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            result.append(String(text[index..<end]))
            index = end
        }
        return result
    }
}
