import AppKit
import SwiftUI

// MARK: - Splash Overlay
// A brief, full-screen branded moment on launch — the app icon fades
// in over a subtle dark scrim, holds for ~1.2s, then dissolves away.
// Only shown for returning users (onboarding handles the first launch).

@MainActor
final class SplashOverlay {

    private var panel: NSPanel?

    func show() {
        guard let screen = NSScreen.main else { return }

        let p = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true          // Click-through
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let splashView = SplashView()
        let hostingView = NSHostingView(rootView: splashView)
        hostingView.frame = screen.frame
        p.contentView = hostingView

        p.alphaValue = 0
        p.orderFrontRegardless()

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        panel = p

        // Hold, then fade out and destroy
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            guard let p = panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.6
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                p.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                p.orderOut(nil)
                self?.panel = nil
            })
        }
    }
}

// MARK: - Splash SwiftUI View

private struct SplashView: View {
    @State private var appeared = false

    private let accent = Color(red: 0.38, green: 0.56, blue: 1.0)

    var body: some View {
        ZStack {
            // Subtle scrim
            Color.black.opacity(0.35)

            VStack(spacing: 14) {
                // App icon
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.13, green: 0.13, blue: 0.17),
                                    Color(red: 0.09, green: 0.09, blue: 0.12)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 72, height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: accent.opacity(0.3), radius: 24, y: 4)

                    Image(systemName: "crop")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(accent)
                }
                .scaleEffect(appeared ? 1.0 : 0.8)
                .opacity(appeared ? 1 : 0)

                Text("SnipTease")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .opacity(appeared ? 1 : 0)
            }
            .offset(y: appeared ? 0 : 6)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
        }
    }
}
