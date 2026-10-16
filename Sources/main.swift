import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    MainActor.assumeIsolated { Snapshot.run(dir: args[i + 1]) }
    exit(0)
}

// `--check` runs one real fetch and prints the numbers (never the token),
// so a broken sign-in can be diagnosed from a terminal.
if args.contains("--check") {
    let done = DispatchSemaphore(value: 0)
    var code: Int32 = 0
    Task.detached {
        switch await UsageClient.fetch() {
        case .success(let u):
            if let s = u.session {
                print("session  \(Int(s.percent.rounded()))%  \(s.severity)  resets \(s.resetsAt.map { "\($0)" } ?? "-")")
            }
            for w in u.weekly { print("\(w.label)  \(Int(w.percent.rounded()))%") }
        case .failure(let e):
            print("error: \(e.message)")
            code = 1
        }
        done.signal()
    }
    done.wait()
    exit(code)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    AppDelegate.shared = delegate
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
