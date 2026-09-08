import XCTest
import Foundation

@testable import ConsolepilotCore

final class ServerTests: XCTestCase {
    func testLocalServerServesAuthenticatedLoopbackRequest() async throws {
        let cli = ClosureCLIRouter { path, body in
            XCTAssertEqual(path, "/ask")
            XCTAssertEqual(body, Data("{}".utf8))
            return (200, Data("ok".utf8))
        }
        let push = ClosurePushRouter { _ in (202, Data("accepted".utf8)) }
        let server = LocalServer(port: 18_765, maxBodyBytes: 1_048_576, authToken: "test-token", cli: cli, push: push)
        try await server.start()
        defer { Task { await server.stop() } }
        let port = await server.actualPort
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/ask")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
    }

    func testLocalServerRequestAuthAndPayloadLimits() throws {
        let body = Data("{\"text\":\"hello\"}".utf8)
        let raw =
            Data("POST /push HTTP/1.1\r\nAuthorization: Bearer token\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            + body
        let request = try XCTUnwrap(LocalServer.parseRequest(raw))
        XCTAssertEqual(request.path, "/push")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.contentLength, body.count)
        XCTAssertEqual(
            LocalServer.authorizationStatus(request: request, expectedToken: "token", maxBodyBytes: 100), 200)
        XCTAssertEqual(
            LocalServer.authorizationStatus(request: request, expectedToken: "wrong", maxBodyBytes: 100), 401)
        XCTAssertEqual(LocalServer.authorizationStatus(request: request, expectedToken: "token", maxBodyBytes: 2), 413)
    }

    func testParseRequestPreservesBinaryBodyAndRejectsIncompleteLength() throws {
        let bytes = Data([0, 255, 1, 2])
        let header = Data("POST /push HTTP/1.1\r\nContent-Length: 4\r\n\r\n".utf8)
        let request = try XCTUnwrap(LocalServer.parseRequest(header + bytes))
        XCTAssertEqual(request.body, bytes)
        XCTAssertNil(LocalServer.parseRequest(header + bytes.prefix(3)))
    }

    func testTailWatcherReadsCompleteLinesAndHandlesRotation() async throws {
        let directory = FileManager.default.temporaryDirectory
        let path = directory.appendingPathComponent("consolepilot-tail-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: path.path, contents: Data("one\n".utf8))
        let lines = LineCollector()
        let watcher = FileTailWatcher(config: TailConfig(path: path.path, enabled: true, format: .text, fromEnd: false))
        { line in
            Task { await lines.append(line) }
        }
        try await watcher.start()
        try await Task.sleep(for: .milliseconds(400))
        try Data("two\npartial".utf8).write(to: path, options: .atomic)
        try await Task.sleep(for: .milliseconds(500))
        try Data("three\n".utf8).write(to: path, options: .atomic)
        try await Task.sleep(for: .milliseconds(500))
        await watcher.stop()
        let captured = await lines.values
        XCTAssertTrue(captured.contains("one"))
        XCTAssertTrue(captured.contains("three"))
    }

    func testTailWatcherRejectsMissingFileBeforeStarting() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("consolepilot-missing-\(UUID().uuidString).log")
        let watcher = FileTailWatcher(
            config: TailConfig(path: missing.path, enabled: true, format: .text, fromEnd: true)) { _ in }
        do {
            try await watcher.start()
            XCTFail("expected missing file error")
        } catch {
            XCTAssertTrue(error is CocoaError)
        }
    }
}

private actor LineCollector {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}
