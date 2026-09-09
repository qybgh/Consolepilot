import Foundation

public enum Log {
    public enum Category: String, Sendable {
        case app, config, capture, transport, render, domain, server, hotkey
    }

    public static func debug(_ message: String, category: Category = .app) {
        write("DEBUG", message, category: category)
    }

    public static func info(_ message: String, category: Category = .app) {
        write("INFO", message, category: category)
    }

    public static func warn(_ message: String, category: Category = .app) {
        write("WARN", message, category: category)
    }

    public static func error(_ message: String, category: Category = .app) {
        write("ERROR", message, category: category)
    }

    private static func write(_ level: String, _ message: String, category: Category) {
        FileHandle.standardError.write(Data("[\(level)] [\(category.rawValue)] \(message)\n".utf8))
    }
}
