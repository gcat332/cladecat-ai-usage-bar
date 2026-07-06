import Foundation

struct ProviderRefreshState {
    let baseInterval: TimeInterval
    let maxInterval: TimeInterval
    var interval: TimeInterval
    var isRefreshing = false
    var didAttemptTokenRefresh = false

    init(baseInterval: TimeInterval, maxInterval: TimeInterval) {
        self.baseInterval = baseInterval
        self.maxInterval = maxInterval
        self.interval = baseInterval
    }

    mutating func beginRefresh() -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        didAttemptTokenRefresh = false
        return true
    }

    mutating func finishRefresh() {
        isRefreshing = false
    }

    mutating func markTokenRefreshAttempted() {
        didAttemptTokenRefresh = true
    }

    mutating func applyRateLimit(retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter {
            interval = min(max(retryAfter + 15, baseInterval), 3600)
        } else {
            interval = min(max(interval * 2, baseInterval), maxInterval)
        }
        return interval
    }

    mutating func resetInterval() {
        interval = baseInterval
    }
}
