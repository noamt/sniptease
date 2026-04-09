import Foundation
import ScreenCaptureKit
import AppKit
import ImageIO
import CoreImage
import UniformTypeIdentifiers

// MARK: - MCP Tool Definitions & Handlers
//
// Each tool is a function an agent can call:
//   capture_for_social  — VLM-guided screenshot → framed social media image
//   capture_region      — direct rect capture (agent already knows coords)
//   list_presets        — discover available presets
//   focus_app           — bring a window to front before capture

@MainActor
final class MCPTools {

    // MARK: - Tool Registry

    func listTools() -> [[String: Any]] {
        [
            [
                "name": "capture_for_social",
                "description": "Take a screenshot and use AI vision to find a specific region, then frame it for a social media preset with correct aspect ratio and safe-zone margins. Optionally focus an app first.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "description": [
                            "type": "string",
                            "description": "Natural language description of what to capture, e.g. 'the code editor showing the main function' or 'the email body in Gmail'"
                        ],
                        "preset": [
                            "type": "string",
                            "description": "Social media preset ID",
                            "enum": PlatformPreset.allPresets.flatMap { $0.presets.map(\.id) }
                        ],
                        "focus_app": [
                            "type": "string",
                            "description": "App name or bundle ID to bring to front before capturing. e.g. 'Google Chrome', 'com.apple.mail'"
                        ],
                        "focus_delay": [
                            "type": "number",
                            "description": "Seconds to wait after focusing app (default 0.5). Increase for slow-loading content."
                        ],
                        "gemini_api_key": [
                            "type": "string",
                            "description": "Gemini API key for VLM bounding box detection. Falls back to GEMINI_API_KEY env var."
                        ]
                    ],
                    "required": ["description", "preset"]
                ]
            ],
            [
                "name": "capture_region",
                "description": "Capture a specific screen region by coordinates (in points) and frame it for a social media preset. Use when the agent already knows exact coordinates.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "x": ["type": "number", "description": "Left edge in screen points"],
                        "y": ["type": "number", "description": "Top edge in screen points"],
                        "width": ["type": "number", "description": "Width in screen points"],
                        "height": ["type": "number", "description": "Height in screen points"],
                        "preset": [
                            "type": "string",
                            "description": "Social media preset ID",
                            "enum": PlatformPreset.allPresets.flatMap { $0.presets.map(\.id) }
                        ]
                    ],
                    "required": ["x", "y", "width", "height", "preset"]
                ]
            ],
            [
                "name": "list_presets",
                "description": "List all available social media presets with their aspect ratios, margin sizes, and export dimensions.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ],
            [
                "name": "focus_app",
                "description": "Bring an application to the front. Useful before capture_for_social if the target content is in a specific app. Returns the focused app's info.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "app": [
                            "type": "string",
                            "description": "Application name (e.g. 'Safari', 'Slack') or bundle identifier (e.g. 'com.apple.Safari')"
                        ]
                    ],
                    "required": ["app"]
                ]
            ],
            [
                "name": "list_windows",
                "description": "List all visible on-screen windows with their app name, title, and position. Useful for discovering what's on screen before capture.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ]
        ]
    }

    // MARK: - Tool Dispatch

    func callTool(name: String, arguments: [String: Any]) async throws -> [[String: Any]] {
        switch name {
        case "capture_for_social":
            return try await captureForSocial(arguments)
        case "capture_region":
            return try await captureRegion(arguments)
        case "list_presets":
            return listPresetsResult()
        case "focus_app":
            return try await focusApp(arguments)
        case "list_windows":
            return try await listWindows()
        default:
            throw MCPError.toolNotFound(name)
        }
    }

    // MARK: - capture_for_social

    private func captureForSocial(_ args: [String: Any]) async throws -> [[String: Any]] {
        guard let description = args["description"] as? String,
              let presetID = args["preset"] as? String else {
            throw MCPError.toolFailed("Missing required: description, preset")
        }

        guard let preset = resolvePreset(presetID) else {
            throw MCPError.toolFailed("Unknown preset: \(presetID)")
        }

        // Optionally focus an app first
        if let focusApp = args["focus_app"] as? String {
            let delay = args["focus_delay"] as? Double ?? 0.5
            try await WindowManager.focusApp(nameOrBundleID: focusApp)
            try await Task.sleep(for: .milliseconds(Int(delay * 1000)))
        }

        // Take full-screen screenshot
        let screenshot = try await AgentCaptureService.takeScreenshot()

        // Find region via VLM
        let apiKey = args["gemini_api_key"] as? String
            ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        guard let apiKey, !apiKey.isEmpty else {
            throw MCPError.toolFailed("No Gemini API key. Pass gemini_api_key or set GEMINI_API_KEY env var.")
        }

        let region = try await AgentCaptureService.findRegion(
            screenshot: screenshot,
            description: description,
            apiKey: apiKey
        )

        // Frame and export
        let result = try await AgentCaptureService.frameAndExport(
            screenshot: screenshot,
            region: region,
            preset: preset
        )

        return [[
            "type": "text",
            "text": """
                Captured "\(description)" for \(preset.name).
                Region found: (\(region.x_min), \(region.y_min)) → (\(region.x_max), \(region.y_max)) [0-1000 scale]
                Output: \(result.path) (\(result.width)×\(result.height), \(result.sizeKB)KB)
                """
        ]]
    }

    // MARK: - capture_region

    private func captureRegion(_ args: [String: Any]) async throws -> [[String: Any]] {
        guard let x = args["x"] as? Double,
              let y = args["y"] as? Double,
              let width = args["width"] as? Double,
              let height = args["height"] as? Double,
              let presetID = args["preset"] as? String else {
            throw MCPError.toolFailed("Missing required: x, y, width, height, preset")
        }

        guard let preset = resolvePreset(presetID) else {
            throw MCPError.toolFailed("Unknown preset: \(presetID)")
        }

        let rect = CGRect(x: x, y: y, width: width, height: height)
        await CaptureService.capture(rect: rect, preset: preset)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "SnipTease_\(preset.id)_\(timestamp).png"

        return [[
            "type": "text",
            "text": "Captured region (\(Int(width))×\(Int(height))pt) for \(preset.name). Saved to Desktop/\(filename) and clipboard."
        ]]
    }

    // MARK: - list_presets

    private func listPresetsResult() -> [[String: Any]] {
        var lines: [String] = []
        for group in PlatformPreset.allPresets {
            for preset in group.presets {
                let ratio = "\(Int(preset.aspectWidth)):\(Int(preset.aspectHeight))"
                lines.append(
                    "\(preset.id): \(preset.name) — \(ratio), " +
                    "margin \(Int(preset.marginFraction * 100))%, " +
                    "export \(Int(preset.exportWidth))px wide"
                )
            }
        }
        return [[
            "type": "text",
            "text": lines.joined(separator: "\n")
        ]]
    }

    // MARK: - focus_app

    private func focusApp(_ args: [String: Any]) async throws -> [[String: Any]] {
        guard let app = args["app"] as? String else {
            throw MCPError.toolFailed("Missing required: app")
        }

        let info = try await WindowManager.focusApp(nameOrBundleID: app)
        return [[
            "type": "text",
            "text": "Focused: \(info.name) (\(info.bundleID))"
        ]]
    }

    // MARK: - list_windows

    private func listWindows() async throws -> [[String: Any]] {
        let windows = try await WindowManager.listVisibleWindows()
        var lines: [String] = []
        for w in windows {
            lines.append(
                "\(w.app) — \"\(w.title)\" at (\(Int(w.frame.origin.x)), \(Int(w.frame.origin.y))) " +
                "\(Int(w.frame.width))×\(Int(w.frame.height))pt"
            )
        }
        return [[
            "type": "text",
            "text": lines.isEmpty ? "No visible windows found." : lines.joined(separator: "\n")
        ]]
    }

    // MARK: - Helpers

    private func resolvePreset(_ id: String) -> PlatformPreset? {
        PlatformPreset.allPresets.flatMap(\.presets).first { $0.id == id }
    }
}
