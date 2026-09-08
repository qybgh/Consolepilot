import Foundation
import GRDB

final class AppDatabase {
    let writer: DatabaseWriter

    init(path: String? = nil, trace: (@Sendable (String) -> Void)? = nil) throws {
        let databasePath = path ?? Self.defaultPath()
        let directory = URL(fileURLWithPath: databasePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.journalMode = .wal
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
            if let trace {
                db.trace { event in trace(event.description) }
            }
        }
        let queue = try DatabaseQueue(path: databasePath, configuration: configuration)
        try Migrations.migrator.migrate(queue)
        writer = queue
    }

    private static func defaultPath() -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Consolepilot/consolepilot.sqlite").path
    }
}
