import AppKit

struct ScrollbackTrimmer {
    let maxLines: Int
    let batchSize: Int = 5_000

    func trim(_ storage: NSMutableAttributedString) {
        guard maxLines > 0 else { return }
        let lineCount = storage.string.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        guard lineCount > maxLines else { return }
        var remaining = lineCount - maxLines
        while remaining > 0 {
            let removeLines = min(batchSize, remaining)
            var end = 0
            var removed = 0
            while end < storage.length, removed < removeLines {
                let range = (storage.string as NSString).lineRange(for: NSRange(location: end, length: 0))
                end = NSMaxRange(range)
                removed += 1
            }
            storage.deleteCharacters(in: NSRange(location: 0, length: min(end, storage.length)))
            remaining -= removeLines
        }
    }
}
