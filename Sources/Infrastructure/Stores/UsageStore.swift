import ConsolepilotDomain
import Foundation
import GRDB
import Observation

@MainActor @Observable
package final class UsageStore {
    private let database: AppDatabase

    package init(database: AppDatabase) { self.database = database }

    func record(_ usage: Usage) {
        do {
            var record = UsageRecord(usage)
            try database.writer.write { db in try record.insert(db) }
        } catch { Log.error("保存用量失败：\(error)", category: .domain) }
    }

    package func summary(period: UsagePeriod) -> UsageSummary {
        do {
            let records = try database.writer.read { db in
                try UsageRecord.fetchAll(db).map(\.entity)
            }.filter { record in
                guard period != .all else { return true }
                let interval: TimeInterval = period == .today ? 86_400 : 7 * 86_400
                return record.createdAt >= Date().addingTimeInterval(-interval)
            }
            return Self.makeSummary(records)
        } catch {
            Log.error("读取用量失败：\(error)", category: .domain)
            return UsageSummary(inputTokens: 0, outputTokens: 0, costUSD: 0, requestCount: 0, byModel: [:])
        }
    }

    private static func makeSummary(_ records: [Usage]) -> UsageSummary {
        let grouped = Dictionary(grouping: records, by: \.model)
        let byModel = grouped.mapValues { makeTotals($0, byModel: [:]) }
        return makeTotals(records, byModel: byModel)
    }

    private static func makeTotals(_ records: [Usage], byModel: [String: UsageSummary]) -> UsageSummary {
        UsageSummary(
            inputTokens: records.reduce(0) { $0 + $1.inputTokens },
            outputTokens: records.reduce(0) { $0 + $1.outputTokens },
            costUSD: records.compactMap(\.costUSD).reduce(0, +),
            requestCount: records.count, byModel: byModel)
    }
}
