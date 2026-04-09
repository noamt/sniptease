import Foundation
import AppKit
import ScreenCaptureKit
import ImageIO
import CoreImage
import UniformTypeIdentifiers

// MARK: - Agent Capture Service
//
// The VLM-powered capture pipeline for agent use:
//   1. Take full-screen Retina screenshot via ScreenCaptureKit
//   2. Send to Gemini VLM with natural language description → bounding box
//   3. Frame the content region inside the preset's safe zone
//   4. Lanczos downscale to export dimensions, save PNG with DPI metadata

struct BoundingRegion {
    let y_min: Int  // 0-1000 scale
    let x_min: Int
    let y_max: Int
    let x_max: Int
}

struct ExportResult {
    let path: String
    let width: Int
    let height: Int
    let sizeKB: Int
}

@MainActor
final class AgentCaptureService {

    private static let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true
    ])

    // MARK: - Step 1: Screenshot

    static func takeScreenshot() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        guard let display = content.displays.first else {
            throw MCPError.toolFailed("No display found")
        }
        guard let screen = NSScreen.main else {
            throw MCPError.toolFailed("No main screen")
        }

        let backingScale = screen.backingScaleFactor
        let nativeW = Int(CGFloat(display.width) * backingScale)
        let nativeH = Int(CGFloat(display.height) * backingScale)

        // Exclude SnipTease's own windows
        let myBundleID = Bundle.main.bundleIdentifier ?? ""
        let myWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == myBundleID
        }

        let filter = SCContentFilter(display: display, excludingWindows: myWindows)
        let config = SCStreamConfiguration()
        config.width = nativeW
        config.height = nativeH
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.displayP3

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return image
    }

    // MARK: - Step 2: VLM Region Detection

    static func findRegion(
        screenshot: CGImage,
        description: String,
        apiKey: String
    ) async throws -> BoundingRegion {
        // Encode screenshot as PNG data → base64
        let pngData = encodePNG(screenshot, dpi: 144)
        guard let pngData else {
            throw MCPError.toolFailed("Failed to encode screenshot for VLM")
        }
        let base64 = pngData.base64EncodedString()

        let prompt = """
            Look at this screenshot. Find the region containing: "\(description)"

            Return ONLY a JSON object with the bounding box of that region:
            {"box_2d": [y_min, x_min, y_max, x_max]}

            Coordinates must be on a 0-1000 scale where (0,0) is top-left and (1000,1000) is bottom-right.
            Be precise — the box should tightly wrap the described content with minimal padding.
            Return ONLY the JSON, no other text.
            """

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inline_data": ["mime_type": "image/png", "data": base64]],
                    ["text": prompt]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 256
            ]
        ]

        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlStr) else {
            throw MCPError.toolFailed("Invalid Gemini API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw MCPError.toolFailed("Gemini API error (HTTP \(statusCode)): \(body)")
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw MCPError.toolFailed("Unexpected Gemini response format")
        }

        // Strip markdown fences if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.split(separator: "\n", maxSplits: 1).last ?? "")
            if let idx = cleaned.lastIndex(of: "`") {
                cleaned = String(cleaned[cleaned.startIndex..<idx])
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let boxData = try JSONSerialization.jsonObject(
            with: Data(cleaned.utf8)
        ) as? [String: Any],
              let box = boxData["box_2d"] as? [Int],
              box.count == 4 else {
            throw MCPError.toolFailed("VLM returned invalid bounding box: \(cleaned)")
        }

        return BoundingRegion(
            y_min: box[0], x_min: box[1],
            y_max: box[2], x_max: box[3]
        )
    }

    // MARK: - Step 3: Frame & Export

    static func frameAndExport(
        screenshot: CGImage,
        region: BoundingRegion,
        preset: PlatformPreset
    ) async throws -> ExportResult {
        let imgW = CGFloat(screenshot.width)
        let imgH = CGFloat(screenshot.height)
        let aspect = preset.aspectRatio
        let margin = preset.marginFraction
        let exportW = Int(preset.exportWidth)
        let exportH = Int((preset.exportWidth / aspect).rounded())

        // Convert 0-1000 → pixels
        let contentX0 = CGFloat(region.x_min) / 1000.0 * imgW
        let contentY0 = CGFloat(region.y_min) / 1000.0 * imgH
        let contentX1 = CGFloat(region.x_max) / 1000.0 * imgW
        let contentY1 = CGFloat(region.y_max) / 1000.0 * imgH
        let contentW = contentX1 - contentX0
        let contentH = contentY1 - contentY0

        // Frame must place content inside safe zone
        let safeScale = max(1.0 - 2.0 * margin, 0.4)
        let minFrameW = contentW / safeScale
        let minFrameH = contentH / safeScale

        // Enforce aspect ratio
        var frameW = max(minFrameW, minFrameH * aspect)
        var frameH = frameW / aspect
        if frameH < minFrameH {
            frameH = minFrameH
            frameW = frameH * aspect
        }

        // Clamp to image bounds
        frameW = min(frameW, imgW)
        frameH = min(frameH, imgH)
        if frameW / frameH > aspect {
            frameW = frameH * aspect
        } else {
            frameH = frameW / aspect
        }

        // Center on content
        let contentCX = (contentX0 + contentX1) / 2.0
        let contentCY = (contentY0 + contentY1) / 2.0
        var frameX0 = contentCX - frameW / 2.0
        var frameY0 = contentCY - frameH / 2.0

        // Keep in bounds
        frameX0 = max(0, min(frameX0, imgW - frameW))
        frameY0 = max(0, min(frameY0, imgH - frameH))

        // Crop
        let cropRect = CGRect(x: frameX0, y: frameY0, width: frameW, height: frameH)
        guard let cropped = screenshot.cropping(to: cropRect) else {
            throw MCPError.toolFailed("Failed to crop screenshot")
        }

        // Resize if needed
        let finalImage: CGImage
        if cropped.width >= exportW && cropped.height >= exportH {
            finalImage = lanczosDownscale(cropped, toWidth: exportW, height: exportH)
        } else {
            finalImage = cropped
        }

        // Save
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "SnipTease_agent_\(preset.id)_\(timestamp).png"
        let outputURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent(filename)

        guard let pngData = encodePNG(finalImage, dpi: 144) else {
            throw MCPError.toolFailed("Failed to encode output PNG")
        }
        try pngData.write(to: outputURL)

        // Also copy to clipboard
        let nsImage = NSImage(
            cgImage: finalImage,
            size: NSSize(
                width: CGFloat(finalImage.width) / 2.0,
                height: CGFloat(finalImage.height) / 2.0
            )
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])

        return ExportResult(
            path: outputURL.path,
            width: finalImage.width,
            height: finalImage.height,
            sizeKB: pngData.count / 1024
        )
    }

    // MARK: - Lanczos Downscale

    private static func lanczosDownscale(_ image: CGImage, toWidth targetW: Int, height targetH: Int) -> CGImage {
        let ciImage = CIImage(cgImage: image)
        let scaleX = CGFloat(targetW) / CGFloat(image.width)
        let scaleY = CGFloat(targetH) / CGFloat(image.height)

        guard let lanczos = CIFilter(name: "CILanczosScaleTransform") else {
            return image
        }

        let uniformScale = min(scaleX, scaleY)
        lanczos.setValue(ciImage, forKey: kCIInputImageKey)
        lanczos.setValue(uniformScale, forKey: kCIInputScaleKey)
        lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let output = lanczos.outputImage else { return image }
        let cropped = output.cropped(to: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? image.colorSpace
            ?? CGColorSpaceCreateDeviceRGB()

        if let result = ciContext.createCGImage(
            cropped, from: cropped.extent,
            format: .RGBA8, colorSpace: colorSpace
        ) {
            return result
        }
        return image
    }

    // MARK: - PNG Encoding

    private static func encodePNG(_ image: CGImage, dpi: Double = 144.0) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1, nil
        ) else { return nil }

        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi
        ]
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
