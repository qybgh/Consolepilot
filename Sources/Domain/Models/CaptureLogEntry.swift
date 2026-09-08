import Foundation
import GRDB

struct CaptureLogEntry: Identifiable, Sendable, Equatable, Codable, FetchableRecord, MutablePersistableRecord {
    let id: String
    let sourceApp: String?
    let sourceBundleId: String?
    let characterCount: Int
    let strategy: CaptureStrategy
    let elapsed: Duration
    let createdAt: Date

    static let databaseTableName = "capture_log"

    init(
        id: String = UUID().uuidString, sourceApp: String?, sourceBundleId: String?, characterCount: Int,
        strategy: CaptureStrategy, elapsed: Duration, createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceApp = sourceApp
        self.sourceBundleId = sourceBundleId
        self.characterCount = characterCount
        self.strategy = strategy
        self.elapsed = elapsed
        self.createdAt = createdAt
    }

    init(row: Row) throws {
        id = row["id"]
        sourceApp = row["source_app"]
        sourceBundleId = row["source_bundle_id"]
        characterCount = row["character_count"]
        strategy = CaptureStrategy(rawValue: row["strategy"] as String) ?? .clipboard
        let nanoseconds: Int64 = row["elapsed_ns"]
        elapsed = .nanoseconds(nanoseconds)
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["source_app"] = sourceApp
        container["source_bundle_id"] = sourceBundleId
        container["character_count"] = characterCount
        container["strategy"] = strategy.rawValue
        container["elapsed_ns"] =
            elapsed.components.seconds * 1_000_000_000 + elapsed.components.attoseconds / 1_000_000_000
        container["created_at"] = createdAt
    }
}
