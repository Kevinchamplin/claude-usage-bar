import SwiftUI

/// A pixel sprite: one string per row, one character per pixel.
/// Characters missing from the palette are transparent.
struct Sprite {
    let rows: [String]

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }

    func mirrored() -> Sprite { Sprite(rows: rows.map { String($0.reversed()) }) }

    func draw(_ ctx: GraphicsContext, at origin: CGPoint, px: CGFloat,
              palette: [Character: Color], opacity: Double = 1,
              colorAt: ((Int, Int, Character) -> Color?)? = nil) {
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = colorAt?(x, y, ch) ?? palette[ch] else { continue }
                // A hair of overlap so adjacent pixels never show a seam.
                let r = CGRect(x: origin.x + CGFloat(x) * px, y: origin.y + CGFloat(y) * px,
                               width: px + 0.25, height: px + 0.25)
                ctx.fill(Path(r), with: .color(c.opacity(opacity)))
            }
        }
    }
}

enum Eyes { case open, droopy, closed }

enum Sprites {
    static let mascotPalette: [Character: Color] = [
        "O": Color(hex: 0xD97757),   // body
        "o": Color(hex: 0xB9603F),   // belly and legs
        "K": Color(hex: 0x1A1A1A),   // open eye
        "k": Color(hex: 0x7A3B24),   // closed eye
    ]

    /// Our blocky critter, 11 x 6. `facing` is -1 (left), 0 (front) or 1 (right):
    /// the eyes shift toward where it is walking.
    static func mascot(legs: Int, eyes: Eyes, facing: Int) -> Sprite {
        let eyeRow: String
        switch facing {
        case 1: eyeRow = "..OOKOOOK.."
        case -1: eyeRow = "..KOOOKOO.."
        default: eyeRow = "..OKOOOKO.."
        }
        let plain = "..OOOOOOO.."
        let r1: String, r2: String
        switch eyes {
        case .open: r1 = eyeRow; r2 = eyeRow
        case .droopy: r1 = plain; r2 = eyeRow
        case .closed: r1 = plain; r2 = eyeRow.replacingOccurrences(of: "K", with: "k")
        }
        return Sprite(rows: [
            plain,
            r1,
            r2,
            "OOOOOOOOOOO",
            "..ooooooo..",
            legs == 0 ? "..o.o.o.o.." : ".o.o...o.o.",
        ])
    }

    static let heart = Sprite(rows: [
        ".XX.XX.",
        "XXXXXXX",
        "XXXXXXX",
        ".XXXXX.",
        "..XXX..",
        "...X...",
    ])

    static let cloudBig = Sprite(rows: [
        "....GGGG.....",
        "..GGGGGGGG...",
        ".GGGGGGGGGGG.",
        "GGGGGGGGGGGGG",
        ".ggggggggggg.",
    ])

    static let cloudSmall = Sprite(rows: [
        "...GGG...",
        ".GGGGGGG.",
        "GGGGGGGGG",
        ".ggggggg.",
    ])

    static let cloudPalette: [Character: Color] = [
        "G": Color(hex: 0x5A5A63),
        "g": Color(hex: 0x4A4A52),
    ]

    static let drop = Sprite(rows: [".c.", "ccc", ".c."])
    static let z = Sprite(rows: ["XXXX", "..X.", ".X..", "XXXX"])
}
