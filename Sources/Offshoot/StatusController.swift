import AppKit
import Observation

/// Owns the menu bar item and its menu. The menu is a plain `NSMenu` that updates in
/// place while open, so Fetch All progress is visible without reopening it.
@MainActor
final class StatusController: NSObject, NSMenuDelegate {
    private let store: RepoStore
    private let settings: SettingsWindowController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let fetchAllItem = NSMenuItem()
    private let fetchAllView = FetchAllView()
    private let summaryItem = NSMenuItem()

    private var renderedIDs: [Repo.ID]?
    private var repoItems: [Repo.ID: NSMenuItem] = [:]
    private var submenuRepos: [ObjectIdentifier: Repo] = [:]

    init(store: RepoStore, settings: SettingsWindowController) {
        self.store = store
        self.settings = settings
        super.init()

        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.setAccessibilityTitle("Offshoot")

        fetchAllView.onClick = { [weak self] in self?.fetchAll() }
        fetchAllItem.view = fetchAllView
        // Keyboard activation goes through the item's action; that path closes the menu.
        fetchAllItem.target = self
        fetchAllItem.action = #selector(fetchAllFromKeyboard)
        fetchAllItem.keyEquivalent = "f"
        summaryItem.isEnabled = false

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusButton() }
        }
        observe()
    }

    // MARK: Rendering

    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func render() {
        let ids = store.repos.map(\.id)
        if ids != renderedIDs { rebuild(ids) }

        updateStatusButton()
        fetchAllView.update(isFetching: store.isSyncingAll, isEnabled: !store.repos.isEmpty)
        summaryItem.title = store.lastSummary ?? ""
        summaryItem.isHidden = store.lastSummary == nil

        for repo in store.repos {
            guard let item = repoItems[repo.id] else { continue }
            item.title = repo.menuTitle
            item.image = repo.status.image
            item.isEnabled = !repo.isBusy
        }
    }

    private func updateStatusButton() {
        let style = UserDefaults.standard.string(forKey: MenuBarIcon.styleKey).flatMap(MenuBarIcon.Style.init) ?? .leaf
        statusItem.button?.image = MenuBarIcon.image(count: store.behindCount, style: style)
    }

    private func rebuild(_ ids: [Repo.ID]) {
        menu.removeAllItems()
        repoItems.removeAll()
        submenuRepos.removeAll()

        menu.addItem(fetchAllItem)
        menu.addItem(summaryItem)
        menu.addItem(.separator())

        if store.repos.isEmpty {
            menu.addItem(.note("No repositories"))
            menu.addItem(ActionMenuItem("Add Repositories…") { [weak self] in self?.settings.show(.repositories) })
        }
        for repo in store.repos {
            let item = NSMenuItem(title: repo.name, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: repo.name)
            submenu.autoenablesItems = false
            submenu.delegate = self
            item.submenu = submenu
            submenuRepos[ObjectIdentifier(submenu)] = repo
            repoItems[repo.id] = item
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Settings…", key: ",") { [weak self] in self?.settings.show(.general) })
        menu.addItem(ActionMenuItem("Quit Offshoot", key: "q") { NSApp.terminate(nil) })
        renderedIDs = ids
    }

    // MARK: Repository submenus

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let repo = submenuRepos[ObjectIdentifier(menu)] else { return }
        menu.removeAllItems()

        if let feedback = repo.feedback, feedback.kind == .failure {
            menu.addItem(.note(feedback.text))
            menu.addItem(.separator())
        }

        if let snap = repo.snapshot {
            addActions(for: repo, snap, to: menu)
            addBranches(for: repo, snap, to: menu)
            menu.addItem(.separator())
        } else if let error = repo.loadError {
            menu.addItem(.note(error))
            menu.addItem(.separator())
        }

        menu.addItem(ActionMenuItem("Fetch") { Task { await repo.sync(fastForward: false) } })
        menu.addItem(ActionMenuItem("Open in Terminal") { repo.openInTerminal() })
        menu.addItem(ActionMenuItem("Reveal in Finder") { repo.revealInFinder() })
    }

    private func addActions(for repo: Repo, _ snap: RepoSnapshot, to menu: NSMenu) {
        if snap.canFastForward {
            menu.addItem(
                ActionMenuItem(
                    "Pull \(Repo.commits(snap.behind))",
                    image: StatusIcon.action("arrow.down.circle.fill", .systemGreen)
                ) { Task { await repo.pull() } })
        }
        if let other = snap.updatableDefault {
            menu.addItem(
                ActionMenuItem(
                    "Update \(other.name) (\(Repo.commits(other.behind)) behind)",
                    image: StatusIcon.action("arrow.down.circle.fill", .systemBlue)
                ) { Task { await repo.updateDefault() } })
        }
        if snap.canFastForward || snap.updatableDefault != nil {
            menu.addItem(.separator())
        }
    }

    private func addBranches(for repo: Repo, _ snap: RepoSnapshot, to menu: NSMenu) {
        let switchTo: (String) -> Void = { name in Task { await repo.switchTo(name) } }
        let ordered = snap.orderedLocalBranches

        menu.addItem(.sectionHeader(title: "Branches"))
        for branch in ordered.prefix(15) {
            let item = ActionMenuItem(branch.menuTitle(isDefault: branch.name == snap.defaultBranch)) {
                switchTo(branch.name)
            }
            item.state = branch.name == snap.branch ? .on : .off
            menu.addItem(item)
        }
        if ordered.count > 15 {
            menu.addItem(
                submenu(
                    "More Branches",
                    ordered.dropFirst(15).map { branch in
                        ActionMenuItem(branch.menuTitle(isDefault: false)) { switchTo(branch.name) }
                    }))
        }
        if !snap.remoteBranches.isEmpty {
            menu.addItem(
                submenu(
                    "Remote Branches",
                    snap.remoteBranches.map { name in ActionMenuItem(name) { switchTo(name) } }))
        }
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.items = items
        item.submenu = submenu
        return item
    }

    // MARK: Actions

    private func fetchAll() {
        Task { await store.syncAll() }
    }

    @objc private func fetchAllFromKeyboard() {
        guard !store.isSyncingAll, !store.repos.isEmpty else { return }
        fetchAll()
    }
}
