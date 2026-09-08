import Foundation

/// Applies a validated configuration to runtime consumers as one atomic update.
/// Provider construction and Carbon registration stay behind this seam so a
/// config reload never exposes a partially updated runtime.
@MainActor
final class RuntimeBindings {
    private let providerFactory: (ProviderKind) -> any AIProvider
    private(set) var providers: [ProviderKind: any AIProvider] = [:]
    let hotkeys: HotkeyRegistry
    var onAction: ((String) -> Void)?

    init(
        config: AppConfig,
        systemHotkeys: Bool = false,
        providerFactory: @escaping (ProviderKind) -> any AIProvider
    ) {
        self.providerFactory = providerFactory
        hotkeys = HotkeyRegistry(systemRegistrationEnabled: systemHotkeys)
        apply(config)
    }

    init(
        configStore: ConfigStore,
        systemHotkeys: Bool = false,
        providerFactory: @escaping (ProviderKind) -> any AIProvider
    ) {
        self.providerFactory = providerFactory
        hotkeys = HotkeyRegistry(systemRegistrationEnabled: systemHotkeys)
        apply(configStore.current)
        configStore.addObserver { [weak self] config in
            self?.apply(config)
        }
    }

    func apply(_ config: AppConfig) {
        var nextProviders: [ProviderKind: any AIProvider] = [:]
        for profile in config.profiles {
            if nextProviders[profile.provider] == nil {
                nextProviders[profile.provider] = providerFactory(profile.provider)
            }
        }

        var nextHotkeys: [String: (HotkeySpec, @MainActor () -> Void)] = [:]
        for action in config.actions {
            guard let raw = action.hotkey, !raw.isEmpty, let spec = HotkeySpec(raw) else { continue }
            let actionID = action.id
            nextHotkeys[actionID] = (spec, { [weak self] in
                self?.onAction?(actionID)
            })
        }

        // Both registries are swapped only after the candidate configuration
        // has passed validation, so consumers never observe a half-applied set.
        providers = nextProviders
        hotkeys.replaceAll(nextHotkeys)
    }

    func provider(for kind: ProviderKind) -> (any AIProvider)? { providers[kind] }

    func shutdown() { hotkeys.removeAll() }
}
