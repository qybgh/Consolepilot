import ConsolepilotDomain
import Foundation

package actor OpenAICompatibleProvider: AIProvider {
    private let session: URLSession
    private let builder = RequestBuilder()

    package init(session: URLSession = .shared) { self.session = session }

    nonisolated package func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
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
        let urlRequest = try builder.buildOpenAI(request)
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw TransportError.connectionLost }
        try TransportSupport.validateHTTPStatus(http.statusCode, headers: http.allHeaderFields)
        continuation.yield(.started(model: request.overrides?.model ?? request.profile.model))
        var decoder = SSEDecoder()
        var sawDone = false
        var lineBuffer = Data()
        for try await byte in bytes {
            lineBuffer.append(byte)
            guard byte == 0x0A else { continue }
            for frame in decoder.consume(lineBuffer) {
                if frame.data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" { sawDone = true }
                try emit(frame, continuation: continuation)
            }
            lineBuffer.removeAll(keepingCapacity: true)
        }
        if !lineBuffer.isEmpty {
            for frame in decoder.consume(lineBuffer) {
                if frame.data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" { sawDone = true }
                try emit(frame, continuation: continuation)
            }
        }
        for frame in decoder.flush() {
            if frame.data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" { sawDone = true }
            try emit(frame, continuation: continuation)
        }
        guard sawDone else { throw TransportError.connectionLost }
        continuation.yield(.finished)
    }

    private func emit(_ frame: SSEFrame, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) throws {
        guard frame.data.trimmingCharacters(in: .whitespacesAndNewlines) != "[DONE]" else { return }
        guard let data = frame.data.data(using: .utf8) else {
            throw TransportError.decoding("OpenAI SSE data 不是有效 JSON")
        }
        let chunk: OpenAICompatStreamChunk
        do {
            chunk = try JSONDecoder().decode(OpenAICompatStreamChunk.self, from: data)
        } catch {
            throw TransportError.decoding("OpenAI SSE data 不是有效 JSON")
        }
        if let usage = chunk.usage,
            let input = usage.promptTokens, let output = usage.completionTokens
        {
            continuation.yield(.usage(input: input, output: output))
        }
        guard let choice = chunk.choices?.first else { return }
        if let text = choice.delta?.content, !text.isEmpty {
            continuation.yield(.delta(text))
        }
        if let reason = choice.finishReason, !reason.isEmpty {
            continuation.yield(.finishReason(reason))
            Log.info("OpenAI finish_reason=\(reason)", category: .transport)
        }
    }

    private static func map(_ error: Error) -> TransportError {
        TransportSupport.map(error)
    }
}
