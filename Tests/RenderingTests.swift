import XCTest

@testable import ConsolepilotLegacyUI

final class RenderingTests: XCTestCase {
    func testChatBubbleWidthPolicyShrinksOnlyTrueSingleLineMessages() {
        XCTAssertEqual(
            ChatBubbleWidthPolicy.resolve(
                containsLineBreak: false, intrinsicSingleLineWidth: 180, maxWidth: 600),
            180)
        XCTAssertEqual(
            ChatBubbleWidthPolicy.resolve(
                containsLineBreak: false, intrinsicSingleLineWidth: 900, maxWidth: 600),
            600)
        XCTAssertEqual(
            ChatBubbleWidthPolicy.resolve(
                containsLineBreak: true, intrinsicSingleLineWidth: 80, maxWidth: 600),
            600)
    }

    func testANSIParserHandlesSplitEscapeSequence() {
        var parser = ANSIParser()
        XCTAssertEqual(parser.consume("hello \u{1B}[3"), [ANSISpan(text: "hello ", attributes: .default)])
        XCTAssertEqual(
            parser.consume("1mworld\u{1B}[0m!"),
            [
                ANSISpan(
                    text: "world",
                    attributes: ANSIAttribute(
                        foreground: 1, background: nil, bold: false, italic: false, underline: false)),
                ANSISpan(text: "!", attributes: .default),
            ])
    }

    func testANSIParserFlushesIncompleteSequenceWithoutDroppingText() {
        var parser = ANSIParser()
        XCTAssertEqual(parser.consume("before\u{1B}["), [ANSISpan(text: "before", attributes: .default)])
        XCTAssertEqual(parser.flush(), [ANSISpan(text: "\u{1B}[", attributes: .default)])
    }

    func testANSIParserTracksAttributesAndReset() {
        var parser = ANSIParser()
        let spans = parser.consume("\u{1B}[1;34mbold blue\u{1B}[22;39mnormal")
        XCTAssertEqual(spans.count, 2)
        XCTAssertTrue(spans[0].attributes.bold)
        XCTAssertEqual(spans[0].attributes.foreground, 4)
        XCTAssertFalse(spans[1].attributes.bold)
        XCTAssertNil(spans[1].attributes.foreground)
    }

    func testMarkdownStylerKeepsCodeBlockStateAcrossIncrements() {
        var styler = MarkdownStyler()
        let theme = Theme.registry["mono"]!
        let first = styler.style("```swift\nlet value = ", theme: theme)
        let second = styler.style("42\n```\n", theme: theme)
        XCTAssertEqual(first.increment.string, "```swift\nlet value = ")
        XCTAssertEqual(second.increment.string, "42\n```\n")
        XCTAssertFalse(second.retroactive.isEmpty)
    }

    func testMarkdownMessageRendererStylesHeadingsListsInlineAndFencedCode() {
        let theme = Theme.registry["tokyo-night"]!
        let rendered = MarkdownMessageRenderer.render(
            "# 标题\n- 列表 **加粗**\n使用 `inline`\n```swift\nlet value = 42\n```",
            theme: theme)
        XCTAssertEqual(rendered.string, "标题\n• 列表 加粗\n使用 inline\nlet value = 42")
        let codeRange = (rendered.string as NSString).range(of: "let value = 42")
        XCTAssertEqual(
            rendered.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil) as? NSColor,
            theme.codeBackground)
        let inlineRange = (rendered.string as NSString).range(of: "inline")
        XCTAssertNotNil(rendered.attribute(.backgroundColor, at: inlineRange.location, effectiveRange: nil))
    }

    func testScrollbackTrimmerRemovesWholeLinesInBatch() {
        let storage = NSMutableAttributedString(string: (0..<20_000).map { "line\($0)\n" }.joined())
        ScrollbackTrimmer(maxLines: 10_000).trim(storage)
        XCTAssertLessThanOrEqual(storage.string.split(separator: "\n").count, 10_000)
        XCTAssertTrue(storage.string.hasPrefix("line"))
    }
}
