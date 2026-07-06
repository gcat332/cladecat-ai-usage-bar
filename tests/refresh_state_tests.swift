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
        assert(state.interval == 180, "success should reset interval to base")
    }
}
