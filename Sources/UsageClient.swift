import Foundation

// Live Claude Code plan usage, the same numbers /usage shows.
// GET https://api.anthropic.com/api/oauth/usage with the Claude Code OAuth token,
// which lives in the login keychain. Claude Code refreshes that token as it runs,
// so we re-read it on every poll and never cache, log or refresh it ourselves.

enum Severity: String {
    case normal, warning, critical

    init(api: String?) {
        self = Severity(rawValue: api ?? "") ?? .normal
    }
}

struct Limit: Identifiable {
    let id: String
    let label: String
    let percent: Double
    let severity: Severity
    let resetsAt: Date?
}

struct Usage {
    var session: Limit?
    var weekly: [Limit]

    /// The all-models weekly limit, which drives the hearts.
    var weeklyAll: Limit? { weekly.first { $0.id == "weekly_all" } }
}

enum UsageError: Error {
    case noToken
    case unauthorized
    case rateLimited
    case network(String)

    var message: String {
        switch self {
        case .noToken: return "No Claude Code sign-in found. Run `claude` once."
        case .unauthorized: return "Sign-in expired. Open Claude Code to refresh it."
        case .rateLimited: return "Rate limited. Backing off."
        case .network(let m): return m
        }
    }

    /// Errors where the mascot goes to sleep instead of just showing a banner.
    var isAuth: Bool {
        switch self {
        case .noToken, .unauthorized: return true
        default: return false
        }
    }
}

enum UsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async -> Result<Usage, UsageError> {
        guard let token = readToken() else { return .failure(.noToken) }
        var req = URLRequest(url: endpoint, timeoutInterval: 20)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200: break
            case 401, 403: return .failure(.unauthorized)
            case 429: return .failure(.rateLimited)
            default: return .failure(.network("Usage API returned \(code)."))
            }
            guard let usage = parse(data) else { return .failure(.network("Could not read the usage response.")) }
            return .success(usage)
        } catch {
            return .failure(.network("Offline or unreachable."))
        }
    }

    private static func readToken() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }

    static func parse(_ data: Data) -> Usage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var usage = Usage(session: nil, weekly: [])

        if let limits = root["limits"] as? [[String: Any]], !limits.isEmpty {
            for l in limits {
                let kind = l["kind"] as? String ?? ""
                let pct = (l["percent"] as? NSNumber)?.doubleValue ?? 0
                let sev = Severity(api: l["severity"] as? String)
                let reset = parseDate(l["resets_at"] as? String)
                switch kind {
                case "session":
                    usage.session = Limit(id: "session", label: "Session", percent: pct, severity: sev, resetsAt: reset)
                case "weekly_all":
                    usage.weekly.insert(Limit(id: "weekly_all", label: "Weekly · all models", percent: pct, severity: sev, resetsAt: reset), at: 0)
                case "weekly_scoped":
                    let scope = l["scope"] as? [String: Any]
                    let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
                    let name = model ?? "scoped"
                    usage.weekly.append(Limit(id: "weekly_\(name)", label: "Weekly · \(name)", percent: pct, severity: sev, resetsAt: reset))
                default:
                    continue
                }
            }
        } else {
            // Older response shape: raw utilization buckets only.
            if let b = root["five_hour"] as? [String: Any] {
                usage.session = bucket("session", "Session", b)
            }
            if let b = root["seven_day"] as? [String: Any] {
                usage.weekly.append(bucket("weekly_all", "Weekly · all models", b))
            }
        }
        return usage.session == nil && usage.weekly.isEmpty ? nil : usage
    }

    private static func bucket(_ id: String, _ label: String, _ b: [String: Any]) -> Limit {
        let pct = (b["utilization"] as? NSNumber)?.doubleValue ?? 0
        let sev: Severity = pct >= 90 ? .critical : pct >= 70 ? .warning : .normal
        return Limit(id: id, label: label, percent: pct, severity: sev, resetsAt: parseDate(b["resets_at"] as? String))
    }

    /// The API sends microsecond fractions ("...00.157518+00:00"), which
    /// ISO8601DateFormatter rejects, so the fraction is stripped first.
    static func parseDate(_ s: String?) -> Date? {
        guard var s else { return nil }
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) { s.removeSubrange(r) }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
