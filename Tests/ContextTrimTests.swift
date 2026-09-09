import ConsolepilotDomain
import XCTest

final class ContextTrimTests: XCTestCase {
    private func userMessage(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    private func assistantMessage(_ content: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: content)
    }

    private func assertValidUTF8(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(String(bytes: Array(text.utf8), encoding: .utf8), file: file, line: line)
    }

    func testUnderBudgetIsReturnedUnchanged() {
        let messages = [userMessage("第一条"), assistantMessage("回复内容 hello world")]
        let result = ContextTrim.trim(systemPrompt: "system", messages: messages, budgetBytes: 1_000_000)
        XCTAssertEqual(result.messages, messages)
        XCTAssertEqual(result.droppedCount, 0)
        XCTAssertFalse(result.truncated)
    }

    func testEmptyMessagesAreUnchanged() {
        let result = ContextTrim.trim(systemPrompt: nil, messages: [], budgetBytes: 1024)
        XCTAssertTrue(result.messages.isEmpty)
        XCTAssertEqual(result.droppedCount, 0)
        XCTAssertFalse(result.truncated)
    }

    func testDropsOldestWholeMessagesFirstAndKeepsNewest() {
        // 4 条消息，正文分别约 60/60/60/10 字节；预算 100 只放得下最后两条。
        let messages = [
            userMessage(String(repeating: "a", count: 60)),
            assistantMessage(String(repeating: "b", count: 60)),
            userMessage(String(repeating: "c", count: 60)),
            assistantMessage(String(repeating: "d", count: 10)),
        ]
        let result = ContextTrim.trim(systemPrompt: nil, messages: messages, budgetBytes: 100)
        XCTAssertEqual(result.messages.count, 2)
        XCTAssertEqual(result.messages[0].content, messages[2].content)
        XCTAssertEqual(result.messages[1].content, messages[3].content)
        XCTAssertEqual(result.droppedCount, 2)
        XCTAssertFalse(result.truncated)
    }

    func testTruncatesNewestAtByteBoundaryWhenItAloneExceedsBudget() {
        let big = String(repeating: "x", count: 200)
        let result = ContextTrim.trim(
            systemPrompt: nil, messages: [userMessage(big), userMessage(big)], budgetBytes: 64)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.droppedCount, 1)
        XCTAssertTrue(result.truncated)
        XCTAssertLessThanOrEqual(result.messages[0].content.utf8.count, 64)
    }

    func testTruncationNeverSplitsMultibyteCharacters() {
        // “中”=3 字节；预算 64 保证落在字符边界而非字节中间。
        let big = String(repeating: "中文😀测试", count: 40)
        let result = ContextTrim.trim(systemPrompt: nil, messages: [userMessage(big)], budgetBytes: 64)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertTrue(result.truncated)
        XCTAssertLessThanOrEqual(result.messages[0].content.utf8.count, 64)
        assertValidUTF8(result.messages[0].content)
        XCTAssertTrue(big.hasPrefix(result.messages[0].content))
    }

    func testSystemPromptConsumesBudgetBeforeMessages() {
        let system = String(repeating: "s", count: 60)
        let messages = [userMessage(String(repeating: "a", count: 60)), userMessage(String(repeating: "b", count: 60))]
        // 预算 100：system 占 60，消息只剩 40 字节可用 → 只能保留截断后的最新一条。
        let result = ContextTrim.trim(systemPrompt: system, messages: messages, budgetBytes: 100)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.droppedCount, 1)
        XCTAssertTrue(result.truncated)
        // 预算 100：system 占 60，消息只剩 40 字节 → 最新一条被截断到 40 字节。
        XCTAssertEqual(result.messages[0].content, String(repeating: "b", count: 40))
        XCTAssertLessThanOrEqual(system.utf8.count + result.messages[0].content.utf8.count, 100)
    }

    func testSystemPromptBytesAreCountedButKeptWhole() {
        let system = String(repeating: "s", count: 60)
        let messages = [userMessage("short")]
        // 预算 70：system 60 + 最新 5 = 65 ≤ 70 → 不动。
        let result = ContextTrim.trim(systemPrompt: system, messages: messages, budgetBytes: 70)
        XCTAssertEqual(result.messages, messages)
        XCTAssertEqual(result.droppedCount, 0)
        XCTAssertFalse(result.truncated)
    }
}
