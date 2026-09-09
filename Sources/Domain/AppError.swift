import Foundation

public enum AppError: Error, Equatable, Sendable {
    case config(ConfigError)
    case capture(CaptureError)
    case transport(TransportError)
    case storage(StorageError)
    case server(ServerError)
    case notImplemented(String)

    /// 面向用户的直接可读文案（中文）。
    public var userMessage: String {
        switch self {
        case .config(let error): error.userMessage
        case .capture(let error): error.userMessage
        case .transport(let error): error.userMessage
        case .storage(let error): error.userMessage
        case .server(let error): error.userMessage
        case .notImplemented(let feature): "该功能尚未实现：\(feature)"
        }
    }

    /// 稳定错误码：不随文案变化，供测试与日志断言。
    public var code: String {
        switch self {
        case .config: "config.invalid"
        case .capture(let error):
            switch error {
            case .noPermission: "capture.noPermission"
            case .allStrategiesFailed: "capture.allStrategiesFailed"
            case .emptySelection: "capture.emptySelection"
            case .excludedApp: "capture.excludedApp"
            case .secureInputActive: "capture.secureInputActive"
            }
        case .transport(let error):
            switch error {
            case .unauthorized: "transport.unauthorized"
            case .rateLimited: "transport.rateLimited"
            case .serverError: "transport.serverError"
            case .network: "transport.network"
            case .decoding: "transport.decoding"
            case .cancelled: "transport.cancelled"
            case .interrupted: "transport.interrupted"
            case .connectionLost: "transport.connectionLost"
            case .configInvalid: "transport.configInvalid"
            }
        case .storage: "storage.unavailable"
        case .server(let error):
            switch error {
            case .portUnavailable: "server.portUnavailable"
            case .nonLoopbackRejected: "server.nonLoopbackRejected"
            case .payloadTooLarge: "server.payloadTooLarge"
            case .tooManyConnections: "server.tooManyConnections"
            case .unauthorized: "server.unauthorized"
            }
        case .notImplemented: "notImplemented"
        }
    }

    /// 下一步可执行建议；无恢复动作的错误返回空串。
    public var recoverySuggestion: String {
        switch self {
        case .config: "请检查配置文件语法与字段取值后重试。"
        case .capture: "请确认已授予辅助功能权限，或改用复制文本后触发。"
        case .transport(let error):
            switch error {
            case .unauthorized: "请检查 API Key 配置与访问权限。"
            case .rateLimited: "请稍后重试。"
            case .serverError: "请稍后重试，或检查服务端状态。"
            case .network: "请检查网络连接后重试。"
            case .decoding: "请更新应用后重试，或联系支持。"
            case .configInvalid: "请检查配置中的模型与接口设置。"
            case .cancelled, .interrupted, .connectionLost: ""
            }
        case .storage: "请确认应用数据目录可写后重试。"
        case .server: "请检查本地服务端口占用与访问来源。"
        case .notImplemented: ""
        }
    }

    /// 脱敏诊断信息：仅含类型/状态等安全上下文，绝不包含密钥或捕获正文。
    public var diagnostic: String {
        switch self {
        case .config: "配置错误"
        case .capture: "文本捕获失败"
        case .transport: "网络或传输层错误"
        case .storage: "存储错误"
        case .server: "本地服务错误"
        case .notImplemented(let feature): "功能未实现：\(feature)"
        }
    }

    public var isRetryable: Bool {
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

public enum CaptureError: Error, Equatable, Sendable {
    case noPermission, allStrategiesFailed, emptySelection
    case excludedApp(String)
    case secureInputActive
    public var userMessage: String {
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

public enum TransportError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited(retryAfter: Duration?)
    case serverError(status: Int)
    case network(URLError.Code)
    case decoding(String)
    case cancelled
    case interrupted
    case connectionLost
    case configInvalid(String)

    public var userMessage: String {
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
    public var isRetryable: Bool {
        if case .rateLimited = self { return true }
        if case .serverError(let status) = self { return status >= 500 }
        return false
    }
}

public enum StorageError: Error, Equatable, Sendable {
    case unavailable(String)
    public var userMessage: String {
        switch self {
        case .unavailable(let details): return "存储失败：\(details)"
        }
    }
}

public enum ServerError: Error, Equatable, Sendable {
    case portUnavailable(tried: [UInt16])
    case nonLoopbackRejected
    case payloadTooLarge
    case tooManyConnections
    case unauthorized
    public var userMessage: String {
        switch self {
        case .portUnavailable: return "本地服务失败：端口不可用"
        case .nonLoopbackRejected: return "本地服务失败：仅允许本机访问"
        case .payloadTooLarge: return "本地服务失败：请求体过大"
        case .tooManyConnections: return "本地服务失败：连接数已达上限"
        case .unauthorized: return "本地服务失败：鉴权失败"
        }
    }
}
