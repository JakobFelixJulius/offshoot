import AppKit

@main
@MainActor
enum OffshootMain {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: RepoStore?
    private var status: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = RepoStore()
        self.store = store
        status = StatusController(store: store, settings: SettingsWindowController(store: store))
        NSApp.mainMenu = Self.makeMainMenu()
    }

    /// Never shown for a menu bar app, but provides ⌘W, ⌘Q and editing shortcuts in the Settings window.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "Offshoot")
        app.addItem(withTitle: "Quit Offshoot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        for submenu in [app, edit, window] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }
}
