import Foundation

struct LocalBranch: Identifiable, Hashable, Sendable {
    let name: String
    let upstream: String?
    let ahead: Int
    let behind: Int
    let upstreamGone: Bool
    var id: String { name }
}

struct Worktree: Identifiable, Hashable, Sendable {
    let path: URL
    let branch: String?
    let head: String
    let isMain: Bool
    let isLocked: Bool
    /// The folder is gone; `git worktree prune` removes the stale entry.
    let isPrunable: Bool
    var id: URL { path }
    var name: String { path.lastPathComponent }
}

/// Everything Offshoot shows about a repo, read in one pass.
struct RepoSnapshot: Sendable {
    var branch: String?
    var detachedAt: String?
    var upstream: String?
    var ahead = 0
    var behind = 0
    var changes = 0
    var untracked = 0
    var defaultBranch: String?
    var localBranches: [LocalBranch] = []
    var remoteBranches: [String] = []
    /// All worktrees of the repository, the main checkout first.
    var worktrees: [Worktree] = []

    var isDirty: Bool { changes > 0 }
    var isDiverged: Bool { ahead > 0 && behind > 0 }
    var canFastForward: Bool { behind > 0 && ahead == 0 }

    /// Branches checked out in other worktrees of this repository, with that worktree.
    /// git refuses to switch to or update these from here.
    var branchesInOtherWorktrees: [String: Worktree] = [:]

    /// Whether the branch was deleted on the remote, which usually means it was merged.
    func isMerged(_ worktree: Worktree) -> Bool {
        guard let branch = worktree.branch else { return false }
        return localBranches.first { $0.name == branch }?.upstreamGone == true
    }

    /// Worktrees that can be cleaned up: their branch is gone upstream, and they are not
    /// the main checkout, the checkout Offshoot tracks, locked, or already missing.
    var mergedWorktrees: [Worktree] {
        let elsewhere = Set(branchesInOtherWorktrees.values.map(\.path))
        return worktrees.filter {
            !$0.isMain && elsewhere.contains($0.path) && !$0.isLocked && !$0.isPrunable && isMerged($0)
        }
    }

    /// The local default branch, when it isn't checked out here or in another worktree.
    var otherDefault: LocalBranch? {
        guard let name = defaultBranch, name != branch, branchesInOtherWorktrees[name] == nil else { return nil }
        return localBranches.first { $0.name == name }
    }

    static func read(at url: URL) async -> Result<RepoSnapshot, RepoError> {
        async let statusRun = Git.run(["status", "--porcelain=v2", "--branch"], in: url)
        async let localRun = Git.run(
            [
                "for-each-ref", "--sort=-committerdate",
                "--format=%(refname:short)%09%(upstream:short)%09%(upstream:track,nobracket)",
                "refs/heads",
            ], in: url)
        async let remoteRun = Git.run(
            [
                "for-each-ref", "--sort=-committerdate", "--count=60",
                "--format=%(refname:short)", "refs/remotes/origin",
            ], in: url)
        async let headRun = Git.run(["symbolic-ref", "--short", "-q", "refs/remotes/origin/HEAD"], in: url)
        async let worktreeRun = Git.run(["worktree", "list", "--porcelain"], in: url)

        let status = await statusRun
        guard status.ok else { return .failure(RepoError(status.message)) }

        var snap = RepoSnapshot()
        for line in status.output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst("# branch.head ".count))
                snap.branch = head == "(detached)" ? nil : head
            } else if line.hasPrefix("# branch.oid ") {
                snap.detachedAt = String(line.dropFirst("# branch.oid ".count).prefix(7))
            } else if line.hasPrefix("# branch.upstream ") {
                snap.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.split(separator: " ")
                if parts.count >= 4 {
                    snap.ahead = Int(parts[2].dropFirst()) ?? 0
                    snap.behind = Int(parts[3].dropFirst()) ?? 0
                }
            } else if line.hasPrefix("? ") {
                snap.untracked += 1
            } else if !line.hasPrefix("#") && !line.hasPrefix("!") {
                snap.changes += 1
            }
        }
        if snap.branch != nil { snap.detachedAt = nil }

        snap.localBranches = (await localRun).output.split(separator: "\n").compactMap(parseLocal)

        let localNames = Set(snap.localBranches.map(\.name))
        let remoteOutput: String = (await remoteRun).output
        var remotes: [String] = []
        for line in remoteOutput.split(separator: "\n") {
            guard line.hasPrefix("origin/"), line != "origin/HEAD" else { continue }
            let name = String(line.dropFirst("origin/".count))
            if !localNames.contains(name) { remotes.append(name) }
        }
        snap.remoteBranches = remotes

        let head = await headRun
        if head.ok, head.output.hasPrefix("origin/") {
            snap.defaultBranch = String(head.output.dropFirst("origin/".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let known = localNames.union(snap.remoteBranches)
            snap.defaultBranch = ["main", "master", "dev", "develop"].first { known.contains($0) }
        }
        snap.worktrees = parseWorktrees((await worktreeRun).output)
        let here = url.resolvingSymlinksInPath().standardizedFileURL
        for worktree in snap.worktrees where worktree.path != here {
            if let branch = worktree.branch { snap.branchesInOtherWorktrees[branch] = worktree }
        }
        return .success(snap)
    }

    /// Parses `git worktree list --porcelain`: blank-line separated records of
    /// `worktree <path>`, `HEAD <sha>`, `branch <ref>` or `detached`, `locked`, `prunable`.
    static func parseWorktrees(_ output: String) -> [Worktree] {
        output.components(separatedBy: "\n\n").enumerated().compactMap { index, record in
            var path: URL?
            var head = ""
            var branch: String?
            var locked = false
            var prunable = false
            for line in record.split(separator: "\n") {
                if line.hasPrefix("worktree ") {
                    let raw = String(line.dropFirst("worktree ".count))
                    path = URL(fileURLWithPath: raw).resolvingSymlinksInPath().standardizedFileURL
                } else if line.hasPrefix("HEAD ") {
                    head = String(line.dropFirst("HEAD ".count).prefix(7))
                } else if line.hasPrefix("branch refs/heads/") {
                    branch = String(line.dropFirst("branch refs/heads/".count))
                } else if line == "locked" || line.hasPrefix("locked ") {
                    locked = true
                } else if line == "prunable" || line.hasPrefix("prunable ") {
                    prunable = true
                }
            }
            guard let path else { return nil }
            return Worktree(
                path: path, branch: branch, head: head, isMain: index == 0, isLocked: locked, isPrunable: prunable)
        }
    }

    private static func parseLocal(_ line: Substring) -> LocalBranch? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard let name = fields.first, !name.isEmpty else { return nil }
        let upstream = fields.count > 1 && !fields[1].isEmpty ? fields[1] : nil
        let track = fields.count > 2 ? fields[2] : ""
        return LocalBranch(
            name: name,
            upstream: upstream,
            ahead: count(of: "ahead", in: track),
            behind: count(of: "behind", in: track),
            upstreamGone: track == "gone"
        )
    }

    /// Reads N from "ahead N, behind M".
    private static func count(of word: String, in track: String) -> Int {
        guard let range = track.range(of: word + " ") else { return 0 }
        return Int(track[range.upperBound...].prefix { $0.isNumber }) ?? 0
    }
}

struct RepoError: Error, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
}
