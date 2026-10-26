import SwiftUI

/// Live wrapper: animates at 12fps while the popover is open, and stops
/// redrawing entirely when it is closed so the app costs nothing in the background.
struct PopoverContent: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !store.isOpen)) { ctx in
            PopoverBody(state: store.state,
                        t: ctx.date.timeIntervalSinceReferenceDate,
                        now: ctx.date,
                        onRefresh: { store.refresh() },
                        onMenu: { AppDelegate.shared?.showMenuAtMouse() })
        }
    }
}

/// The whole popover as a pure function of state and time. Snapshot mode
/// renders this directly, so every preview image matches the live app.
struct PopoverBody: View {
    let state: ViewState
    let t: Double
    let now: Date
    var onRefresh: () -> Void = {}
    var onMenu: () -> Void = {}

    private var session: Limit? { state.usage?.session }
    private var severity: Severity { session.map(Severity.effective) ?? .normal }

    private var accent: Color {
        if state.sleeping { return Theme.dim }
        if session == nil { return Theme.label }
        return Theme.color(severity)
    }

    private var mood: Mood {
        if state.sleeping { return .asleep }
        switch severity {
        case .critical: return .tired
        case .warning: return .busy
        case .normal: return .happy
        }
    }

    /// Hearts are weekly (all models) headroom: 3 full hearts at 0%, empty at 100%.
    private var hearts: Double? {
        guard let w = state.usage?.weeklyAll else { return nil }
        let v = (100 - w.percent) / 100 * 3
        return max(0, min(3, (v * 2).rounded() / 2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            hero
            sessionBlock
            if let weekly = state.usage?.weekly, !weekly.isEmpty {
                weeklyBlock(weekly)
            }
            if let err = state.error { banner(err) }
            footer
        }
        .padding(Theme.padding)
        .frame(width: Theme.width)
        .background(background)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Text("CLAUDE USAGE")
                .font(Fonts.ui(11, .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.label)
            Spacer()
            HeartsView(value: hearts)
            Button(action: onMenu) {
                Image(systemName: "ellipsis")
                    .font(Fonts.ui(12, .bold))
                    .foregroundStyle(Theme.label)
                    .frame(width: 22, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            SceneView(t: t, mood: mood)
                .frame(width: Theme.content, height: 108)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(session.map { String(Int($0.percent.rounded())) } ?? "--")
                    .font(Fonts.rounded(48, .light))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("%")
                    .font(Fonts.rounded(20))
                    .opacity(0.7)
            }
            .foregroundStyle(accent)
            .shadow(color: accent.opacity(0.45), radius: 12)
            .padding(.leading, 12)
            .padding(.bottom, 14)
        }
        .frame(width: Theme.content, height: 108)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06)))
    }

    private var sessionBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            GlowBar(percent: session?.percent ?? 0, color: accent, t: t,
                    height: 10, sheen: true, width: Theme.content)
            HStack {
                Text(resetLine)
                    .font(Fonts.mono(11, .medium))
                    .foregroundStyle(Theme.label)
                Spacer()
                Text("5-hour session")
                    .font(Fonts.ui(10))
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private var resetLine: String {
        if let r = session?.resetsAt {
            // Numbers from before a reset are stale; say so instead of "1m".
            return r <= now ? "reset since last update" : "resets in \(Format.span(until: r, now: now))"
        }
        if session == nil && state.error == nil { return "loading..." }
        return " "
    }

    private func weeklyBlock(_ limits: [Limit]) -> some View {
        let inner = Theme.content - 24
        return VStack(alignment: .leading, spacing: 11) {
            ForEach(limits) { l in
                let c = state.sleeping ? Theme.dim : Theme.color(Severity.effective(l))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Text(l.label)
                            .font(Fonts.ui(11))
                            .foregroundStyle(Theme.label)
                        Spacer()
                        Text("\(Int(l.percent.rounded()))%")
                            .font(Fonts.rounded(11, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(c)
                        if let r = l.resetsAt {
                            Text("· \(r <= now ? "reset" : Format.span(until: r, now: now))")
                                .font(Fonts.mono(10))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    GlowBar(percent: l.percent, color: c, t: t, height: 5, sheen: false, width: inner)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: state.sleeping ? "moon.zzz.fill" : "exclamationmark.triangle.fill")
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(Fonts.ui(11))
        .foregroundStyle(Theme.amber)
        .padding(10)
        .background(Theme.amber.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .shadow(color: dotColor.opacity(0.8), radius: 3)
            Text(updatedText)
                .font(Fonts.ui(10))
                .foregroundStyle(Theme.dim)
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(Fonts.ui(10, .semibold))
                    .foregroundStyle(Theme.label)
                    .rotationEffect(.degrees(state.loading ? (t * 360).truncatingRemainder(dividingBy: 360) : 0))
                    .frame(width: 18, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text("CHAMPLIN ENTERPRISES")
                .font(Fonts.ui(9, .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.brass.opacity(0.85))
        }
    }

    private var dotColor: Color {
        if state.error != nil { return Theme.amber }
        guard let last = state.lastFetch else { return Theme.dim }
        return now.timeIntervalSince(last) > 300 ? Theme.amber : Theme.green
    }

    private var updatedText: String {
        guard let last = state.lastFetch else { return state.loading ? "Loading" : "Not updated yet" }
        return "Updated \(Format.ago(last, now: now)) ago"
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.16), .clear],
                           center: UnitPoint(x: 0.8, y: 0.22), startRadius: 0, endRadius: 230)
        }
    }
}

/// A capsule progress bar with a gradient fill, a soft glow in its own color,
/// and (for the session bar) a highlight that sweeps across the fill.
struct GlowBar: View {
    let percent: Double
    let color: Color
    let t: Double
    var height: CGFloat
    var sheen: Bool
    var width: CGFloat

    var body: some View {
        let p = max(0, min(1, percent / 100))
        let fw = p > 0 ? max(height, width * p) : 0
        let span = Double(fw) + 60
        let sx = CGFloat((t * 70).truncatingRemainder(dividingBy: span)) - 30

        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.07))
            ZStack(alignment: .leading) {
                LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
                if sheen && fw > 0 {
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.38), .white.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 30)
                        .offset(x: sx)
                }
            }
            .frame(width: fw, height: height)
            .clipShape(Capsule())
            .shadow(color: color.opacity(0.55), radius: height * 0.7)
        }
        .frame(width: width, height: height)
    }
}
