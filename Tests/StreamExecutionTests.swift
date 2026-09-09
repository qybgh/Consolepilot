import ConsolepilotDomain
import XCTest

@testable import ConsolepilotInfrastructure

/// P1-C：RequestExecution 生命周期状态机 + StreamCoordinator 统一取消注册表。
/// 断言取消后不再收增量、已收前缀以 interrupted 落库、usage 恰好一次。
final class StreamExecutionTests: XCTestCase {
    private actor RunFlag {
        private(set) var didRun = false
        func mark() { didRun = true }
    }

    // MARK: - RequestExecution actor

    func testExecutionTransitionsQueuedToConnectingToStreaming() async {
        let execution = RequestExecution(sessionId: "session-1")
        let queued = await execution.state
        XCTAssertEqual(queued, .queued)

        await execution.start {
            await execution.mark(.connecting)
            await execution.mark(.streaming)
        }
        await execution.awaitCompletion()

        let streamed = await execution.state
        XCTAssertEqual(streamed, .streaming)
    }

    func testExecutionCompletesAndIgnoresMarksAfterTerminalState() async {
        let execution = RequestExecution(sessionId: "session-1")
        await execution.start {
            await execution.mark(.connecting)
        }
        await execution.awaitCompletion()
        await execution.mark(.completed)
        let completedNow = await execution.state
        XCTAssertEqual(completedNow, .completed)

        await execution.mark(.failed)
        await execution.mark(.cancelled)
        let completed = await execution.state
        XCTAssertEqual(completed, .completed, "终态后的写入必须被忽略")
    }

    func testCancelBeforeStartCancelsTheWork() async {
        let execution = RequestExecution(sessionId: "session-1")
        await execution.cancel()
        let cancelled = await execution.state
        XCTAssertEqual(cancelled, .cancelled)

        let flag = RunFlag()
        await execution.start {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }
            await flag.mark()
        }
        await execution.awaitCompletion()

        let didRun = await flag.didRun
        XCTAssertFalse(didRun, "先取消后启动不得执行任务体")
    }

    func testCancelIsIdempotentAndReachesTerminalState() async {
        let execution = RequestExecution(sessionId: "session-1")
        await execution.start {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }
        }

        await execution.cancel()
        await execution.cancel()
        let cancelled = await execution.state
        XCTAssertEqual(cancelled, .cancelled)
        await execution.awaitCompletion()
    }

    // MARK: - StreamCoordinator 统一取消

    @MainActor
    func testCoordinatorCancelStopsFurtherDeltasAndPreservesReceivedPrefix() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotCoordinatorCancel-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path)
        let sessions = try SessionStore(database: database)
        let session = sessions.create(
            channel: .console, title: "Cancel",
            meta: SessionMeta(actionId: nil, profileId: nil, provider: nil, model: nil, sourceApp: nil))
        let usage = UsageStore(database: database)
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: usage)
        var received = ""
        coordinator.onDelta = { _, batch in received += batch.text }
        var continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation!
        let events = AsyncThrowingStream<StreamEvent, Error> { continuation = $0 }
        let task = Task { await coordinator.consume(events, into: session.id) }
        continuation.yield(.started(model: "test"))
        continuation.yield(.delta("prefix-"))
        // 合帧窗口为 17ms：先让 drive 完成对已收 delta 的处理。
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(coordinator.isStreaming(sessionId: session.id))

        await coordinator.cancel(sessionId: session.id)
        // interrupt 在取消前同步 flush，已收前缀必须立刻可见。
        XCTAssertEqual(received, "prefix-")
        // 取消已生效后再到达的增量必须被丢弃。
        continuation.yield(.delta("tail-"))
        continuation.finish()
        await task.value

        XCTAssertFalse(coordinator.isStreaming(sessionId: session.id))
        XCTAssertEqual(received, "prefix-", "取消后不得再接收增量")
        let stored = try await database.writer.read { db in try MessageRecord.fetchAll(db).map(\.entity) }
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].content, "prefix-")
        XCTAssertEqual(stored[0].state, .interrupted)
        XCTAssertEqual(usage.summary(period: .all).requestCount, 0, "被取消的流不得记录 usage")
    }

    @MainActor
    func testCoordinatorCancelOnIdleSessionIsNoop() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotCoordinatorCancelIdle-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path)
        let sessions = try SessionStore(database: database)
        let coordinator = StreamCoordinator(
            sessionStore: sessions, usageStore: UsageStore(database: database))

        await coordinator.cancel(sessionId: "missing-session")

        XCTAssertFalse(coordinator.isStreaming)
    }

    @MainActor
    func testCoordinatorRecordsUsageExactlyOnceOnCompletion() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsolepilotCoordinatorUsageOnce-\(UUID().uuidString).sqlite"
        ).path
        let database = try AppDatabase(path: path)
        let sessions = try SessionStore(database: database)
        let session = sessions.create(
            channel: .action, title: "Usage",
            meta: SessionMeta(
                actionId: "usage-action", profileId: "local", provider: .openai,
                model: "mock-stream-v1", sourceApp: "TextEdit"))
        let usage = UsageStore(database: database)
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: usage)
        let events = AsyncThrowingStream<StreamEvent, Error> { continuation in
            continuation.yield(.started(model: "mock-stream-v1"))
            continuation.yield(.delta("你好"))
            continuation.yield(.usage(input: 12, output: 7))
            continuation.yield(.finishReason("stop"))
            continuation.yield(.finished)
            continuation.finish()
        }

        await coordinator.consume(events, into: session.id)

        let summary = usage.summary(period: .all)
        XCTAssertEqual(summary.requestCount, 1, "usage 只能记录一次")
        XCTAssertEqual(summary.inputTokens, 12)
        XCTAssertEqual(summary.outputTokens, 7)
    }
}
