import AppKit
import SwiftUI

/// The Settings window: toolbar-style tabs hosting the SwiftUI settings panes,
/// matching what a SwiftUI `Settings` scene produces.
@MainActor
final class SettingsWindowController {
    enum Tab: Int {
        case general, repositories
    }

    private let store: RepoStore
    private var window: NSWindow?

    init(store: RepoStore) {
        self.store = store
    }

    func show(_ tab: Tab) {
        let window = window ?? makeWindow()
        self.window = window
        (window.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = tab.rawValue
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(pane("General", symbol: "gearshape", GeneralSettings(store: store)))
        tabs.addTabViewItem(pane("Repositories", symbol: "folder", RepositorySettings(store: store)))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func pane(_ label: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
