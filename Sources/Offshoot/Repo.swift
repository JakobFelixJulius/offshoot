import AppKit
import Foundation
import Observation
import os

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Offshoot", category: "git")

struct Feedback: Equatable {
    enum Kind { case success, failure }
    let kind: Kind
    let text: String
}

@MainActor
@Observable
final class Repo: Identifiable {
    let url: URL
    var snapshot: RepoSnapshot?
    var loadError: String?
    var activity: String?
    var feedback: Feedback?

    private var feedbackTask: Task<Void, Never>?

    nonisolated var id: URL { url }
    var name: String { url.lastPathComponent }
    var isBusy: Bool { activity != nil }

    init(url: URL) {
        self.url = url
    }

    func refresh() async {
        switch await RepoSnapshot.read(at: url) {
        case .success(let snap):
            snapshot = snap
            loadError = nil
        case .failure(let error):
            loadError = error.message
        }
    }

    func switchTo(_ branch: String) async {
        await perform("Switching…", success: "On \(branch)") {
            await Git.run(["switch", branch], in: self.url)
        }
    }

    func pull() async {
        let behind = snapshot?.behind ?? 0
        await perform("Pulling…", success: "Pulled \(Self.commits(behind))") {
            await Git.run(["pull", "--ff-only", "--quiet"], in: self.url)
        }
    }

    /// Fast-forwards the default branch without checking it out.
    func updateDefault() async {
        guard let target = snapshot?.otherDefault else { return }
        await perform("Updating \(target.name)…", success: "\(target.name) updated") {
            await Git.run(["fetch", "--quiet", "origin", "\(target.name):\(target.name)"], in: self.url)
        }
    }

    /// Fetches, then fast-forwards what can move without touching local work.
    /// Returns the number of branches that moved.
    @discardableResult
    func sync(fastForward: Bool) async -> Int {
        guard !isBusy else { return 0 }
        activity = "Fetching…"
        defer { activity = nil }

        var fetch = await Git.run(["fetch", "--all", "--prune", "--quiet"], in: url, timeout: 180)
        // Another git process (an IDE, an agent, another fetcher) holding a ref lock is
        // transient; one retry after it finishes avoids a false error.
        if !fetch.ok, Self.isLockContention(fetch.error) {
            try? await Task.sleep(for: .seconds(2))
            fetch = await Git.run(["fetch", "--all", "--prune", "--quiet"], in: url, timeout: 180)
        }
        guard fetch.ok else {
            await refresh()
            show(.failure, fetch.message)
            return 0
        }
        if feedback?.kind == .failure { feedback = nil }
        await refresh()
        guard fastForward, let snap = snapshot else { return 0 }

        var moved = 0
        var failure: String?
        if snap.branch != nil, snap.upstream != nil, snap.canFastForward, !snap.isDirty {
            let merge = await Git.run(["merge", "--ff-only", "--quiet", "@{u}"], in: url)
            if merge.ok { moved += 1 } else { failure = merge.message }
        }
        if let other = snap.otherDefault, other.upstream != nil, other.behind > 0, other.ahead == 0 {
            let ff = await Git.run(
                ["fetch", "--quiet", ".", "\(other.upstream!):refs/heads/\(other.name)"], in: url)
            if ff.ok { moved += 1 } else { failure = failure ?? ff.message }
        }
        await refresh()
        if let failure {
            show(.failure, failure)
        } else if moved > 0 {
            show(.success, moved == 1 ? "Fast-forwarded" : "Fast-forwarded \(moved) branches")
        }
        return moved
    }

    /// Removes merged worktrees and prunes missing ones, as of the latest snapshot.
    func cleanUpWorktrees() async {
        guard let snap = snapshot else { return }
        await removeWorktrees(snap.mergedWorktrees, pruneMissing: snap.worktrees.contains(where: \.isPrunable))
    }

    /// Removes worktrees with `git worktree remove`, never `--force`: git keeps any worktree
    /// with uncommitted or untracked changes, and those are reported as skipped. Branches stay.
    /// `pruneMissing` also drops the records of worktrees whose folders are already gone.
    func removeWorktrees(_ worktrees: [Worktree], pruneMissing: Bool = false) async {
        guard !isBusy, !worktrees.isEmpty || pruneMissing else { return }
        let total = worktrees.count + (pruneMissing ? 1 : 0)
        activity = "Removing worktrees…"
        var removed = 0
        var skipped: [String] = []
        for (index, worktree) in worktrees.enumerated() {
            activity = "Removing worktree \(index + 1) of \(total)…"
            let result = await Git.run(["worktree", "remove", worktree.path.path], in: url)
            if result.ok { removed += 1 } else { skipped.append(worktree.name) }
        }
        var pruned = false
        if pruneMissing {
            pruned = await Git.run(["worktree", "prune"], in: url).ok
        }
        await refresh()
        activity = nil

        var parts: [String] = []
        if removed > 0 { parts.append(removed == 1 ? "Removed 1 worktree" : "Removed \(removed) worktrees") }
        if pruned { parts.append(parts.isEmpty ? "Cleared missing worktrees" : "cleared missing ones") }
        let done = parts.isEmpty ? "No worktrees removed" : parts.joined(separator: ", ")
        if skipped.isEmpty {
            show(.success, done)
        } else {
            show(.failure, "\(done). Kept \(skipped.joined(separator: ", ")): uncommitted changes")
        }
    }

    func openInTerminal() {
        Self.openInTerminal(url)
    }

    func revealInFinder() {
        Self.revealInFinder(url)
    }

    static func openInTerminal(_ folder: URL) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return
        }
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    static func revealInFinder(_ folder: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func perform(_ label: String, success: String, _ operation: @escaping () async -> GitResult) async {
        guard !isBusy else { return }
        activity = label
        let result = await operation()
        await refresh()
        activity = nil
        show(result.ok ? .success : .failure, result.ok ? success : result.message)
    }

    private func show(_ kind: Feedback.Kind, _ text: String) {
        if kind == .failure { log.error("\(self.name, privacy: .public): \(text, privacy: .public)") }
        feedback = Feedback(kind: kind, text: text)
        feedbackTask?.cancel()
        // Errors stay until the next action; confirmations fade.
        guard kind == .success else { return }
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.feedback = nil
        }
    }

    private static func isLockContention(_ error: String) -> Bool {
        error.contains(".lock") && (error.contains("File exists") || error.contains("cannot lock ref"))
    }
}
