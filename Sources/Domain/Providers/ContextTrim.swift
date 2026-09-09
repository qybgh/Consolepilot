import Foundation

/// 上下文输入裁剪（纯规则，供 Profile/Action 的 `maxContextBytes` 落地）。
///
/// 预算 = 单次请求携带的 UTF-8 字节上限（system 提示 + 消息正文）。裁剪策略
/// 按“尽量保留最近对话”的常见做法执行：
/// 1. 未超预算：原样返回；
/// 2. 超出时从最早的整条消息开始丢弃（system 提示始终保留）；
/// 3. 只剩最新一条仍超时，才在 UTF-8 字符边界截断其正文——绝不丢弃当前轮次；
/// 4. 只作用于发给 Provider 的请求副本，不改动落库/界面历史，重复触发结果确定。
public enum ContextTrim {
    public struct Result: Sendable, Equatable {
        public let messages: [ChatMessage]
        /// 因超预算被整体丢弃的历史消息条数（不含截断）。
        public let droppedCount: Int
        /// 最新一条消息是否被截断。
        public let truncated: Bool
    }

    public static func trim(
        systemPrompt: String?, messages: [ChatMessage], budgetBytes: Int
    ) -> Result {
        guard !messages.isEmpty else {
            return Result(messages: [], droppedCount: 0, truncated: false)
        }
        let available = max(0, budgetBytes - (systemPrompt?.utf8.count ?? 0))
        var total = messages.reduce(0) { $0 + $1.content.utf8.count }
        var start = messages.startIndex
        // 从最早的整条开始丢弃，直到只剩最新一条或已放得下。
        while messages.index(after: start) < messages.endIndex && total > available {
            total -= messages[start].content.utf8.count
            start = messages.index(after: start)
        }
        var kept = Array(messages[start...])
        var truncated = false
        if total > available, let lastIndex = kept.indices.last {
            let newest = kept[lastIndex]
            let target = max(0, available - (total - newest.content.utf8.count))
            kept[lastIndex] = ChatMessage(
                role: newest.role, content: utf8Prefix(newest.content, maxBytes: target))
            truncated = true
        }
        return Result(
            messages: kept, droppedCount: messages.distance(from: messages.startIndex, to: start),
            truncated: truncated)
    }

    /// 在 UTF-8 字节预算内按字符边界截断；未超限时原样返回。
    private static func utf8Prefix(_ text: String, maxBytes: Int) -> String {
        guard maxBytes >= 0, text.utf8.count > maxBytes else { return text }
        var used = 0
        var end = text.startIndex
        for index in text.indices {
            let width = text[index].utf8.count
            guard used + width <= maxBytes else { break }
            used += width
            end = text.index(after: index)
        }
        return String(text[..<end])
    }
}
