import AppKit
import SwiftUI

/// Every font in the app comes from here.
enum Fonts {
    static func ui(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> Font {
        Font(NSFont.systemFont(ofSize: size, weight: weight))
    }

    static func rounded(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> Font {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded),
              let f = NSFont(descriptor: d, size: size) else { return Font(base) }
        return Font(f)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> Font {
        Font(NSFont.monospacedSystemFont(ofSize: size, weight: weight))
    }
}
