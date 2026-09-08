import Foundation

enum StreamEvent: Sendable, Equatable {
    case started(model: String)
    case delta(String)
    case usage(input: Int, output: Int)
    case finishReason(String)
    case finished
    case failed(TransportError)
}

struct TokenBatch: Sendable, Equatable {
    let sessionId: String
    let text: String
    let deltaCount: Int
}
