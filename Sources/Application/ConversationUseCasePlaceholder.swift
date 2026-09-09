/// 过渡占位实现：P1-C 以 StreamCoordinator/RequestExecution 重建前，任何调用明确失败。
import ConsolepilotDomain

struct ConversationUseCasePlaceholder: ConversationUseCase {
    func send(_ request: ConversationRequest) async throws -> ConversationResponse {
        throw AppError.notImplemented("ConversationUseCase.send")
    }

    func cancelCurrent() async throws {
        throw AppError.notImplemented("ConversationUseCase.cancelCurrent")
    }
}
