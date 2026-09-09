/// 一次合帧后交付给 UI 的增量批次。
package struct TokenBatch: Sendable, Equatable {
    package let sessionId: String
    package let text: String
    package let deltaCount: Int

    package init(sessionId: String, text: String, deltaCount: Int) {
        self.sessionId = sessionId
        self.text = text
        self.deltaCount = deltaCount
    }
}
