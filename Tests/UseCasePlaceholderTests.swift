import XCTest

@testable import ConsolepilotCore

/// P0-C 空壳契约测试：固定 Conversation/Action 两个用例协议的入口存在，
/// 且占位实现明确抛 `.notImplemented`（P1 接线前的契约方向）。
final class UseCasePlaceholderTests: XCTestCase {
    func testConversationUseCasePlaceholderThrowsNotImplemented() async {
        let useCase = ConversationUseCasePlaceholder()
        let request = ConversationRequest(text: "你好", sessionId: nil, profileId: "local")

        do {
            _ = try await useCase.send(request)
            XCTFail("占位实现应抛出 notImplemented")
        } catch let error as AppError {
            XCTAssertEqual(error.code, "notImplemented")
        } catch {
            XCTFail("错误类型不符合契约：\(error)")
        }

        do {
            try await useCase.cancelCurrent()
            XCTFail("占位实现应抛出 notImplemented")
        } catch let error as AppError {
            XCTAssertEqual(error.code, "notImplemented")
        } catch {
            XCTFail("错误类型不符合契约：\(error)")
        }
    }

    func testActionExecutionUseCasePlaceholderThrowsNotImplemented() async {
        let useCase = ActionExecutionUseCasePlaceholder()
        let request = ActionExecutionRequest(actionId: "summarize", overrideInput: nil)

        do {
            _ = try await useCase.run(request)
            XCTFail("占位实现应抛出 notImplemented")
        } catch let error as AppError {
            XCTAssertEqual(error.code, "notImplemented")
        } catch {
            XCTFail("错误类型不符合契约：\(error)")
        }
    }
}
