import AppKit
import HoverTalkCore

/// `NSPasteboard.general` for `SelectionCopy`: saves every item with every type, so restoring
/// puts back images and files too, not only text.
struct SystemPasteboard: PasteboardAccess {
    typealias Saved = [[NSPasteboard.PasteboardType: Data]]

    private var board: NSPasteboard { .general }

    var changeCount: Int { board.changeCount }

    func save() -> Saved {
        (board.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [:]) { saved, type in
                if let data = item.data(forType: type) { saved[type] = data }
            }
        }
    }

    func restore(_ saved: Saved) {
        board.clearContents()
        let items = saved.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { board.writeObjects(items) }
    }

    func text() -> String? {
        board.string(forType: .string)
    }
}
