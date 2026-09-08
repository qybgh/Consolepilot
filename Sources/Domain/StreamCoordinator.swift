import Foundation

struct StreamDraft: Sendable, Equatable {
    let sessionId: String
    let messageId: String
    let startedAt: Date
    let text: String
}

/// 唯一的流汇聚点。每个会话拥有独立上下文；流进行中定期写入检查点，
/// 因此中断、切换会话或应用退出都不会丢失已经收到的内容。
@MainActor
final class StreamCoordinator {
    private final class Context {
        let startedAt = Date()
        let clockStartedAt = ContinuousClock.now
        var accumulatedText = ""
        var pending = ""
        var deltaCount = 0
        var inputTokens = 0
        var outputTokens = 0
        var model: String?
        var finishReason: String?
        var didFinish = false
        var windowStart = ContinuousClock.now
        var lastCheckpoint = Date.distantPast
        var didReceiveFirstDelta = false
        var firstDeltaLatency: Duration?
        let assistantMessageId = UUID().uuidString
    }

    private let sessionStore: SessionStore
    private let usageStore: UsageStore
    private var contexts: [String: Context] = [:]

    var onDelta: ((String, TokenBatch) -> Void)?
    var onFinish: ((String, MessageState) -> Void)?
    var onStarted: ((String, String) -> Void)?
    var onFirstDelta: ((String, Duration) -> Void)?
    var onFinishReason: ((String, String) -> Void)?
    var onCompleted: ((String, MessageState, Int, String?, Duration?, Duration) -> Void)?

    init(sessionStore: SessionStore, usageStore: UsageStore) {
        self.sessionStore = sessionStore
        self.usageStore = usageStore
    }

    var isStreaming: Bool { !contexts.isEmpty }

    func isStreaming(sessionId: String) -> Bool { contexts[sessionId] != nil }

    /// Persist active drafts before termination while the store is still alive.
    func persistActiveDrafts() {
        for (sessionId, context) in contexts {
            flush(context, sessionId: sessionId)
            persistCheckpoint(context, sessionId: sessionId, state: .interrupted, force: true)
        }
    }

    /// Synchronously checkpoint a session before its provider task is cancelled.
    /// This closes the small race where cancellation occurs before the next
    /// streaming flush (especially visible during the first few tokens).
    func interrupt(sessionId: String) {
        guard let context = contexts[sessionId], !context.didFinish else { return }
        flush(context, sessionId: sessionId)
        persistCheckpoint(context, sessionId: sessionId, state: .interrupted, force: true)
    }

    func draft(sessionId: String) -> StreamDraft? {
        guard let context = contexts[sessionId] else { return nil }
        let draft = StreamDraft(
            sessionId: sessionId, messageId: context.assistantMessageId, startedAt: context.startedAt,
            text: context.accumulatedText)
        // 草稿已经包含尚未合帧的字符；恢复界面后不能再次发送这些 pending。
        context.pending.removeAll(keepingCapacity: true)
        context.deltaCount = 0
        // Checkpoint at most four times per second during a long stream. The
        // final/interrupted path below always writes the latest complete text.
        persistCheckpoint(context, sessionId: sessionId, state: .interrupted, force: false)
        context.windowStart = ContinuousClock.now
        return draft
    }

    func consume(_ events: AsyncThrowingStream<StreamEvent, Error>, into sessionId: String) async {
        guard contexts[sessionId] == nil else { return }
        let context = Context()
        contexts[sessionId] = context
        defer { contexts.removeValue(forKey: sessionId) }

        do {
            for try await event in events {
                try Task.checkCancellation()
                switch event {
                case .started(let startedModel):
                    context.model = startedModel
                    onStarted?(sessionId, startedModel)
                case .delta(let delta):
                    if !context.didReceiveFirstDelta {
                        context.didReceiveFirstDelta = true
                        let latency = context.clockStartedAt.duration(to: ContinuousClock.now)
                        context.firstDeltaLatency = latency
                        onFirstDelta?(sessionId, latency)
                        Log.info("流首字节：session=\(sessionId) latency=\(latency)", category: .transport)
                    }
                    context.pending.append(delta)
                    context.accumulatedText.append(delta)
                    context.deltaCount += 1
                    if context.windowStart.duration(to: .now) >= .milliseconds(17) {
                        flush(context, sessionId: sessionId)
                        context.windowStart = ContinuousClock.now
                    }
                case .usage(let input, let output):
                    context.inputTokens += input
                    context.outputTokens += output
                case .finishReason(let reason):
                    context.finishReason = reason
                    onFinishReason?(sessionId, reason)
                case .finished:
                    flush(context, sessionId: sessionId)
                    finish(context, sessionId: sessionId, state: .complete)
                case .failed:
                    flush(context, sessionId: sessionId)
                    finish(context, sessionId: sessionId, state: .failed)
                }
            }
            // Cancellation of an AsyncThrowingStream is allowed to terminate
            // iteration without throwing. If the provider ended without an
            // explicit `.finished`/`.failed` event, preserve the accumulated
            // prefix as an interrupted response instead of dropping it.
            if !context.didFinish {
                flush(context, sessionId: sessionId)
                finish(context, sessionId: sessionId, state: .interrupted)
            }
        } catch {
            flush(context, sessionId: sessionId)
            finish(context, sessionId: sessionId, state: .interrupted)
            if !(error is CancellationError) {
                Log.error("流消费中断：\(error)", category: .domain)
            }
        }
    }

    private func flush(_ context: Context, sessionId: String) {
        guard !context.pending.isEmpty else { return }
        onDelta?(
            sessionId,
            TokenBatch(
                sessionId: sessionId, text: context.pending,
                deltaCount: context.deltaCount))
        context.pending.removeAll(keepingCapacity: true)
        context.deltaCount = 0
    }

    private func finish(_ context: Context, sessionId: String, state: MessageState) {
        guard !context.didFinish else { return }
        context.didFinish = true
        onFinish?(sessionId, state)
        let totalDuration = context.clockStartedAt.duration(to: ContinuousClock.now)
        onCompleted?(
            sessionId, state, context.accumulatedText.count, context.finishReason,
            context.firstDeltaLatency, totalDuration)
        persistCheckpoint(context, sessionId: sessionId, state: state, force: true)
        guard let session = sessionStore.session(id: sessionId),
            let profileId = session.profileId,
            let provider = session.provider,
            let model = context.model,
            context.inputTokens > 0 || context.outputTokens > 0
        else { return }
        usageStore.record(
            UsageRecord(
                sessionId: sessionId, actionId: session.actionId, profileId: profileId,
                provider: provider, model: model, inputTokens: context.inputTokens,
                outputTokens: context.outputTokens,
                total: context.clockStartedAt.duration(to: ContinuousClock.now)))
    }

    private func persistCheckpoint(
        _ context: Context, sessionId: String, state: MessageState, force: Bool
    ) {
        guard !context.accumulatedText.isEmpty else { return }
        let now = Date()
        guard force || now.timeIntervalSince(context.lastCheckpoint) >= 0.25 else { return }
        context.lastCheckpoint = now
        sessionStore.upsertMessage(
            Message(
                id: context.assistantMessageId, sessionId: sessionId, role: .assistant,
                content: context.accumulatedText, state: state, createdAt: context.startedAt))
    }
}
