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
    /// Destructive rows ("<repo path>|<action>") waiting for a confirming second click.
    private var confirmingActions: Set<String> = []
    /// The preview lines currently shown below an armed confirm row, by the same key.
    private var previewItems: [String: [NSMenuItem]] = [:]

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
        if let repo = submenuRepos[ObjectIdentifier(menu)] {
            confirmingActions = confirmingActions.filter { !$0.hasPrefix("\(repo.id.path)|") }
        }
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
        let worktrees =
            repo.worktreeCleanup.map { "\($0.worktree.name) · \($0.reason.label)" }
            + snap.missingWorktrees.map { "\($0.name) · folder missing" }
        let branches = repo.branchCleanup.map { "\($0.branch.name) · \($0.reason.label)" }
        let cleanups = [
            confirmRow(
                for: repo, key: "worktrees", preview: worktrees, activityPrefix: "Removing",
                title: "Clean Up Worktrees", noun: ("worktree", "worktrees"), verb: "remove", symbol: "trash",
                help: "Removes worktrees whose branch is merged, and records of worktrees whose folder is gone. "
                    + "Folders are deleted with ignored files such as .env or node_modules. Worktrees with "
                    + "uncommitted changes and all branches are kept. Make sure no agent is still working in them."
            ) { await repo.cleanUpWorktrees() },
            confirmRow(
                for: repo, key: "branches", preview: branches, activityPrefix: "Deleting",
                title: "Delete Merged Branches", noun: ("branch", "branches"), verb: "delete",
                symbol: "arrow.triangle.branch",
                help: "Deletes local branches that are merged: fully contained in the default branch, merged as "
                    + "a pull request (with GitHub CLI), or deleted on the remote (without it). The default branch "
                    + "and branches checked out in any worktree are kept. Each branch's last commit is written to "
                    + "the system log (search Console for Offshoot), so `git branch <name> <sha>` restores it "
                    + "within about two weeks."
            ) { await repo.deleteMergedBranches() },
        ].compactMap { $0 }
        cleanups.forEach(menu.addItem)
        if snap.canFastForward || snap.updatableDefault != nil || !cleanups.isEmpty {
            menu.addItem(.separator())
        }
    }

    /// A destructive action that keeps the menu open. A dialog cannot show while the menu stays
    /// open, so the first click lists what will happen right below the row and arms it; a second
    /// click within 15 seconds runs it. The row itself updates in place, so its highlight stays.
    private func confirmRow(
        for repo: Repo, key: String, preview: [String], activityPrefix: String, title: String,
        noun: (one: String, many: String), verb: String, symbol: String, help: String,
        action: @escaping @MainActor () async -> Void
    ) -> NSMenuItem? {
        let count = preview.count
        let isRunning = repo.activity?.hasPrefix(activityPrefix) == true
        guard count > 0 || isRunning else { return nil }

        let confirmKey = "\(repo.id.path)|\(key)"
        let item = NSMenuItem()
        let row = KeepOpenMenuRow(title: "", symbol: symbol)
        row.toolTip = help
        item.view = row

        let update = { [weak self, weak row, weak item] in
            guard let self, let row, let item else { return }
            let confirming = self.confirmingActions.contains(confirmKey)
            let what = count == 1 ? "1 \(noun.one)" : "\(count) \(noun.many)"
            let text =
                isRunning
                ? repo.activity ?? "Working…"
                : confirming ? "Click again to \(verb) \(what)" : "\(title) (\(count))"
            row.update(title: text, isBusy: isRunning, isEnabled: !repo.isBusy || isRunning, isWarning: confirming)
            self.showPreview(confirming && !isRunning ? preview : [], for: confirmKey, below: item)
        }
        row.onClick = { [weak self] in
            guard let self else { return }
            if self.confirmingActions.remove(confirmKey) != nil {
                update()
                Task { await action() }
                return
            }
            self.confirmingActions.insert(confirmKey)
            update()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.confirmingActions.remove(confirmKey) != nil else { return }
                update()
            }
        }
        // Applied once the item is in its menu, so the preview lands below it.
        DispatchQueue.main.async { update() }
        row.update(title: "\(title) (\(count))", isBusy: isRunning, isEnabled: !repo.isBusy || isRunning)
        return item
    }

    /// Inserts (or removes, for an empty list) the indented preview lines below a confirm row.
    private func showPreview(_ lines: [String], for key: String, below item: NSMenuItem) {
        for old in previewItems[key] ?? [] { old.menu?.removeItem(old) }
        previewItems[key] = nil
        guard !lines.isEmpty, let menu = item.menu else { return }
        let limit = 20
        var items = lines.prefix(limit).map { NSMenuItem.note($0) }
        if lines.count > limit { items.append(.note("and \(lines.count - limit) more")) }
        let start = menu.index(of: item) + 1
        for (offset, note) in items.enumerated() {
            note.indentationLevel = 1
            menu.insertItem(note, at: start + offset)
        }
        previewItems[key] = items
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
        if snap.isDirty {
            // git carries changes that don't conflict over to the new branch, which is easy to miss.
            let changes = snap.changes == 1 ? "1 uncommitted change moves" : "\(snap.changes) uncommitted changes move"
            menu.addItem(.note("\(changes) with you when switching"))
        }
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
            let item = NSMenuItem(
                title: Self.title(for: worktree, snap, pullRequests: repo.pullRequests), action: nil, keyEquivalent: "")
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

    private static func title(
        for worktree: Worktree, _ snap: RepoSnapshot, pullRequests: PullRequestData?
    ) -> String {
        var parts = [worktree.isMain ? "\(worktree.name) (main)" : worktree.name]
        parts.append("· \(Repo.truncated(worktree.branch ?? "detached @ \(worktree.head)"))")
        if let branch = worktree.branch, let info = snap.localBranches.first(where: { $0.name == branch }) {
            if info.behind > 0 { parts.append("↓\(info.behind)") }
            if info.ahead > 0 { parts.append("↑\(info.ahead)") }
        }
        if let reason = snap.cleanupReason(for: worktree, pullRequests: pullRequests) {
            parts.append("· \(reason.label)")
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
