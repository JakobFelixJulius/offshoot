import SwiftUI

@main
struct OffshootApp: App {
    @State private var store = RepoStore()
    @AppStorage(MenuBarIcon.styleKey) private var iconStyle = MenuBarIcon.Style.leaf

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(nsImage: MenuBarIcon.image(count: store.behindCount, style: iconStyle))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(store: store)
        }
    }
}
