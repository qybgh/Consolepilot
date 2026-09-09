import Foundation

public struct TemplateContext: Sendable {
    public let input: String
    public let selection: String?
    public let clipboard: String?
    public let frontmost: FrontmostInfo
    public let now: Date
    public let language: String

    public init(
        input: String, selection: String?, clipboard: String?, frontmost: FrontmostInfo, now: Date,
        language: String
    ) {
        self.input = input
        self.selection = selection
        self.clipboard = clipboard
        self.frontmost = frontmost
        self.now = now
        self.language = language
    }
}

public struct TemplateEngine {
    public static let knownPlaceholders: Set<String> = [
        "input", "selection", "clipboard", "app", "bundleId", "appBundleId", "windowTitle", "date", "time",
        "datetime", "language", "lang",
    ]

    public init() {}

    public func render(_ template: String, context: TemplateContext) -> String {
        let date = context.now.formatted(.dateTime.year().month().day())
        let time = context.now.formatted(.dateTime.hour().minute().second())
        let values: [String: String] = [
            "input": context.input,
            "selection": context.selection ?? "",
            "clipboard": context.clipboard ?? "",
            "app": context.frontmost.appName ?? "",
            "bundleId": context.frontmost.bundleId ?? "",
            "appBundleId": context.frontmost.bundleId ?? "",
            "windowTitle": context.frontmost.windowTitle ?? "",
            "date": date,
            "time": time,
            "datetime": context.now.formatted(.iso8601),
            "language": context.language,
            "lang": context.language,
        ]
        return Self.placeholders(in: template).reduce(template) { result, key in
            if key.hasPrefix("env:") {
                let name = String(key.dropFirst(4))
                return result.replacingOccurrences(
                    of: "{{\(key)}}", with: ProcessInfo.processInfo.environment[name] ?? "")
            }
            return result.replacingOccurrences(of: "{{\(key)}}", with: values[key] ?? "")
        }
    }

    public static func placeholders(in template: String) -> Set<String> {
        var result = Set<String>()
        var cursor = template.startIndex
        while let start = template[cursor...].range(of: "{{") {
            guard let end = template[start.upperBound...].range(of: "}}") else { break }
            let name = String(template[start.upperBound..<end.lowerBound]).trimmingCharacters(
                in: .whitespacesAndNewlines)
            result.insert(name)
            cursor = end.upperBound
        }
        return result
    }
}
