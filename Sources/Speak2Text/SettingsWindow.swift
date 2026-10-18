import Cocoa
import SwiftUI
import Combine

/// Modern settings window: translucent sidebar (NSSplitViewController) + grouped forms in the detail pane.
private let settingsItems: [(id: String, title: String, symbol: String)] = [
    ("general", L("General"), "gearshape"),
    ("model", L("Model"), "cpu"),
    ("dictionary", L("Dictionary"), "character.book.closed"),
    ("history", L("History"), "clock.arrow.circlepath"),
    ("permissions", L("Permissions"), "lock.shield"),
    ("about", L("About"), "info.circle")]

struct SettingsSidebar: View {
    @ObservedObject var nav = SettingsNav.shared
    var body: some View {
        List(selection: Binding<String?>(get: { nav.tab }, set: { if let v = $0 { nav.tab = v } })) {
            ForEach(settingsItems, id: \.id) { it in
                Label(it.title, systemImage: it.symbol).tag(it.id)
            }
        }
        .listStyle(.sidebar)
    }
}

struct SettingsDetail: View {
    @ObservedObject var nav = SettingsNav.shared
    var body: some View {
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
            let split = NSSplitViewController()
            let side = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: SettingsSidebar()))
            side.minimumThickness = 190
            side.maximumThickness = 260
            side.canCollapse = false
            split.addSplitViewItem(side)
            split.addSplitViewItem(NSSplitViewItem(viewController: NSHostingController(rootView: SettingsDetail())))
            let w = NSWindow(contentViewController: split)
            settingsTitleSub = SettingsNav.shared.$tab.sink { [weak w] t in
                w?.title = settingsItems.first { $0.id == t }?.title ?? "Speak2Text"
            }
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
