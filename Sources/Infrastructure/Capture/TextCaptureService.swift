import AppKit
import ConsolepilotDomain

@MainActor
package final class TextCaptureService {
    private let config: CaptureConfig
    private let frontmost: FrontmostAppObserver
    private let accessibilityCapture: @MainActor () throws -> String
    private let clipboardCapture: @MainActor () -> String?
    private let simulatedCopyCapture: @MainActor (pid_t?) async throws -> String
    private let secureInputActive: @MainActor () -> Bool

    package init(config: CaptureConfig, frontmost: FrontmostAppObserver = FrontmostAppObserver()) {
        self.config = config
        self.frontmost = frontmost
        accessibilityCapture = { try AccessibilityCapture().selectedText() }
        clipboardCapture = { NSPasteboard.general.string(forType: .string) }
        simulatedCopyCapture = {
            pid in
            try await SimulatedCopyCapture().copyAndRead(
                wait: config.simulatedCopyWait, restore: config.restoreClipboard, targetPID: pid)
        }
        secureInputActive = { SecureInputDetector.isActive }
    }

    init(
        config: CaptureConfig,
        frontmost: FrontmostAppObserver,
        accessibility: @escaping @MainActor () throws -> String,
        clipboard: @escaping @MainActor () -> String?,
        simulatedCopy: @escaping @MainActor () async throws -> String,
        secureInput: @escaping @MainActor () -> Bool
    ) {
        self.config = config
        self.frontmost = frontmost
        accessibilityCapture = accessibility
        clipboardCapture = clipboard
        simulatedCopyCapture = { _ in try await simulatedCopy() }
        secureInputActive = secureInput
    }

    /// Captures text for an Action. Selection Actions must not fall back to a
    /// pre-existing clipboard value: that value may belong to an unrelated
    /// earlier copy operation and would silently become the prompt context.
    func capture(selectionOnly: Bool = false, targetPID: pid_t? = nil) async throws -> CaptureResult {
        let started = ContinuousClock.now
        let info = frontmost.snapshot()
        if let bundleID = info.bundleId, config.excludeBundleIds.contains(bundleID) {
            throw CaptureError.excludedApp(bundleID)
        }
        if secureInputActive() { throw CaptureError.secureInputActive }

        var lastError: CaptureError?
        for strategy in config.strategy {
            do {
                let text: String
                switch strategy {
                case .accessibility:
                    text = try accessibilityCapture()
                case .clipboard:
                    if selectionOnly { continue }
                    text = clipboardCapture() ?? ""
                case .simulatedCopy:
                    text = try await simulatedCopyCapture(targetPID)
                }
                guard !text.isEmpty else { continue }
                let originalLength = text.count
                let output = String(text.prefix(config.maxInputChars))
                return CaptureResult(
                    text: output, strategy: strategy, sourceApp: info.appName,
                    sourceBundleId: info.bundleId, windowTitle: info.windowTitle,
                    wasTruncated: output.count < originalLength, originalLength: originalLength,
                    elapsed: started.duration(to: .now))
            } catch let error as CaptureError {
                lastError = error
                if case .secureInputActive = error { throw error }
                if case .excludedApp = error { throw error }
            } catch {
                lastError = .allStrategiesFailed
                continue
            }
        }
        throw lastError ?? CaptureError.allStrategiesFailed
    }

    func diagnose() -> [CaptureStrategy: Bool] {
        Dictionary(
            uniqueKeysWithValues: config.strategy.map { strategy in
                switch strategy {
                case .accessibility: (strategy, PermissionChecker.hasAccessibility)
                case .simulatedCopy: (strategy, !secureInputActive())
                case .clipboard: (strategy, clipboardCapture() != nil)
                }
            })
    }
}
