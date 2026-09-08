import Foundation

/// Shared HTTP and URLSession error semantics for all streaming providers.
enum TransportSupport {
    static func validateHTTPStatus(_ status: Int, headers: [AnyHashable: Any] = [:]) throws {
        switch status {
        case 200...299:
            return
        case 401, 403:
            throw TransportError.unauthorized
        case 429:
            let retry = (headers["Retry-After"] as? String)
                .flatMap(Int64.init)
                .map(Duration.seconds)
            throw TransportError.rateLimited(retryAfter: retry)
        case 500...599:
            throw TransportError.serverError(status: status)
        default:
            throw TransportError.configInvalid("HTTP \(status)")
        }
    }

    static func map(_ error: Error) -> TransportError {
        if let error = error as? TransportError { return error }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return .cancelled }
            if [.networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed]
                .contains(urlError.code)
            {
                return .connectionLost
            }
            return .network(urlError.code)
        }
        return .connectionLost
    }
}
