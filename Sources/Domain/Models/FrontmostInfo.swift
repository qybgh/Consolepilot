import Foundation

/// 前台应用快照（模板渲染与捕获共用；纯值类型）。
public struct FrontmostInfo: Sendable, Equatable {
    public let appName: String?
    public let bundleId: String?
    public let windowTitle: String?

    public init(appName: String?, bundleId: String?, windowTitle: String?) {
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
    }
}
