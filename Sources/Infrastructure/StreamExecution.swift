import Foundation

/// 单条请求执行的生命周期状态机与取消句柄（P1-C）。
///
/// 状态迁移：`queued → connecting → streaming → completed/failed/cancelled`；
/// 终态不可逆。每个进行中会话由 `StreamCoordinator` 持有一个实例，
/// 退出/会话删除/配置热重载/Action 取消/断网等统一走 `cancel()`。
package actor RequestExecution {
    package enum State: Sendable, Equatable {
        case queued, connecting, streaming, completed, failed, cancelled

        var isActive: Bool {
            switch self {
            case .queued, .connecting, .streaming: true
            case .completed, .failed, .cancelled: false
            }
        }
    }

    package let sessionId: String
    package private(set) var state: State = .queued
    private var task: Task<Void, Never>?
    private var cancelledBeforeStart = false

    package init(sessionId: String) {
        self.sessionId = sessionId
    }

    /// 启动真正的消费任务（同一执行只允许启动一次）。
    package func start(_ body: @escaping @Sendable () async -> Void) {
        guard task == nil else { return }
        let newTask = Task { await body() }
        task = newTask
        if cancelledBeforeStart {
            newTask.cancel()
        }
    }

    package func awaitCompletion() async {
        await task?.value
    }

    /// 统一取消入口：先标记 cancelled，再取消消费任务；尚未启动的任务在
    /// `start` 时立即取消，避免「先取消后启动」丢失取消信号。
    package func cancel() {
        guard state.isActive else { return }
        state = .cancelled
        cancelledBeforeStart = true
        task?.cancel()
    }

    /// 记录粗粒度状态迁移；非法迁移与终态后的重复写入被忽略。
    package func mark(_ next: State) {
        switch (state, next) {
        case (.queued, .connecting), (.connecting, .streaming), (.queued, .streaming):
            state = next
        case (let current, .completed), (let current, .failed), (let current, .cancelled):
            guard current.isActive else { return }
            state = next
        default:
            break
        }
    }
}
