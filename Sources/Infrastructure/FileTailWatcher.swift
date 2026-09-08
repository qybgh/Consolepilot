import Foundation

public actor FileTailWatcher {
    private let config: TailConfig
    private let onLine: @Sendable (String) -> Void
    private var task: Task<Void, Never>?
    private var offset: UInt64 = 0
    private var pending = ""
    private var fileIdentity: AnyHashable?

    init(config: TailConfig, onLine: @escaping @Sendable (String) -> Void) {
        self.config = config
        self.onLine = onLine
    }

    public func start() throws {
        guard config.enabled else { return }
        let attrs = try FileManager.default.attributesOfItem(atPath: config.path)
        if config.fromEnd { offset = (attrs[.size] as? UInt64) ?? 0 }
        fileIdentity = Self.identity(attrs)
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: config.path) else { return }
        let identity = Self.identity(attrs)
        let size = Self.fileSize(attrs)
        if identity != fileIdentity || size < offset {
            offset = 0
            pending.removeAll()
            fileIdentity = identity
        }
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: config.path)) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        offset += UInt64(data.count)
        guard let text = String(data: data, encoding: .utf8) else { return }
        pending.append(text)
        while let newline = pending.firstIndex(where: \.isNewline) {
            let line = String(pending[..<newline])
            pending.removeSubrange(...newline)
            if !line.isEmpty { emit(line) }
        }
    }

    private func emit(_ line: String) {
        guard config.format == .jsonl else {
            onLine(line)
            return
        }
        guard let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            onLine(line)
            return
        }
        for key in ["message", "text", "line"] {
            if let value = object[key] as? String {
                onLine(value)
                return
            }
        }
        onLine(line)
    }

    private static func identity(_ attrs: [FileAttributeKey: Any]) -> AnyHashable? {
        if let inode = attrs[.systemFileNumber] as? NSNumber { return AnyHashable(inode.int64Value) }
        return nil
    }

    private static func fileSize(_ attrs: [FileAttributeKey: Any]) -> UInt64 {
        if let number = attrs[.size] as? NSNumber { return number.uint64Value }
        return 0
    }
}
