import ConsolepilotDomain
import Foundation

/// `ConfigurationRepository` 的文件实现：解析 + 校验通过才原子替换 `current`，
/// 失败抛出 `ConfigError` 并保留最后有效配置（D6 热重载语义）。
///
/// 不承担文件监听；UI 侧的自动热重载仍由 `ConfigStore`（MainActor + watcher）负责，
/// 本实现是领域契约的纯实现，可脱离 UI 使用。
package final class FileConfigurationRepository: ConfigurationRepository {
    private let loader: ConfigLoader
    private let lock = NSLock()
    private var storage: AppConfig

    package var current: AppConfig {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    package init(loader: ConfigLoader = ConfigLoader()) throws {
        self.loader = loader
        storage = try loader.loadValidated()
    }

    package func reload() throws {
        let candidate = try loader.loadValidated()
        lock.lock()
        defer { lock.unlock() }
        storage = candidate
    }
}
