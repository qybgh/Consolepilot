import ConsolepilotDomain
import Foundation
import GRDB

/// `CaptureAuditRepository` 的 SQLite 实现：审计只落元数据，绝不落捕获正文。
package struct SQLiteCaptureAuditRepository: CaptureAuditRepository {
    private let writer: DatabaseWriter

    package init(database: AppDatabase) {
        writer = database.writer
    }

    package func record(_ entry: CaptureLogEntry) throws {
        try writer.write { db in
            var record = CaptureLogRecord(entry)
            try record.insert(db)
        }
    }
}
