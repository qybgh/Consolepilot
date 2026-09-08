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
