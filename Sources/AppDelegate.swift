import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: AppDelegate?

    let store = UsageStore()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()
    private lazy var glyphAwake = Self.glyph(sleeping: false)
    private lazy var glyphAsleep = Self.glyph(sleeping: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeft
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingController(rootView: PopoverContent(store: store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        store.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] s in self?.updateButton(s) }
            .store(in: &bag)
        store.start()
    }

    // MARK: Menu bar

    private func updateButton(_ s: ViewState) {
        guard let button = item.button else { return }
        button.image = s.sleeping ? glyphAsleep : glyphAwake

        let text: String, color: NSColor
        if let session = s.usage?.session {
            text = " \(Int(session.percent.rounded()))%"
            color = s.sleeping ? .secondaryLabelColor : Theme.nsColor(Severity.effective(session))
        } else {
            text = " --%"
            color = .secondaryLabelColor
        }
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
        ])
        button.toolTip = s.error ?? "Claude usage"
    }

    private static func glyph(sleeping: Bool) -> NSImage? {
        let r = ImageRenderer(content: MascotGlyph(sleeping: sleeping))
        r.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = r.nsImage
        img?.isTemplate = false
        return img
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let m = makeMenu()
            m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func showMenuAtMouse() {
        makeMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func makeMenu() -> NSMenu {
        let m = NSMenu()
        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
        let open = NSMenuItem(title: "Open usage on claude.ai", action: #selector(openUsage), keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit Claude Usage", action: #selector(quit), keyEquivalent: "q")
        for i in [refresh, open, quit] { i.target = self }
        m.addItem(refresh)
        m.addItem(open)
        m.addItem(.separator())
        m.addItem(quit)
        return m
    }

    @objc private func refreshNow() { store.refresh() }

    @objc private func openUsage() {
        if let url = URL(string: "https://claude.ai/settings/usage") { NSWorkspace.shared.open(url) }
    }

    // Exit 0 on purpose: the LaunchAgent only restarts on an unsuccessful exit,
    // so Quit really quits until the next login.
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) { store.popoverOpened() }
    func popoverDidClose(_ notification: Notification) { store.popoverClosed() }
}
