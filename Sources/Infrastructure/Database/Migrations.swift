import GRDB

enum Migrations {
    static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "sessions") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("channel", .text).notNull()
                t.column("action_id", .text)
                t.column("profile_id", .text)
                t.column("provider", .text)
                t.column("model", .text)
                t.column("source_app", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("archived", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "messages") { t in
                t.primaryKey("id", .text)
                t.column("session_id", .text).notNull().references("sessions", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("state", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "messages_session_created", on: "messages", columns: ["session_id", "created_at"])
            try db.create(table: "usage_records") { t in
                t.primaryKey("id", .text)
                t.column("session_id", .text).references("sessions", onDelete: .setNull)
                t.column("action_id", .text)
                t.column("profile_id", .text).notNull()
                t.column("provider", .text).notNull()
                t.column("model", .text).notNull()
                t.column("input_tokens", .integer).notNull()
                t.column("output_tokens", .integer).notNull()
                t.column("cost_usd", .double)
                t.column("ttfb_ns", .integer)
                t.column("total_ns", .integer)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "usage_created", on: "usage_records", columns: ["created_at"])
            try db.create(table: "capture_log") { t in
                t.primaryKey("id", .text)
                t.column("source_app", .text)
                t.column("source_bundle_id", .text)
                t.column("character_count", .integer).notNull()
                t.column("strategy", .text).notNull()
                t.column("elapsed_ns", .integer).notNull()
                t.column("created_at", .datetime).notNull()
            }
        }
        return migrator
    }()
}
