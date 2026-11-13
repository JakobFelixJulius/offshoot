import Foundation

struct PullRequest: Decodable, Hashable, Sendable {
    enum State: String, Decodable, Sendable {
        case open = "OPEN"
        case closed = "CLOSED"
        case merged = "MERGED"
    }

    let number: Int
    let state: State
    let headRefName: String
    /// The commit the pull request ended on; a local branch still pointing there holds nothing new.
    let headRefOid: String
}

/// Optional pull request lookups through the GitHub CLI (`gh`), so squash-merged branches are
/// recognized by their merged pull request instead of by their remote branch being deleted.
enum GitHubCLI {
    static let settingKey = "useGitHubCLI"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: settingKey) && executable != nil
    }

    static var executable: URL? {
        Command.searchPath.map { URL(fileURLWithPath: "\($0)/gh") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The most recent pull request per head branch, or nil when gh is unavailable, not signed
    /// in, or the repository is not on GitHub.
    static func pullRequests(in repo: URL) async -> [String: PullRequest]? {
        guard let executable else { return nil }
        let result = await Command.run(
            executable,
            [
                "pr", "list", "--state", "all", "--limit", "300",
                "--json", "number,state,headRefName,headRefOid",
            ], in: repo, environment: ["GH_PROMPT_DISABLED": "1", "NO_COLOR": "1"], timeout: 30)
        guard result.ok else { return nil }
        return parse(result.output)
    }

    static func parse(_ json: String) -> [String: PullRequest]? {
        guard let list = try? JSONDecoder().decode([PullRequest].self, from: Data(json.utf8)) else { return nil }
        var latest: [String: PullRequest] = [:]
        for pullRequest in list where pullRequest.number > (latest[pullRequest.headRefName]?.number ?? 0) {
            latest[pullRequest.headRefName] = pullRequest
        }
        return latest
    }
}
