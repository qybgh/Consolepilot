import Darwin
import Foundation

@MainActor
final class ConfigStore {
    private let loader: ConfigLoader
    private let validator: ConfigValidator
    private(set) var current: AppConfig
    private(set) var lastReport = ValidationReport(errors: [], warnings: [])
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedURL: URL?
    private var reloadWorkItem: DispatchWorkItem?
    private var observers: [(@MainActor (AppConfig) -> Void)] = []

    /// Called after a valid configuration becomes current. The callback is
    /// delivered on the main actor and can be used by UI/hotkey consumers to
    /// rebind their runtime state without rebuilding the store.
    var onChange: ((AppConfig) -> Void)?

    func addObserver(_ observer: @escaping @MainActor (AppConfig) -> Void) {
        observers.append(observer)
    }

    init(loader: ConfigLoader = ConfigLoader(), validator: ConfigValidator = ConfigValidator()) throws {
        self.loader = loader
        self.validator = validator
        let url = try loader.resolveConfigURL()
        let text = try String(contentsOf: url, encoding: .utf8)
        let config = try loader.parse(text)
        let report = validator.validate(config, sourceText: text)
        guard report.isAcceptable else {
            throw ConfigError.invalid(report.errors.map(\.message).joined(separator: "；"))
        }
        current = config
        lastReport = report
    }

    func reload() {
        do {
            let url = try loader.resolveConfigURL()
            let text = try String(contentsOf: url, encoding: .utf8)
            let candidate = try loader.parse(text)
            let report = validator.validate(candidate, sourceText: text)
            lastReport = report
            if report.isAcceptable {
                current = candidate
                onChange?(candidate)
                for observer in observers { observer(candidate) }
            }
        } catch let error as ConfigError {
            lastReport = ValidationReport(
                errors: [ConfigIssue(code: .parseFailure, line: nil, message: error.userMessage)], warnings: [])
        } catch {
            lastReport = ValidationReport(
                errors: [ConfigIssue(code: .parseFailure, line: nil, message: "无法读取配置文件")], warnings: [])
        }
    }

    func startWatching() throws {
        stopWatching()
        let url = try loader.resolveConfigURL()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { throw ConfigError.invalid("无法监听配置文件") }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let requiresRebind = source.data.contains(.rename) || source.data.contains(.delete)
            // Editors commonly emit several events while replacing a file.
            // Coalesce them and reload after the replacement has settled, then
            // re-open the descriptor when the inode changed.
            self.reloadWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.reload()
                if requiresRebind { try? self.startWatching() }
            }
            self.reloadWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40), execute: work)
        }
        source.setCancelHandler { close(descriptor) }
        watchedURL = url
        watcher = source
        source.resume()
    }

    func stopWatching() {
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        watcher?.cancel()
        watcher = nil
        watchedURL = nil
    }
}
