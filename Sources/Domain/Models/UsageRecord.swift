import Foundation
import GRDB

struct UsageRecord: Identifiable, Sendable, Equatable, Codable, FetchableRecord, MutablePersistableRecord {
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

    static let databaseTableName = "usage_records"

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

    init(row: Row) throws {
        id = row["id"]
        sessionId = row["session_id"]
        actionId = row["action_id"]
        profileId = row["profile_id"]
        provider = ProviderKind(rawValue: row["provider"] as String) ?? .openai
        model = row["model"]
        inputTokens = row["input_tokens"]
        outputTokens = row["output_tokens"]
        costUSD = row["cost_usd"]
        let ttfbNanoseconds: Int64? = row["ttfb_ns"]
        let totalNanoseconds: Int64? = row["total_ns"]
        ttfb = ttfbNanoseconds.map { .nanoseconds($0) }
        total = totalNanoseconds.map { .nanoseconds($0) }
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["session_id"] = sessionId
        container["action_id"] = actionId
        container["profile_id"] = profileId
        container["provider"] = provider.rawValue
        container["model"] = model
        container["input_tokens"] = inputTokens
        container["output_tokens"] = outputTokens
        container["cost_usd"] = costUSD
        container["ttfb_ns"] = ttfb.map(Self.nanoseconds)
        container["total_ns"] = total.map(Self.nanoseconds)
        container["created_at"] = createdAt
    }

    private static func nanoseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
    }
}
