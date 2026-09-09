import ConsolepilotDomain
import Foundation
import TOMLDecoder

// MARK: - 默认配置资源定位（Xcode 资源阶段适配）

extension ConfigLoader {
    /// 返回随 App/CLI/测试 bundle 分发的 `DefaultConfig.toml`。
    /// 优先 Bundle.main，其次按 bundle identifier 探测 ConsolepilotInfrastructure 资源，
    /// 最后扫描已加载 bundle 作为兜底（适配 Xcode 下 host/test 不同装载形态）。
    static func bundledDefaultConfigURL() -> URL? {
        let candidates: [Bundle?] = [.main, Bundle(identifier: "com.consolepilot.ConsolepilotInfrastructure")]
        for bundle in candidates {
            if let url = bundle?.url(forResource: "DefaultConfig", withExtension: "toml") {
                return url
            }
        }
        let probe = (Bundle.allBundles + Bundle.allFrameworks).first { bundle in
            bundle.url(forResource: "DefaultConfig", withExtension: "toml") != nil
        }
        return probe?.url(forResource: "DefaultConfig", withExtension: "toml")
    }
}

package struct ConfigLoader {
    let fileManager: FileManager
    private let explicitURL: URL?

    package init(fileManager: FileManager = .default, configURL: URL? = nil) {
        self.fileManager = fileManager
        self.explicitURL = configURL
    }

    func resolveConfigURL() throws -> URL {
        if let explicitURL {
            let parent = explicitURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            return explicitURL
        }
        let home = fileManager.homeDirectoryForCurrentUser
        let primary = home.appendingPathComponent(".config/consolepilot/config.toml")
        let fallback = home.appendingPathComponent("Library/Application Support/Consolepilot/config.toml")
        if fileManager.fileExists(atPath: primary.path) { return primary }
        if fileManager.fileExists(atPath: fallback.path) { return fallback }
        try fileManager.createDirectory(at: primary.deletingLastPathComponent(), withIntermediateDirectories: true)
        let template =
            ConfigLoader.bundledDefaultConfigURL()
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        try template.write(to: primary, atomically: true, encoding: .utf8)
        return primary
    }

    func parse(_ text: String) throws -> AppConfig {
        do {
            // NSTextView.string may be an NSString-backed bridged String.
            // TOMLDecoder 0.3 force-unwraps contiguous UTF-8 storage, so
            // normalize the input before handing it to the decoder.
            guard let normalized = String(bytes: Array(text.utf8), encoding: .utf8) else {
                throw ConfigError.invalid("配置文本不是有效 UTF-8")
            }
            try Self.rejectDeprecatedActionFields(in: normalized)
            try Self.preflightNumericFields(in: normalized)
            let document = try TOMLDecoder().decode(RawConfig.self, from: normalized)
            return try document.makeConfig()
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.invalid(Self.userFacingParseError(error))
        }
    }

    private static func userFacingParseError(_ error: Error) -> String {
        let description: String
        if case DecodingError.dataCorrupted(let context) = error,
            let underlying = context.underlyingError
        {
            description = String(describing: underlying)
        } else {
            description = String(describing: error)
        }
        if let lineAndMessage = Self.extractLine(description) {
            return "第\(lineAndMessage.line)行：\(Self.localize(lineAndMessage.message))"
        }
        return "TOML 格式错误，请检查引号、逗号和括号"
    }

    /// 从 TOMLDecoder 错误描述提取行号与原始原因；返回 nil 表示无行号信息。
    private static func extractLine(_ description: String) -> (line: Int, message: String)? {
        let pattern = #"\(Line\s+(\d+)\)\s*(.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: description, range: NSRange(description.startIndex..., in: description)),
            let lineRange = Range(match.range(at: 1), in: description),
            let messageRange = Range(match.range(at: 2), in: description),
            let line = Int(description[lineRange])
        else { return nil }
        return (line, String(description[messageRange]))
    }

    /// 把 TOMLDecoder 的英文原因映射为面向用户的中文短句。
    private static func localize(_ rawMessage: String) -> String {
        if rawMessage.localizedCaseInsensitiveContains("unterminated triple-d-quote") {
            return "多行字符串三引号未闭合"
        }
        if rawMessage.localizedCaseInsensitiveContains("unterminated") {
            return "字符串未闭合"
        }
        if rawMessage.localizedCaseInsensitiveContains("syntax error") {
            return "TOML 语法错误"
        }
        if rawMessage.localizedCaseInsensitiveContains("invalid float") {
            return "数值格式无效（应为小数）"
        }
        if rawMessage.localizedCaseInsensitiveContains("invalid integer") {
            return "数值格式无效（应为整数）"
        }
        if rawMessage.localizedCaseInsensitiveContains("invalid boolean") {
            return "布尔值格式无效（应为 true 或 false）"
        }
        if rawMessage.localizedCaseInsensitiveContains("type mismatch") {
            return "字段类型与配置不符"
        }
        if rawMessage.localizedCaseInsensitiveContains("ill-formed key") {
            return "键名格式错误"
        }
        if rawMessage.localizedCaseInsensitiveContains("already exists") {
            return "键重复定义"
        }
        return "TOML 格式错误"
    }

    /// 旧 `attachTo` 字段已废弃为 `sessionMode`：任何残留值都必须迁移，
    /// 否则后台独立会话语义会被旧配置静默破坏。报错必须带行号与改法。
    private static func rejectDeprecatedActionFields(in text: String) throws {
        let pattern = #"^\s*attachTo\s*="#
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let hits = lines.enumerated().compactMap { index, rawLine -> Int? in
            let line = String(rawLine)
            guard line.range(of: pattern, options: .regularExpression) != nil else { return nil }
            return index + 1
        }
        guard !hits.isEmpty else { return }
        let listed = hits.map(String.init).joined(separator: "、")
        throw ConfigError.invalid(
            "第\(listed)行：attachTo 已废弃。请删除该行，并改为 sessionMode = \"dedicated\"（本轮仅支持 dedicated）")
    }

    /// TOMLDecoder 0.3 force-unwraps while unpacking malformed integer
    /// tokens. Catch those edits before entering the decoder so the settings
    /// editor reports an error instead of terminating the App.
    private static func preflightNumericFields(in text: String) throws {
        let integerKeys = Set([
            "port", "scrollbackLines", "maxBodyBytes", "simulatedCopyWait", "maxInputChars",
            "maxTokens", "timeoutSec",
        ])
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard integerKeys.contains(String(key)) else { continue }
            let value =
                line[line.index(after: equals)...].split(separator: "#", maxSplits: 1, omittingEmptySubsequences: true)
                .first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard Int(value) != nil else {
                throw ConfigError.invalid("配置项 \(key) 必须是整数")
            }
        }
    }

    func loadValidated() throws -> AppConfig {
        let url = try resolveConfigURL()
        let text = try String(contentsOf: url, encoding: .utf8)
        let config = try parse(text)
        let report = ConfigValidator().validate(config, sourceText: text)
        guard report.isAcceptable else {
            let details = report.errors.map { issue in
                if let line = issue.line { return "第\(line)行：\(issue.message)" }
                return issue.message
            }.joined(separator: "；")
            throw ConfigError.invalid(details)
        }
        return config
    }
}

