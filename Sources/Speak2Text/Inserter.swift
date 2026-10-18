import Cocoa

/// Insert text into the focused app: save clipboard, put text, Cmd+V, restore after ~0.5 s.
enum Inserter {
    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        var saved: [[(NSPasteboard.PasteboardType, Data)]] = []
        for item in pb.pasteboardItems ?? [] {
            var entry: [(NSPasteboard.PasteboardType, Data)] = []
            for t in item.types { if let d = item.data(forType: t) { entry.append((t, d)) } }
            saved.append(entry)
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        let changeAfterSet = pb.changeCount
        let src = CGEventSource(stateID: .combinedSessionState)
        let d = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let u = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        d?.flags = .maskCommand; u?.flags = .maskCommand
        d?.post(tap: .cghidEventTap); u?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard pb.changeCount == changeAfterSet else { return }  // user copied something meanwhile
            pb.clearContents()
            for entry in saved {
                let it = NSPasteboardItem()
                for (t, data) in entry { it.setData(data, forType: t) }
                pb.writeObjects([it])
            }
        }
    }
}
