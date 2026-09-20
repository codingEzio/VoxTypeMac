import AppKit

struct ClipboardSnapshot {
    struct Item {
        var values: [NSPasteboard.PasteboardType: Data]
    }

    let items: [Item]

    static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let copiedItems = (pasteboard.pasteboardItems ?? []).map { source in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in source.types {
                if let data = source.data(forType: type) {
                    values[type] = data
                }
            }
            return Item(values: values)
        }
        return ClipboardSnapshot(items: copiedItems)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems: [NSPasteboardItem] = items.map { stored in
            let item = NSPasteboardItem()
            for (type, data) in stored.values {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty { pasteboard.writeObjects(restoredItems) }
    }
}
