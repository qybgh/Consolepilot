import ConsolepilotDomain
import Foundation

package struct ConfigValidator: Sendable {
    let hasAccessibility: Bool

    package init(hasAccessibility: Bool = true) {
        self.hasAccessibility = hasAccessibility
    }

    // 规则引擎聚合入口：覆盖重复 ID/快捷键/模板/范围/引用/服务等全部规则。
    // P1-E 随 schema 变更重构为按规则分文件时消除本条豁免。
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func validate(_ config: AppConfig, sourceText: String) -> ValidationReport {
        var errors: [ConfigIssue] = []
        var warnings: [ConfigIssue] = []
        let profiles = config.profiles
        let profileIDs = profiles.map(\.id)
        let actionIDs = config.actions.map(\.id)
        let line: (String) -> Int? = { needle in
            sourceText.split(separator: "\n", omittingEmptySubsequences: false).firstIndex {
                $0.contains(needle)
            }.map { $0 + 1 }
        }

        for id in Set(profileIDs.filter { candidate in profileIDs.filter { $0 == candidate }.count > 1 }) {
            errors.append(
                ConfigIssue(code: .duplicateProfileId, line: line("id = \"\(id)\""), message: "重复的 profile.id：\(id)"))
        }
        for id in Set(actionIDs.filter { candidate in actionIDs.filter { $0 == candidate }.count > 1 }) {
            errors.append(
                ConfigIssue(code: .duplicateActionId, line: line("id = \"\(id)\""), message: "重复的 action.id：\(id)"))
        }

        var hotkeys: [String: String] = [:]
        for action in config.actions {
            if !profileIDs.contains(action.profileId) {
                errors.append(
                    ConfigIssue(
                        code: .unknownProfileRef, line: line("profile = \"\(action.profileId)\""),
                        message: "未知 profile：\(action.profileId)"))
            }
            if let hotkey = action.hotkey, !hotkey.isEmpty {
                guard Self.isValidHotkey(hotkey) else {
                    errors.append(
                        ConfigIssue(
                            code: .invalidHotkeySyntax, line: line("hotkey = \"\(hotkey)\""),
                            message: "快捷键语法无效：\(hotkey)"))
                    continue
                }
                if let previous = hotkeys[hotkey] {
                    errors.append(
                        ConfigIssue(
                            code: .duplicateHotkey, line: line("hotkey = \"\(hotkey)\""),
                            message: "快捷键与 action \(previous) 重复"))
                } else {
                    hotkeys[hotkey] = action.id
                }
            }
            let templates = [action.userPrompt, action.systemPrompt ?? ""]
            let placeholders = templates.flatMap { Self.placeholders(in: $0) }
            let unknown = placeholders.filter {
                !Self.knownPlaceholders.contains($0) && !$0.hasPrefix("env:")
            }
            for placeholder in Set(unknown) {
                errors.append(
                    ConfigIssue(code: .unknownPlaceholder, line: line(placeholder), message: "未知占位符：{{\(placeholder)}}")
                )
            }
            for placeholder in Set(placeholders.filter({ $0.hasPrefix("env:") })) {
                let name = String(placeholder.dropFirst(4))
                if name.isEmpty || ProcessInfo.processInfo.environment[name] == nil {
                    errors.append(
                        ConfigIssue(
                            code: .unresolvableSecret, line: line(placeholder),
                            message: "环境变量不存在：\(name)"))
                }
            }
            if action.input == .selection && !hasAccessibility {
                warnings.append(
                    ConfigIssue(
                        code: .warnNoAXPermission, line: line("input = \"selection\""), message: "未授予辅助功能权限，将按降级链路捕获"))
            }
            if let overrides = action.overrides,
                (overrides.temperature.map { !$0.isFinite || $0 < 0 || $0 > 2 } ?? false)
                    || (overrides.maxTokens.map { $0 <= 0 } ?? false)
                    || (overrides.timeoutSec.map { $0 <= 0 } ?? false)
                    || (overrides.model != nil
                        && overrides.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
            {
                errors.append(
                    ConfigIssue(
                        code: .valueOutOfRange, line: nil,
                        message: "Action \(action.id) 的 overrides 参数超出范围"))
            }
            if !InputSource.allCases.contains(action.input) {
                errors.append(
                    ConfigIssue(
                        code: .invalidInputSource, line: nil, message: "action.input 无效：\(action.input.rawValue)"))
            }
            if !SessionMode.allCases.contains(action.sessionMode) {
                errors.append(
                    ConfigIssue(
                        code: .invalidSessionMode, line: nil,
                        message: "action.sessionMode 无效：\(action.sessionMode.rawValue)"))
            }
            if let timeoutSec = action.timeoutSec, timeoutSec <= 0 {
                errors.append(
                    ConfigIssue(
                        code: .valueOutOfRange, line: nil,
                        message: "Action \(action.id) 的 timeoutSec 必须是正整数"))
            }
        }

        for profile in profiles {
            guard ["http", "https"].contains(profile.baseURL.scheme?.lowercased()), profile.baseURL.host != nil else {
                errors.append(
                    ConfigIssue(
                        code: .invalidBaseURL, line: line("baseURL = \"\(profile.baseURL.absoluteString)\""),
                        message: "baseURL 必须使用 http 或 https"))
                continue
            }
            if !ProviderKind.allCases.contains(profile.provider) {
                errors.append(
                    ConfigIssue(code: .unknownProvider, line: nil, message: "未知 provider：\(profile.provider.rawValue)"))
            }
            if !profile.temperature.isFinite || profile.temperature < 0 || profile.temperature > 2
                || profile.maxTokens <= 0 || profile.timeoutSec <= 0
            {
                errors.append(ConfigIssue(code: .valueOutOfRange, line: nil, message: "Profile \(profile.id) 的参数超出范围"))
            }
            let isLoopback =
                profile.baseURL.host == "127.0.0.1" || profile.baseURL.host == "localhost"
                || profile.baseURL.host == "::1"
            if !isLoopback && !Self.isSecretReference(profile.apiKeyRef) {
                errors.append(
                    ConfigIssue(
                        code: .unresolvableSecret, line: nil, message: "远程 Profile 的 API Key 必须引用 Keychain 或环境变量"))
            }
        }

        if !config.general.opacity.isFinite || config.general.opacity < 0.75 || config.general.opacity > 1 {
            errors.append(ConfigIssue(code: .valueOutOfRange, line: nil, message: "opacity 必须在 0.75 到 1.0 之间"))
        }
        // UI 外观字体字段仅做有限数/正数校验，随 P2 SwiftUI 迁移接线。
        if !config.general.fontSize.isFinite || config.general.fontSize <= 0
            || !config.general.compactFontSize.isFinite || config.general.compactFontSize <= 0
        {
            errors.append(ConfigIssue(code: .valueOutOfRange, line: nil, message: "fontSize/compactFontSize 必须为正数"))
        }
        if config.general.port < 1024 || config.general.port > 65_535 {
            errors.append(ConfigIssue(code: .valueOutOfRange, line: nil, message: "port 必须在 1024 到 65535 之间"))
        }
        if config.general.scrollbackLines < 1000 {
            errors.append(ConfigIssue(code: .valueOutOfRange, line: nil, message: "scrollbackLines 必须至少为 1000"))
        }
        if !["tokyo-night", "solarized-dark", "nord", "mono"].contains(config.general.theme) {
            errors.append(ConfigIssue(code: .unknownTheme, line: nil, message: "未知主题：\(config.general.theme)"))
        }
        if config.capture.strategy.isEmpty
            || config.capture.strategy.contains(where: { !CaptureStrategy.allCases.contains($0) })
        {
            errors.append(ConfigIssue(code: .invalidStrategy, line: nil, message: "capture 配置无效"))
        }
        if config.capture.maxInputChars < 100 || config.capture.maxInputChars > 1_000_000 {
            errors.append(ConfigIssue(code: .valueOutOfRange, line: nil, message: "maxInputChars 必须在 100 到 1000000 之间"))
        }
        if ((!config.server.authTokenRef.isEmpty && !Self.isSecretReference(config.server.authTokenRef))
            || config.server.maxBodyBytes < 1024)
            || config.server.maxBodyBytes > 10 * 1024 * 1024
        {
            errors.append(ConfigIssue(code: .invalidServerAuth, line: nil, message: "server 鉴权配置无效"))
        }
        return ValidationReport(errors: errors, warnings: warnings)
    }

    private static let knownPlaceholders: Set<String> = TemplateEngine.knownPlaceholders

    private static func placeholders(in template: String) -> Set<String> {
        let pattern = #"\{\{([^{}]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        return Set(
            regex.matches(in: template, range: range).compactMap {
                guard let matchRange = Range($0.range(at: 1), in: template) else { return nil }
                return String(template[matchRange])
            })
    }

    private static func isSecretReference(_ value: String) -> Bool {
        value.range(of: #"^\$\{(keychain|env):[^}]+\}$"#, options: .regularExpression) != nil
    }

    private static func isValidHotkey(_ value: String) -> Bool {
        value.range(
            of: #"^(cmd|ctrl|alt|shift)(\+(cmd|ctrl|alt|shift))*\+[A-Za-z0-9`]+(\*2)?$"#, options: .regularExpression)
            != nil
    }
}

struct ValidationReport: Equatable, Sendable {
    let errors: [ConfigIssue]
    let warnings: [ConfigIssue]
    var isAcceptable: Bool { errors.isEmpty }
}

struct ConfigIssue: Equatable, Sendable {
    let code: ConfigErrorCode
    let line: Int?
    let message: String
}

enum ConfigErrorCode: String, Sendable {
    case duplicateProfileId, duplicateActionId, unknownProfileRef
    case invalidHotkeySyntax, duplicateHotkey
    case unknownPlaceholder, invalidBaseURL, unresolvableSecret
    case valueOutOfRange, unknownTheme, invalidStrategy
    case invalidInputSource, invalidSessionMode
    case unknownProvider, invalidServerAuth, parseFailure, warnNoAXPermission
}
