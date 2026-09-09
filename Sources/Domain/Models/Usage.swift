import Foundation

/// 单次请求的用量领域实体（纯值类型；持久化映射见 `UsageRecord`）。
struct Usage: Identifiable, Sendable, Equatable {
    let id: String
    let sessionId: String?
    let actionId: String?
    let profileId: String
    let provider: ProviderKind
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double?
    let ttfb: Duration?
    let total: Duration?
    let createdAt: Date

    init(
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
