import AppKit
import ScreenCaptureKit

// MARK: - Window Manager
//
// Activates applications and enumerates windows for agent use.
// Agents can focus an app before capture to ensure the right content is on screen.

struct WindowInfo {
    let app: String
    let title: String
    let frame: CGRect
    let bundleID: String
    let isOnScreen: Bool
}

struct AppInfo {
    let name: String
    let bundleID: String
}

@MainActor
final class WindowManager {

    // MARK: - Focus App

    /// Bring an application to the front by name or bundle ID.
    /// Launches the app if it's not running.
    @discardableResult
    static func focusApp(nameOrBundleID: String) async throws -> AppInfo {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications

        // Try matching by bundle ID first
        if let app = running.first(where: {
            $0.bundleIdentifier?.lowercased() == nameOrBundleID.lowercased()
        }) {
            app.activate()
            return AppInfo(
                name: app.localizedName ?? nameOrBundleID,
                bundleID: app.bundleIdentifier ?? nameOrBundleID
            )
        }

        // Try matching by localized name (case-insensitive)
        if let app = running.first(where: {
            $0.localizedName?.lowercased() == nameOrBundleID.lowercased()
        }) {
            app.activate()
            return AppInfo(
                name: app.localizedName ?? nameOrBundleID,
                bundleID: app.bundleIdentifier ?? ""
            )
        }

        // Try partial name match (e.g. "Chrome" matches "Google Chrome")
        if let app = running.first(where: {
            $0.localizedName?.lowercased().contains(nameOrBundleID.lowercased()) == true
        }) {
            app.activate()
            return AppInfo(
                name: app.localizedName ?? nameOrBundleID,
                bundleID: app.bundleIdentifier ?? ""
            )
        }

        // App not running — try to launch it
        let appURL: URL?
        if nameOrBundleID.contains(".") {
            // Looks like a bundle ID
            appURL = workspace.urlForApplication(withBundleIdentifier: nameOrBundleID)
        } else {
            // Try finding by name
            appURL = findAppURL(name: nameOrBundleID)
        }

        if let url = appURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try await workspace.openApplication(at: url, configuration: config)

            // Wait a moment for the app to come up
            try await Task.sleep(for: .milliseconds(500))

            // Find the now-running app
            if let app = workspace.runningApplications.first(where: {
                $0.bundleURL == url || $0.localizedName?.lowercased() == nameOrBundleID.lowercased()
            }) {
                return AppInfo(
                    name: app.localizedName ?? nameOrBundleID,
                    bundleID: app.bundleIdentifier ?? ""
                )
            }
        }

        throw MCPError.toolFailed(
            "App not found: \"\(nameOrBundleID)\". " +
            "Use the exact app name (e.g. 'Google Chrome') or bundle ID (e.g. 'com.google.Chrome')."
        )
    }

    // MARK: - List Windows

    /// List all visible on-screen windows via ScreenCaptureKit.
    static func listVisibleWindows() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true
        )

        let myBundleID = Bundle.main.bundleIdentifier ?? ""

        return content.windows
            .filter { $0.owningApplication?.bundleIdentifier != myBundleID }
            .filter { $0.isOnScreen && $0.frame.width > 0 && $0.frame.height > 0 }
            .map { window in
                WindowInfo(
                    app: window.owningApplication?.applicationName ?? "Unknown",
                    title: window.title ?? "",
                    frame: window.frame,
                    bundleID: window.owningApplication?.bundleIdentifier ?? "",
                    isOnScreen: window.isOnScreen
                )
            }
            .sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    // MARK: - Helpers

    private static func findAppURL(name: String) -> URL? {
        let searchPaths = [
            "/Applications",
            "/System/Applications",
            "/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]

        for dir in searchPaths {
            let appPath = "\(dir)/\(name).app"
            if FileManager.default.fileExists(atPath: appPath) {
                return URL(fileURLWithPath: appPath)
            }
        }
        return nil
    }
}
