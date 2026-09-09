import AppKit
import ConsolepilotDomain

struct SyntaxPalette: Sendable, Equatable {
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let type: NSColor
    let function: NSColor
}

struct Theme: Sendable, Equatable {
    let name: String
    let background: NSColor
    let foreground: NSColor
    let cursor: NSColor
    let ansi: [NSColor]
    let roleColors: [MessageRole: NSColor]
    let channelColors: [SessionChannel: NSColor]
    let codeBackground: NSColor
    let syntax: SyntaxPalette

    static let fallback = Theme(
        name: "fallback", background: .black, foreground: .white, cursor: .white,
        ansi: [.black, .white], roleColors: [:], channelColors: [:], codeBackground: .black,
        syntax: SyntaxPalette(
            keyword: .white, string: .white, number: .white,
            comment: .white, type: .white, function: .white))

    static let registry: [String: Theme] = [
        "tokyo-night": Theme(
            name: "tokyo-night", background: NSColor(calibratedRed: 0.055, green: 0.063, blue: 0.102, alpha: 1),
            foreground: NSColor(calibratedRed: 0.78, green: 0.81, blue: 0.91, alpha: 1),
            cursor: NSColor.systemBlue, ansi: Self.standardANSI,
            roleColors: [.user: NSColor.systemCyan, .assistant: NSColor.systemGreen, .system: NSColor.systemYellow],
            channelColors: [
                .action: NSColor.systemPurple, .console: NSColor.systemBlue, .cli: NSColor.systemOrange,
                .push: NSColor.systemPink, .tail: NSColor.systemGray,
            ],
            codeBackground: NSColor(calibratedWhite: 0.12, alpha: 1),
            syntax: SyntaxPalette(
                keyword: .systemPurple, string: .systemGreen, number: .systemOrange,
                comment: .systemGray, type: .systemBlue, function: .systemCyan)
        ),
        "mono": Theme(
            name: "mono", background: .black, foreground: .white, cursor: .white, ansi: Self.standardANSI,
            roleColors: [.user: .white, .assistant: .white, .system: .white],
            channelColors: [.action: .white, .console: .white, .cli: .white, .push: .white, .tail: .white],
            codeBackground: NSColor(calibratedWhite: 0.12, alpha: 1),
            syntax: SyntaxPalette(
                keyword: .white, string: .white, number: .white, comment: .white,
                type: .white, function: .white)
        ),
    ]

    private static let standardANSI: [NSColor] = [
        .black, .systemRed, .systemGreen, .systemYellow, .systemBlue, .systemPurple, .systemCyan, .white,
        .darkGray, .systemRed, .systemGreen, .systemYellow, .systemBlue, .systemPurple, .systemCyan, .white,
    ]
}
