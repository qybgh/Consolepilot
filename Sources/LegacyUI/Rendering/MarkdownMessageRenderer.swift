import AppKit

enum MarkdownMessageRenderer {
    static func render(_ markdown: String, theme: Theme) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var inCodeBlock = false
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, rawLine) in lines.enumerated() {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }

            if inCodeBlock {
                result.append(codeLine(line, theme: theme))
            } else {
                result.append(markdownLine(line, theme: theme))
            }
            if index < lines.count - 1 { result.append(NSAttributedString(string: "\n")) }
        }
        if !markdown.hasSuffix("\n"), result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }
        return result
    }

    private static func codeLine(_ line: String, theme: Theme) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 8
        paragraph.firstLineHeadIndent = 8
        paragraph.tailIndent = -8
        paragraph.paragraphSpacingBefore = 2
        paragraph.paragraphSpacing = 2
        return NSAttributedString(
            string: line.isEmpty ? " " : line,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                .foregroundColor: theme.syntax.string,
                .backgroundColor: theme.codeBackground,
                .paragraphStyle: paragraph,
            ])
    }

    private static func markdownLine(_ line: String, theme: Theme) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefixCount = trimmed.prefix { $0 == "#" }.count
        if prefixCount > 0, prefixCount <= 6, trimmed.dropFirst(prefixCount).first == " " {
            let text = String(trimmed.dropFirst(prefixCount + 1))
            let size = max(14, 19 - CGFloat(prefixCount))
            return inline(
                text, theme: theme,
                base: [.font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: theme.foreground])
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let content = String(trimmed.dropFirst(2))
            let value = NSMutableAttributedString(
                string: "• ", attributes: normalAttributes(theme))
            value.append(inline(content, theme: theme, base: normalAttributes(theme)))
            return value
        }
        if trimmed.hasPrefix("> ") {
            let value = NSMutableAttributedString(
                string: "│ ",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: theme.syntax.comment,
                ])
            value.append(
                inline(
                    String(trimmed.dropFirst(2)), theme: theme,
                    base: [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: theme.foreground.withAlphaComponent(0.82),
                    ]))
            return value
        }
        return inline(line, theme: theme, base: normalAttributes(theme))
    }

    private static func inline(
        _ text: String, theme: Theme, base: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix("**"),
                let end = text[text.index(index, offsetBy: 2)...].range(of: "**")?.lowerBound
            {
                let start = text.index(index, offsetBy: 2)
                var attributes = base
                attributes[.font] = NSFont.systemFont(ofSize: 13, weight: .bold)
                result.append(NSAttributedString(string: String(text[start..<end]), attributes: attributes))
                index = text.index(end, offsetBy: 2)
            } else if text[index] == "`", let end = text[text.index(after: index)...].firstIndex(of: "`") {
                let start = text.index(after: index)
                result.append(
                    NSAttributedString(
                        string: String(text[start..<end]),
                        attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                            .foregroundColor: theme.syntax.string,
                            .backgroundColor: theme.codeBackground,
                        ]))
                index = text.index(after: end)
            } else {
                let next = nextMarker(in: text, after: index) ?? text.endIndex
                result.append(NSAttributedString(string: String(text[index..<next]), attributes: base))
                index = next
            }
        }
        return result
    }

    private static func nextMarker(in text: String, after index: String.Index) -> String.Index? {
        let searchStart = text.index(after: index)
        guard searchStart < text.endIndex else { return nil }
        let suffix = text[searchStart...]
        return [suffix.range(of: "**")?.lowerBound, suffix.firstIndex(of: "`")].compactMap { $0 }.min()
    }

    private static func normalAttributes(_ theme: Theme) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: theme.foreground]
    }
}
