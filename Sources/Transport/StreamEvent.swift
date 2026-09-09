import ConsolepilotDomain
import Foundation

package enum StreamEvent: Sendable, Equatable {
    case started(model: String)
    case delta(String)
    case usage(input: Int, output: Int)
    case finishReason(String)
    case finished
    case failed(TransportError)
}

package struct TokenBatch: Sendable, Equatable {
    package let sessionId: String
    package let text: String
    package let deltaCount: Int

    package init(sessionId: String, text: String, deltaCount: Int) {
        self.sessionId = sessionId
        self.text = text
        self.deltaCount = deltaCount
    }
}