public enum LocalServerClientConfiguration {
    public static func resolveURL() throws -> URL {
        try ConfigLoader().resolveConfigURL()
    }

    /// 返回随应用分发的初始默认配置文本（设置窗口「初始化」按钮使用），
    /// 与首次启动自动落盘的模板一致；内容不含任何密钥。
    public static func defaultConfigurationText() throws -> String {
        guard let url = ConfigLoader.bundledDefaultConfigURL() else {
            throw ConfigError.invalid("找不到随应用分发的默认配置（DefaultConfig.toml）")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static func resolveToken() throws -> String {
        let config = try ConfigLoader().loadValidated()
        return try SecretResolver().resolve(config.server.authTokenRef)
    }

    /// Validates editor text without reading secrets or changing the active
    /// configuration. Settings UI uses this before writing a file so an
    /// invalid draft can never replace the last known-good TOML on disk.
    public static func validate(_ text: String) throws {
        let loader = ConfigLoader()
        let config = try loader.parse(text)
        let report = ConfigValidator().validate(config, sourceText: text)
        guard report.isAcceptable else {
            throw ConfigError.invalid(report.errors.map(\.message).joined(separator: "；"))
        }
    }
}

private struct RawConfig: Decodable {
    let general: RawGeneral?
    let server: RawServer?
    let capture: RawCapture?
    let profiles: [RawProfile]?
    let actions: [RawAction]?

    func makeConfig() throws -> AppConfig {
        let general = general ?? RawGeneral()
        let server = server ?? RawServer()
        let capture = capture ?? RawCapture()
        return AppConfig(
            general: general.makeConfig(),
            server: server.makeConfig(),
            capture: try capture.makeConfig(),
            profiles: try (profiles ?? []).map { try $0.makeConfig() },
            actions: try (actions ?? []).map { try $0.makeConfig() }
        )
    }
}

private struct RawGeneral: Decodable {
    private enum CodingKeys: String, CodingKey {
        case port, theme, opacity, alwaysOnTop, fontName, fontSize, compactFontSize, scrollbackLines, allowRealProvider
    }
    // Decode as Int first. TOMLDecoder 0.3 has a force-unwrap bug in its
    // UInt16 decoding path, which can terminate the process even for a valid
    // value edited in the settings window.
    var port = 8765
    var theme = "tokyo-night"
    var opacity = 0.92
    var alwaysOnTop = true
    var fontName = "SF Mono"
    var fontSize = 13.0
    var compactFontSize = 11.0
    var scrollbackLines = 100_000
    var allowRealProvider = false

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        port = try values.decodeIfPresent(Int.self, forKey: .port) ?? 8765
        theme = try values.decodeIfPresent(String.self, forKey: .theme) ?? "tokyo-night"
        opacity = try values.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.92
        alwaysOnTop = try values.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? true
        fontName = try values.decodeIfPresent(String.self, forKey: .fontName) ?? "SF Mono"
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 13
        compactFontSize = try values.decodeIfPresent(Double.self, forKey: .compactFontSize) ?? 11
        scrollbackLines = try values.decodeIfPresent(Int.self, forKey: .scrollbackLines) ?? 100_000
        allowRealProvider = try values.decodeIfPresent(Bool.self, forKey: .allowRealProvider) ?? false
    }

    func makeConfig() -> GeneralConfig {
        guard (0...65_535).contains(port) else {
            return GeneralConfig(
                port: 0, theme: theme, opacity: opacity, alwaysOnTop: alwaysOnTop,
                fontName: fontName, fontSize: fontSize, compactFontSize: compactFontSize,
                scrollbackLines: scrollbackLines, allowRealProvider: allowRealProvider)
        }
        return GeneralConfig(
            port: UInt16(port), theme: theme, opacity: opacity, alwaysOnTop: alwaysOnTop,
            fontName: fontName, fontSize: fontSize, compactFontSize: compactFontSize,
            scrollbackLines: scrollbackLines, allowRealProvider: allowRealProvider)
    }
}

private struct RawServer: Decodable {
    private enum CodingKeys: String, CodingKey { case authToken, maxBodyBytes }
    // Empty disables the optional local HTTP/CLI bridge.
    var authToken = ""
    var maxBodyBytes = 1_048_576

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        authToken = try values.decodeIfPresent(String.self, forKey: .authToken) ?? ""
        maxBodyBytes = try values.decodeIfPresent(Int.self, forKey: .maxBodyBytes) ?? 1_048_576
    }

