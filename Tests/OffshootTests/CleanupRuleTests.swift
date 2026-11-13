import Foundation
import Testing

@testable import Offshoot

/// The cleanup rules as pure functions: which branches may go, and why.
struct CleanupRuleTests {
    private func branch(
        _ name: String, upstream: String? = nil, gone: Bool = false, ahead: Int = 0, sha: String = "aaa"
    ) -> LocalBranch {
        LocalBranch(name: name, upstream: upstream, ahead: ahead, behind: 0, upstreamGone: gone, sha: sha)
    }

    private func snapshot(_ branches: [LocalBranch], merged: Set<String> = []) -> RepoSnapshot {
        var snap = RepoSnapshot()
        snap.branch = "main"
        snap.defaultBranch = "main"
        snap.localBranches = [branch("main", upstream: "origin/main")] + branches
        snap.mergedIntoDefault = merged.union(["main"])
        return snap
    }

    private func pr(_ number: Int, _ state: PullRequest.State, head: String, sha: String) -> PullRequest {
        PullRequest(number: number, state: state, headRefName: head, headRefOid: sha)
    }

    @Test func fullyMergedNeedsAnUpstreamAndUsesSafeDelete() {
        let snap = snapshot(
            [branch("merged", upstream: "origin/merged"), branch("fresh")], merged: ["merged", "fresh"])
        let cleanup = snap.branchCleanup(pullRequests: nil)
        #expect(cleanup.map(\.branch.name) == ["merged"])
        #expect(cleanup.first?.reason == .mergedIntoDefault("main"))
    }

    @Test func withoutGitHubADeletedRemoteBranchCounts() {
        let snap = snapshot([
            branch("gone", upstream: "origin/gone", gone: true), branch("alive", upstream: "origin/alive"),
        ])
        #expect(snap.branchCleanup(pullRequests: nil).map(\.reason) == [.remoteDeleted])
    }

    @Test func withGitHubOnlyMergedUnchangedPullRequestsCount() {
        let snap = snapshot([
            branch("squashed", upstream: "origin/squashed", gone: true, sha: "s1"),
            branch("changed-after-merge", upstream: "origin/x", gone: true, sha: "local"),
            branch("behind-merged-pr", upstream: "origin/b", gone: true, sha: "before-review-fix"),
            branch("closed", upstream: "origin/closed", gone: true, sha: "c1"),
            branch("no-pr", upstream: "origin/no-pr", gone: true, sha: "n1"),
            branch("merged-remote-kept", upstream: "origin/kept", ahead: 0, sha: "old"),
            branch("merged-remote-kept-ahead", upstream: "origin/kept2", ahead: 1, sha: "newer"),
            branch("open", upstream: "origin/open", sha: "o1"),
        ])
        let pullRequests = [
            "squashed": pr(1, .merged, head: "squashed", sha: "s1"),
            "changed-after-merge": pr(2, .merged, head: "changed-after-merge", sha: "merged-sha"),
            "closed": pr(3, .closed, head: "closed", sha: "c1"),
            "merged-remote-kept": pr(4, .merged, head: "merged-remote-kept", sha: "remote-sha"),
            "merged-remote-kept-ahead": pr(5, .merged, head: "merged-remote-kept-ahead", sha: "remote-sha"),
            "open": pr(6, .open, head: "open", sha: "o1"),
            "behind-merged-pr": pr(7, .merged, head: "behind-merged-pr", sha: "after-review-fix"),
        ]
        // git merge-base found the local commit inside the merged pull request.
        let behind = branch("behind-merged-pr", upstream: "origin/b", gone: true, sha: "before-review-fix")
        let data = PullRequestData(byBranch: pullRequests, containedCommits: [PullRequestData.key(behind)])
        let cleanup = snap.branchCleanup(pullRequests: data)
        #expect(cleanup.map(\.branch.name) == ["squashed", "behind-merged-pr", "merged-remote-kept"])
        #expect(cleanup.map(\.reason) == [.pullRequestMerged(1), .pullRequestMerged(7), .pullRequestMerged(4)])

        // Without the containment check, the branch behind its PR is kept.
        #expect(
            !snap.branchCleanup(pullRequests: PullRequestData(byBranch: pullRequests)).map(\.branch.name)
                .contains("behind-merged-pr"))
    }

    @Test func neverTheDefaultCurrentOrWorktreeBranch() {
        var snap = snapshot(
            [branch("in-worktree", upstream: "origin/w", gone: true)], merged: ["main", "in-worktree"])
        snap.branchesInOtherWorktrees["in-worktree"] = Worktree(
            path: URL(fileURLWithPath: "/tmp/w"), branch: "in-worktree", head: "", isMain: false, isLocked: false,
            isPrunable: false)
        #expect(snap.branchCleanup(pullRequests: nil).isEmpty)
    }

    @Test func parsesPullRequestsKeepingTheLatestPerBranch() {
        let json = """
            [{"number":3,"state":"CLOSED","headRefName":"a","headRefOid":"x"},
             {"number":9,"state":"MERGED","headRefName":"a","headRefOid":"y"},
             {"number":5,"state":"OPEN","headRefName":"b","headRefOid":"z"}]
            """
        let parsed = GitHubCLI.parse(json)
        #expect(parsed?["a"]?.number == 9)
        #expect(parsed?["a"]?.state == .merged)
        #expect(parsed?["b"]?.state == .open)
        #expect(GitHubCLI.parse("not json") == nil)
    }
}
