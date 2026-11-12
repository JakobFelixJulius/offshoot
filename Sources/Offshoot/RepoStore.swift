import AppKit
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class RepoStore {
    private(set) var repos: [Repo] = []
    private(set) var isSyncingAll = false
    private(set) var lastFetch: Date?
    private(set) var lastSummary: String?
    private(set) var loginItemStatus: SMAppService.Status = .notRegistered

    /// 0 turns background fetching off.
    var autoFetchMinutes: Int {
        didSet {
            UserDefaults.standard.set(autoFetchMinutes, forKey: Keys.autoFetchMinutes)
            scheduleAutoFetch()
        }
    }

    static let autoFetchChoices = [0, 5, 15, 30, 60]

    private enum Keys {
        static let paths = "repoPaths"
        static let autoFetchMinutes = "autoFetchMinutes"
    }

    private var lastRefresh = Date.distantPast
    private var autoFetchTask: Task<Void, Never>?
    private var localRefreshTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        autoFetchMinutes = defaults.object(forKey: Keys.autoFetchMinutes) as? Int ?? 15
        repos = (defaults.stringArray(forKey: Keys.paths) ?? []).map { Repo(url: URL(fileURLWithPath: $0)) }
        updateLoginItemStatus()

        // Refresh local state whenever the menu opens, so it never shows stale branches.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        }

        localRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        scheduleAutoFetch()
    }

    /// Repos with something to pull, shown as the menu bar count.
    var behindCount: Int {
        repos.filter { repo in
            guard let snap = repo.snapshot else { return false }
            return snap.behind > 0 || (snap.otherDefault?.behind ?? 0) > 0
        }.count
    }

    func refreshAll() async {
        lastRefresh = .now
        await withTaskGroup(of: Void.self) { group in
            for repo in repos { group.addTask { await repo.refresh() } }
        }
    }

    func syncAll(fastForward: Bool = true) async {
        guard !isSyncingAll else { return }
        isSyncingAll = true
        defer { isSyncingAll = false }

        let moved = await withTaskGroup(of: Int.self) { group in
            for repo in repos { group.addTask { await repo.sync(fastForward: fastForward) } }
            var total = 0
            for await count in group { total += count }
            return total
        }
        lastFetch = .now
        let failed = repos.filter { $0.feedback?.kind == .failure }.count
        if failed > 0 {
            lastSummary = failed == 1 ? "1 repository failed" : "\(failed) repositories failed"
        } else if fastForward {
            lastSummary =
                moved == 0 ? "Everything up to date" : (moved == 1 ? "Updated 1 branch" : "Updated \(moved) branches")
        }
    }

    // MARK: Repository list

    func add(_ urls: [URL]) async {
        for picked in urls {
            let top = await Git.run(["rev-parse", "--show-toplevel"], in: picked)
            guard top.ok else { continue }
            let url = URL(fileURLWithPath: top.output.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !repos.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { continue }
            let repo = Repo(url: url)
            repos.append(repo)
            await repo.refresh()
        }
        save()
    }

    func remove(_ ids: Set<Repo.ID>) {
        repos.removeAll { ids.contains($0.id) }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        repos.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        updateLoginItemStatus()
    }

    func updateLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }

    // MARK: Private

    private func refreshSoon() {
        guard Date.now.timeIntervalSince(lastRefresh) > 3 else { return }
        Task { await refreshAll() }
    }

    /// Background fetches never fast-forward: an agent may be working in a checkout.
    private func scheduleAutoFetch() {
        autoFetchTask?.cancel()
        guard autoFetchMinutes > 0 else { return }
        let interval = Duration.seconds(autoFetchMinutes * 60)
        autoFetchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self?.syncAll(fastForward: false)
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(repos.map(\.url.path), forKey: Keys.paths)
    }
}
