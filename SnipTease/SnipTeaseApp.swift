import SwiftUI
import AppKit
import ScreenCaptureKit
import Sparkle

// MARK: - Constants

enum SnipTeaseInfo {
    static let repoURL = URL(string: "https://github.com/noamt/sniptease")!
    static let issuesURL = URL(string: "https://github.com/noamt/sniptease/issues/new")!
}

extension Bundle {
    /// Marketing version string, e.g. "1.0.0"
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    /// Build number, e.g. "1"
    var buildNumber: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }
}

// MARK: - App Entry Point
//
// Two modes:
//   Normal:  Menu bar app with overlay capture UI
//   MCP:     Headless JSON-RPC server over stdio (launch with --mcp)
//
// Agents configure SnipTease as an MCP server in their config:
//   { "command": "/path/to/SnipTease.app/Contents/MacOS/SnipTease", "args": ["--mcp"] }

@main
struct SnipTeaseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible scenes — everything is driven from the menu bar.
        Settings {
            Text("SnipTease Settings")
                .frame(width: 200, height: 100)
        }
    }
}

// MARK: - App Delegate
// Uses NSStatusItem (battle-tested) instead of SwiftUI MenuBarExtra
// for reliable menu bar icon rendering.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let appState = AppState()
    var overlayController: OverlayController?
    var hotkeyManager: HotkeyManager?
    private var onboardingController: OnboardingWindowController?
    private var splash: SplashOverlay?
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // ── Menu bar ───────────────────────────────────────────────
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ── 0. Check for MCP mode ─────────────────────────────
        if CommandLine.arguments.contains("--mcp") {
            startMCPServer()
            return
        }

        // ── 1. Set up the status bar item ──────────────────────
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "crop", accessibilityDescription: "SnipTease")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // ── 2. Set up the popover ──────────────────────────────
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(appState)
        )

        // ── 3. Set up the overlay controller ───────────────────
        overlayController = OverlayController(appState: appState)

        // ── 4. React to overlay state changes ──────────────────
        Task { @MainActor in
            for await isActive in appState.$isOverlayActive.values {
                if isActive {
                    self.popover.performClose(nil)
                    self.overlayController?.show()
                    self.appState.captureScreen = self.overlayController?.activeScreen
                } else {
                    self.overlayController?.dismiss()
                }
            }
        }

        // ── 5. Onboarding or normal startup ───────────────────
        if !appState.hasCompletedOnboarding {
            showOnboarding()
        } else {
            // Already onboarded — show splash, register hotkey, verify permissions
            splash = SplashOverlay()
            splash?.show()
            registerHotkey()
            checkPermissionsSilently()
        }

        print("SnipTease: Menu bar item created. Look for the crop icon!")
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        guard hotkeyManager == nil else { return }
        hotkeyManager = HotkeyManager {
            Task { @MainActor in
                self.appState.toggleOverlay()
            }
        }
        hotkeyManager?.register()
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        onboardingController = OnboardingWindowController(appState: appState) { [weak self] in
            self?.onboardingController = nil
            // Now that onboarding is done, register the hotkey
            self?.registerHotkey()
            self?.checkPermissionsSilently()
            print("SnipTease: ✅ Onboarding complete")
        }
        onboardingController?.show()
    }

    // MARK: - Permissions (silent check for returning users)

    private func checkPermissionsSilently() {
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                print("SnipTease: ✅ Screen Recording permission granted")
            } catch {
                print("SnipTease: ⚠️ Screen Recording not granted — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - About / GitHub / Report Issue

    @objc func showAboutPanel() {
        popover?.performClose(nil)

        // Build credits with a clickable link back to the repo.
        let credits = NSMutableAttributedString(
            string: "A native macOS menu bar utility for framing screenshots for social media.\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor
            ]
        )
        let linkText = NSAttributedString(
            string: SnipTeaseInfo.repoURL.absoluteString,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .link: SnipTeaseInfo.repoURL,
                .foregroundColor: NSColor.linkColor
            ]
        )
        credits.append(linkText)

        NSApp.activate(ignoringOtherApps: true)
        // NSHumanReadableCopyright from Info.plist is shown automatically.
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "SnipTease",
            .applicationVersion: Bundle.main.appVersion,
            .version: Bundle.main.buildNumber,
            .credits: credits
        ])
    }

    @objc func openGitHub() {
        popover?.performClose(nil)
        NSWorkspace.shared.open(SnipTeaseInfo.repoURL)
    }

    @objc func openReportIssue() {
        popover?.performClose(nil)
        NSWorkspace.shared.open(SnipTeaseInfo.issuesURL)
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Ensure the popover's window becomes key so it receives focus
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - MCP Server Mode

    private func startMCPServer() {
        // Hide dock icon in MCP mode — we're headless
        NSApp.setActivationPolicy(.accessory)

        let tools = MCPTools()
        let server = MCPServer(tools: tools)

        Task {
            await server.run()
            // Server exited (stdin closed) — quit cleanly
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Menu Bar Dropdown View
// Raycast-inspired design: dark vibrancy, hover states, accent gradients,
// tight spacing rhythm, keyboard-shortcut badges, subtle animations.

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredPresetID: String?
    @State private var isHoveringCapture = false
    @State private var isHoveringQuit = false
    @State private var hoveredFooterID: String?

    // Raycast-style blue/indigo accent
    private let accent = Color(red: 0.38, green: 0.56, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "crop")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text("SnipTease")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("v\(Bundle.main.appVersion)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            menuDivider

            // ── Preset list ───────────────────────────────────────
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(PlatformPreset.allPresets.enumerated()), id: \.element.platform) { index, group in
                    if index > 0 { Spacer().frame(height: 4) }
                    sectionLabel(group.platform)
                    ForEach(group.presets) { preset in
                        presetRow(preset)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)

            menuDivider

            // ── Margin toggle ─────────────────────────────────────
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { appState.showMargins.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: appState.showMargins ? "square.dashed.inset.filled" : "square.dashed")
                        .font(.system(size: 12))
                        .foregroundColor(appState.showMargins ? accent : .secondary)
                        .frame(width: 20)
                    Text("Margin guides")
                        .font(.system(size: 12.5))
                        .foregroundColor(.primary)
                    Spacer()
                    // Mini toggle pill
                    Capsule()
                        .fill(appState.showMargins ? accent : Color.white.opacity(0.1))
                        .frame(width: 28, height: 16)
                        .overlay(
                            Circle()
                                .fill(.white)
                                .frame(width: 12, height: 12)
                                .offset(x: appState.showMargins ? 6 : -6),
                            alignment: .center
                        )
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: appState.showMargins)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            menuDivider

            // ── Capture button ────────────────────────────────────
            Button(action: { appState.activateOverlay() }) {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Start Capture")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    kbdBadge("⌃⇧S")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isHoveringCapture
                                ? accent
                                : accent.opacity(0.85)
                        )
                )
                .scaleEffect(isHoveringCapture ? 1.01 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringCapture = $0 }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .animation(.easeOut(duration: 0.12), value: isHoveringCapture)

            // ── Status message ────────────────────────────────────
            if let msg = appState.statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.green.opacity(0.9))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            menuDivider

            // ── About / GitHub / Report Issue ─────────────────────
            VStack(alignment: .leading, spacing: 0) {
                footerRow(
                    id: "update",
                    icon: "arrow.triangle.2.circlepath",
                    title: "Check for Updates\u{2026}",
                    action: {
                        (NSApp.delegate as? AppDelegate)?.updaterController.checkForUpdates(nil)
                    }
                )
                footerRow(
                    id: "about",
                    icon: "info.circle",
                    title: "About SnipTease",
                    action: {
                        (NSApp.delegate as? AppDelegate)?.showAboutPanel()
                    }
                )
                footerRow(
                    id: "github",
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "SnipTease on GitHub",
                    action: {
                        (NSApp.delegate as? AppDelegate)?.openGitHub()
                    }
                )
                footerRow(
                    id: "issue",
                    icon: "exclamationmark.bubble",
                    title: "Report an Issue",
                    action: {
                        (NSApp.delegate as? AppDelegate)?.openReportIssue()
                    }
                )
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)

            menuDivider

            // ── Quit ──────────────────────────────────────────────
            Button(action: { NSApp.terminate(nil) }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.from.line")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Text("Quit")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                    Spacer()
                    kbdBadge("⌘Q")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHoveringQuit ? Color.white.opacity(0.06) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHoveringQuit = $0 }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(width: 280)
        .preferredColorScheme(.dark)
    }

    // MARK: - Components

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.6))
            .tracking(0.8)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private func presetRow(_ preset: PlatformPreset) -> some View {
        let isSelected = appState.selectedPreset == preset
        let isHovered = hoveredPresetID == preset.id

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.selectPreset(preset)
            }
        }) {
            HStack(spacing: 8) {
                // Icon
                Image(systemName: preset.icon)
                    .font(.system(size: 11.5))
                    .foregroundColor(isSelected ? accent : .secondary)
                    .frame(width: 20)

                // Name
                Text(preset.name)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // Ratio badge
                Text(preset.ratioLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? accent.opacity(0.9) : .secondary.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isSelected ? accent.opacity(0.12) : Color.white.opacity(0.04))
                    )

                // Selection indicator
                if isSelected {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? accent.opacity(0.1)
                            : (isHovered ? Color.white.opacity(0.06) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredPresetID = hovering ? preset.id : nil
            }
        }
    }

    private func footerRow(
        id: String,
        icon: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredFooterID == id
        return Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundColor(.primary.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredFooterID = hovering ? id : nil
            }
        }
    }

    private func kbdBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.45))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 10)
    }
}
