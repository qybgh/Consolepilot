import Foundation
import GRDB

/// usage_records 表的 GRDB record，负责 `Usage` 领域实体与数据库行之间的映射。
struct UsageRecord: FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    var id: String
    var sessionId: String?
    var actionId: String?
    var profileId: String
    var provider: String
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double?
    var ttfbNs: Int64?
    var totalNs: Int64?
    var createdAt: Date

    static let databaseTableName = "usage_records"

    enum Columns {
        static let id = Column("id")
        static let sessionId = Column("session_id")
        static let actionId = Column("action_id")
        static let profileId = Column("profile_id")
        static let provider = Column("provider")
        static let model = Column("model")
        static let inputTokens = Column("input_tokens")
        static let outputTokens = Column("output_tokens")
        static let costUSD = Column("cost_usd")
        static let ttfbNs = Column("ttfb_ns")
        static let totalNs = Column("total_ns")
        static let createdAt = Column("created_at")
    }

    init(_ usage: Usage) {
        id = usage.id
        sessionId = usage.sessionId
        actionId = usage.actionId
        profileId = usage.profileId
        provider = usage.provider.rawValue
        model = usage.model
        inputTokens = usage.inputTokens
        outputTokens = usage.outputTokens
        costUSD = usage.costUSD
        ttfbNs = usage.ttfb.map(Self.nanoseconds)
        totalNs = usage.total.map(Self.nanoseconds)
        createdAt = usage.createdAt
    }

    init(row: Row) throws {
        id = row["id"]
        sessionId = row["session_id"]
        actionId = row["action_id"]
        profileId = row["profile_id"]
        provider = row["provider"]
        model = row["model"]
        inputTokens = row["input_tokens"]
        outputTokens = row["output_tokens"]
        costUSD = row["cost_usd"]
        ttfbNs = row["ttfb_ns"]
        totalNs = row["total_ns"]
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["session_id"] = sessionId
        container["action_id"] = actionId
        container["profile_id"] = profileId
        container["provider"] = provider
        container["model"] = model
        container["input_tokens"] = inputTokens
        container["output_tokens"] = outputTokens
        container["cost_usd"] = costUSD
        container["ttfb_ns"] = ttfbNs
        container["total_ns"] = totalNs
        container["created_at"] = createdAt
    }

    var entity: Usage {
        Usage(
            id: id, sessionId: sessionId, actionId: actionId, profileId: profileId,
            provider: ProviderKind(rawValue: provider) ?? .openai, model: model,
            inputTokens: inputTokens, outputTokens: outputTokens, costUSD: costUSD,
            ttfb: ttfbNs.map { .nanoseconds($0) }, total: totalNs.map { .nanoseconds($0) },
            createdAt: createdAt)
    }

    private static func nanoseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
    }
}
