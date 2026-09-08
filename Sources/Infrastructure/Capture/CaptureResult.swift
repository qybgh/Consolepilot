import Foundation

struct CaptureResult: Sendable, Equatable {
    let text: String
    let strategy: CaptureStrategy
    let sourceApp: String?
    let sourceBundleId: String?
    let windowTitle: String?
    let wasTruncated: Bool
    let originalLength: Int
    let elapsed: Duration
}
