import AppKit
import ConsolepilotDomain
import GRDB
import XCTest

@testable import ConsolepilotInfrastructure

final class InfrastructureTests: XCTestCase {
    private func validConfig() -> AppConfig {
        AppConfig(
            general: GeneralConfig(
                port: 8765, theme: "tokyo-night", opacity: 0.92, alwaysOnTop: true,
                fontName: "SF Mono", fontSize: 13, compactFontSize: 11, scrollbackLines: 100_000),
            server: ServerConfig(authTokenRef: "${env:CONSOLEPILOT_TEST_SECRET}", maxBodyBytes: 1_048_576),
            capture: CaptureConfig(
                strategy: [.clipboard], simulatedCopyWait: .milliseconds(120), restoreClipboard: true,
                maxInputChars: 40_000, excludeBundleIds: []),
            profiles: [
                Profile(
                    id: "local", provider: .openai, baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
                    model: "test", apiKeyRef: "", temperature: 0.3, maxTokens: 100, timeoutSec: 30,
                    priceInput: nil, priceOutput: nil)
            ],
            actions: [
                Action(
                    id: "ask", name: "Ask", hotkey: nil, profileId: "local", systemPrompt: nil,
                    userPrompt: "{{input}}", input: .prompt, sessionMode: .dedicated, timeoutSec: nil, autoShow: true,
                    notifyOnDone: false, overrides: nil)
            ])
    }

    private func report(for config: AppConfig) -> ValidationReport {
        ConfigValidator().validate(config, sourceText: "")
    }

