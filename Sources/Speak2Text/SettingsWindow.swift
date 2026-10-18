import Cocoa
import SwiftUI

/// Settings window in the standard preferences style: an NSTabViewController with toolbar tabs (icon + title).
final class SettingsTabController: NSTabViewController {
    private struct Tab { let id: String; let title: String; let symbol: String; let size: NSSize; let view: AnyView }

    private var tabs: [Tab] {
        [
            Tab(id: "general", title: L("General"), symbol: "gearshape", size: NSSize(width: 560, height: 440), view: AnyView(GeneralTab())),
            Tab(id: "model", title: L("Model"), symbol: "cpu", size: NSSize(width: 560, height: 290), view: AnyView(ModelTab())),
            Tab(id: "dictionary", title: L("Dictionary"), symbol: "character.book.closed", size: NSSize(width: 560, height: 560), view: AnyView(DictionaryTab())),
            Tab(id: "history", title: L("History"), symbol: "clock.arrow.circlepath", size: NSSize(width: 560, height: 560), view: AnyView(HistoryTab())),
            Tab(id: "permissions", title: L("Permissions"), symbol: "lock.shield", size: NSSize(width: 560, height: 380), view: AnyView(PermissionsView())),
            Tab(id: "about", title: L("About"), symbol: "info.circle", size: NSSize(width: 560, height: 300), view: AnyView(AboutTab())),
        ]
    }
    private var ids: [String] = []

    override func viewDidLoad() {
        tabStyle = .toolbar
        super.viewDidLoad()
        for t in tabs {
            let hc = NSHostingController(rootView: t.view.frame(width: t.size.width, height: t.size.height))
            hc.preferredContentSize = t.size
            let item = NSTabViewItem(viewController: hc)
            item.label = t.title
            item.image = NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title)
            item.identifier = t.id
            addTabViewItem(item)
            ids.append(t.id)
        }
    }

    func select(_ id: String) {
        if let i = ids.firstIndex(of: id), selectedTabViewItemIndex != i { selectedTabViewItemIndex = i }
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let id = tabViewItem?.identifier as? String { SettingsNav.shared.tab = id }
        view.window?.title = tabViewItem?.label ?? "Speak2Text"
    }
}

extension AppDelegate {
    /// Opens (or brings to the front) the settings window, optionally on a given tab.
    @objc func openSettingsFromMenu() { openSettings(tab: nil) }

    func openSettings(tab: String?) {
        if settingsWindow == nil {
            let vc = SettingsTabController()
            let w = NSWindow(contentViewController: vc)
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.toolbarStyle = .preference
            w.center()
            settingsWindow = w
            settingsTabs = vc
        }
        if let tab { settingsTabs?.select(tab) }
        settingsWindow?.title = settingsTabs?.tabViewItems[settingsTabs?.selectedTabViewItemIndex ?? 0].label ?? "Speak2Text"
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
