import AppKit

struct ClipboardSnapshot: Equatable {
    private let items: [[String: Data]]

    private init(items: [[String: Data]]) {
        self.items = items
    }

    static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            [String: Data](
                uniqueKeysWithValues: item.types.compactMap { type in
                    guard let data = item.data(forType: type) else { return nil }
                    return (type.rawValue, data)
                })
        }
        return ClipboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            values.forEach { type, data in
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }

    func isContentEqual(to other: ClipboardSnapshot) -> Bool {
        items == other.items
    }
}
