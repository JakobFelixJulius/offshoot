import Foundation

/// Why a local branch (or its worktree) is no longer needed.
enum CleanupReason: Hashable, Sendable {
    /// Every commit is in the remote default branch; git itself can prove it.
    case mergedIntoDefault(String)
    /// Its pull request was merged and holds every commit of the local branch.
    case pullRequestMerged(Int)
    /// The remote branch was deleted, which usually follows a merge. Used without GitHub CLI.
    case remoteDeleted

    var label: String {
        switch self {
        case .mergedIntoDefault(let base): "merged into \(base)"
        case .pullRequestMerged(let number): "PR #\(number) merged"
        case .remoteDeleted: "deleted on remote"
        }
    }
}

/// Pull requests by head branch, plus local branch commits verified to be contained in their
/// merged pull request (`git merge-base --is-ancestor`). Those are keyed by branch and commit,
/// so a branch that gets new commits after the check no longer counts as contained.
struct PullRequestData: Sendable {
    var byBranch: [String: PullRequest]
    var containedCommits: Set<String> = []

    static func key(_ branch: LocalBranch) -> String {
        "\(branch.name)\t\(branch.sha)"
    }

    func isContained(_ branch: LocalBranch) -> Bool {
        containedCommits.contains(Self.key(branch))
    }
}

struct BranchCleanup: Hashable, Sendable {
    let branch: LocalBranch
    let reason: CleanupReason
}

struct WorktreeCleanup: Hashable, Sendable {
    let worktree: Worktree
    let reason: CleanupReason
}

extension RepoSnapshot {
    /// The cleanup reason for a branch, or nil to keep it. `pullRequests` is nil when GitHub CLI
    /// is off or unavailable; then a deleted remote branch is taken as a sign of a merge.
    func cleanupReason(for branch: LocalBranch, pullRequests: PullRequestData?) -> CleanupReason? {
        guard let base = defaultBranch, branch.name != base else { return nil }
        // A branch that was never pushed may be brand new, with no commits of its own yet.
        if mergedIntoDefault.contains(branch.name), branch.upstream != nil {
            return .mergedIntoDefault(base)
        }
        if let pullRequests {
            guard let pullRequest = pullRequests.byBranch[branch.name], pullRequest.state == .merged else {
                return nil
            }
            // Nothing local is lost: the branch is what was merged, is contained in it, or is
            // not ahead of a remote branch that still exists.
            let contained =
                branch.sha == pullRequest.headRefOid || pullRequests.isContained(branch)
                || (branch.upstream != nil && !branch.upstreamGone && branch.ahead == 0)
            return contained ? .pullRequestMerged(pullRequest.number) : nil
        }
        return branch.upstreamGone ? .remoteDeleted : nil
    }

    /// Branches to delete: not checked out here or in any worktree.
    func branchCleanup(pullRequests: PullRequestData?) -> [BranchCleanup] {
        localBranches.compactMap { branch in
            guard branch.name != self.branch, branchesInOtherWorktrees[branch.name] == nil,
                let reason = cleanupReason(for: branch, pullRequests: pullRequests)
            else { return nil }
            return BranchCleanup(branch: branch, reason: reason)
        }
    }

    /// Worktrees to remove: their branch is done, and they are not the main checkout, the
    /// checkout Offshoot tracks, locked, or already missing.
    func worktreeCleanup(pullRequests: PullRequestData?) -> [WorktreeCleanup] {
        let removable = Set(branchesInOtherWorktrees.values.map(\.path))
        return worktrees.compactMap { worktree in
            guard !worktree.isMain, removable.contains(worktree.path), !worktree.isLocked, !worktree.isPrunable,
                let reason = cleanupReason(for: worktree, pullRequests: pullRequests)
            else { return nil }
            return WorktreeCleanup(worktree: worktree, reason: reason)
        }
    }

    func cleanupReason(for worktree: Worktree, pullRequests: PullRequestData?) -> CleanupReason? {
        guard let name = worktree.branch, let branch = localBranches.first(where: { $0.name == name }) else {
            return nil
        }
        return cleanupReason(for: branch, pullRequests: pullRequests)
    }

    var missingWorktrees: [Worktree] {
        worktrees.filter(\.isPrunable)
    }
}
