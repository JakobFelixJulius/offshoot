import Foundation

/// How a repository is described in the menu.
extension Repo {
    var menuTitle: String {
        if let activity { return "\(name) · \(activity)" }
        guard let snap = snapshot else { return name }
        var parts = ["\(name) · \(Self.truncated(snap.branch ?? "detached"))"]
        if snap.behind > 0 { parts.append("↓\(snap.behind)") }
        if snap.ahead > 0 { parts.append("↑\(snap.ahead)") }
        if snap.isDirty { parts.append("· \(snap.changes) changed") }
        if let other = snap.otherDefault, other.behind > 0 { parts.append("· \(other.name) ↓\(other.behind)") }
        return parts.joined(separator: " ")
    }

    var status: StatusIcon {
        if isBusy { return .busy }
        if loadError != nil || feedback?.kind == .failure { return .error }
        guard let snap = snapshot else { return .unknown }
        if snap.isDiverged { return .diverged }
        if snap.behind > 0 || (snap.otherDefault?.behind ?? 0) > 0 { return .behind }
        if snap.isDirty { return .dirty }
        if snap.ahead > 0 { return .ahead }
        return .upToDate
    }

    static func truncated(_ text: String, limit: Int = 32) -> String {
        guard text.count > limit else { return text }
        let half = (limit - 1) / 2
        return "\(text.prefix(half))…\(text.suffix(half))"
    }

    static func commits(_ n: Int) -> String {
        n == 1 ? "1 commit" : "\(n) commits"
    }
}

extension RepoSnapshot {
    /// Default branch first, then by most recent commit.
    var orderedLocalBranches: [LocalBranch] {
        guard let name = defaultBranch, let main = localBranches.first(where: { $0.name == name }) else {
            return localBranches
        }
        return [main] + localBranches.filter { $0.name != name }
    }

    /// The default branch when it is behind and can fast-forward without a checkout.
    var updatableDefault: LocalBranch? {
        guard let other = otherDefault, other.behind > 0, other.ahead == 0 else { return nil }
        return other
    }
}

extension LocalBranch {
    func menuTitle(isDefault: Bool) -> String {
        var parts = [name]
        if behind > 0 { parts.append("↓\(behind)") }
        if ahead > 0 { parts.append("↑\(ahead)") }
        if upstreamGone { parts.append("(gone)") }
        if isDefault { parts.append("· default") }
        return parts.joined(separator: " ")
    }
}
