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
    /// Pull requests from GitHub CLI; nil when off, unavailable or not loaded yet.
    private var loadedPullRequests: PullRequestData?
    private var pullRequestsLoadedAt: Date?

    private var feedbackTask: Task<Void, Never>?

    nonisolated var id: URL { url }
    var name: String { url.lastPathComponent }
    var isBusy: Bool { activity != nil }

    var pullRequests: PullRequestData? {
        GitHubCLI.isEnabled ? loadedPullRequests : nil
    }

    var branchCleanup: [BranchCleanup] {
        snapshot?.branchCleanup(pullRequests: pullRequests) ?? []
    }

    var worktreeCleanup: [WorktreeCleanup] {
        snapshot?.worktreeCleanup(pullRequests: pullRequests) ?? []
    }

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
        await loadPullRequests(maxAge: 10 * 60)
    }

    /// Reloads pull requests when GitHub CLI is enabled and the cached list is older than `maxAge`,
    /// then checks which local branches are contained in their merged pull request.
    private func loadPullRequests(maxAge: TimeInterval) async {
        guard GitHubCLI.isEnabled else {
            loadedPullRequests = nil
            pullRequestsLoadedAt = nil
            return
        }
        if pullRequestsLoadedAt.map({ Date.now.timeIntervalSince($0) >= maxAge }) ?? true {
            pullRequestsLoadedAt = .now
            loadedPullRequests = await GitHubCLI.pullRequests(in: url).map { PullRequestData(byBranch: $0) }
        }
        guard var data = loadedPullRequests, let snap = snapshot else { return }
        data.containedCommits = await containedCommits(of: snap.localBranches, in: data.byBranch)
        loadedPullRequests = data
    }

    /// Local branches behind their merged pull request, for example when review fixes were pushed
    /// to the pull request but never pulled. When the pull request's final commit isn't local,
    /// it is fetched from GitHub's permanent `refs/pull/<number>/head`; if that fails, the branch
    /// counts as not contained and is kept.
    private func containedCommits(
        of branches: [LocalBranch], in pullRequests: [String: PullRequest]
    ) async -> Set<String> {
        var contained: Set<String> = []
        for branch in branches {
            guard let pullRequest = pullRequests[branch.name], pullRequest.state == .merged,
                branch.sha != pullRequest.headRefOid
            else { continue }
            let head = pullRequest.headRefOid
            if !(await Git.run(["cat-file", "-e", "\(head)^{commit}"], in: url).ok) {
                _ = await Git.run(["fetch", "--quiet", "origin", "refs/pull/\(pullRequest.number)/head"], in: url)
            }
            let check = await Git.run(["merge-base", "--is-ancestor", branch.sha, head], in: url)
            if check.ok { contained.insert(PullRequestData.key(branch)) }
        }
        return contained
    }

    func switchTo(_ branch: String) async {
        await perform("Switching…", success: "On \(branch)") {
            await Git.run(["switch", branch], in: self.url)
        }
    }

    func pull() async {
        let behind = snapshot?.behind ?? 0
        // fetch + merge --ff-only rather than pull, so a pull.rebase setting never applies.
        await perform("Pulling…", success: "Pulled \(Self.commits(behind))") {
            let fetch = await Git.run(["fetch", "--quiet"], in: self.url)
            guard fetch.ok else { return fetch }
            return await Git.run(["merge", "--ff-only", "--quiet", "@{u}"], in: self.url)
        }
    }

    /// Fast-forwards the default branch from its own upstream, without checking it out.
    /// A refspec without `+` only ever fast-forwards.
    func updateDefault() async {
        guard let target = snapshot?.otherDefault else { return }
        await perform("Updating \(target.name)…", success: "\(target.name) updated") {
            let upstream = await Git.run(
                [
                    "for-each-ref", "--format=%(upstream:remotename)%09%(upstream:remoteref)",
                    "refs/heads/\(target.name)",
                ],
                in: self.url)
            let parts = upstream.output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
            guard parts.count == 2 else {
                return GitResult(status: 1, output: "", error: "\(target.name) has no upstream branch")
            }
            return await Git.run(
                ["fetch", "--quiet", String(parts[0]), "\(parts[1]):refs/heads/\(target.name)"], in: self.url)
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
        await loadPullRequests(maxAge: 0)
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

    /// Deletes the branches `branchCleanup` lists. Right before each deletion it checks that the
    /// branch still points at the previewed commit and, for "merged into" branches, that the commit
    /// is still in the remote default branch. Squash merges need `-D` because git cannot see them
    /// as merged; git still refuses branches checked out anywhere. Each branch's last commit is
    /// logged first, so `git branch <name> <sha>` restores it until git's garbage collection.
    func deleteMergedBranches() async {
        let cleanup = branchCleanup
        guard !isBusy, !cleanup.isEmpty else { return }
        var deleted = 0
        var kept: [String] = []
        for (index, item) in cleanup.enumerated() {
            activity = "Deleting branch \(index + 1) of \(cleanup.count)…"
            guard await isUnchanged(item) else {
                kept.append(item.branch.name)
                continue
            }
            log.notice(
                "\(self.name, privacy: .public): deleting branch \(item.branch.name, privacy: .public) at \(item.branch.sha, privacy: .public) (\(item.reason.label, privacy: .public))"
            )
            let result = await Git.run(["branch", "-D", item.branch.name], in: url)
            if result.ok { deleted += 1 } else { kept.append(item.branch.name) }
        }
        await refresh()
        activity = nil
        let done = deleted == 1 ? "Deleted 1 branch" : "Deleted \(deleted) branches"
        if kept.isEmpty {
            show(.success, done)
        } else {
            show(.failure, "\(done). Kept \(kept.joined(separator: ", ")): changed or checked out meanwhile")
        }
    }

    private func isUnchanged(_ item: BranchCleanup) async -> Bool {
        let current = await Git.run(["rev-parse", "--verify", "--quiet", "refs/heads/\(item.branch.name)"], in: url)
        guard current.output.trimmingCharacters(in: .whitespacesAndNewlines) == item.branch.sha else { return false }
        guard case .mergedIntoDefault(let base) = item.reason else { return true }
        return await Git.run(
            ["merge-base", "--is-ancestor", item.branch.sha, "refs/remotes/origin/\(base)"], in: url
        ).ok
    }

    /// Removes the worktrees `worktreeCleanup` lists and prunes missing ones.
    func cleanUpWorktrees() async {
        guard let snap = snapshot else { return }
        await removeWorktrees(worktreeCleanup.map(\.worktree), pruneMissing: !snap.missingWorktrees.isEmpty)
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
