/// 过渡占位实现：P1-E 落地 Action 生命周期前，任何调用明确失败。
import ConsolepilotDomain

struct ActionExecutionUseCasePlaceholder: ActionExecutionUseCase {
    func run(_ request: ActionExecutionRequest) async throws -> ActionExecutionResponse {
        throw AppError.notImplemented("ActionExecutionUseCase.run")
    }
}
