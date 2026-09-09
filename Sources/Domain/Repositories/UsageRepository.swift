/// 用量审计的持久化契约（由 Infrastructure 以 SQLite/GRDB 实现）。
protocol UsageRepository {
    func record(_ usage: UsageRecord) throws
    func fetchSummary(period: UsagePeriod) throws -> UsageSummary
}
