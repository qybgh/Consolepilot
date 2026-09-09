/// 模型服务商标识（配置、Usage 与 Provider 注册共用）。
enum ProviderKind: String, Sendable, CaseIterable { case openai, anthropic }
