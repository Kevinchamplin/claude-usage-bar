import AppKit
import Foundation

/// Gets a fresh sign-in without the app ever touching the OAuth refresh token:
/// it asks Claude Code to refresh its own token, and when that is not possible
/// opens `claude auth login` in Terminal. Blocking calls; run off the main thread.
enum ClaudeCLI {
    enum Outcome {
        case refreshed
        case needsLogin(claude: String)
        case notInstalled
    }

    static func refresh() -> Outcome {
        guard let claude = binary() else { return .notInstalled }
        if UsageClient.hasFreshToken() { return .refreshed }
        // Only `loggedIn` is read; the rest of the output is discarded.
        guard let st = run(claude, ["auth", "status", "--json"], timeout: 20),
              let obj = try? JSONSerialization.jsonObject(with: Data(st.utf8)) as? [String: Any],
              obj["loggedIn"] as? Bool == true
        else { return .needsLogin(claude: claude) }
        if UsageClient.hasFreshToken() { return .refreshed }
        // One tiny headless request: Claude Code refreshes its token first.
        _ = run(claude, ["-p", "ok", "--model", "haiku", "--tools", "", "--strict-mcp-config",
                         "--disable-slash-commands", "--setting-sources", "",
                         "--no-session-persistence"], timeout: 60)
        return UsageClient.hasFreshToken() ? .refreshed : .needsLogin(claude: claude)
    }

    /// Writes a .command file and opens it, which macOS runs in Terminal.
    @discardableResult
    static func openLoginInTerminal(claude: String) -> Bool {
        guard let file = writeLoginScript(claude: claude) else { return false }
        return NSWorkspace.shared.open(file)
    }

    static func writeLoginScript(claude: String) -> URL? {
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsageBar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("login.command")
        let quoted = "'" + claude.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = """
        #!/bin/zsh -l
        # Opened by Claude Usage (menu bar) to sign Claude Code in on this Mac.
        clear
        echo "Signing Claude Code in. Finish in your browser; the menu bar updates by itself."
        echo
        \(quoted) auth login
        echo
        echo "Done. You can close this window."

        """
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            return file
        } catch {
            return nil
        }
    }

    /// The LaunchAgent's PATH is minimal, so look in the usual install spots
    /// before asking a login shell.
    static func binary() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let spots = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
                     "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if let hit = spots.first(where: { fm.isExecutableFile(atPath: $0) }) { return hit }
        let found = run("/bin/zsh", ["-lc", "command -v claude"], timeout: 10)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return found.hasPrefix("/") && fm.isExecutableFile(atPath: found) ? found : nil
    }

    /// Runs with a clean environment and a temp cwd, stdout captured, stderr
    /// dropped, killed after `timeout`. Returns nil if it could not start.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        p.environment = [
            "HOME": home,
            "USER": NSUserName(),
            "LANG": "en_US.UTF-8",
            "PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return String(decoding: data, as: UTF8.self)
    }
}
