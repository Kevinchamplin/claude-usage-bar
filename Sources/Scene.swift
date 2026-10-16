import SwiftUI

/// What the mascot is doing, driven by the session severity.
enum Mood { case happy, busy, tired, asleep }

/// The animated strip behind the big number: drifting clouds, twinkling stars,
/// a ground line and the mascot. Everything is a pure function of `t` (seconds),
/// so the live popover and the snapshot renderer draw identical frames.
struct SceneView: View {
    let t: Double
    let mood: Mood

    var body: some View {
        Canvas { ctx, size in
            SceneDrawer.draw(ctx, size: size, t: t, mood: mood)
        }
    }
}

enum SceneDrawer {
    static let px: CGFloat = 4

    static func draw(_ ctx: GraphicsContext, size: CGSize, t: Double, mood: Mood) {
        let ground = size.height - 12
        stars(ctx, size: size, t: t, dim: mood == .asleep)
        clouds(ctx, size: size, t: t)
        groundLine(ctx, width: size.width, y: ground)
        mascot(ctx, size: size, ground: ground, t: t, mood: mood)
    }

    // MARK: Background

    private static func stars(_ ctx: GraphicsContext, size: CGSize, t: Double, dim: Bool) {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rand() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        for _ in 0..<16 {
            let x = rand() * size.width, y = rand() * (size.height - 30)
            let speed = 0.8 + rand() * 2.2, phase = rand() * 6.28
            let tw = 0.5 + 0.5 * sin(t * speed + phase)
            let a = (dim ? 0.10 : 0.12) + tw * (dim ? 0.15 : 0.38)
            let s: CGFloat = rand() > 0.8 ? 2 : 1.5
            ctx.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: s, height: s)),
                     with: .color(.white.opacity(a)))
        }
    }

    private static func clouds(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        // (sprite, pixel size, start x, y, speed px/s, opacity)
        let layers: [(Sprite, CGFloat, Double, CGFloat, Double, Double)] = [
            (Sprites.cloudBig, 3, 20, 8, 5, 0.95),
            (Sprites.cloudSmall, 2, 170, 30, 8, 0.75),
            (Sprites.cloudSmall, 3, 260, 14, 4, 0.85),
            (Sprites.cloudBig, 2, 100, 44, 10, 0.55),
        ]
        for (sprite, p, x0, y, speed, op) in layers {
            let w = Double(CGFloat(sprite.width) * p)
            let span = Double(size.width) + w
            var x = (x0 + speed * t).truncatingRemainder(dividingBy: span)
            if x < 0 { x += span }
            x -= w
            sprite.draw(ctx, at: CGPoint(x: x.rounded(), y: y), px: p,
                        palette: Sprites.cloudPalette, opacity: op)
        }
    }

    private static func groundLine(_ ctx: GraphicsContext, width: CGFloat, y: CGFloat) {
        var x: CGFloat = 2
        while x < width {
            ctx.fill(Path(CGRect(x: x, y: y + 2, width: 3, height: 2)), with: .color(.white.opacity(0.10)))
            x += 7
        }
    }

    // MARK: Mascot

    struct Pose {
        var x: CGFloat
        var lift: CGFloat
        var legs: Int
        var facing: Int
        var eyes: Eyes
    }

    static func pose(mood: Mood, t: Double, minX: CGFloat, maxX: CGFloat) -> Pose {
        let range = Double(maxX - minX)
        let mid = minX + (maxX - minX) * 0.55

        func walk(speed: Double) -> (CGFloat, Int) {
            let period = 2 * range / speed
            let p = t.truncatingRemainder(dividingBy: period)
            let half = period / 2
            if p < half { return (minX + CGFloat(p * speed), 1) }
            return (maxX - CGFloat((p - half) * speed), -1)
        }

        switch mood {
        case .happy:
            let (x, dir) = walk(speed: 22)
            let legs = Int(t * 8) % 2
            var lift: CGFloat = legs == 1 ? 1 : 0
            let hop = t.truncatingRemainder(dividingBy: 3.2)
            if hop < 0.4 { lift = CGFloat(sin(.pi * hop / 0.4) * 9) }
            let blink = t.truncatingRemainder(dividingBy: 3.7) < 0.14
            return Pose(x: x.rounded(), lift: lift, legs: hop < 0.4 ? 0 : legs,
                        facing: dir, eyes: blink ? .closed : .open)
        case .busy:
            let (x, dir) = walk(speed: 10)
            let legs = Int(t * 5) % 2
            let blink = t.truncatingRemainder(dividingBy: 2.9) < 0.14
            return Pose(x: x.rounded(), lift: legs == 1 ? 1 : 0, legs: legs,
                        facing: dir, eyes: blink ? .closed : .open)
        case .tired:
            let breathe = sin(t * 1.6) > 0.3 ? CGFloat(1) : 0
            return Pose(x: mid.rounded(), lift: breathe, legs: 0, facing: -1, eyes: .droopy)
        case .asleep:
            return Pose(x: mid.rounded(), lift: 0, legs: 0, facing: 0, eyes: .closed)
        }
    }

    private static func mascot(_ ctx: GraphicsContext, size: CGSize, ground: CGFloat, t: Double, mood: Mood) {
        let w = CGFloat(11) * px, h = CGFloat(6) * px
        // The number sits on the left, so the mascot keeps to the right ~55%.
        let minX = (size.width * 0.44).rounded(), maxX = size.width - w - 6
        let pose = pose(mood: mood, t: t, minX: minX, maxX: maxX)
        let top = ground - h - pose.lift

        // Shadow shrinks while airborne.
        let sw = w * (1 - min(pose.lift, 9) / 30)
        ctx.fill(Path(ellipseIn: CGRect(x: pose.x + (w - sw) / 2, y: ground - 1, width: sw, height: 4)),
                 with: .color(.black.opacity(0.4)))

        let sprite = Sprites.mascot(legs: pose.legs, eyes: pose.eyes, facing: pose.facing)
        sprite.draw(ctx, at: CGPoint(x: pose.x, y: top), px: px,
                    palette: Sprites.mascotPalette, opacity: mood == .asleep ? 0.8 : 1)

        let dropColor: [Character: Color] = ["c": Color(hex: 0x67E8F9)]
        switch mood {
        case .busy:
            // A sweat drop that blinks on the trailing side of the head.
            if Int(t * 2) % 2 == 0 {
                let dx: CGFloat = pose.facing == 1 ? -8 : w + 2
                Sprites.drop.draw(ctx, at: CGPoint(x: pose.x + dx, y: top + 2), px: 2, palette: dropColor)
            }
        case .tired:
            for i in 0..<2 {
                let p = (t * 0.9 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let dx: CGFloat = i == 0 ? -8 : w + 2
                Sprites.drop.draw(ctx, at: CGPoint(x: pose.x + dx, y: top + CGFloat(p * 12)), px: 2,
                                  palette: dropColor, opacity: 1 - p * 0.8)
            }
        case .asleep:
            for i in 0..<3 {
                let p = (t + Double(i) * 0.8).truncatingRemainder(dividingBy: 2.4) / 2.4
                let a = p < 0.15 ? p / 0.15 : 1 - p
                let zpx: CGFloat = i == 1 ? 2.5 : 2
                Sprites.z.draw(ctx, at: CGPoint(x: pose.x + w - 4 + CGFloat(p * 14), y: top - 6 - CGFloat(p * 26)),
                               px: zpx, palette: ["X": Color(hex: 0xC9C9D1)], opacity: a)
            }
        case .happy:
            break
        }
    }
}

