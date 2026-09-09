import ConsolepilotDomain
import Foundation
import GRDB

/// `UsageRepository` 的 SQLite 实现：逐条记录用量，聚合时按周期过滤后汇总。
package struct SQLiteUsageRepository: UsageRepository {
    private let writer: DatabaseWriter

    package init(database: AppDatabase) {
        writer = database.writer
    }

    package func record(_ usage: Usage) throws {
        try writer.write { db in
            var record = UsageRecord(usage)
            try record.insert(db)
        }
    }

    package func fetchSummary(period: UsagePeriod) throws -> UsageSummary {
        let records = try writer.read { db in
            try UsageRecord.fetchAll(db).map(\.entity)
        }
        let filtered: [Usage]
        if period == .all {
            filtered = records
        } else {
            let interval: TimeInterval = period == .today ? 86_400 : 7 * 86_400
            let cutoff = Date().addingTimeInterval(-interval)
            filtered = records.filter { $0.createdAt >= cutoff }
        }
        return UsageAggregator.summary(filtered)
    }
}
