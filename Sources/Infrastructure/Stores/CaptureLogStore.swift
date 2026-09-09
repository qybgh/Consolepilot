import ConsolepilotDomain
import Foundation

@MainActor
package final class CaptureLogStore {
    private let database: AppDatabase

    init(database: AppDatabase) { self.database = database }

    func record(_ result: CaptureResult) {
        do {
            let entry = CaptureLogEntry(
                sourceApp: result.sourceApp,
                sourceBundleId: result.sourceBundleId,
                characterCount: result.originalLength,
                strategy: result.strategy,
                elapsed: result.elapsed)
            var record = CaptureLogRecord(entry)
            try database.writer.write { db in try record.insert(db) }
        } catch {
            Log.error("保存文本捕获日志失败：\(error)", category: .capture)
        }
    }
}
