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
    private let fetchAllView = KeepOpenMenuRow(
        title: "Fetch All", symbol: "arrow.triangle.2.circlepath", shortcut: "⌘F")
    private let summaryItem = NSMenuItem()

    private var renderedIDs: [Repo.ID]?
    private var repoItems: [Repo.ID: NSMenuItem] = [:]
    private var submenuRepos: [ObjectIdentifier: Repo] = [:]
    private var openSubmenus: Set<ObjectIdentifier> = []
    /// Repositories whose Clean Up Worktrees row waits for a confirming second click.
    private var confirmingCleanup: Set<Repo.ID> = []

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
        fetchAllView.update(
            title: store.isSyncingAll ? "Fetching…" : "Fetch All", isBusy: store.isSyncingAll,
            isEnabled: !store.repos.isEmpty)
        summaryItem.title = store.lastSummary ?? ""
        summaryItem.isHidden = store.lastSummary == nil

        for repo in store.repos {
            guard let item = repoItems[repo.id] else { continue }
            item.title = repo.menuTitle
            // Stays enabled while busy: disabling it would close its open submenu.
            item.image = repo.status.image
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
        observeSubmenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        openSubmenus.insert(ObjectIdentifier(menu))
    }

    func menuDidClose(_ menu: NSMenu) {
        openSubmenus.remove(ObjectIdentifier(menu))
        if let repo = submenuRepos[ObjectIdentifier(menu)] { confirmingCleanup.remove(repo.id) }
    }

    /// Builds a repository submenu and rebuilds it whenever that repository changes while
    /// the submenu is open, so cleanup progress and results appear in place.
    private func observeSubmenu(_ menu: NSMenu) {
        guard let repo = submenuRepos[ObjectIdentifier(menu)] else { return }
        let id = repo.id
        withObservationTracking {
            build(menu, for: repo)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let menu = self.repoItems[id]?.submenu,
                    self.openSubmenus.contains(ObjectIdentifier(menu))
                else { return }
                self.observeSubmenu(menu)
            }
        }
    }

    private func build(_ menu: NSMenu, for repo: Repo) {
        menu.removeAllItems()

        if let feedback = repo.feedback {
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
        let cleanup = cleanupItem(for: repo, snap)
        if let cleanup { menu.addItem(cleanup) }
        if snap.canFastForward || snap.updatableDefault != nil || cleanup != nil {
            menu.addItem(.separator())
        }
    }

    /// Clean Up Worktrees removes merged worktrees and prunes missing ones. It confirms
    /// inline, with a second click within 5 seconds, because a dialog cannot show while the
    /// menu stays open.
    private func cleanupItem(for repo: Repo, _ snap: RepoSnapshot) -> NSMenuItem? {
        let count = snap.mergedWorktrees.count + snap.worktrees.filter(\.isPrunable).count
        let isRemoving = repo.activity?.hasPrefix("Removing") == true
        guard count > 0 || isRemoving else { return nil }

        let row = KeepOpenMenuRow(title: "", symbol: "trash")
        row.toolTip =
            "Removes worktrees whose branch was deleted on the remote, and records of worktrees whose folder "
            + "is gone. Folders are deleted with ignored files such as .env or node_modules. Worktrees with "
            + "uncommitted changes and all branches are kept. Make sure no agent is still working in them."
        let update = { [weak self, weak row] in
            guard let self, let row else { return }
            let confirming = self.confirmingCleanup.contains(repo.id)
            let noun = count == 1 ? "1 worktree" : "\(count) worktrees"
            let title =
                isRemoving
                ? repo.activity ?? "Removing…"
                : confirming ? "Click again to remove \(noun)" : "Clean Up Worktrees (\(count))"
            row.update(title: title, isBusy: isRemoving, isEnabled: !repo.isBusy || isRemoving, isWarning: confirming)
        }
        update()
        // The confirm state updates this row in place, so the hover highlight stays.
        row.onClick = { [weak self] in
            guard let self else { return }
            if self.confirmingCleanup.remove(repo.id) != nil {
                update()
                Task { await repo.cleanUpWorktrees() }
                return
            }
            self.confirmingCleanup.insert(repo.id)
            update()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.confirmingCleanup.remove(repo.id) != nil else { return }
                update()
            }
        }
        let item = NSMenuItem()
        item.view = row
        return item
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

        let items = snap.worktrees.map { worktree -> NSMenuItem in
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
            let canAdd = !tracked.contains(worktree.path)
            let canRemove = !worktree.isMain && worktree.path != here && !worktree.isLocked
            if canAdd || canRemove { actions.append(.separator()) }
            if canAdd {
                actions.append(
                    ActionMenuItem("Add to Offshoot") { [weak self] in
                        Task { await self?.store.add([worktree.path]) }
                    })
            }
            if canRemove {
                actions.append(
                    ActionMenuItem("Remove Worktree…") {
                        Self.confirmRemoval(of: worktree, in: repo)
                    })
            }
            let submenu = NSMenu(title: worktree.name)
            submenu.items = actions
            item.submenu = submenu
            return item
        }
        menu.addItem(submenu("Worktrees (\(snap.worktrees.count))", items))
    }

    /// Asks before deleting a worktree folder: ignored files such as `.env` or `node_modules`
    /// go with it, and an agent may still be working in it.
    private static func confirmRemoval(of worktree: Worktree, in repo: Repo) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove the worktree “\(worktree.name)”?"
        alert.informativeText = """
            The folder is deleted, including ignored files such as .env or node_modules. \
            The branch is kept, and git refuses if the worktree has uncommitted changes. \
            Make sure no agent is still working in it.
            """
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await repo.removeWorktrees([worktree]) }
    }

    private static func title(for worktree: Worktree, _ snap: RepoSnapshot) -> String {
        var parts = [worktree.isMain ? "\(worktree.name) (main)" : worktree.name]
        parts.append("· \(Repo.truncated(worktree.branch ?? "detached @ \(worktree.head)"))")
        if let branch = worktree.branch, let info = snap.localBranches.first(where: { $0.name == branch }) {
            if info.behind > 0 { parts.append("↓\(info.behind)") }
            if info.ahead > 0 { parts.append("↑\(info.ahead)") }
        }
        if snap.isMerged(worktree) { parts.append("· merged") }
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
