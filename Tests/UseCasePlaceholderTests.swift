import ConsolepilotDomain
import XCTest

@testable import ConsolepilotApplication

/// P0-C 空壳契约测试：固定 Conversation 用例协议入口存在，且占位实现明确抛
/// `.notImplemented`。ActionExecutionUseCase 已在 P1-E 由 ActionRunner 真实实现，
/// 真实接线测试见 InfrastructureTests 的 `testActionRunnerImplementsActionExecutionUseCaseContract`。
final class ConversationUseCasePlaceholderTests: XCTestCase {
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
}
