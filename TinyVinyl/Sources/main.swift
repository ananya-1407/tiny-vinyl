import Cocoa
import SwiftUI

final class PlayerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let model = PlayerModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Tiny Vinyl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu

        let frame = NSRect(x: 0, y: 0, width: PlayerLayout.width, height: PlayerLayout.height)
        window = PlayerWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Tiny Vinyl"
        window.identifier = NSUserInterfaceItemIdentifier("player")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = model.pinned ? .floating : .normal
        window.delegate = self
        let glass = NSVisualEffectView(frame: frame)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .vibrantLight)
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 23
        glass.layer?.masksToBounds = true
        let content = NSHostingView(rootView: PlayerView(model: model))
        content.frame = glass.bounds
        content.autoresizingMask = [.width, .height]
        glass.addSubview(content)
        window.contentView = glass
        window.center()
        window.setFrameAutosaveName("TinyVinylPosition")
        window.setContentSize(frame.size)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let args = CommandLine.arguments
        if args.contains("--preview") { model.togglePreview() }
        if let index = args.firstIndex(of: "--snapshot"), args.count > index + 1 {
            if args.contains("--snapshot-preview") { model.togglePreview() }
            let destination = args[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                if let view = window.contentView,
                   let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: destination))
                    }
                }
                NSApp.terminate(nil)
            }
        } else { model.start() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { model.beats.stop() }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { application.run() }
}
