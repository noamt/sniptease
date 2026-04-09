import AppKit
import SwiftUI

// MARK: - Overlay Controller
// Manages showing/hiding the transparent full-screen overlay panel.

@MainActor
final class OverlayController {

    private var panel: OverlayPanel?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        guard panel == nil else { return }
        guard let screen = NSScreen.main else { return }

        let p = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear        // SwiftUI handles the dimming
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = false

        let overlayView = OverlayContentView(appState: appState)
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = screen.frame
        p.contentView = hostingView

        // Fade in
        p.alphaValue = 0
        p.orderFrontRegardless()
        p.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }
        panel = p
    }

    func dismiss() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
        })
    }
}

// MARK: - Overlay Panel (NSPanel subclass)
// A borderless, transparent panel that covers the screen.

final class OverlayPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Allow Escape to dismiss
    override func keyDown(with event: NSEvent) {
        if CGKeyCode(event.keyCode) == KeyCode.escape {
            NotificationCenter.default.post(name: .dismissOverlay, object: nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

extension Notification.Name {
    static let dismissOverlay = Notification.Name("SnipTease.dismissOverlay")
    static let captureRequested = Notification.Name("SnipTease.captureRequested")
}
