import Foundation

struct ViewState {
    var usage: Usage?
    var error: String?
    var sleeping = false
    var loading = false
    var lastFetch: Date?
}

/// Polls the usage API every 60s. Backs off on 429, keeps the last good
/// numbers on screen when a poll fails, and refreshes on open when stale.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var state = ViewState()
    @Published var isOpen = false

    private var timer: Timer?
    private var interval: TimeInterval = 60
    private var inFlight = false

    func start() {
        refresh()
    }

    func popoverOpened() {
        isOpen = true
        if let last = state.lastFetch, Date().timeIntervalSince(last) < 20 { return }
        refresh()
    }

    func popoverClosed() { isOpen = false }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
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
        case .failure(let err):
            state.error = err.message
            state.sleeping = err.isAuth
            if case .rateLimited = err {
                interval = min(interval * 2, 600)
            } else {
                interval = 60
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
