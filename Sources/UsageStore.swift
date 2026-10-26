import Foundation

struct ViewState {
    var usage: Usage?
    var error: String?
    var sleeping = false
    var loading = false
    var lastFetch: Date?
    var signingIn = false
    var signInNote: String?
}

/// Polls the usage API every 60s. Backs off on 429 (honouring Retry-After),
/// keeps the last good numbers on screen when a poll fails, and refreshes on
/// open when stale, but never earlier than the backoff allows.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var state = ViewState()
    @Published var isOpen = false

    private var timer: Timer?
    private var interval: TimeInterval = 60
    private var inFlight = false
    private var lastAttempt: Date?
    /// Set by a 429; opening the popover does not poll before this.
    private var nextAllowed = Date.distantPast
    /// One sign-in at a time: two overlapping refreshes is the token
    /// rotation race the README warns about.
    private var signInBusy = false
    private var lastAutoSignIn: Date?

    func start() {
        refresh()
    }

    func popoverOpened() {
        isOpen = true
        let now = Date()
        if now < nextAllowed { return }
        if let last = lastAttempt, now.timeIntervalSince(last) < 20 { return }
        refresh()
    }

    func popoverClosed() { isOpen = false }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        lastAttempt = Date()
        state.loading = true
        Task {
            let result = await UsageClient.fetch()
            apply(result)
        }
    }

    /// The Sign in button. Asks Claude Code to refresh its own token, and only
    /// if that fails opens `claude auth login` in Terminal and waits for it.
    func signIn() { startSignIn(interactive: true) }

    private func startSignIn(interactive: Bool) {
        guard !signInBusy else { return }
        signInBusy = true
        if interactive {
            state.signingIn = true
            state.signInNote = "Asking Claude Code to refresh…"
        }
        Task {
            let outcome = await Task.detached { ClaudeCLI.refresh() }.value
            await handle(outcome, interactive: interactive)
        }
    }

    private func handle(_ outcome: ClaudeCLI.Outcome, interactive: Bool) async {
        switch outcome {
        case .refreshed:
            finishSignIn()
            refresh()
        case .notInstalled:
            finishSignIn()
            if interactive {
                state.error = "Claude Code isn't installed on this Mac. Install it and sign in, then try again."
            }
        case .needsLogin(let claude):
            // The silent attempt never opens a window; only the button does.
            guard interactive, ClaudeCLI.openLoginInTerminal(claude: claude) else {
                finishSignIn()
                return
            }
            state.signInNote = "Finish signing in in Terminal and your browser…"
            for _ in 0..<120 {   // up to 10 minutes
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !state.signingIn { return }   // a normal poll already got a token
                if await Task.detached(operation: { UsageClient.hasFreshToken() }).value {
                    finishSignIn()
                    refresh()
                    return
                }
            }
            finishSignIn()
        }
    }

    private func finishSignIn() {
        signInBusy = false
        state.signingIn = false
        state.signInNote = nil
    }

    private func apply(_ result: Result<Usage, UsageError>) {
        inFlight = false
        state.loading = false
        switch result {
        case .success(let usage):
            state.usage = usage
            state.error = nil
            state.sleeping = false
            state.lastFetch = Date()
            interval = 60
            nextAllowed = .distantPast
            finishSignInIfIdle()
        case .failure(let err):
            state.error = err.message
            state.sleeping = err.isAuth
            if case .rateLimited(let retryAfter) = err {
                let backoff = min(max(interval, 60) * 2, 900)
                interval = max(backoff, min(retryAfter ?? 0, 3600))
                nextAllowed = Date().addingTimeInterval(interval)
            } else {
                // Expired/no token costs no request, so checking each minute
                // picks up Claude Code's refreshed token quickly.
                interval = 60
                nextAllowed = .distantPast
            }
            // An expired token on a Mac where Claude Code isn't running: ask it
            // to refresh quietly, at most every 30 minutes.
            if case .expired = err, Date().timeIntervalSince(lastAutoSignIn ?? .distantPast) > 1800 {
                lastAutoSignIn = Date()
                startSignIn(interactive: false)
            }
        }
        schedule()
    }

    /// A fresh token turned up some other way (Claude Code ran): stop waiting.
    private func finishSignInIfIdle() {
        if state.signingIn { finishSignIn() }
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}
