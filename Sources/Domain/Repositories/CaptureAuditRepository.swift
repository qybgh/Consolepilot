/// 文本捕获审计的持久化契约（由 Infrastructure 以 SQLite/GRDB 实现）。
///
/// 审计只落元数据（来源 App、字符数、策略、耗时），绝不落捕获正文。
protocol CaptureAuditRepository {
    func record(_ entry: CaptureLogEntry) throws
}
