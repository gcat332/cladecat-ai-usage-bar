import Foundation

func parseISO(_ s: String) -> Date? {
    let cleaned = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    return ISO8601DateFormatter().date(from: cleaned)
}

func resetSuffix(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "EEE HH:mm"
    return "  (resets \(f.string(from: d)))"
}

func fmtClaude(_ w: UsageWindow?, _ label: String) -> String {
    guard let w = w, let pct = w.utilization else { return "\(label): —" }
    let d = w.resets_at.flatMap(parseISO)
    return String(format: "%@: %.0f%%%@", label, pct, resetSuffix(d))
}

func fmtCodex(_ w: CodexWindow?, _ label: String) -> String {
    guard let w = w, let pct = w.used_percent else { return "\(label): —" }
    let d = w.reset_at.map { Date(timeIntervalSince1970: $0) }
    return String(format: "%@: %.0f%%%@", label, pct, resetSuffix(d))
}
