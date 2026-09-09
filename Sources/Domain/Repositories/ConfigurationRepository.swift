/// 配置来源的契约（由 Infrastructure 以 TOML 文件 + 校验实现）。
///
/// 热重载语义：`reload()` 必须解析并校验来源；失败时保留最后有效配置并抛错，
/// 成功时原子替换 `current`（先解析校验、再生效）。
public protocol ConfigurationRepository {
    /// 当前生效配置（始终为最后有效配置）。
    var current: AppConfig { get }
    func reload() throws
}
