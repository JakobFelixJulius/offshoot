import Foundation

struct GitResult: Sendable {
    let status: Int32
    let output: String
    let error: String

    var ok: Bool { status == 0 }

    /// The first meaningful line git printed, for showing in the UI.
    var message: String {
        let text = error.isEmpty ? output : error
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("fatal: ") || $0.hasPrefix("error: ") ? String($0.dropFirst(7)) : $0 }
            .filter { !$0.isEmpty && !$0.hasPrefix("hint:") }
        return lines.first ?? "git exited with status \(status)"
    }
}

enum Git {
    /// GUI apps don't inherit the shell's PATH, so git is called by absolute path.
    static let executable = URL(fileURLWithPath: "/usr/bin/git")

    static func run(_ arguments: [String], in directory: URL, timeout: TimeInterval = 120) async -> GitResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(arguments, in: directory, timeout: timeout))
            }
        }
    }

    private static func runBlocking(_ arguments: [String], in directory: URL, timeout: TimeInterval) -> GitResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory

        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "C"
        // Hooks (husky, lfs) expect Homebrew tools on PATH.
        env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
            .joined(separator: ":")
        process.environment = env

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return GitResult(status: -1, output: "", error: error.localizedDescription)
        }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // Drain stderr on its own thread so a full pipe can't deadlock stdout.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()

        return GitResult(
            status: process.terminationStatus,
            output: String(decoding: outData, as: UTF8.self),
            error: String(decoding: errBox.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
