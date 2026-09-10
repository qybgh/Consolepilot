import ConsolepilotDomain
import Foundation

package struct StreamDraft: Sendable, Equatable {
    package let sessionId: String
    package let messageId: String
    package let startedAt: Date
    package let text: String

    package init(sessionId: String, messageId: String, startedAt: Date, text: String) {
        self.sessionId = sessionId
        self.messageId = messageId
        self.startedAt = startedAt
        self.text = text
    }
}

/// 唯一的流汇聚点。每个会话拥有独立上下文；流进行中定期写入检查点，
/// 因此中断、切换会话或应用退出都不会丢失已经收到的内容。
@MainActor
package final class StreamCoordinator {
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
        var didStart = false
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
    /// 每个进行中会话的请求执行（取消注册表）：退出/会话删除/配置热重载/
    /// Action 取消/断网统一经 `cancel(sessionId:)` 走此表。
    private var executions: [String: RequestExecution] = [:]

    package var onDelta: ((String, TokenBatch) -> Void)?
    package var onFinish: ((String, MessageState) -> Void)?
    package var onStarted: ((String, String) -> Void)?
    package var onFirstDelta: ((String, Duration) -> Void)?
    package var onFinishReason: ((String, String) -> Void)?
    package var onCompleted: ((String, MessageState, Int, String?, Duration?, Duration) -> Void)?

    package init(sessionStore: SessionStore, usageStore: UsageStore) {
        self.sessionStore = sessionStore
        self.usageStore = usageStore
    }

    var isStreaming: Bool { !contexts.isEmpty }

    package func isStreaming(sessionId: String) -> Bool { contexts[sessionId] != nil }

    /// Persist active drafts before termination while the store is still alive.
    package func persistActiveDrafts() {
        for (sessionId, context) in contexts {
            flush(context, sessionId: sessionId)
            persistCheckpoint(context, sessionId: sessionId, state: .interrupted, force: true)
        }
    }

    /// Synchronously checkpoint a session before its provider task is cancelled.
    /// This closes the small race where cancellation occurs before the next
    /// streaming flush (especially visible during the first few tokens).
    package func interrupt(sessionId: String) {
        guard let context = contexts[sessionId], !context.didFinish else { return }
        flush(context, sessionId: sessionId)
        persistCheckpoint(context, sessionId: sessionId, state: .interrupted, force: true)
    }

    package func draft(sessionId: String) -> StreamDraft? {
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

    package func consume(_ events: AsyncThrowingStream<StreamEvent, Error>, into sessionId: String) async {
        guard contexts[sessionId] == nil, executions[sessionId] == nil else { return }
        let context = Context()
        let execution = RequestExecution(sessionId: sessionId)
        contexts[sessionId] = context
        executions[sessionId] = execution
        defer {
            contexts.removeValue(forKey: sessionId)
            executions.removeValue(forKey: sessionId)
        }
        // 消费任务由 RequestExecution 持有：统一取消经 `cancel(sessionId:)`
        // 取消该任务，从而立即终止对 events 的迭代（不再接收增量）。
        await execution.start { [weak self] in
            await self?.drive(events, into: sessionId, execution: execution)
        }
        await execution.awaitCompletion()
    }

    /// 统一取消入口：先同步 flush + checkpoint（不丢已收内容），再取消该会话
    /// 的执行任务；此后该会话不再产生增量。
    package func cancel(sessionId: String) async {
        interrupt(sessionId: sessionId)
        await executions[sessionId]?.cancel()
    }

    /// 逐事件驱动流状态机并维护 checkpoint/usage。任务被取消时 `for await`
    /// 立即结束（或 `Task.checkCancellation` 抛出），已收前缀以 `.interrupted`
    /// 落库保留。
    private func drive(
        _ events: AsyncThrowingStream<StreamEvent, Error>, into sessionId: String,
        execution: RequestExecution
    ) async {
        guard let context = contexts[sessionId] else { return }
        await execution.mark(.connecting)
        var outcome: RequestExecution.State = .failed
        do {
            for try await event in events {
                try Task.checkCancellation()
                switch event {
                case .started(let startedModel):
                    context.model = startedModel
                    context.didStart = true
                    await execution.mark(.streaming)
                    onStarted?(sessionId, startedModel)
                case .delta(let delta):
                    if !context.didReceiveFirstDelta {
                        context.didReceiveFirstDelta = true
                        let latency = context.clockStartedAt.duration(to: ContinuousClock.now)
                        context.firstDeltaLatency = latency
                        await execution.mark(.streaming)
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
                    outcome = .completed
                    finish(context, sessionId: sessionId, state: .complete)
                case .failed:
                    flush(context, sessionId: sessionId)
                    outcome = .failed
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
                outcome = Task.isCancelled ? .cancelled : .failed
            }
        } catch {
            flush(context, sessionId: sessionId)
            finish(context, sessionId: sessionId, state: .interrupted)
            outcome = (error is CancellationError) ? .cancelled : .failed
            if !(error is CancellationError) {
                Log.error("流消费中断：\(error)", category: .domain)
            }
        }
        // 终态登记；若 `cancel()` 已先行把状态置为终态，此处的写入会被忽略。
        await execution.mark(outcome)
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
        // 流到达终态即从“进行中”集合移除：`isStreaming(sessionId:)`/`draft`
        // 立刻反映“已结束”，UI 收尾不再与 consume() 的清理时序竞争（consume
        // 要等执行任务完全返回才移除 executions，收尾期间仍会拦截同会话重复
        // consume）。已完成消息已由随后的 force checkpoint 落库。
        contexts.removeValue(forKey: sessionId)
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
            context.didStart,
            state == .complete || context.inputTokens > 0 || context.outputTokens > 0
        else { return }
        usageStore.record(
            Usage(
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
