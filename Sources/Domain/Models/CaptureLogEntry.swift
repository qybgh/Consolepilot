import Foundation

/// 文本捕获审计领域实体：只含元数据，绝不落捕获正文（持久化映射见 `CaptureLogRecord`）。
public struct CaptureLogEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let sourceApp: String?
    public let sourceBundleId: String?
    public let characterCount: Int
    public let strategy: CaptureStrategy
    public let elapsed: Duration
    public let createdAt: Date

    public init(
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
