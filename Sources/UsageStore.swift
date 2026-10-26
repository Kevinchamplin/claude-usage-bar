import Foundation

struct ViewState {
    var usage: Usage?
    var error: String?
    var sleeping = false
    var loading = false
    var lastFetch: Date?
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
        }
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}
