import AppKit
import Foundation

/// In-app updater for builds installed from a local git clone via install.sh.
///
/// install.sh embeds the clone path and the built commit into Info.plist
/// (SDRepoPath / SDBuildCommit). "Check for Updates" fetches that clone's
/// remote, and if the tracked branch is ahead, pulls, re-runs install.sh, and
/// relaunches. Using the local clone's git means we reuse whatever credentials
/// that machine already has for the (private) repo — no embedded tokens.
final class UpdateManager {
    static let shared = UpdateManager()

    private let gitPath = "/usr/bin/git"

    var repoPath: String? {
        (Bundle.main.object(forInfoDictionaryKey: "SDRepoPath") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    var buildCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "SDBuildCommit") as? String
    }

    /// True when this build knows how to update itself (installed from a clone
    /// that still exists and has an install.sh). App Store builds return false.
    var canSelfUpdate: Bool {
        guard let repo = repoPath else { return false }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: repo + "/.git", isDirectory: &isDir)
            && fm.fileExists(atPath: repo + "/install.sh")
    }

    struct Status { let behind: Int; let latestShort: String; let branch: String }

    // MARK: - Check

    /// Fetch the clone's remote and report how many commits behind upstream it is.
    func check(completion: @escaping (Result<Status, Error>) -> Void) {
        guard let repo = repoPath else {
            completion(.failure(Self.err("This build has no linked source repo.")))
            return
        }
        DispatchQueue.global(qos: .utility).async {
            do {
                _ = try self.git(repo, ["fetch", "--quiet", "origin"])
                var branch = try self.git(repo, ["rev-parse", "--abbrev-ref", "HEAD"]).trimmed
                if branch.isEmpty || branch == "HEAD" { branch = "main" }
                let upstream = "origin/\(branch)"
                let behind = Int(try self.git(repo, ["rev-list", "--count", "HEAD..\(upstream)"]).trimmed) ?? 0
                let latest = (try? self.git(repo, ["rev-parse", "--short", upstream]).trimmed) ?? ""
                DispatchQueue.main.async {
                    completion(.success(Status(behind: behind, latestShort: latest, branch: branch)))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Update

    /// Pull, rebuild/install, then relaunch the freshly installed app.
    func performUpdate(progress: @escaping (String) -> Void,
                       done: @escaping (Result<Void, Error>) -> Void) {
        guard let repo = repoPath else {
            done(.failure(Self.err("This build has no linked source repo.")))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                DispatchQueue.main.async { progress("Pulling latest changes…") }
                _ = try self.git(repo, ["pull", "--ff-only", "origin"])
                DispatchQueue.main.async { progress("Building and installing…") }
                try self.runInstall(repo)
                DispatchQueue.main.async {
                    progress("Relaunching…")
                    self.scheduleRelaunch()
                    done(.success(()))
                }
            } catch {
                DispatchQueue.main.async { done(.failure(error)) }
            }
        }
    }

    // MARK: - Shell helpers

    @discardableResult
    private func git(_ repo: String, _ args: [String]) throws -> String {
        try run(gitPath, ["-C", repo] + args)
    }

    private func runInstall(_ repo: String) throws {
        _ = try run("/bin/bash", [repo + "/install.sh"], cwd: repo)
    }

    @discardableResult
    private func run(_ launchPath: String, _ args: [String], cwd: String? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        if let cwd = cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe(), errPipe = Pipe()
        p.standardOutput = out
        p.standardError = errPipe
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? ""
            throw Self.err(msg.isEmpty ? "Command failed (\(p.terminationStatus))." : msg.trimmed)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Spawn a detached helper that waits for this app to quit, then relaunches it.
    private func scheduleRelaunch() {
        let appPath = Bundle.main.bundlePath
        let script = "sleep 1; /usr/bin/open \"\(appPath)\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()  // detached; not waited
    }

    private static func err(_ message: String) -> NSError {
        NSError(domain: "ScreenDivider.Update", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
