import ConsolepilotDomain
import Foundation

actor AnthropicProvider: AIProvider {
    private let session: URLSession
    private let builder = RequestBuilder()

    init(session: URLSession = .shared) { self.session = session }

    nonisolated func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.consume(request, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(Self.map(error)))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func consume(_ request: ChatRequest, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation)
        async throws
    {
        let urlRequest = try builder.buildAnthropic(request)
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw TransportError.connectionLost }
        try TransportSupport.validateHTTPStatus(http.statusCode, headers: http.allHeaderFields)
        continuation.yield(.started(model: request.overrides?.model ?? request.profile.model))
        var decoder = SSEDecoder()
        var sawStop = false
        var lineBuffer = Data()
        for try await byte in bytes {
            lineBuffer.append(byte)
            guard byte == 0x0A else { continue }
            for frame in decoder.consume(lineBuffer) {
                if frame.event == "message_stop" { sawStop = true }
                try emit(frame, continuation: continuation)
            }
            lineBuffer.removeAll(keepingCapacity: true)
        }
        if !lineBuffer.isEmpty {
            for frame in decoder.consume(lineBuffer) {
                if frame.event == "message_stop" { sawStop = true }
                try emit(frame, continuation: continuation)
            }
        }
        for frame in decoder.flush() {
            if frame.event == "message_stop" { sawStop = true }
            try emit(frame, continuation: continuation)
        }
        guard sawStop else { throw TransportError.connectionLost }
        continuation.yield(.finished)
    }

    private func emit(_ frame: SSEFrame, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) throws {
        guard let data = frame.data.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw TransportError.decoding("Anthropic SSE data 不是有效 JSON") }
        switch frame.event {
        case "message_start":
            if let message = object["message"] as? [String: Any], let usage = message["usage"] as? [String: Any],
                let input = usage["input_tokens"] as? Int
            {
                continuation.yield(.usage(input: input, output: 0))
            }
        case "content_block_delta":
            if let delta = object["delta"] as? [String: Any], let text = delta["text"] as? String {
                continuation.yield(.delta(text))
            }
        case "message_delta":
            if let usage = object["usage"] as? [String: Any], let output = usage["output_tokens"] as? Int {
                continuation.yield(.usage(input: 0, output: output))
            }
        default: break
        }
    }

    private static func map(_ error: Error) -> TransportError {
        TransportSupport.map(error)
    }
}
