import AppKit
import ConsolepilotDomain
import Foundation

@MainActor
package final class ActionRunner {
    private let config: ConfigStore
    private let capture: TextCaptureService
    private let secrets: SecretResolver
    private let providerResolver: (ProviderKind) -> (any AIProvider)?
    private let coordinator: StreamCoordinator
    private let sessionStore: SessionStore
    private let captureLogStore: CaptureLogStore?
    private let localProvider: (any AIProvider)?
    private let templateEngine = TemplateEngine()
    package var onSessionCreated: (@MainActor (String) -> Void)?

    init(
        config: ConfigStore, capture: TextCaptureService, secrets: SecretResolver,
        providers: [ProviderKind: any AIProvider], coordinator: StreamCoordinator,
        sessionStore: SessionStore, captureLogStore: CaptureLogStore? = nil,
        localProvider: (any AIProvider)? = nil
    ) {
        self.config = config
        self.capture = capture
        self.secrets = secrets
        self.providerResolver = { providers[$0] }
        self.coordinator = coordinator
        self.sessionStore = sessionStore
        self.captureLogStore = captureLogStore
        self.localProvider = localProvider
    }

    package init(
        config: ConfigStore, capture: TextCaptureService, secrets: SecretResolver,
        providerResolver: @escaping (ProviderKind) -> (any AIProvider)?, coordinator: StreamCoordinator,
        sessionStore: SessionStore, captureLogStore: CaptureLogStore? = nil,
        localProvider: (any AIProvider)? = nil
    ) {
        self.config = config
        self.capture = capture
        self.secrets = secrets
        self.providerResolver = providerResolver
        self.coordinator = coordinator
        self.sessionStore = sessionStore
        self.captureLogStore = captureLogStore
        self.localProvider = localProvider
    }

    /// 执行一次 Action 并返回承载该次执行的会话 id。
    ///
    /// `sessionMode = .dedicated`：会话按 `actionId + sourceApp` 复用——最近一个
    /// 匹配且空闲（无进行中流）的会话会被续写，否则新建独立后台会话。
    @discardableResult
    package func run(actionId: String, overrideInput: String? = nil, sourcePID: pid_t? = nil) async throws -> String {
        guard let action = config.current.action(id: actionId) else {
            throw ConfigError.invalid("未知 action：\(actionId)")
        }
        guard let profile = config.current.profile(id: action.profileId) else {
            throw ConfigError.invalid("action 未找到 profile：\(action.profileId)")
        }
        let frontmostObserver = FrontmostAppObserver()
        let frontmost = frontmostObserver.snapshot()
        // Capture the source process before the first await. The Carbon
        // callback can otherwise give the App a chance to become frontmost,
        // causing synthetic ⌘C to target Consolepilot instead of the source.
        let sourcePID = sourcePID ?? frontmostObserver.processIdentifier()
        let input = try await resolveInput(action.input, overrideInput: overrideInput, targetPID: sourcePID)
        if let captured = lastCaptureResult { captureLogStore?.record(captured) }
        let context = TemplateContext(
            input: input, selection: action.input == .selection ? input : nil,
            clipboard: action.input == .clipboard ? input : nil, frontmost: frontmost,
            now: Date(), language: "")
        let prompt = templateEngine.render(action.userPrompt, context: context)
        let session =
            dedicatedSession(for: action, sourceApp: frontmost.appName)
            ?? sessionStore.create(
                channel: .action, title: action.name,
                meta: SessionMeta(
                    actionId: action.id, profileId: profile.id, provider: profile.provider,
                    model: profile.model, sourceApp: frontmost.appName))
        sessionStore.appendMessage(Message(sessionId: session.id, role: .user, content: prompt))
        onSessionCreated?(session.id)
        let provider =
            Self.isLoopback(profile.baseURL)
            ? (localProvider ?? providerResolver(profile.provider))
            : providerResolver(profile.provider)
        guard let provider else {
            throw ConfigError.invalid("未注册 provider：\(profile.provider.rawValue)")
        }
        // The app may intentionally bind configured profiles to the local
        // Mock provider for acceptance. Mock runs must never require or read a
        // remote API key; real providers still resolve secrets strictly here.
        let apiKey: String
        if provider is MockAIProvider {
            apiKey = ""
        } else {
            apiKey = try secrets.resolve(profile.apiKeyRef)
        }
        // 独立会话续写：携带该会话完整历史作为上下文，仅保留 user/assistant 轮次。
        let history = sessionStore.history(sessionId: session.id)
            .filter { $0.role == .user || $0.role == .assistant }
            .map { ChatMessage(role: $0.role, content: $0.content) }
        let request = ChatRequest(
            profile: profile, apiKey: apiKey, systemPrompt: action.systemPrompt,
            messages: history,
            overrides: mergedOverrides(for: action))
        let events = provider.stream(request)
        await coordinator.consume(events, into: session.id)
        return session.id
    }

    /// 在专用会话里复用「最近一个匹配且空闲」的会话；进行中会话不参与复用，
    /// 避免并发续写污染同一流。`sourceApp` 为 nil 时仅按 actionId 匹配。
    private func dedicatedSession(for action: Action, sourceApp: String?) -> Session? {
        sessionStore.sessions.first { candidate in
            guard candidate.channel == .action,
                candidate.actionId == action.id,
                candidate.sourceApp == sourceApp,
                !candidate.archived
            else { return false }
            return !coordinator.isStreaming(sessionId: candidate.id)
        }
    }

    /// Action 级 `timeoutSec` 覆盖 profile 默认值，与 TOML overrides 表合并。
    private func mergedOverrides(for action: Action) -> ParamOverrides? {
        let base = action.overrides
        guard action.timeoutSec != nil || base != nil else { return nil }
        return ParamOverrides(
            temperature: base?.temperature, maxTokens: base?.maxTokens, model: base?.model,
            timeoutSec: action.timeoutSec)
    }

    private var lastCaptureResult: CaptureResult?

    private static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func resolveInput(_ source: InputSource, overrideInput: String?, targetPID: pid_t?) async throws -> String {
        lastCaptureResult = nil
        if let overrideInput { return overrideInput }
        switch source {
        case .none, .prompt: return ""
        case .clipboard: return NSPasteboard.general.string(forType: .string) ?? ""
        case .selection:
            let result = try await capture.capture(selectionOnly: true, targetPID: targetPID)
            lastCaptureResult = result
            return result.text
        }
    }
}

/// `ActionRunner` 是 `ActionExecutionUseCase` 的真实实现：捕获/模板/独立会话/
/// 流执行/终态 checkpoint 全部经由此引擎，热键与 HTTP `/run` 共用。
extension ActionRunner: ActionExecutionUseCase {
    package func run(_ request: ActionExecutionRequest) async throws -> ActionExecutionResponse {
        let sessionId = try await run(
            actionId: request.actionId, overrideInput: request.overrideInput, sourcePID: nil)
        return ActionExecutionResponse(sessionId: sessionId)
    }
}
