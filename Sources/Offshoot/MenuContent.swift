import SwiftUI

/// The status item's menu. Built from standard menu items only, so it looks and
/// behaves like any system menu (keyboard navigation, VoiceOver, appearance).
struct MenuContent: View {
    let store: RepoStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(store.isSyncingAll ? "Fetching…" : "Fetch All") {
            Task { await store.syncAll() }
        }
        .keyboardShortcut("f")
        .disabled(store.isSyncingAll || store.repos.isEmpty)

        if let summary = store.lastSummary {
            Text(summary)
        }

        Divider()

        if store.repos.isEmpty {
            Text("No repositories")
            Button("Add Repositories…", action: showSettings)
        } else {
            ForEach(store.repos) { repo in
                RepoMenu(repo: repo)
            }
        }

        Divider()

        Button("Settings…", action: showSettings)
            .keyboardShortcut(",")
        Button("Quit Offshoot") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }
}

private struct RepoMenu: View {
    let repo: Repo

    var body: some View {
        Menu {
            if let feedback = repo.feedback, feedback.kind == .failure {
                Text(feedback.text)
                Divider()
            }

            if let snap = repo.snapshot {
                actions(snap)
                branches(snap)
                Divider()
            } else if let error = repo.loadError {
                Text(error)
                Divider()
            }

            Button("Fetch") { Task { await repo.sync(fastForward: false) } }
            Button("Open in Terminal") { repo.openInTerminal() }
            Button("Reveal in Finder") { repo.revealInFinder() }
        } label: {
            Label {
                Text(title)
            } icon: {
                status.image
            }
        }
        .disabled(repo.isBusy)
    }

    @ViewBuilder
    private func actions(_ snap: RepoSnapshot) -> some View {
        let other = snap.otherDefault.flatMap { $0.behind > 0 && $0.ahead == 0 ? $0 : nil }
        if snap.canFastForward {
            Button {
                Task { await repo.pull() }
            } label: {
                Label {
                    Text("Pull \(Self.commits(snap.behind))")
                } icon: {
                    StatusIcon.action("arrow.down.circle.fill", .systemGreen)
                }
            }
        }
        if let other {
            Button {
                Task { await repo.updateDefault() }
            } label: {
                Label {
                    Text("Update \(other.name) (\(Self.commits(other.behind)) behind)")
                } icon: {
                    StatusIcon.action("arrow.down.circle.fill", .systemBlue)
                }
            }
        }
        if snap.canFastForward || other != nil {
            Divider()
        }
    }

    @ViewBuilder
    private func branches(_ snap: RepoSnapshot) -> some View {
        let ordered = Self.ordered(snap)
        Section("Branches") {
            ForEach(ordered.prefix(15)) { branch in
                Toggle(
                    Self.title(for: branch, isDefault: branch.name == snap.defaultBranch),
                    isOn: Binding(
                        get: { branch.name == snap.branch },
                        set: { on in if on { switchTo(branch.name) } }
                    ))
            }
        }
        if ordered.count > 15 {
            Menu("More Branches") {
                ForEach(ordered.dropFirst(15)) { branch in
                    Button(Self.title(for: branch, isDefault: false)) { switchTo(branch.name) }
                }
            }
        }
        if !snap.remoteBranches.isEmpty {
            Menu("Remote Branches") {
                ForEach(snap.remoteBranches, id: \.self) { name in
                    Button(name) { switchTo(name) }
                }
            }
        }
    }

    private func switchTo(_ name: String) {
        Task { await repo.switchTo(name) }
    }

    private var title: String {
        if let activity = repo.activity { return "\(repo.name) · \(activity)" }
        guard let snap = repo.snapshot else { return repo.name }
        var parts = ["\(repo.name) · \(Self.truncated(snap.branch ?? "detached"))"]
        if snap.behind > 0 { parts.append("↓\(snap.behind)") }
        if snap.ahead > 0 { parts.append("↑\(snap.ahead)") }
        if snap.isDirty { parts.append("· \(snap.changes) changed") }
        if let other = snap.otherDefault, other.behind > 0 { parts.append("· \(other.name) ↓\(other.behind)") }
        return parts.joined(separator: " ")
    }

    private var status: StatusIcon {
        if repo.isBusy { return .busy }
        if repo.loadError != nil || repo.feedback?.kind == .failure { return .error }
        guard let snap = repo.snapshot else { return .unknown }
        if snap.isDiverged { return .diverged }
        if snap.behind > 0 || (snap.otherDefault?.behind ?? 0) > 0 { return .behind }
        if snap.isDirty { return .dirty }
        if snap.ahead > 0 { return .ahead }
        return .upToDate
    }

    /// Default branch first, then by most recent commit.
    private static func ordered(_ snap: RepoSnapshot) -> [LocalBranch] {
        guard let name = snap.defaultBranch, let main = snap.localBranches.first(where: { $0.name == name }) else {
            return snap.localBranches
        }
        return [main] + snap.localBranches.filter { $0.name != name }
    }

    private static func title(for branch: LocalBranch, isDefault: Bool) -> String {
        var parts = [branch.name]
        if branch.behind > 0 { parts.append("↓\(branch.behind)") }
        if branch.ahead > 0 { parts.append("↑\(branch.ahead)") }
        if branch.upstreamGone { parts.append("(gone)") }
        if isDefault { parts.append("· default") }
        return parts.joined(separator: " ")
    }

    private static func truncated(_ name: String, limit: Int = 32) -> String {
        guard name.count > limit else { return name }
        let half = (limit - 1) / 2
        return "\(name.prefix(half))…\(name.suffix(half))"
    }

    private static func commits(_ n: Int) -> String {
        n == 1 ? "1 commit" : "\(n) commits"
    }
}
