import Foundation
import Network

public protocol CLIRouter: Sendable {
    func handle(path: String, body: Data) async -> (status: Int, body: Data)
}

public protocol PushRouter: Sendable {
    func handle(body: Data) async -> (status: Int, body: Data)
}

public struct ClosureCLIRouter: CLIRouter {
    private let handler: @Sendable (String, Data) async -> (status: Int, body: Data)

    public init(handler: @escaping @Sendable (String, Data) async -> (status: Int, body: Data)) {
        self.handler = handler
    }

    public func handle(path: String, body: Data) async -> (status: Int, body: Data) {
        await handler(path, body)
    }
}

public struct ClosurePushRouter: PushRouter {
    private let handler: @Sendable (Data) async -> (status: Int, body: Data)

    public init(handler: @escaping @Sendable (Data) async -> (status: Int, body: Data)) {
        self.handler = handler
    }

    public func handle(body: Data) async -> (status: Int, body: Data) {
        await handler(body)
    }
}

public actor LocalServer {
    private let config: ServerConfig
    private let cli: any CLIRouter
    private let push: any PushRouter
    private let secrets: SecretResolver
    private let directToken: String?
    private var listener: NWListener?
    public private(set) var actualPort: UInt16 = 0

    init(
        config: ServerConfig, port: UInt16, cli: any CLIRouter,
        push: any PushRouter, secrets: SecretResolver = SecretResolver()
    ) {
        self.config = config
        self.actualPort = port
        self.cli = cli
        self.push = push
        self.secrets = secrets
        self.directToken = nil
    }

    public init(
        port: UInt16, maxBodyBytes: Int, authToken: String,
        cli: any CLIRouter, push: any PushRouter
    ) {
        config = ServerConfig(authTokenRef: "", maxBodyBytes: maxBodyBytes)
        actualPort = port
        self.cli = cli
        self.push = push
        self.secrets = SecretResolver()
        self.directToken = authToken
    }

    public func start() async throws {
        let token = try directToken ?? secrets.resolve(config.authTokenRef)
        guard !token.isEmpty else { throw ServerError.unauthorized }
        var tried: [UInt16] = []
        for offset in 0..<5 {
            let candidate = actualPort &+ UInt16(offset)
            tried.append(candidate)
            do {
                let parameters = NWParameters.tcp
                guard let port = NWEndpoint.Port(rawValue: candidate) else { continue }
                parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host("127.0.0.1"),
                    port: port
                )
                let listener = try NWListener(using: parameters)
                listener.newConnectionHandler = { [weak self] connection in
                    connection.start(queue: .global())
                    Task { await self?.handle(connection, token: token) }
                }
                do {
                    try await withCheckedThrowingContinuation { continuation in
                        let gate = ContinuationGate()
                        listener.stateUpdateHandler = { state in
                            guard gate.claim() else { return }
                            switch state {
                            case .ready:
                                continuation.resume()
                            case .failed(let error):
                                continuation.resume(throwing: error)
                            case .cancelled:
                                continuation.resume(throwing: ServerError.portUnavailable(tried: [candidate]))
                            default:
                                break
                            }
                        }
                        listener.start(queue: .global())
                    }
                    self.listener = listener
                    actualPort = candidate
                    return
                } catch {
                    listener.cancel()
                    continue
                }
            } catch { continue }
        }
        throw ServerError.portUnavailable(tried: tried)
    }

    private final class ContinuationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection, token: String) async {
        guard Self.isLoopback(connection) else {
            send(connection, status: 403, body: "Forbidden")
            connection.cancel()
            return
        }
        let data = await receive(connection)
        guard data.count <= config.maxBodyBytes + 16_384 else {
            send(connection, status: 413, body: "Payload Too Large")
            return
        }
        guard let request = Self.parseRequest(data) else {
            send(connection, status: 400, body: "Bad Request")
            return
        }
        let authStatus = Self.authorizationStatus(
            request: request, expectedToken: token, maxBodyBytes: config.maxBodyBytes)
        guard authStatus == 200 else {
            send(connection, status: authStatus, body: authStatus == 413 ? "Payload Too Large" : "Unauthorized")
            return
        }
        let result =
            request.path == "/push"
            ? await push.handle(body: request.body) : await cli.handle(path: request.path, body: request.body)
        send(connection, status: result.status, body: result.body)
    }

    private func receive(_ connection: NWConnection) async -> Data {
        await withCheckedContinuation { continuation in
            @Sendable func read(_ accumulated: Data) {
                let limit = config.maxBodyBytes + 16_384
                guard accumulated.count < limit else {
                    continuation.resume(returning: accumulated)
                    return
                }
                connection.receive(minimumIncompleteLength: 1, maximumLength: limit - accumulated.count) {
                    data, _, isComplete, _ in
                    let chunk = data ?? Data()
                    var next = accumulated
                    next.append(chunk)
                    if isComplete || chunk.isEmpty || Self.hasCompleteRequest(next) {
                        continuation.resume(returning: next)
                    } else {
                        read(next)
                    }
                }
            }
            read(Data())
        }
    }

    private func send(_ connection: NWConnection, status: Int, body: String) {
        send(connection, status: status, body: Data(body.utf8))
    }
    private func send(_ connection: NWConnection, status: Int, body: Data) {
        let reason = status == 200 ? "OK" : "Error"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    struct Request: Sendable, Equatable {
        let method: String
        let path: String
        let authorization: String?
        let body: Data
        let contentLength: Int?
    }

    static func parseRequest(_ data: Data) -> Request? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter),
            let head = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var auth: String?
        var contentLength: Int?
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            switch pieces[0].lowercased() {
            case "authorization": auth = pieces[1].trimmingCharacters(in: .whitespaces)
            case "content-length": contentLength = Int(pieces[1].trimmingCharacters(in: .whitespaces))
            default: break
            }
        }
        let bodyStart = headerRange.upperBound
        let body = data[bodyStart...]
        if let contentLength, contentLength < 0 || body.count < contentLength { return nil }
        let exactBody = Data(body.prefix(contentLength ?? body.count))
        return Request(
            method: String(parts[0]), path: String(parts[1]), authorization: auth, body: exactBody,
            contentLength: contentLength)
    }

    static func authorizationStatus(request: Request, expectedToken: String, maxBodyBytes: Int) -> Int {
        guard request.body.count <= maxBodyBytes else { return 413 }
        guard request.method == "POST" else { return 405 }
        guard request.authorization == "Bearer \(expectedToken)" else { return 401 }
        return 200
    }

    private static func hasCompleteRequest(_ data: Data) -> Bool {
        guard let request = parseRequest(data) else { return false }
        if let length = request.contentLength {
            let delimiter = Data("\r\n\r\n".utf8)
            guard let range = data.range(of: delimiter) else { return false }
            return data.count - range.upperBound >= length
        }
        return true
    }

    private static func isLoopback(_ connection: NWConnection) -> Bool {
        guard let endpoint = connection.currentPath?.remoteEndpoint else { return true }
        switch endpoint {
        case .hostPort(let host, _):
            let value = String(describing: host)
            return value == "127.0.0.1" || value == "::1" || value == "localhost"
        default:
            return false
        }
    }
}
