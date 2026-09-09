import Foundation

/// 配置领域值类型（纯规则；解析/校验/热重载实现位于 Infrastructure）。
public struct AppConfig: Sendable, Equatable {
    public let general: GeneralConfig
    public let server: ServerConfig
    public let capture: CaptureConfig
    public let profiles: [Profile]
    public let actions: [Action]
    public let tails: [TailConfig]

    public init(
        general: GeneralConfig, server: ServerConfig, capture: CaptureConfig, profiles: [Profile],
        actions: [Action], tails: [TailConfig]
    ) {
        self.general = general
        self.server = server
        self.capture = capture
        self.profiles = profiles
        self.actions = actions
        self.tails = tails
    }

    public func profile(id: String) -> Profile? { profiles.first { $0.id == id } }
    public func action(id: String) -> Action? { actions.first { $0.id == id } }
}

public struct GeneralConfig: Sendable, Equatable {
    public let port: UInt16
    public let theme: String
    public let opacity: Double
    public let alwaysOnTop: Bool
    public let fontName: String
    public let fontSize: Double
    public let compactFontSize: Double
    public let scrollbackLines: Int
    public let launchAtLogin: Bool
    public let toggleHotkey: String
    public let allowRealProvider: Bool

    public init(
        port: UInt16, theme: String, opacity: Double, alwaysOnTop: Bool, fontName: String,
        fontSize: Double, compactFontSize: Double, scrollbackLines: Int, launchAtLogin: Bool,
        toggleHotkey: String, allowRealProvider: Bool = false
    ) {
        self.port = port
        self.theme = theme
        self.opacity = opacity
        self.alwaysOnTop = alwaysOnTop
        self.fontName = fontName
        self.fontSize = fontSize
        self.compactFontSize = compactFontSize
        self.scrollbackLines = scrollbackLines
        self.launchAtLogin = launchAtLogin
        self.toggleHotkey = toggleHotkey
        self.allowRealProvider = allowRealProvider
    }
}

public struct ServerConfig: Sendable, Equatable {
    public let authTokenRef: String
    public let maxBodyBytes: Int

    public init(authTokenRef: String, maxBodyBytes: Int) {
        self.authTokenRef = authTokenRef
        self.maxBodyBytes = maxBodyBytes
    }
}

public struct CaptureConfig: Sendable, Equatable {
    public let strategy: [CaptureStrategy]
    public let simulatedCopyWait: Duration
    public let restoreClipboard: Bool
    public let maxInputChars: Int
    public let excludeBundleIds: Set<String>

    public init(
        strategy: [CaptureStrategy], simulatedCopyWait: Duration, restoreClipboard: Bool,
        maxInputChars: Int, excludeBundleIds: Set<String>
    ) {
        self.strategy = strategy
        self.simulatedCopyWait = simulatedCopyWait
        self.restoreClipboard = restoreClipboard
        self.maxInputChars = maxInputChars
        self.excludeBundleIds = excludeBundleIds
    }
}

public struct Profile: Sendable, Equatable, Identifiable {
    public let id: String
    public let provider: ProviderKind
    public let baseURL: URL
    public let model: String
    public let apiKeyRef: String
    public let temperature: Double
    public let maxTokens: Int
    public let timeoutSec: Int
    public let priceInput: Double?
    public let priceOutput: Double?

    public init(
        id: String, provider: ProviderKind, baseURL: URL, model: String, apiKeyRef: String,
        temperature: Double, maxTokens: Int, timeoutSec: Int, priceInput: Double?, priceOutput: Double?
    ) {
        self.id = id
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.apiKeyRef = apiKeyRef
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeoutSec = timeoutSec
        self.priceInput = priceInput
        self.priceOutput = priceOutput
    }
}

public struct Action: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let hotkey: String?
    public let profileId: String
    public let systemPrompt: String?
    public let userPrompt: String
    public let input: InputSource
    public let attachTo: AttachMode
    public let autoShow: Bool
    public let notifyOnDone: Bool
    public let overrides: ParamOverrides?

    public init(
        id: String, name: String, hotkey: String?, profileId: String, systemPrompt: String?,
        userPrompt: String, input: InputSource, attachTo: AttachMode, autoShow: Bool,
        notifyOnDone: Bool, overrides: ParamOverrides?
    ) {
        self.id = id
        self.name = name
        self.hotkey = hotkey
        self.profileId = profileId
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.input = input
        self.attachTo = attachTo
        self.autoShow = autoShow
        self.notifyOnDone = notifyOnDone
        self.overrides = overrides
    }
}

public enum InputSource: String, Sendable, CaseIterable { case selection, clipboard, prompt, none }
public enum AttachMode: String, Sendable, CaseIterable { case newSession, currentSession }

public struct ParamOverrides: Sendable, Equatable {
    public let temperature: Double?
    public let maxTokens: Int?
    public let model: String?

    public init(temperature: Double?, maxTokens: Int?, model: String?) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.model = model
    }
}

public struct TailConfig: Sendable, Equatable {
    public let path: String
    public let enabled: Bool
    public let format: TailFormat
    public let fromEnd: Bool

    public init(path: String, enabled: Bool, format: TailFormat, fromEnd: Bool) {
        self.path = path
        self.enabled = enabled
        self.format = format
        self.fromEnd = fromEnd
    }
}

public enum TailFormat: String, Sendable, CaseIterable { case text, jsonl }
