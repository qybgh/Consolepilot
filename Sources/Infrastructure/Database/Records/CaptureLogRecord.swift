import ConsolepilotDomain
import Foundation
import GRDB

/// capture_log 表的 GRDB record，负责 `CaptureLogEntry` 领域实体与数据库行之间的映射。
struct CaptureLogRecord: FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    var id: String
    var sourceApp: String?
    var sourceBundleId: String?
    var characterCount: Int
    var strategy: String
    var elapsedNs: Int64
    var createdAt: Date

    static let databaseTableName = "capture_log"

    enum Columns {
        static let id = Column("id")
        static let sourceApp = Column("source_app")
        static let sourceBundleId = Column("source_bundle_id")
        static let characterCount = Column("character_count")
        static let strategy = Column("strategy")
        static let elapsedNs = Column("elapsed_ns")
        static let createdAt = Column("created_at")
    }

    init(_ entry: CaptureLogEntry) {
        id = entry.id
        sourceApp = entry.sourceApp
        sourceBundleId = entry.sourceBundleId
        characterCount = entry.characterCount
        strategy = entry.strategy.rawValue
        elapsedNs =
            entry.elapsed.components.seconds * 1_000_000_000
            + entry.elapsed.components.attoseconds / 1_000_000_000
        createdAt = entry.createdAt
    }

    init(row: Row) throws {
        id = row["id"]
        sourceApp = row["source_app"]
        sourceBundleId = row["source_bundle_id"]
        characterCount = row["character_count"]
        strategy = row["strategy"]
        elapsedNs = row["elapsed_ns"]
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["source_app"] = sourceApp
        container["source_bundle_id"] = sourceBundleId
        container["character_count"] = characterCount
        container["strategy"] = strategy
        container["elapsed_ns"] = elapsedNs
        container["created_at"] = createdAt
    }

    var entity: CaptureLogEntry {
        CaptureLogEntry(
            id: id, sourceApp: sourceApp, sourceBundleId: sourceBundleId,
            characterCount: characterCount, strategy: CaptureStrategy(rawValue: strategy) ?? .clipboard,
            elapsed: .nanoseconds(elapsedNs), createdAt: createdAt)
    }
}
