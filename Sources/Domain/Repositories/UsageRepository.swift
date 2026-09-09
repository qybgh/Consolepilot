/// 用量审计的持久化契约（由 Infrastructure 以 SQLite/GRDB 实现）。
public protocol UsageRepository {
    func record(_ usage: Usage) throws
    func fetchSummary(period: UsagePeriod) throws -> UsageSummary
}
