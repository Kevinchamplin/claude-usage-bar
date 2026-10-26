import AppKit
import SwiftUI

/// `ClaudeUsageBar --snapshot <dir>` renders the popover with fixture data to
/// PNGs (no network, no keychain), so the design can be reviewed and diffed
/// without running the app. Also writes animation frames for each mood.
@MainActor
enum Snapshot {
    static func run(dir: String) {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date()

        let fixtures = fixtures(now: now)
        for (name, state) in fixtures {
            write(PopoverBody(state: state, t: 1.3, now: now), to: root.appendingPathComponent("\(name).png"))
        }

        for (name, state) in fixtures where name != "loading" {
            let dir = root.appendingPathComponent("frames-\(name)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for i in 0..<48 {
                let f = String(format: "f%03d.png", i)
                write(PopoverBody(state: state, t: 20 + Double(i) / 12, now: now), to: dir.appendingPathComponent(f))
            }
        }

        for (name, state) in fixtures {
            write(MenuBarMock(state: state), to: root.appendingPathComponent("menubar-\(name).png"))
        }
        print("snapshots written to \(root.path)")
    }

    static func fixtures(now: Date) -> [(String, ViewState)] {
        func lim(_ id: String, _ label: String, _ pct: Double, _ sev: Severity, _ hrs: Double) -> Limit {
            Limit(id: id, label: label, percent: pct, severity: sev, resetsAt: now.addingTimeInterval(hrs * 3600))
        }
        func usage(_ s: Double, _ sSev: Severity, _ w: Double, _ wSev: Severity, _ f: Double) -> Usage {
            Usage(session: lim("session", "Session", s, sSev, 3 + 11.0 / 60),
                  weekly: [lim("weekly_all", "Weekly · all models", w, wSev, 52),
                           lim("weekly_Fable", "Weekly · Fable", f, .normal, 52)])
        }
        let fresh = now.addingTimeInterval(-12)
        return [
            ("normal", ViewState(usage: usage(27, .normal, 41, .normal, 12), lastFetch: fresh)),
            ("warning", ViewState(usage: usage(74, .warning, 63, .normal, 30), lastFetch: fresh)),
            ("critical", ViewState(usage: usage(96, .critical, 88, .warning, 55), lastFetch: fresh)),
            ("asleep", ViewState(usage: usage(27, .normal, 41, .normal, 12),
                                 error: UsageError.expired.message, sleeping: true,
                                 lastFetch: now.addingTimeInterval(-1800))),
            ("loading", ViewState(loading: true)),
        ]
    }

    static func write<V: View>(_ view: V, to url: URL) {
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let cg = r.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else {
            print("render failed: \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
    }
}

/// A stand-in for the menu bar item, for previews only.
private struct MenuBarMock: View {
    let state: ViewState

    var body: some View {
        let session = state.usage?.session
        let color: Color = state.sleeping || session == nil
            ? Theme.label : Theme.color(session.map(Severity.effective) ?? .normal)
        return HStack(spacing: 4) {
            MascotGlyph(sleeping: state.sleeping)
            Text(session.map { "\(Int($0.percent.rounded()))%" } ?? "--%")
                .font(Fonts.ui(12, .medium))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color(hex: 0x2A2A2E))
    }
}
