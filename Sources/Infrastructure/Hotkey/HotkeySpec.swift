import Foundation

struct HotkeySpec: Sendable, Equatable, Hashable {
    let key: String
    let modifiers: Set<String>
    /// Number of consecutive presses required before the Action fires.
    /// `1` is the normal single-press behavior; `2` enables double-press.
    let pressCount: Int

    init?(_ raw: String) {
        let parts = raw.split(separator: "+").map { String($0).lowercased() }
        guard let rawKey = parts.last, !rawKey.isEmpty else { return nil }
        let keyParts = rawKey.split(separator: "*", omittingEmptySubsequences: false)
        guard let keyPart = keyParts.first, !keyPart.isEmpty else { return nil }
        let pressCount: Int
        if keyParts.count == 1 {
            pressCount = 1
        } else if keyParts.count == 2, keyParts[1] == "2" {
            pressCount = 2
        } else {
            return nil
        }
        let allowed: Set<String> = ["cmd", "ctrl", "alt", "shift"]
        let modifiers = Set(parts.dropLast())
        guard !modifiers.isEmpty, modifiers.isSubset(of: allowed) else { return nil }
        self.key = String(keyPart)
        self.modifiers = modifiers
        self.pressCount = pressCount
    }
}
