import Foundation

struct AppConfig: Sendable, Equatable {
    let general: GeneralConfig
    let server: ServerConfig
    let capture: CaptureConfig
    let profiles: [Profile]
    let actions: [Action]
    let tails: [TailConfig]

    func profile(id: String) -> Profile? { profiles.first { $0.id == id } }
    func action(id: String) -> Action? { actions.first { $0.id == id } }
}

struct GeneralConfig: Sendable, Equatable {
    let port: UInt16
    let theme: String
    let opacity: Double
    let alwaysOnTop: Bool
    let fontName: String
    let fontSize: Double
    let compactFontSize: Double
    let scrollbackLines: Int
    let launchAtLogin: Bool
    let toggleHotkey: String
    let allowRealProvider: Bool

    init(
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

struct CaptureConfig: Sendable, Equatable {
    let strategy: [CaptureStrategy]
    let simulatedCopyWait: Duration
    let restoreClipboard: Bool
    let maxInputChars: Int
    let excludeBundleIds: Set<String>
}

enum CaptureStrategy: String, Sendable, CaseIterable, Codable { case accessibility, simulatedCopy, clipboard }

struct Profile: Sendable, Equatable, Identifiable {
    let id: String
    let provider: ProviderKind
    let baseURL: URL
    let model: String
    let apiKeyRef: String
    let temperature: Double
    let maxTokens: Int
    let timeoutSec: Int
    let priceInput: Double?
    let priceOutput: Double?
}

enum ProviderKind: String, Sendable, CaseIterable, Codable { case openai, anthropic }

struct Action: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let hotkey: String?
    let profileId: String
    let systemPrompt: String?
    let userPrompt: String
    let input: InputSource
    let attachTo: AttachMode
    let autoShow: Bool
    let notifyOnDone: Bool
    let overrides: ParamOverrides?
}

enum InputSource: String, Sendable, CaseIterable { case selection, clipboard, prompt, none }
enum AttachMode: String, Sendable, CaseIterable { case newSession, currentSession }

struct ParamOverrides: Sendable, Equatable {
    let temperature: Double?
    let maxTokens: Int?
    let model: String?
}

struct TailConfig: Sendable, Equatable {
    let path: String
    let enabled: Bool
    let format: TailFormat
    let fromEnd: Bool
}

enum TailFormat: String, Sendable, CaseIterable { case text, jsonl }
