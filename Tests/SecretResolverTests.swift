import ConsolepilotDomain
import XCTest

@testable import ConsolepilotInfrastructure

/// Profile API Key 解析失败的可读化：UI/CLI 展示的是带原因与解决步骤的
/// ConfigError，而不是裸 SecretResolverError。
final class SecretResolverTests: XCTestCase {
    func testEmptyReferenceReportsActionableConfigError() throws {
        let resolver = SecretResolver()
        XCTAssertThrowsError(try resolver.resolvedProfileKey(profileId: "remote", reference: "")) { error in
            guard let configError = error as? ConfigError else {
                return XCTFail("expected ConfigError, got \(error)")
            }
            XCTAssertTrue(configError.userMessage.contains("未配置 apiKey"), configError.userMessage)
            XCTAssertTrue(configError.userMessage.contains("remote"), configError.userMessage)
        }
    }

    func testMissingKeychainMapsToActionableChineseError() {
        let error = SecretResolver.mapResolutionError(
            profileId: "remote", error: SecretResolverError.missingKeychain("chatanywhere.free"))
        let message = error.userMessage
        XCTAssertTrue(message.contains("remote"), message)
        XCTAssertTrue(message.contains("chatanywhere.free"), message)
        XCTAssertTrue(message.contains("钥匙串访问"), message)
    }

    func testMissingEnvironmentMapsToActionableChineseError() {
        let error = SecretResolver.mapResolutionError(
            profileId: "remote", error: SecretResolverError.missingEnvironment("CHATANYWHERE_API_KEY"))
        let message = error.userMessage
        XCTAssertTrue(message.contains("remote"), message)
        XCTAssertTrue(message.contains("CHATANYWHERE_API_KEY"), message)
        XCTAssertTrue(message.contains("export"), message)
    }
}
