import Foundation
import Testing

@testable import Offshoot

/// Exercises Offshoot's git actions against a throwaway origin with two clones:
/// `work` is the checkout Offshoot manages, `other` pushes new commits.
@MainActor
@Suite(.serialized)
struct RepoTests {
    let root: URL
    let work: URL
    let other: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "offshoot-tests-\(UUID().uuidString)")
        work = root.appending(path: "work")
        other = root.appending(path: "other")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try sh("git init -q --bare -b main origin.git", in: root)
        try sh("git clone -q origin.git seed", in: root)
        let seed = root.appending(path: "seed")
        try sh("echo one > file && git add file && git commit -qm one && git push -q origin main", in: seed)
        try sh("git clone -q origin.git work && git clone -q origin.git other", in: root)
    }

    @Test func snapshotReadsBranchAndDefault() async throws {
        let snap = try await RepoSnapshot.read(at: work).get()
        #expect(snap.branch == "main")
        #expect(snap.upstream == "origin/main")
        #expect(snap.defaultBranch == "main")
        #expect(snap.behind == 0 && snap.ahead == 0 && !snap.isDirty)
    }

    @Test func fetchAllFastForwardsCleanCheckout() async throws {
        try push("two")
        let repo = Repo(url: work)
        let moved = await repo.sync(fastForward: true)
        #expect(moved == 1)
        #expect(repo.snapshot?.behind == 0)
        #expect(try head(work) == head(other))
    }

    @Test func autoFetchOnlyFetches() async throws {
        try push("two")
        let repo = Repo(url: work)
        await repo.sync(fastForward: false)
        #expect(repo.snapshot?.behind == 1)
        #expect(repo.snapshot?.canFastForward == true)
    }

    @Test func dirtyCheckoutIsNotMerged() async throws {
        try push("two")
        try sh("echo local > file", in: work)
        let repo = Repo(url: work)
        await repo.sync(fastForward: true)
        #expect(repo.snapshot?.behind == 1)
        #expect(repo.snapshot?.isDirty == true)
    }

    @Test func pullFastForwards() async throws {
        try push("two")
        let repo = Repo(url: work)
        await repo.sync(fastForward: false)
        await repo.pull()
        #expect(repo.snapshot?.behind == 0)
        #expect(repo.feedback?.kind == .success)
    }

    @Test func defaultBranchUpdatesWithoutCheckout() async throws {
        try sh("git switch -q -c feature", in: work)
        try push("two")
        let repo = Repo(url: work)
        await repo.sync(fastForward: false)
        #expect(repo.snapshot?.otherDefault?.behind == 1)

        await repo.updateDefault()
        #expect(repo.snapshot?.branch == "feature")
        #expect(repo.snapshot?.otherDefault?.behind == 0)

        try push("three")
        await repo.sync(fastForward: true)
        #expect(repo.snapshot?.branch == "feature")
        #expect(repo.snapshot?.otherDefault?.behind == 0)
    }

    @Test func switchesToLocalAndRemoteBranches() async throws {
        try sh(
            "git switch -q -c teammate && echo t > t && git add t && git commit -qm t && git push -q origin teammate",
            in: other)
        let repo = Repo(url: work)
        await repo.sync(fastForward: false)
        #expect(repo.snapshot?.remoteBranches.contains("teammate") == true)

        await repo.switchTo("teammate")
        #expect(repo.snapshot?.branch == "teammate")
        #expect(repo.snapshot?.upstream == "origin/teammate")

        await repo.switchTo("main")
        #expect(repo.snapshot?.branch == "main")
        #expect(repo.snapshot?.localBranches.map(\.name).contains("teammate") == true)
    }

    @Test func failedSwitchReportsGitError() async throws {
        let repo = Repo(url: work)
        await repo.switchTo("does-not-exist")
        #expect(repo.feedback?.kind == .failure)
        #expect(repo.snapshot?.branch == "main")
    }

    // MARK: Helpers

    private func push(_ content: String) throws {
        try sh(
            "git switch -q main && git pull -q && echo \(content) > file && git commit -qam \(content) && git push -q origin main",
            in: other)
    }

    private func head(_ url: URL) throws -> String {
        try sh("git rev-parse main", in: url)
    }

    @discardableResult
    private func sh(_ command: String, in dir: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["GIT_AUTHOR_NAME"] = "Offshoot Test"
        env["GIT_AUTHOR_EMAIL"] = "test@example.invalid"
        env["GIT_COMMITTER_NAME"] = "Offshoot Test"
        env["GIT_COMMITTER_EMAIL"] = "test@example.invalid"
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RepoError("`\(command)` failed with \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
