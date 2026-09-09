import ConsolepilotDomain
import Foundation

public struct SecretResolver {
    let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    public func resolve(_ reference: String) throws -> String {
        guard !reference.isEmpty else { return "" }
        if let name = capture(reference, prefix: "${keychain:", suffix: "}") {
            do { return try keychain.read(name: name) } catch { throw SecretResolverError.missingKeychain(name) }
        }
        if let name = capture(reference, prefix: "${env:", suffix: "}") {
            guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
                throw SecretResolverError.missingEnvironment(name)
            }
            return value
        }
        return reference
    }

    /// 解析 Profile 的 API Key。失败时抛出带明确中文原因与解决步骤的
    /// `ConfigError`，供 UI/CLI 直接展示，避免把底层 `SecretResolverError`
    /// 暴露给用户。
    public func resolvedProfileKey(profileId: String, reference: String) throws -> String {
        guard !reference.isEmpty else {
            throw ConfigError.invalid(
                "Profile「\(profileId)」未配置 apiKey。远程 Provider 必须配置密钥："
                    + "把 apiKey 设为 ${keychain:账户名} 或 ${env:变量名}，并确保对应值可用")
        }
        do {
            return try resolve(reference)
        } catch {
            throw Self.mapResolutionError(profileId: profileId, error: error)
        }
    }

    /// 将底层密钥解析失败映射为带原因与解决步骤的中文 `ConfigError`。
    static func mapResolutionError(profileId: String, error: Error) -> ConfigError {
        switch error {
        case SecretResolverError.missingKeychain(let name):
            return ConfigError.invalid(
                "Profile「\(profileId)」引用的钥匙串账户「\(name)」不存在。"
                    + "请打开“钥匙串访问”新建“密码”项目（名称/账户 = \(name)）后重试；"
                    + "或改用 ${env:变量名} 并在启动应用的终端里设置该变量")
        case SecretResolverError.missingEnvironment(let name):
            return ConfigError.invalid(
                "Profile「\(profileId)」引用的环境变量「\(name)」未设置或为空。"
                    + "请在启动 Consolepilot 的同一终端先 export \(name)=<密钥> 再启动；"
                    + "或改用 ${keychain:账户名} 并先在钥匙串中创建对应密码项目")
        default:
            return ConfigError.invalid(
                "Profile「\(profileId)」读取 API Key 失败：\(error.localizedDescription)")
        }
    }

    func canResolve(_ reference: String) -> Bool {
        do {
            _ = try resolve(reference)
            return true
        } catch {
            return false
        }
    }

    private func capture(_ value: String, prefix: String, suffix: String) -> String? {
        guard value.hasPrefix(prefix), value.hasSuffix(suffix) else { return nil }
        let start = value.index(value.startIndex, offsetBy: prefix.count)
        let end = value.index(value.endIndex, offsetBy: -suffix.count)
        guard start < end else { return nil }
        return String(value[start..<end])
    }
}

enum SecretResolverError: Error, Equatable, Sendable {
    case missingEnvironment(String)
    case missingKeychain(String)
}
