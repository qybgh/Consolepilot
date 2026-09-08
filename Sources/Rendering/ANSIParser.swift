import Foundation

struct ANSIParser {
    private var pending = ""
    private(set) var attribute = ANSIAttribute.default

    mutating func consume(_ text: String) -> [ANSISpan] {
        pending.append(text)
        var spans: [ANSISpan] = []
        var plain = ""
        while !pending.isEmpty {
            guard let escapeIndex = pending.firstIndex(of: "\u{1B}") else {
                plain.append(contentsOf: pending)
                pending.removeAll()
                break
            }
            if escapeIndex > pending.startIndex {
                plain.append(contentsOf: pending[..<escapeIndex])
                pending.removeSubrange(..<escapeIndex)
            }
            guard pending.count >= 2 else { break }
            let afterEscape = pending.index(after: pending.startIndex)
            guard pending[afterEscape] == "[" else {
                plain.append("\u{1B}")
                pending.removeFirst()
                continue
            }
            guard let terminator = pending[afterEscape...].first(where: { $0.isLetter || $0 == "m" }) else { break }
            guard let terminatorIndex = pending.firstIndex(of: terminator) else { break }
            let end = pending.index(after: terminatorIndex)
            let sequence = String(pending[pending.index(pending.startIndex, offsetBy: 2)..<terminatorIndex])
            if !plain.isEmpty {
                spans.append(ANSISpan(text: plain, attributes: attribute))
                plain.removeAll()
            }
            if terminator == "m" { applySGR(sequence) }
            pending.removeSubrange(..<end)
        }
        if !plain.isEmpty { spans.append(ANSISpan(text: plain, attributes: attribute)) }
        return spans
    }

    mutating func flush() -> [ANSISpan] {
        guard !pending.isEmpty else { return [] }
        let text = pending
        pending.removeAll()
        return [ANSISpan(text: text, attributes: attribute)]
    }

    private mutating func applySGR(_ sequence: String) {
        let values = sequence.isEmpty ? [0] : sequence.split(separator: ";").compactMap { Int($0) }
        for value in values {
            switch value {
            case 0: attribute = .default
            case 1: attribute.bold = true
            case 3: attribute.italic = true
            case 4: attribute.underline = true
            case 22: attribute.bold = false
            case 23: attribute.italic = false
            case 24: attribute.underline = false
            case 30...37: attribute.foreground = value - 30
            case 39: attribute.foreground = nil
            case 40...47: attribute.background = value - 40
            case 49: attribute.background = nil
            case 90...97: attribute.foreground = value - 90 + 8
            case 100...107: attribute.background = value - 100 + 8
            default: break
            }
        }
    }
}

struct ANSISpan: Equatable, Sendable {
    let text: String
    let attributes: ANSIAttribute
}

struct ANSIAttribute: Equatable, Sendable {
    var foreground: Int?
    var background: Int?
    var bold: Bool
    var italic: Bool
    var underline: Bool

    static let `default` = ANSIAttribute(foreground: nil, background: nil, bold: false, italic: false, underline: false)
}
