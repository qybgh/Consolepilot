import ConsolepilotDomain

/// `Usage` 聚合的纯函数集合，供 UsageStore 与 SQLiteUsageRepository 共用，
/// 避免两处重复汇总规则。
enum UsageAggregator {
    static func summary(_ records: [Usage]) -> UsageSummary {
        let grouped = Dictionary(grouping: records, by: \.model)
        let byModel = grouped.mapValues { totals($0, byModel: [:]) }
        return totals(records, byModel: byModel)
    }

    static func totals(_ records: [Usage], byModel: [String: UsageSummary]) -> UsageSummary {
        UsageSummary(
            inputTokens: records.reduce(0) { $0 + $1.inputTokens },
            outputTokens: records.reduce(0) { $0 + $1.outputTokens },
            costUSD: records.compactMap(\.costUSD).reduce(0, +),
            requestCount: records.count, byModel: byModel)
    }
}
