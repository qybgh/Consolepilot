import Foundation

/// 文本捕获审计领域实体：只含元数据，绝不落捕获正文（持久化映射见 `CaptureLogRecord`）。
struct CaptureLogEntry: Identifiable, Sendable, Equatable {
    let id: String
    let sourceApp: String?
    let sourceBundleId: String?
    let characterCount: Int
    let strategy: CaptureStrategy
    let elapsed: Duration
    let createdAt: Date

    init(
        id: String = UUID().uuidString, sourceApp: String?, sourceBundleId: String?, characterCount: Int,
        strategy: CaptureStrategy, elapsed: Duration, createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceApp = sourceApp
        self.sourceBundleId = sourceBundleId
        self.characterCount = characterCount
        self.strategy = strategy
        self.elapsed = elapsed
        self.createdAt = createdAt
    }
}
