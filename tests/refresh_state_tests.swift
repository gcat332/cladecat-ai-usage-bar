import Foundation

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write("FAIL: \(message)\n".data(using: .utf8)!)
        exit(1)
    }
}

@main
struct RefreshStateTests {
    static func main() {
        var state = ProviderRefreshState(baseInterval: 180, maxInterval: 900)

        assert(state.beginRefresh(), "first refresh should start")
        assert(!state.beginRefresh(), "overlapping refresh should be skipped")

        state.markTokenRefreshAttempted()
        assert(state.didAttemptTokenRefresh, "token refresh flag should be set")

        state.finishRefresh()
        assert(!state.isRefreshing, "finishRefresh should clear isRefreshing")

        assert(state.beginRefresh(), "refresh should start again after finishing")
        assert(!state.didAttemptTokenRefresh, "new refresh should clear token refresh flag")
        state.finishRefresh()

        let retryAfterInterval = state.applyRateLimit(retryAfter: 30)
        assert(retryAfterInterval == 180, "retry-after shorter than base should clamp to base")

        let doubled = state.applyRateLimit(retryAfter: nil)
        assert(doubled == 360, "missing retry-after should double current interval")

        state.resetInterval()
        let nextAfterRefreshRateLimit = state.applyTokenRefreshFailure(statusCode: 429, retryAfter: nil)
        assert(nextAfterRefreshRateLimit == 360, "token refresh 429 should back off from the base interval")
        assert(state.interval == 360, "token refresh 429 should update provider interval")

        let nextAfterRetryAfter = state.applyTokenRefreshFailure(statusCode: 429, retryAfter: 600)
        assert(nextAfterRetryAfter == 615, "token refresh Retry-After should be respected with safety margin")

        let noBackoff = state.applyTokenRefreshFailure(statusCode: 400, retryAfter: 600)
        assert(noBackoff == nil, "non-rate-limited token refresh failure should not change interval")

        let cooldownStart = Date(timeIntervalSince1970: 1_000)
        state.resetInterval()
        let cooldown = state.applyTokenRefreshFailure(statusCode: 429, retryAfter: nil, now: cooldownStart)
        assert(cooldown == 360, "token refresh 429 should create a cooldown interval")
        assert(!state.beginRefresh(now: cooldownStart.addingTimeInterval(100)), "refresh should be skipped during token refresh cooldown")
        assert(state.beginRefresh(now: cooldownStart.addingTimeInterval(361)), "refresh should resume after token refresh cooldown")
        state.finishRefresh()

        var restored = ProviderRefreshState(
            baseInterval: 180,
            maxInterval: 900,
            cooldownUntil: cooldownStart.addingTimeInterval(600)
        )
        assert(!restored.beginRefresh(now: cooldownStart.addingTimeInterval(100)), "restored cooldown should block refresh after restart")
        assert(restored.beginRefresh(now: cooldownStart.addingTimeInterval(601)), "restored cooldown should allow refresh after expiry")
        restored.finishRefresh()

        state.resetInterval()
        assert(state.interval == 180, "success should reset interval to base")
    }
}
