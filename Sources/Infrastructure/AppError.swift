import Foundation

enum AppError: Error, Equatable, Sendable {
    case config(ConfigError)
    case capture(CaptureError)
    case transport(TransportError)
    case storage(StorageError)
    case server(ServerError)

    var userMessage: String {
        switch self {
        case .config(let error): error.userMessage
        case .capture(let error): error.userMessage
        case .transport(let error): error.userMessage
        case .storage(let error): error.userMessage
        case .server(let error): error.userMessage
        }
    }

    var isRetryable: Bool {
        switch self {
        case .transport(let error): error.isRetryable
        default: false
        }
    }
}

public enum ConfigError: Error, Equatable, Sendable {
    case invalid(String)
    public var userMessage: String {
        switch self {
        case .invalid(let details): return "配置无效：\(details)"
        }
    }
}

enum CaptureError: Error, Equatable, Sendable {
    case noPermission, allStrategiesFailed, emptySelection
    case excludedApp(String)
    case secureInputActive
    var userMessage: String {
        switch self {
        case .noPermission:
            return "无法捕获选中文字：需要辅助功能权限"
        case .allStrategiesFailed:
            return "无法捕获选中文字：请先复制文本，或检查捕获配置"
        case .emptySelection:
            return "无法捕获选中文字：当前没有选中文本"
        case .excludedApp(let bundleId):
            return "无法捕获选中文字：当前应用已被排除（\(bundleId)）"
        case .secureInputActive:
            return "无法捕获选中文字：当前窗口启用了安全输入"
        }
    }
}

enum TransportError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited(retryAfter: Duration?)
    case serverError(status: Int)
    case network(URLError.Code)
    case decoding(String)
    case cancelled
    case interrupted
    case connectionLost
    case configInvalid(String)

    var userMessage: String {
        switch self {
        case .unauthorized: return "网络请求失败：API Key 无效或未授权"
        case .rateLimited(let retry):
            if let retry { return "网络请求失败：请求过于频繁，请在 \(retry) 后重试" }
            return "网络请求失败：请求过于频繁"
        case .serverError(let status): return "网络请求失败：服务端错误（HTTP \(status)）"
        case .network(let code): return "网络请求失败：网络错误（\(code.rawValue)）"
        case .decoding(let details): return "网络请求失败：响应解析错误（\(details)）"
        case .cancelled: return "请求已取消"
        case .interrupted: return "请求已中断，已保留已接收内容"
        case .connectionLost: return "网络连接中断，已保留已接收内容"
        case .configInvalid(let details): return "网络请求失败：配置无效（\(details)）"
        }
    }
    var isRetryable: Bool {
        if case .rateLimited = self { return true }
        if case .serverError(let status) = self { return status >= 500 }
        return false
    }
}

enum StorageError: Error, Equatable, Sendable {
    case unavailable(String)
    var userMessage: String {
        switch self {
        case .unavailable(let details): return "存储失败：\(details)"
        }
    }
}

enum ServerError: Error, Equatable, Sendable {
    case portUnavailable(tried: [UInt16])
    case nonLoopbackRejected
    case payloadTooLarge
    case tooManyConnections
    case unauthorized
    var userMessage: String {
        switch self {
        case .portUnavailable: return "本地服务失败：端口不可用"
        case .nonLoopbackRejected: return "本地服务失败：仅允许本机访问"
        case .payloadTooLarge: return "本地服务失败：请求体过大"
        case .tooManyConnections: return "本地服务失败：连接数已达上限"
        case .unauthorized: return "本地服务失败：鉴权失败"
        }
    }
}
