import Foundation

struct SSEDecoder {
    private var pendingBytes = Data()
    private var pendingLine = ""
    private var event: String?
    private var dataLines: [String] = []

    mutating func consume(_ input: some Sequence<UInt8>) -> [SSEFrame] {
        pendingBytes.append(contentsOf: input)
        guard let text = decodeAvailableBytes() else { return [] }
        pendingLine.append(text)
        return consumeCompleteLines()
    }

    mutating func flush() -> [SSEFrame] {
        if !pendingBytes.isEmpty, let text = String(data: pendingBytes, encoding: .utf8) {
            pendingBytes.removeAll()
            pendingLine.append(text)
        }
        var frames = consumeCompleteLines()
        if !pendingLine.isEmpty {
            consumeLine(pendingLine, into: &frames)
            pendingLine.removeAll()
        }
        if event != nil || !dataLines.isEmpty { frames.append(makeFrame()) }
        return frames
    }

    private mutating func decodeAvailableBytes() -> String? {
        guard !pendingBytes.isEmpty else { return nil }
        if let text = String(data: pendingBytes, encoding: .utf8) {
            pendingBytes.removeAll()
            return text
        }
        for trim in 1...min(3, pendingBytes.count) {
            let split = pendingBytes.count - trim
            if let text = String(data: pendingBytes.prefix(split), encoding: .utf8) {
                pendingBytes = Data(pendingBytes.suffix(trim))
                return text
            }
        }
        return nil
    }

    private mutating func consumeCompleteLines() -> [SSEFrame] {
        var frames: [SSEFrame] = []
        while let newline = pendingLine.firstIndex(of: "\n") {
            var line = String(pendingLine[..<newline])
            pendingLine.removeSubrange(...newline)
            if line.last == "\r" { line.removeLast() }
            consumeLine(line, into: &frames)
        }
        return frames
    }

    private mutating func consumeLine(_ line: String, into frames: inout [SSEFrame]) {
        if line.isEmpty {
            if event != nil || !dataLines.isEmpty { frames.append(makeFrame()) }
            return
        }
        if line.hasPrefix(":") { return }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        let value = parts.count == 2 ? String(parts[1].drop(while: { $0 == " " })) : ""
        switch field {
        case "event": event = value
        case "data": dataLines.append(value)
        default: break
        }
    }

    private mutating func makeFrame() -> SSEFrame {
        let frame = SSEFrame(event: event, data: dataLines.joined(separator: "\n"))
        event = nil
        dataLines.removeAll()
        return frame
    }
}

struct SSEFrame: Equatable, Sendable {
    let event: String?
    let data: String
}
