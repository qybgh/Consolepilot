/// 文本捕获策略（按优先级回退；Capture 审计与配置共用）。
public enum CaptureStrategy: String, Sendable, CaseIterable { case accessibility, simulatedCopy, clipboard }