    func makeConfig() -> ServerConfig { ServerConfig(authTokenRef: authToken, maxBodyBytes: maxBodyBytes) }
}

private struct RawCapture: Decodable {
    private enum CodingKeys: String, CodingKey {
        case strategy, simulatedCopyWait, restoreClipboard, maxInputChars, excludeBundleIds
    }
    var strategy = ["accessibility", "simulatedCopy", "clipboard"]
    var simulatedCopyWait = 120
    var restoreClipboard = true
    var maxInputChars = 40_000
    var excludeBundleIds: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        strategy =
            try values.decodeIfPresent([String].self, forKey: .strategy)
            ?? ["accessibility", "simulatedCopy", "clipboard"]
        simulatedCopyWait = try values.decodeIfPresent(Int.self, forKey: .simulatedCopyWait) ?? 120
        restoreClipboard = try values.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? true
        maxInputChars = try values.decodeIfPresent(Int.self, forKey: .maxInputChars) ?? 40_000
        excludeBundleIds = try values.decodeIfPresent([String].self, forKey: .excludeBundleIds) ?? []
    }

    func makeConfig() throws -> CaptureConfig {
        let strategies = try strategy.map {
            guard let value = CaptureStrategy(rawValue: $0) else { throw ConfigError.invalid("未知捕获策略：\($0)") }
            return value
        }
        return CaptureConfig(
            strategy: strategies, simulatedCopyWait: .milliseconds(simulatedCopyWait),
            restoreClipboard: restoreClipboard, maxInputChars: maxInputChars,
            excludeBundleIds: Set(excludeBundleIds))
    }
}

