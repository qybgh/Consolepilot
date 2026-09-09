import Foundation

/// 单次请求的用量领域实体（纯值类型；持久化映射见 `UsageRecord`）。
public struct Usage: Identifiable, Sendable, Equatable {
    public let id: String
    public let sessionId: String?
    public let actionId: String?
    public let profileId: String
    public let provider: ProviderKind
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let costUSD: Double?
    public let ttfb: Duration?
    public let total: Duration?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString, sessionId: String? = nil, actionId: String? = nil,
        profileId: String, provider: ProviderKind, model: String, inputTokens: Int, outputTokens: Int,
        costUSD: Double? = nil, ttfb: Duration? = nil, total: Duration? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.actionId = actionId
        self.profileId = profileId
        self.provider = provider
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.ttfb = ttfb
        self.total = total
        self.createdAt = createdAt
    }
}
