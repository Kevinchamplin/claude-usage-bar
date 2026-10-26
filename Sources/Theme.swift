import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    static let width: CGFloat = 320
    static let padding: CGFloat = 16
    static var content: CGFloat { width - padding * 2 }

    static let bgTop = Color(hex: 0x17171B)
    static let bgBottom = Color(hex: 0x101013)
    static let label = Color(hex: 0x9A9AA3)
    static let dim = Color(hex: 0x6B6B74)
    static let brass = Color(hex: 0xE4C27C)

    static let green = Color(hex: 0x4ADE80)
    static let amber = Color(hex: 0xFBBF24)
    static let red = Color(hex: 0xF87171)

    static let coral = Color(hex: 0xE8735A)
    static let heartEmpty = Color(hex: 0x3A3A40)

    static func color(_ s: Severity) -> Color {
        switch s {
        case .normal: return green
        case .warning: return amber
        case .critical: return red
        }
    }

    static func nsColor(_ s: Severity) -> NSColor {
        switch s {
        case .normal: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }
}

extension Severity {
    var rank: Int {
        switch self {
        case .normal: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    /// The API's own severity, raised to at least what the percentage implies,
    /// so an 85% bar never renders green.
    static func effective(_ l: Limit) -> Severity {
        let byPct: Severity = l.percent >= 90 ? .critical : l.percent >= 70 ? .warning : .normal
        return byPct.rank > l.severity.rank ? byPct : l.severity
    }
}

enum Format {
    /// "3h 11m", "42m", "2d 4h"
    static func span(until date: Date, now: Date) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 1))m"
    }

    static func ago(_ date: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 172800 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}
