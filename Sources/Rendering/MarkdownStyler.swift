import AppKit

struct PendingBlockState: Equatable {
    enum Kind: Equatable {
        case none
        case fencedCode(language: String?)
        case list, quote
    }
    var kind: Kind = .none
    var startOffset: Int = 0
}

struct StyleOutput {
    let increment: NSAttributedString
    let retroactive: [(range: NSRange, attributes: [NSAttributedString.Key: Any])]
}

struct MarkdownStyler {
    private var state = PendingBlockState()
    private var fullText = ""

    mutating func style(_ increment: String, theme: Theme) -> StyleOutput {
        let start = fullText.utf16.count
        fullText.append(increment)
        var output = NSMutableAttributedString()
        var retroactive: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
        var cursor = increment.startIndex

        while cursor < increment.endIndex {
            let lineEnd =
                increment[cursor...].firstIndex(of: "\n").map { increment.index(after: $0) } ?? increment.endIndex
            let line = String(increment[cursor..<lineEnd])
            let isFence = line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```")
            if isFence {
                if case .fencedCode = state.kind {
                    let attrs = codeAttributes(theme)
                    output.append(NSAttributedString(string: line, attributes: attrs))
                    let range = NSRange(location: state.startOffset, length: start + output.length - state.startOffset)
                    retroactive.append((range: range, attributes: attrs))
                    state = PendingBlockState()
                } else {
                    let language = line.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(3)
                    output.append(NSAttributedString(string: line, attributes: normalAttributes(theme)))
                    state = PendingBlockState(
                        kind: .fencedCode(language: language.isEmpty ? nil : String(language)),
                        startOffset: start + output.length)
                }
            } else {
                let attrs: [NSAttributedString.Key: Any]
                if case .fencedCode = state.kind {
                    attrs = codeAttributes(theme)
                } else {
                    attrs = normalAttributes(theme)
                }
                output.append(NSAttributedString(string: line, attributes: attrs))
            }
            cursor = lineEnd
        }
        return StyleOutput(increment: output, retroactive: retroactive)
    }

    mutating func flush(theme: Theme) -> StyleOutput {
        guard !fullText.isEmpty else { return StyleOutput(increment: NSAttributedString(), retroactive: []) }
        return StyleOutput(increment: NSAttributedString(), retroactive: [])
    }

    private func normalAttributes(_ theme: Theme) -> [NSAttributedString.Key: Any] {
        [.foregroundColor: theme.foreground]
    }

    private func codeAttributes(_ theme: Theme) -> [NSAttributedString.Key: Any] {
        [.foregroundColor: theme.syntax.string, .backgroundColor: theme.codeBackground]
    }
}