private struct RawProfile: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, provider, baseURL, model, apiKey, temperature, maxTokens, timeoutSec, priceInput, priceOutput
    }
    let id: String
    let provider: String
    let baseURL: String
    let model: String
    let apiKey: String
    var temperature = 0.3
    var maxTokens = 4096
    var timeoutSec = 120
    var priceInput: Double?
    var priceOutput: Double?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        provider = try values.decode(String.self, forKey: .provider)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        model = try values.decode(String.self, forKey: .model)
        apiKey = try values.decode(String.self, forKey: .apiKey)
        temperature = try values.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.3
        maxTokens = try values.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 4096
        timeoutSec = try values.decodeIfPresent(Int.self, forKey: .timeoutSec) ?? 120
        priceInput = try values.decodeIfPresent(Double.self, forKey: .priceInput)
        priceOutput = try values.decodeIfPresent(Double.self, forKey: .priceOutput)
    }

    func makeConfig() throws -> Profile {
        guard let provider = ProviderKind(rawValue: provider), let url = URL(string: baseURL) else {
            throw ConfigError.invalid("Profile \(id) 的 provider 或 baseURL 无效")
        }
        return Profile(
            id: id, provider: provider, baseURL: url, model: model, apiKeyRef: apiKey,
            temperature: temperature, maxTokens: maxTokens, timeoutSec: timeoutSec,
            priceInput: priceInput, priceOutput: priceOutput)
    }
}

private struct RawAction: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, hotkey, profile, systemPrompt, userPrompt, input, sessionMode, timeoutSec, autoShow,
            notifyOnDone, overrides
    }
    let id: String
    let name: String
    var hotkey: String?
    let profile: String
    var systemPrompt: String?
    let userPrompt: String
    var input: String = "selection"
    var sessionMode = "dedicated"
    var timeoutSec: Int?
    var autoShow = true
    var notifyOnDone = false
    var overrides: RawOverrides?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        hotkey = try values.decodeIfPresent(String.self, forKey: .hotkey)
        profile = try values.decode(String.self, forKey: .profile)
        systemPrompt = try values.decodeIfPresent(String.self, forKey: .systemPrompt)
        userPrompt = try values.decode(String.self, forKey: .userPrompt)
        input = try values.decodeIfPresent(String.self, forKey: .input) ?? "selection"
        sessionMode = try values.decodeIfPresent(String.self, forKey: .sessionMode) ?? "dedicated"
        timeoutSec = try values.decodeIfPresent(Int.self, forKey: .timeoutSec)
        autoShow = try values.decodeIfPresent(Bool.self, forKey: .autoShow) ?? true
        notifyOnDone = try values.decodeIfPresent(Bool.self, forKey: .notifyOnDone) ?? false
        overrides = try values.decodeIfPresent(RawOverrides.self, forKey: .overrides)
    }

    func makeConfig() throws -> Action {
        guard let input = InputSource(rawValue: input) else {
            throw ConfigError.invalid("Action \(id) 的 input 无效：\(input)")
        }
        guard let sessionMode = SessionMode(rawValue: sessionMode) else {
            throw ConfigError.invalid("Action \(id) 的 sessionMode 无效：\(sessionMode)（本轮仅支持 dedicated）")
        }
        return Action(
            id: id, name: name, hotkey: hotkey, profileId: profile, systemPrompt: systemPrompt,
            userPrompt: userPrompt, input: input, sessionMode: sessionMode, timeoutSec: timeoutSec,
            autoShow: autoShow, notifyOnDone: notifyOnDone, overrides: overrides?.makeConfig())
    }
}

private struct RawOverrides: Decodable {
    var temperature: Double?
    var maxTokens: Int?
    var model: String?

    func makeConfig() -> ParamOverrides {
        ParamOverrides(temperature: temperature, maxTokens: maxTokens, model: model)
    }
}
