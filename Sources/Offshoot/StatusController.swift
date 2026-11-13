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
            addWorktrees(for: repo, snap, to: menu)
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

        let branchItem = { (branch: LocalBranch, isDefault: Bool) -> NSMenuItem in
            let elsewhere = snap.branchesInOtherWorktrees[branch.name]
            let title = branch.menuTitle(isDefault: isDefault) + (elsewhere == nil ? "" : " · in worktree")
            let item = ActionMenuItem(title) { switchTo(branch.name) }
            item.state = branch.name == snap.branch ? .on : .off
            if let elsewhere {
                item.isEnabled = false
                item.toolTip = "Checked out in \(Self.abbreviated(elsewhere.path))"
            }
            return item
        }

        menu.addItem(.sectionHeader(title: "Branches"))
        for branch in ordered.prefix(15) {
            menu.addItem(branchItem(branch, branch.name == snap.defaultBranch))
        }
        if ordered.count > 15 {
            menu.addItem(submenu("More Branches", ordered.dropFirst(15).map { branchItem($0, false) }))
        }
        if !snap.remoteBranches.isEmpty {
            menu.addItem(
                submenu(
                    "Remote Branches",
                    snap.remoteBranches.map { name in ActionMenuItem(name) { switchTo(name) } }))
        }
    }

    /// A Worktrees submenu, shown when the repository has worktrees besides the main checkout.
    private func addWorktrees(for repo: Repo, _ snap: RepoSnapshot, to menu: NSMenu) {
        guard snap.worktrees.count > 1 else { return }
        let here = repo.url.resolvingSymlinksInPath().standardizedFileURL
        let tracked = Set(store.repos.map { $0.url.resolvingSymlinksInPath().standardizedFileURL })

        var items = snap.worktrees.map { worktree -> NSMenuItem in
            let item = NSMenuItem(title: Self.title(for: worktree, snap), action: nil, keyEquivalent: "")
            item.state = worktree.path == here ? .on : .off
            item.toolTip = Self.abbreviated(worktree.path)
            if worktree.isPrunable {
                item.isEnabled = false
                return item
            }
            var actions: [NSMenuItem] = [
                ActionMenuItem("Open in Terminal") { Repo.openInTerminal(worktree.path) },
                ActionMenuItem("Reveal in Finder") { Repo.revealInFinder(worktree.path) },
            ]
            if !tracked.contains(worktree.path) {
                actions.append(.separator())
                actions.append(
                    ActionMenuItem("Add to Offshoot") { [weak self] in
                        Task { await self?.store.add([worktree.path]) }
                    })
            }
            let submenu = NSMenu(title: worktree.name)
            submenu.items = actions
            item.submenu = submenu
            return item
        }
        if snap.worktrees.contains(where: \.isPrunable) {
            items.append(.separator())
            items.append(ActionMenuItem("Remove Missing Worktrees") { Task { await repo.pruneWorktrees() } })
        }
        menu.addItem(submenu("Worktrees (\(snap.worktrees.count))", items))
    }

    private static func title(for worktree: Worktree, _ snap: RepoSnapshot) -> String {
        var parts = [worktree.isMain ? "\(worktree.name) (main)" : worktree.name]
        parts.append("· \(Repo.truncated(worktree.branch ?? "detached @ \(worktree.head)"))")
        if let branch = worktree.branch, let info = snap.localBranches.first(where: { $0.name == branch }) {
            if info.behind > 0 { parts.append("↓\(info.behind)") }
            if info.ahead > 0 { parts.append("↑\(info.ahead)") }
        }
        if worktree.isLocked { parts.append("· locked") }
        if worktree.isPrunable { parts.append("· missing") }
        return parts.joined(separator: " ")
    }

    private static func abbreviated(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
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
