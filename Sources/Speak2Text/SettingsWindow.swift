import Cocoa
import SwiftUI

/// Modern settings window: translucent sidebar (NavigationSplitView) + grouped forms in the detail pane.
struct SettingsRoot: View {
    @ObservedObject var nav = SettingsNav.shared

    private struct Item: Identifiable { let id: String; let title: String; let symbol: String; var idv: String { id } }
    private var items: [Item] {
        [Item(id: "general", title: L("General"), symbol: "gearshape"),
         Item(id: "model", title: L("Model"), symbol: "cpu"),
         Item(id: "dictionary", title: L("Dictionary"), symbol: "character.book.closed"),
         Item(id: "history", title: L("History"), symbol: "clock.arrow.circlepath"),
         Item(id: "permissions", title: L("Permissions"), symbol: "lock.shield"),
         Item(id: "about", title: L("About"), symbol: "info.circle")]
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: Binding<String?>(get: { nav.tab }, set: { if let v = $0 { nav.tab = v } })) {
                ForEach(items) { it in
                    Label(it.title, systemImage: it.symbol).tag(it.id)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(items.first { $0.id == nav.tab }?.title ?? "Speak2Text")
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    @ViewBuilder private var detail: some View {
        switch nav.tab {
        case "model": ModelTab()
        case "dictionary": DictionaryTab()
        case "history": HistoryTab()
        case "permissions": PermissionsView()
        case "about": AboutTab()
        default: GeneralTab()
        }
    }
}

extension AppDelegate {
    @objc func openSettingsFromMenu() { openSettings(tab: nil) }

    /// Opens (or brings to the front) the settings window, optionally on a given section.
    func openSettings(tab: String?) {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsRoot()))
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 680, height: 460)
            w.setContentSize(NSSize(width: 760, height: 560))
            w.setFrameAutosaveName("SettingsWindow")
            if !w.setFrameUsingName("SettingsWindow") { w.center() }
            settingsWindow = w
        }
        if let tab { SettingsNav.shared.tab = tab }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