    private func assertError(
        _ code: ConfigErrorCode, in config: AppConfig, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            report(for: config).errors.contains { $0.code == code }, "missing \(code)", file: file, line: line)
    }

    func testConfigValidatorCoversCoreValueAndReferenceRules() {
        let base = validConfig()
        let profile = Profile(
            id: "local", provider: .openai, baseURL: URL(string: "ftp://example.com")!, model: "test",
            apiKeyRef: "plain-secret", temperature: 3, maxTokens: 0, timeoutSec: 0, priceInput: nil, priceOutput: nil)
        let general = GeneralConfig(
            port: 80, theme: "unknown", opacity: 0.5, alwaysOnTop: true, fontName: "", fontSize: 13,
            compactFontSize: 11, scrollbackLines: 1)
        let capture = CaptureConfig(
            strategy: [], simulatedCopyWait: .zero, restoreClipboard: true, maxInputChars: 1, excludeBundleIds: [])
        let badHotkeyAction = Action(
            id: "bad-hotkey", name: "Bad", hotkey: "bad", profileId: "local", systemPrompt: nil,
            userPrompt: "{{input}}", input: .prompt, sessionMode: .dedicated, timeoutSec: nil,
            autoShow: true, notifyOnDone: false, overrides: nil)
        let config = AppConfig(
            general: general, server: ServerConfig(authTokenRef: "plain", maxBodyBytes: 1), capture: capture,
            profiles: [profile], actions: base.actions + [badHotkeyAction])
        assertError(.invalidBaseURL, in: config)
        assertError(.valueOutOfRange, in: config)
        assertError(.invalidHotkeySyntax, in: config)
        assertError(.unknownTheme, in: config)
        assertError(.invalidStrategy, in: config)
        assertError(.invalidServerAuth, in: config)
        let remote = Profile(
            id: "remote", provider: .openai, baseURL: URL(string: "https://example.com/v1")!, model: "test",
            apiKeyRef: "plain-secret", temperature: 0.3, maxTokens: 100, timeoutSec: 30, priceInput: nil,
            priceOutput: nil)
        let remoteConfig = AppConfig(
            general: validConfig().general, server: validConfig().server, capture: validConfig().capture,
            profiles: [remote], actions: [])
        assertError(.unresolvableSecret, in: remoteConfig)
    }

    func testConfigValidatorDetectsDuplicatesUnknownReferencesAndTemplateErrors() {
        let base = validConfig()
        let actions = [
            Action(
                id: "ask", name: "Ask", hotkey: "cmd+k", profileId: "missing", systemPrompt: "{{unknown}}",
                userPrompt: "{{input}}", input: .prompt, sessionMode: .dedicated, timeoutSec: nil, autoShow: true,
                notifyOnDone: false, overrides: nil),
            Action(
                id: "ask", name: "Ask 2", hotkey: "cmd+k", profileId: "local", systemPrompt: nil,
                userPrompt: "{{input}}", input: .prompt, sessionMode: .dedicated, timeoutSec: nil, autoShow: true,
                notifyOnDone: false, overrides: nil),
        ]
        let config = AppConfig(
            general: base.general, server: base.server, capture: base.capture,
            profiles: [base.profiles[0], base.profiles[0]], actions: actions)
        let codes = Set(report(for: config).errors.map(\.code))
        XCTAssertTrue(codes.contains(.duplicateProfileId))
        XCTAssertTrue(codes.contains(.duplicateActionId))
        XCTAssertTrue(codes.contains(.unknownProfileRef))
        XCTAssertTrue(codes.contains(.duplicateHotkey))
        XCTAssertTrue(codes.contains(.unknownPlaceholder))
    }

    func testConfigValidatorWarnsWhenAccessibilityIsUnavailable() {
        let base = validConfig()
        let action = Action(
            id: "ask", name: "Ask", hotkey: nil, profileId: "local", systemPrompt: nil,
            userPrompt: "{{selection}}", input: .selection, sessionMode: .dedicated, timeoutSec: nil, autoShow: true,
            notifyOnDone: false, overrides: nil)
        let config = AppConfig(
            general: base.general, server: base.server, capture: base.capture, profiles: base.profiles,
            actions: [action])
        let report = ConfigValidator(hasAccessibility: false).validate(config, sourceText: "")
        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertTrue(report.warnings.contains { $0.code == .warnNoAXPermission })
    }

    func testConfigLoaderRejectsUnknownEnumValues() {
        XCTAssertThrowsError(
            try ConfigLoader().parse(
                """
                [[profiles]]
                id = "x"
                provider = "unknown"
                baseURL = "http://127.0.0.1"
                model = "x"
                apiKey = ""
                """))
    }

    func testConfigLoaderParsesNativeIntegerAfterEditorStyleRoundTrip() throws {
        let source = """
            [general]
            port = 8766
            scrollbackLines = 100000
            [server]
            authToken = "${env:CONSOLEPILOT_TEST_SECRET}"
            [capture]
            strategy = ["clipboard"]
            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "mock"
            apiKey = ""
            """
        let bridged = NSString(string: source) as String
        let config = try ConfigLoader().parse(bridged)
        XCTAssertEqual(config.general.port, 8766)
    }

    func testConfigLoaderRejectsMalformedIntegerBeforeTOMLDecoder() {
        XCTAssertThrowsError(
            try ConfigLoader().parse(
                """
                [general]
                port =
                """)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("必须是整数"))
        }
    }

    func testConfigLoaderReportsConciseMultilineStringError() {
        let text = """
            [[actions]]
            id = "demo"
            name = "Demo"
            profile = "local"
            systemPrompt = \"\"\"
            未闭合内容
            """
        do {
            _ = try ConfigLoader().parse(text)
            XCTFail("expected malformed TOML")
        } catch let error as ConfigError {
            XCTAssertTrue(error.userMessage.contains("第 5 行") || error.userMessage.contains("第5行"))
            XCTAssertTrue(error.userMessage.contains("三引号未闭合"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testTemplateEngineSupportsPlanPlaceholdersAndEnvironment() {
        setenv("CONSOLEPILOT_TEMPLATE_ENV", "env-value", 1)
        let context = TemplateContext(
            input: "input", selection: "selection", clipboard: "clipboard",
            frontmost: FrontmostInfo(appName: "Notes", bundleId: "com.apple.Notes", windowTitle: "Doc"),
            now: Date(timeIntervalSince1970: 0), language: "zh-Hans")
        let rendered = TemplateEngine().render(
            "{{app}} {{appBundleId}} {{bundleId}} {{lang}} {{language}} {{datetime}} {{env:CONSOLEPILOT_TEMPLATE_ENV}}",
            context: context)
        XCTAssertTrue(rendered.contains("Notes com.apple.Notes com.apple.Notes zh-Hans zh-Hans"))
        XCTAssertTrue(rendered.contains("env-value"))
    }

    func testConfigValidatorRejectsMissingEnvironmentPlaceholder() {
        let base = validConfig()
        let action = Action(
            id: "ask", name: "Ask", hotkey: nil, profileId: "local", systemPrompt: nil,
            userPrompt: "{{env:CONSOLEPILOT_MISSING_TEMPLATE_ENV}}", input: .prompt,
            sessionMode: .dedicated, timeoutSec: nil, autoShow: true, notifyOnDone: false, overrides: nil)
        let config = AppConfig(
            general: base.general, server: base.server, capture: base.capture,
            profiles: base.profiles, actions: [action])
        XCTAssertTrue(report(for: config).errors.contains { $0.code == .unresolvableSecret })
    }

    func testTransportErrorRetryability() {
        XCTAssertTrue(TransportError.serverError(status: 503).isRetryable)
        XCTAssertFalse(TransportError.serverError(status: 400).isRetryable)
    }

    func testUserFacingErrorMessagesAreStableAndActionable() {
        XCTAssertTrue(CaptureError.noPermission.userMessage.contains("辅助功能权限"))
        XCTAssertTrue(CaptureError.secureInputActive.userMessage.contains("安全输入"))
        XCTAssertTrue(CaptureError.excludedApp("com.example.app").userMessage.contains("com.example.app"))
        XCTAssertTrue(TransportError.connectionLost.userMessage.contains("连接中断"))
        XCTAssertTrue(TransportError.unauthorized.userMessage.contains("API Key"))
        XCTAssertEqual(ConfigError.invalid("端口无效").userMessage, "配置无效：端口无效")
    }

    func testConfigLoaderParsesMinimalConfiguration() throws {
        let text = """
            [general]
            port = 8765
            theme = "tokyo-night"
            opacity = 0.92
            alwaysOnTop = true
            fontName = "SF Mono"
            fontSize = 13
            compactFontSize = 11
            scrollbackLines = 100000

            [server]
            authToken = "${env:TEST_TOKEN}"
            maxBodyBytes = 1048576

            [capture]
            strategy = ["clipboard"]
            simulatedCopyWait = 120
            restoreClipboard = true
            maxInputChars = 40000
            excludeBundleIds = []

            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "test"
            apiKey = ""

            [[actions]]
            id = "ask"
            name = "Ask"
            profile = "local"
            userPrompt = "{{input}}"
            input = "prompt"
            sessionMode = "dedicated"
            timeoutSec = 45
            autoShow = true
            notifyOnDone = false
            """

        let config = try ConfigLoader().parse(text)
        XCTAssertEqual(config.profiles.first?.id, "local")
        XCTAssertEqual(config.actions.first?.sessionMode, .dedicated)
        XCTAssertEqual(config.actions.first?.timeoutSec, 45)
        XCTAssertEqual(config.capture.strategy, [.clipboard])
    }

    func testDefaultConfigurationPassesCoreValidation() throws {
        let url = ConfigLoader.bundledDefaultConfigURL()
        let text = try XCTUnwrap(url).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let config = try ConfigLoader().parse(try XCTUnwrap(text))
        let report = ConfigValidator().validate(config, sourceText: try XCTUnwrap(text))
        XCTAssertTrue(report.errors.isEmpty, report.errors.map(\.message).joined(separator: "\n"))
    }

    func testDefaultConfigurationTextMatchesBundledTemplateAndValidates() throws {
        // 设置窗口「初始化」按钮依赖该公开入口：返回内容必须与随应用分发的
        // 默认模板一致、非空，且能通过完整校验（保存后可直接热重载生效）。
        let text = try LocalServerClientConfiguration.defaultConfigurationText()
        let bundledURL = try XCTUnwrap(ConfigLoader.bundledDefaultConfigURL())
        XCTAssertEqual(text, try String(contentsOf: bundledURL, encoding: .utf8))
        XCTAssertFalse(text.isEmpty)
        XCTAssertNoThrow(try LocalServerClientConfiguration.validate(text))
    }

    func testConfigLoaderParsesContextBudgetFieldsAndDefaults() throws {
        let text = """
            [general]
            port = 8765
            [server]
            authToken = ""
            [capture]
            strategy = ["clipboard"]
            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "test"
            apiKey = ""
            maxContextBytes = 2048
            [[actions]]
            id = "ask"
            name = "Ask"
            profile = "local"
            userPrompt = "{{input}}"
            input = "prompt"
            maxContextBytes = 4096
            """
        let config = try ConfigLoader().parse(text)
        XCTAssertEqual(config.profiles.first?.maxContextBytes, 2048)
        XCTAssertEqual(config.actions.first?.maxContextBytes, 4096)

        let defaultsText = """
            [general]
            port = 8765
            [server]
            authToken = ""
            [capture]
            strategy = ["clipboard"]
            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "test"
            apiKey = ""
            [[actions]]
            id = "ask"
            name = "Ask"
            profile = "local"
            userPrompt = "{{input}}"
            input = "prompt"
            """
        let defaults = try ConfigLoader().parse(defaultsText)
        XCTAssertEqual(defaults.profiles.first?.maxContextBytes, 131_072)
        XCTAssertNil(defaults.actions.first?.maxContextBytes)
    }

    func testConfigValidatorRejectsTinyContextBudgets() {
        let base = validConfig()
        let tinyProfile = Profile(
            id: "local", provider: .openai, baseURL: URL(string: "http://127.0.0.1:11434/v1")!,
            model: "test", apiKeyRef: "", temperature: 0.3, maxTokens: 100, timeoutSec: 30,
            maxContextBytes: 512, priceInput: nil, priceOutput: nil)
        let profileConfig = AppConfig(
            general: base.general, server: base.server, capture: base.capture,
            profiles: [tinyProfile], actions: [])
        assertError(.valueOutOfRange, in: profileConfig)

        let tinyAction = Action(
            id: "ask", name: "Ask", hotkey: nil, profileId: "local", systemPrompt: nil,
            userPrompt: "{{input}}", input: .prompt, sessionMode: .dedicated, timeoutSec: nil,
            maxContextBytes: 0, autoShow: true, notifyOnDone: false, overrides: nil)
        let actionConfig = AppConfig(
            general: base.general, server: base.server, capture: base.capture,
            profiles: base.profiles, actions: [tinyAction])
        assertError(.valueOutOfRange, in: actionConfig)
    }

    @MainActor
    func testConfigStoreRejectsInvalidReloadAndKeepsPreviousConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotConfig-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        let valid = """
            [general]
            port = 8765
            theme = "tokyo-night"
            opacity = 0.92
            alwaysOnTop = true
            fontName = "SF Mono"
            fontSize = 13
            compactFontSize = 11
            scrollbackLines = 100000
            [server]
            authToken = "${env:TEST_TOKEN}"
            maxBodyBytes = 1048576
            [capture]
            strategy = ["clipboard"]
            maxInputChars = 40000
            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "test"
            apiKey = ""
            """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try valid.write(to: url, atomically: true, encoding: .utf8)
        let store = try ConfigStore(loader: ConfigLoader(configURL: url))
        let original = store.current

        try valid.replacingOccurrences(of: "port = 8765", with: "port = 80")
            .write(to: url, atomically: true, encoding: .utf8)
        store.reload()

        XCTAssertEqual(store.current, original)
        XCTAssertEqual(store.lastReport.errors.first?.code, .valueOutOfRange)
    }

    @MainActor
    func testConfigStoreNotifiesOnlyAfterValidReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotConfigChange-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let template = """
            [general]
            port = %d
            theme = "tokyo-night"
            """
        try String(format: template, 8765).write(to: url, atomically: true, encoding: .utf8)
        let store = try ConfigStore(loader: ConfigLoader(configURL: url))
        var changes: [UInt16] = []
        store.onChange = { changes.append($0.general.port) }

        try String(format: template, 80).write(to: url, atomically: true, encoding: .utf8)
        store.reload()
        XCTAssertTrue(changes.isEmpty)

        try String(format: template, 8766).write(to: url, atomically: true, encoding: .utf8)
        store.reload()
        XCTAssertEqual(changes, [8766])
        XCTAssertEqual(store.current.general.port, 8766)
    }

    @MainActor
    func testRuntimeBindingsRebuildProvidersAndHotkeysOnlyForValidConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotRuntime-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let template = """
            [general]
            port = %d
            theme = "tokyo-night"
            [server]
            authToken = "${env:CONSOLEPILOT_TEST_SECRET}"
            [capture]
            strategy = ["clipboard"]
            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "mock"
            apiKey = ""
            [[actions]]
            id = "ask"
            name = "Ask"
            profile = "local"
            userPrompt = "{{input}}"
            hotkey = "%@"
            input = "prompt"
            sessionMode = "dedicated"
            """
        try String(format: template, 8765, "cmd+k").write(to: url, atomically: true, encoding: .utf8)
        let store = try ConfigStore(loader: ConfigLoader(configURL: url))
        let bindings = RuntimeBindings(configStore: store) { _ in MockAIProvider(delay: .zero) }
        var triggered: String?
        bindings.onAction = { triggered = $0 }
        XCTAssertNotNil(bindings.provider(for: .openai))
        XCTAssertEqual(bindings.hotkeys.registeredNames, ["ask"])
        bindings.hotkeys.trigger(name: "ask")
        XCTAssertEqual(triggered, "ask")

        try String(format: template, 80, "").write(to: url, atomically: true, encoding: .utf8)
        store.reload()
        XCTAssertEqual(bindings.hotkeys.registeredNames, ["ask"])
        XCTAssertEqual(store.current.general.port, 8765, "invalid reload must not replace runtime config")

        try String(format: template, 8766, "cmd+shift+k").write(to: url, atomically: true, encoding: .utf8)
        store.reload()
        XCTAssertEqual(bindings.hotkeys.registeredNames, ["ask"])
        XCTAssertEqual(store.current.general.port, 8766)
    }

    @MainActor
    func testConfigStoreSurvivesTwentyAtomicReplacements() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotConfigWatch-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let template = """
            [general]
            port = %d
            theme = "tokyo-night"
            """
        try String(format: template, 8765).write(to: url, atomically: true, encoding: .utf8)
        let store = try ConfigStore(loader: ConfigLoader(configURL: url))
        var changes = 0
        store.onChange = { _ in changes += 1 }
        try store.startWatching()
        defer { store.stopWatching() }

        for index in 0..<20 {
            let replacement = URL(fileURLWithPath: url.path + ".tmp")
            try String(format: template, 8765 + index).write(
                to: replacement, atomically: true, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: replacement)
            // Allow the coalesced filesystem event to reload before the next
            // inode replacement, matching editor save behavior.
            try await Task.sleep(for: .milliseconds(80))
        }

        XCTAssertEqual(store.current.general.port, 8784)
        XCTAssertGreaterThanOrEqual(changes, 1)
        XCTAssertTrue(store.lastReport.errors.isEmpty)
    }

    func testSecretResolverReadsEnvironmentReference() throws {
        setenv("CONSOLEPILOT_TEST_SECRET", "test-value", 1)
        let resolver = SecretResolver()
        XCTAssertEqual(try resolver.resolve("${env:CONSOLEPILOT_TEST_SECRET}"), "test-value")
        XCTAssertFalse(resolver.canResolve("${env:CONSOLEPILOT_MISSING_SECRET}"))
    }

    func testKeychainStoreRoundTripsAndDeletesOnlyTestAccount() throws {
        let keychain = KeychainStore()
        let account = "test-\(UUID().uuidString)"
        defer { try? keychain.delete(name: account) }

        XCTAssertFalse(keychain.exists(name: account))
        try keychain.write(name: account, value: "secret-value")
        XCTAssertTrue(keychain.exists(name: account))
        XCTAssertEqual(try keychain.read(name: account), "secret-value")

        try keychain.write(name: account, value: "updated-value")
        XCTAssertEqual(try keychain.read(name: account), "updated-value")
        try keychain.delete(name: account)
        XCTAssertFalse(keychain.exists(name: account))
    }

    func testSecretResolverReportsMissingKeychainReference() {
        let resolver = SecretResolver()
        XCTAssertEqual(
            resolver.canResolve("${keychain:missing-\(UUID().uuidString)}"), false)
    }

    func testRemovedLaunchAtLoginAndToggleHotkeyFieldsAreToleratedAsUnknownKeys() throws {
        // launchAtLogin/toggleHotkey 已从 schema 删除：旧配置残留按键应被忽略而不报错。
        let text = """
            [general]
            port = 8765
            launchAtLogin = true
            toggleHotkey = "cmd+shift+space"
            theme = "tokyo-night"
            """
        let config = try ConfigLoader().parse(text)
        XCTAssertEqual(config.general.port, 8765)
        XCTAssertTrue(report(for: config).errors.isEmpty)
    }

    func testConfigLoaderRejectsDeprecatedAttachToWithLineAndFixHint() {
        let text = """
            [[actions]]
            id = "summarize"
            name = "总结"
            profile = "local"
            userPrompt = "{{input}}"
            input = "selection"
            attachTo = "newSession"
            """
        XCTAssertThrowsError(try ConfigLoader().parse(text)) { error in
            let message = (error as? ConfigError)?.userMessage ?? String(describing: error)
            XCTAssertTrue(message.contains("第7行"), message)
            XCTAssertTrue(message.contains("attachTo 已废弃"), message)
            XCTAssertTrue(message.contains("sessionMode = \"dedicated\""), message)
        }
    }

    func testConfigLoaderRejectsUnknownSessionModeValue() {
        let text = """
            [[actions]]
            id = "summarize"
            name = "总结"
            profile = "local"
            userPrompt = "{{input}}"
            input = "selection"
            sessionMode = "currentSession"
            """
        XCTAssertThrowsError(try ConfigLoader().parse(text)) { error in
            let message = (error as? ConfigError)?.userMessage ?? String(describing: error)
            XCTAssertTrue(message.contains("sessionMode 无效"), message)
            XCTAssertTrue(message.contains("dedicated"), message)
        }
    }

    func testConfigValidatorRejectsNonFiniteNumbers() {
        let base = validConfig()
        let nanOpacity = AppConfig(
            general: GeneralConfig(
                port: base.general.port, theme: base.general.theme, opacity: .nan, alwaysOnTop: true,
                fontName: "SF Mono", fontSize: 13, compactFontSize: 11,
                scrollbackLines: base.general.scrollbackLines),
            server: base.server, capture: base.capture, profiles: base.profiles, actions: base.actions)
        assertError(.valueOutOfRange, in: nanOpacity)

        let infiniteProfile = AppConfig(
            general: base.general, server: base.server, capture: base.capture,
            profiles: [
                Profile(
                    id: "local", provider: .openai, baseURL: URL(string: "http://127.0.0.1")!,
                    model: "test", apiKeyRef: "", temperature: .infinity, maxTokens: 100, timeoutSec: 30,
                    priceInput: nil, priceOutput: nil)
            ],
            actions: base.actions)
        assertError(.valueOutOfRange, in: infiniteProfile)

        let nanOverride = AppConfig(
            general: base.general, server: base.server, capture: base.capture, profiles: base.profiles,
            actions: [
                Action(
                    id: "ask", name: "Ask", hotkey: nil, profileId: "local", systemPrompt: nil,
                    userPrompt: "{{input}}", input: .prompt, sessionMode: .dedicated, timeoutSec: nil,
                    autoShow: true, notifyOnDone: false,
                    overrides: ParamOverrides(temperature: .nan, maxTokens: nil, model: nil))
            ])
        assertError(.valueOutOfRange, in: nanOverride)
    }

    func testConfigValidatorRejectsNonPositiveActionTimeout() {
        let base = validConfig()
        let action = Action(
            id: "ask", name: "Ask", hotkey: nil, profileId: "local", systemPrompt: nil,
            userPrompt: "{{input}}", input: .prompt, sessionMode: .dedicated, timeoutSec: 0,
            autoShow: true, notifyOnDone: false, overrides: nil)
        let config = AppConfig(
            general: base.general, server: base.server, capture: base.capture,
            profiles: base.profiles, actions: [action])
        assertError(.valueOutOfRange, in: config)
    }

    func testConfigLoaderParseErrorReportsLineForNonSyntaxTOMLFailure() {
        let text = """
            [general]
            theme = "tokyo-night"
            theme = "nord"
            """
        XCTAssertThrowsError(try ConfigLoader().parse(text)) { error in
            let message = (error as? ConfigError)?.userMessage ?? String(describing: error)
            XCTAssertTrue(message.contains("第3行"), message)
            // TOMLDecoder 对同表重复键按行号报错（badKey/keyExists 形态均可）。
            XCTAssertTrue(
                message.contains("键名格式错误") || message.contains("键重复定义"), message)
        }
    }

    func testConfigValidatorChecksActionOverrides() {
        let base = validConfig()
        let action = Action(
            id: "ask", name: "Ask", hotkey: nil, profileId: "local", systemPrompt: nil,
            userPrompt: "{{input}}", input: .prompt, sessionMode: .dedicated, timeoutSec: nil, autoShow: true,
            notifyOnDone: false,
            overrides: ParamOverrides(temperature: 2.5, maxTokens: 0, model: "  "))
        let config = AppConfig(
            general: base.general, server: base.server, capture: base.capture,
            profiles: base.profiles, actions: [action])
        assertError(.valueOutOfRange, in: config)
    }

    @MainActor
    func testActionRunnerBuildsPromptAndPersistsMockAssistantReply() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotAction-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configText = """
            [general]
            port = 8765
            theme = "tokyo-night"
            opacity = 0.92
            scrollbackLines = 100000
            [server]
            authToken = "${env:CONSOLEPILOT_TEST_SECRET}"
            [capture]
            strategy = ["clipboard"]
            maxInputChars = 40000
            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "mock"
            apiKey = ""
            [[actions]]
            id = "summarize"
            name = "Summarize"
            profile = "local"
            userPrompt = "请总结：{{input}}"
            input = "prompt"
            sessionMode = "dedicated"
            """
        try configText.write(to: url, atomically: true, encoding: .utf8)
        let config = try ConfigStore(loader: ConfigLoader(configURL: url))
        let database = try AppDatabase(path: directory.appendingPathComponent("db.sqlite").path)
        let sessions = try SessionStore(database: database)
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: UsageStore(database: database))
        let runner = ActionRunner(
            config: config, capture: TextCaptureService(config: config.current.capture),
            secrets: SecretResolver(), providers: [.openai: MockAIProvider(delay: .zero)],
            coordinator: coordinator, sessionStore: sessions)
        try await runner.run(actionId: "summarize", overrideInput: "测试输入")
        XCTAssertEqual(sessions.sessions.count, 1)
        XCTAssertEqual(sessions.messages.first?.content, "请总结：测试输入")
        XCTAssertTrue(sessions.messages.contains { $0.role == .assistant && $0.content.contains("Consolepilot") })
    }

    @MainActor
    func testActionRunnerTrimsHistoryToActionContextBudget() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotActionTrim-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configText = """
            [general]
            port = 8765
            theme = "tokyo-night"
            opacity = 0.92
            scrollbackLines = 100000
            [server]
            authToken = "${env:CONSOLEPILOT_TEST_SECRET}"
            [capture]
            strategy = ["clipboard"]
            maxInputChars = 40000
            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "mock"
            apiKey = "${env:CONSOLEPILOT_TEST_SECRET}"
            maxContextBytes = 131072
            [[actions]]
            id = "summarize"
            name = "Summarize"
            profile = "local"
            userPrompt = "请总结：{{input}}"
            input = "prompt"
            sessionMode = "dedicated"
            maxContextBytes = 1024
            """
        try configText.write(to: url, atomically: true, encoding: .utf8)
        let config = try ConfigStore(loader: ConfigLoader(configURL: url))
        let database = try AppDatabase(path: directory.appendingPathComponent("db.sqlite").path)
        let sessions = try SessionStore(database: database)
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: UsageStore(database: database))
        let recorder = RecordingProvider()
        let runner = ActionRunner(
            config: config, capture: TextCaptureService(config: config.current.capture),
            secrets: SecretResolver(), providers: [.openai: recorder],
            coordinator: coordinator, sessionStore: sessions)
        setenv("CONSOLEPILOT_TEST_SECRET", "test-value", 1)
        defer { unsetenv("CONSOLEPILOT_TEST_SECRET") }
        // 第一次触发写入远超 Action 级预算的历史；第二次触发应只发送裁剪后的上下文。
        let bulky = String(repeating: "中文内容", count: 1000)
        try await runner.run(actionId: "summarize", overrideInput: bulky)
        try await runner.run(actionId: "summarize", overrideInput: "第二次")
        let requests = recorder.requests
        XCTAssertGreaterThanOrEqual(requests.count, 2)
        let second = requests[requests.count - 1]
        let bytes =
            (second.systemPrompt?.utf8.count ?? 0)
            + second.messages.reduce(0) { $0 + $1.content.utf8.count }
        XCTAssertLessThanOrEqual(bytes, 1024)
        XCTAssertFalse(second.messages.isEmpty)
        // 最新一轮的 prompt 必须被保留（只裁剪更早的历史）。
        XCTAssertEqual(second.messages.last?.content, "请总结：第二次")
    }

    @MainActor
    func testActionRunnerUsesSelectedTextTemplateAndCreatesSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotSelectionAction-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configText = """
            [general]
            port = 8765
            theme = "tokyo-night"
            opacity = 0.92
            scrollbackLines = 100000
            [server]
            authToken = "${env:CONSOLEPILOT_TEST_SECRET}"
            [capture]
            strategy = ["accessibility"]
            maxInputChars = 40000
            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "mock"
            apiKey = ""
            [[actions]]
            id = "summarize"
            name = "总结选中文本"
            profile = "local"
            userPrompt = "请总结以下选中内容：{{selection}}"
            input = "selection"
            sessionMode = "dedicated"
            """
        try configText.write(to: url, atomically: true, encoding: .utf8)
        let config = try ConfigStore(loader: ConfigLoader(configURL: url))
        let database = try AppDatabase(path: directory.appendingPathComponent("db.sqlite").path)
        let sessions = try SessionStore(database: database)
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: UsageStore(database: database))
        let capture = TextCaptureService(
            config: config.current.capture,
            frontmost: FrontmostAppObserver(),
            accessibility: { "选中的中文文本 🚀" },
            clipboard: { nil },
            simulatedCopy: { "" },
            secureInput: { false })
        var createdID: String?
        let runner = ActionRunner(
            config: config, capture: capture, secrets: SecretResolver(),
            providers: [.openai: MockAIProvider(delay: .zero)], coordinator: coordinator,
            sessionStore: sessions)
        runner.onSessionCreated = { createdID = $0 }
        try await runner.run(actionId: "summarize")
        XCTAssertNotNil(createdID)
        XCTAssertEqual(sessions.sessions.count, 1)
        XCTAssertEqual(sessions.messages.first?.content, "请总结以下选中内容：选中的中文文本 🚀")
        XCTAssertTrue(sessions.messages.contains { $0.role == .assistant })
    }

    @MainActor
    func testActionRunnerReusesDedicatedSessionByActionAndSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotDedicatedAction-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configText = """
            [general]
            port = 8765
            theme = "tokyo-night"
            opacity = 0.92
            scrollbackLines = 100000
            [server]
            authToken = "${env:CONSOLEPILOT_TEST_SECRET}"
            [capture]
            strategy = ["clipboard"]
            maxInputChars = 40000
            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "mock"
            apiKey = ""
            [[actions]]
            id = "summarize"
            name = "Summarize"
            profile = "local"
            userPrompt = "请总结：{{input}}"
            input = "prompt"
            sessionMode = "dedicated"
            timeoutSec = 30
            """
        try configText.write(to: url, atomically: true, encoding: .utf8)
        let config = try ConfigStore(loader: ConfigLoader(configURL: url))
        let database = try AppDatabase(path: directory.appendingPathComponent("db.sqlite").path)
        let sessions = try SessionStore(database: database)
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: UsageStore(database: database))
        let runner = ActionRunner(
            config: config, capture: TextCaptureService(config: config.current.capture),
            secrets: SecretResolver(), providers: [.openai: MockAIProvider(delay: .zero)],
            coordinator: coordinator, sessionStore: sessions)

        let first = try await runner.run(actionId: "summarize", overrideInput: "第一轮")
        let second = try await runner.run(actionId: "summarize", overrideInput: "第二轮")

        XCTAssertEqual(first, second, "dedicated 会话应按 actionId+sourceApp 复用")
        XCTAssertEqual(sessions.sessions.count, 1)
        let users = sessions.history(sessionId: first).filter { $0.role == .user }
        XCTAssertEqual(users.map(\.content), ["请总结：第一轮", "请总结：第二轮"])
        let assistants = sessions.history(sessionId: first).filter { $0.role == .assistant }
        XCTAssertEqual(assistants.count, 2, "每轮续写都应产生一条助手回复")
    }

    @MainActor
    func testActionRunnerImplementsActionExecutionUseCaseContract() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotUseCase-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configText = """
            [general]
            port = 8765
            theme = "tokyo-night"
            opacity = 0.92
            scrollbackLines = 100000
            [server]
            authToken = "${env:CONSOLEPILOT_TEST_SECRET}"
            [capture]
            strategy = ["clipboard"]
            maxInputChars = 40000
            [[profiles]]
            id = "local"
            provider = "openai"
            baseURL = "http://127.0.0.1:11434/v1"
            model = "mock"
            apiKey = ""
            [[actions]]
            id = "summarize"
            name = "Summarize"
            profile = "local"
            userPrompt = "请总结：{{input}}"
            input = "prompt"
            """
        try configText.write(to: url, atomically: true, encoding: .utf8)
        let config = try ConfigStore(loader: ConfigLoader(configURL: url))
        let database = try AppDatabase(path: directory.appendingPathComponent("db.sqlite").path)
        let sessions = try SessionStore(database: database)
        let coordinator = StreamCoordinator(sessionStore: sessions, usageStore: UsageStore(database: database))
        let runner = ActionRunner(
            config: config, capture: TextCaptureService(config: config.current.capture),
            secrets: SecretResolver(), providers: [.openai: MockAIProvider(delay: .zero)],
            coordinator: coordinator, sessionStore: sessions)
        let useCase: any ActionExecutionUseCase = runner

        let response = try await useCase.run(
            ActionExecutionRequest(actionId: "summarize", overrideInput: "契约输入"))

        XCTAssertEqual(response.sessionId, sessions.sessions.first?.id)
        XCTAssertEqual(
            sessions.history(sessionId: response.sessionId).first?.content, "请总结：契约输入")
    }

    @MainActor
    func testCaptureLogStorePersistsMetadataWithoutCapturedText() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsolepilotCaptureLog-\(UUID().uuidString)", isDirectory: true)
        let database = try AppDatabase(path: directory.appendingPathComponent("db.sqlite").path)
        let store = CaptureLogStore(database: database)
        let sensitiveText = "sensitive-selected-text"
        store.record(
            CaptureResult(
                text: sensitiveText, strategy: .clipboard, sourceApp: "Notes",
                sourceBundleId: "com.apple.Notes", windowTitle: "Secret",
                wasTruncated: false, originalLength: sensitiveText.count, elapsed: .milliseconds(4)))
        let row = try await database.writer.read { db in try CaptureLogRecord.fetchOne(db)?.entity }
        XCTAssertEqual(row?.characterCount, sensitiveText.count)
        XCTAssertEqual(row?.sourceApp, "Notes")
        let columns = try await database.writer.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(capture_log)").map { $0["name"] as String }
        }
        XCTAssertFalse(columns.contains("content"))
        XCTAssertFalse(columns.contains("text"))
    }

    func testClipboardSnapshotRestoresStringRTFImageAndMultipleItems() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: .init("ConsolepilotTests-\(UUID().uuidString)")))
        pasteboard.clearContents()

        let first = NSPasteboardItem()
        first.setString("selected text", forType: .string)
        first.setData(Data("{\\rtf1 test}".utf8), forType: .rtf)
        first.setData(Data([0, 1, 2, 3]), forType: .tiff)
        let second = NSPasteboardItem()
        second.setString("second item", forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([first, second]))

        let before = ClipboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("mutated", forType: .string)
        before.restore(to: pasteboard)
        let after = ClipboardSnapshot.capture(from: pasteboard)

        XCTAssertTrue(before.isContentEqual(to: after))
        XCTAssertEqual(pasteboard.string(forType: .string), "selected text\nsecond item")
    }

    func testClipboardSnapshotRoundTripsOneHundredTimes() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: .init("ConsolepilotTests-\(UUID().uuidString)")))
        pasteboard.clearContents()
        pasteboard.setString("round-trip", forType: .string)

        let original = ClipboardSnapshot.capture(from: pasteboard)
        for _ in 0..<100 {
            pasteboard.clearContents()
            pasteboard.setString("temporary", forType: .string)
            original.restore(to: pasteboard)
            XCTAssertTrue(original.isContentEqual(to: ClipboardSnapshot.capture(from: pasteboard)))
        }
    }

    @MainActor
    func testTextCaptureFallbackUsesConfiguredOrderAndMetadata() async throws {
        let config = CaptureConfig(
            strategy: [.accessibility, .simulatedCopy, .clipboard], simulatedCopyWait: .zero,
            restoreClipboard: true, maxInputChars: 5, excludeBundleIds: [])
        let frontmost = FrontmostAppObserver()
        var attempts: [CaptureStrategy] = []
        let service = TextCaptureService(
            config: config, frontmost: frontmost,
            accessibility: {
                attempts.append(.accessibility)
                throw CaptureError.noPermission
            },
            clipboard: {
                attempts.append(.clipboard)
                return "abcdef"
            },
            simulatedCopy: {
                attempts.append(.simulatedCopy)
                throw CaptureError.allStrategiesFailed
            },
            secureInput: { false })
        let result = try await service.capture()
        XCTAssertEqual(result.strategy, .clipboard, "fallback order must follow configured strategies")
        XCTAssertEqual(result.text, String("abcdef".prefix(5)))
        XCTAssertTrue(result.wasTruncated)
        XCTAssertEqual(result.originalLength, 6)
        XCTAssertEqual(attempts, [.accessibility, .simulatedCopy, .clipboard])
    }

    @MainActor
    func testSelectionCaptureNeverUsesStaleClipboardFallback() async throws {
        let config = CaptureConfig(
            strategy: [.accessibility, .simulatedCopy, .clipboard], simulatedCopyWait: .zero,
            restoreClipboard: true, maxInputChars: 100, excludeBundleIds: [])
        var attempts: [CaptureStrategy] = []
        let service = TextCaptureService(
            config: config, frontmost: FrontmostAppObserver(),
            accessibility: {
                attempts.append(.accessibility)
                throw CaptureError.noPermission
            },
            clipboard: {
                attempts.append(.clipboard)
                return "stale clipboard content"
            },
            simulatedCopy: {
                attempts.append(.simulatedCopy)
                throw CaptureError.emptySelection
            },
            secureInput: { false })
        do {
            _ = try await service.capture(selectionOnly: true)
            XCTFail("selection capture must not use stale clipboard content")
        } catch let error as CaptureError {
            XCTAssertEqual(error, .emptySelection)
            XCTAssertEqual(attempts, [.accessibility, .simulatedCopy])
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func testTextCaptureStopsBeforeSyntheticCopyWhenSecureInputIsActive() async {
        let config = CaptureConfig(
            strategy: [.simulatedCopy, .clipboard], simulatedCopyWait: .zero,
            restoreClipboard: true, maxInputChars: 100, excludeBundleIds: [])
        var simulatedCopyCalled = false
        let service = TextCaptureService(
            config: config, frontmost: FrontmostAppObserver(),
            accessibility: { "" }, clipboard: { "clipboard" },
            simulatedCopy: {
                simulatedCopyCalled = true
                return "unsafe"
            },
            secureInput: { true })
        do {
            _ = try await service.capture()
            XCTFail("secure input should block capture")
        } catch let error as CaptureError {
            XCTAssertEqual(error, .secureInputActive)
            XCTAssertFalse(simulatedCopyCalled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func testTextCaptureReturnsNoPermissionWhenAllConfiguredStrategiesFailForPermission() async {
        let config = CaptureConfig(
            strategy: [.accessibility], simulatedCopyWait: .zero, restoreClipboard: true,
            maxInputChars: 100, excludeBundleIds: [])
        let service = TextCaptureService(
            config: config, frontmost: FrontmostAppObserver(),
            accessibility: { throw CaptureError.noPermission }, clipboard: { nil },
            simulatedCopy: { throw CaptureError.noPermission }, secureInput: { false })
        do {
            _ = try await service.capture()
            XCTFail("expected permission error")
        } catch let error as CaptureError {
            XCTAssertEqual(error, .noPermission)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - 出厂默认配置：洁净、可发现、无过期字段

    func testBundledDefaultConfigIsCleanDiscoverableAndFreeOfRemovedFields() throws {
        let url = try XCTUnwrap(ConfigLoader.bundledDefaultConfigURL())
        let text = try String(contentsOf: url, encoding: .utf8)
        // 已移除/过期字段必须零残留（含注释示例），避免旧示例误导用户。
        for token in ["launchAtLogin", "toggleHotkey", "attachTo", "tails", "TailConfig", "高级配置参考"] {
            XCTAssertFalse(text.contains(token), "出厂默认配置不得包含 \(token)")
        }
        // 可发现性：所有可配置 TOML 键都必须在文件中出现（生效键或整段注释示例），
        // 用户即使不看文档也能知道全部可用设置项，不允许“隐藏设置”。
        let visible = tomlKeys(in: text)
        for key in [
            "port", "theme", "opacity", "alwaysOnTop", "fontName", "fontSize", "compactFontSize",
            "scrollbackLines", "allowRealProvider",
            "authToken", "maxBodyBytes",
            "strategy", "simulatedCopyWait", "restoreClipboard", "maxInputChars", "excludeBundleIds",
            "id", "provider", "baseURL", "model", "apiKey", "temperature", "maxTokens", "timeoutSec",
            "maxContextBytes", "priceInput", "priceOutput",
            "name", "hotkey", "profile", "systemPrompt", "userPrompt", "input", "sessionMode",
            "autoShow", "notifyOnDone",
        ] {
            XCTAssertTrue(visible.contains(key), "默认配置缺少可用设置项示例：\(key)")
        }
        XCTAssertTrue(
            text.contains("[actions.overrides]") || text.contains("overrides ="),
            "默认配置缺少 overrides 参数覆盖示例")
        // 首次安装安全：Profile/Action 示例以整段注释存在，不激活任何条目。
        let active = text.split(separator: "\n")
            .filter { !$0.hasPrefix("#") }
            .joined(separator: "\n")
        XCTAssertFalse(active.contains("[[profiles]]"))
        XCTAssertFalse(active.contains("[[actions]]"))
    }

    /// 收集文本中所有 `key =` 形式的键名（注释行剥去行首 # 后同样识别）。
    private func tomlKeys(in text: String) -> Set<String> {
        var keys = Set<String>()
        for rawLine in text.split(separator: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { line = String(line.dropFirst()) }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                .prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !key.isEmpty { keys.insert(String(key)) }
        }
        return keys
    }
}

/// 记录每次收到请求的 Provider（内部委托 Mock，便于断言请求构造）。
private final class RecordingProvider: AIProvider, @unchecked Sendable {
    private let inner = MockAIProvider(delay: .zero)
    private let lock = NSLock()
    private var recorded: [ChatRequest] = []

    var requests: [ChatRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        lock.lock()
        recorded.append(request)
        lock.unlock()
        return inner.stream(request)
    }
}
