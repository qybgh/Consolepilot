/// 会话与消息的持久化契约（由 Infrastructure 以 SQLite/GRDB 实现）。
///
/// 目录与分页语义：`fetchMessages(sessionId:offset:limit:)` 以 `offset` 起始
/// 返回 `limit` 条；排序方向由实现决定（现有 UI 按更新时间倒序取最新页）。
public protocol SessionRepository {
    func fetchSessions() throws -> [Session]
    func fetchSession(id: String) throws -> Session?
    func fetchMessages(sessionId: String, offset: Int, limit: Int) throws -> [Message]
    func searchMessages(matching query: String, limit: Int) throws -> [Message]
    func save(_ session: Session) throws
    func save(_ message: Message) throws
    func deleteSession(id: String) throws
    func deleteAllSessions() throws
}