/// The 22 x 12 pt mascot shown in the menu bar.
struct MascotGlyph: View {
    var sleeping = false

    var body: some View {
        Canvas { ctx, _ in
            let s = Sprites.mascot(legs: 0, eyes: sleeping ? .closed : .open, facing: 0)
            s.draw(ctx, at: .zero, px: 2, palette: Sprites.mascotPalette, opacity: sleeping ? 0.6 : 1)
        }
        .frame(width: 22, height: 12)
    }
}

/// Three pixel hearts, filled in halves.
struct HeartsView: View {
    /// 0...3 in steps of 0.5, or nil for "unknown" (all grey).
    let value: Double?

    var body: some View {
        Canvas { ctx, _ in
            let px: CGFloat = 2
            for i in 0..<3 {
                let filled = (value ?? 0) - Double(i)
                let origin = CGPoint(x: CGFloat(i) * (7 * px + 4), y: 0)
                Sprites.heart.draw(ctx, at: origin, px: px, palette: [:]) { x, _, ch in
                    guard ch == "X" else { return nil }
                    if filled >= 1 { return Theme.coral }
                    if filled >= 0.5 && x < 4 { return Theme.coral }
                    return Theme.heartEmpty
                }
            }
        }
        .frame(width: 3 * 14 + 8, height: 12)
    }
}
