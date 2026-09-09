import Foundation

public enum UsagePeriod: String, CaseIterable, Sendable { case today, week, all }

public struct UsageSummary: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let costUSD: Double
    public let requestCount: Int
    public let byModel: [String: UsageSummary]

    public init(
        inputTokens: Int, outputTokens: Int, costUSD: Double, requestCount: Int,
        byModel: [String: UsageSummary]
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.requestCount = requestCount
        self.byModel = byModel
    }
}
