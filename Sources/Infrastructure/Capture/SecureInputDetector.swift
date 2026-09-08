@preconcurrency import Carbon.HIToolbox
import Foundation

struct SecureInputDetector {
    static var isActive: Bool { IsSecureEventInputEnabled() }
}
