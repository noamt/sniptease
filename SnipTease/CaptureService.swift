import AppKit
import ScreenCaptureKit
import ImageIO
import CoreGraphics
import CoreImage
import UniformTypeIdentifiers

// MARK: - Capture Service
//
// Quality strategy:
//   1. Capture at full native Retina resolution (1:1 with sourceRect pixels).
//      This avoids ScreenCaptureKit letterboxing entirely.
//   2. If native resolution ≥ export target → Lanczos downscale to exact export
//      dimensions. Downscaling from more pixels always looks sharp.
//   3. If native resolution < export target → keep native resolution as-is.
//      Upscaling manufactures pixels that don't exist and looks soft.
//      The image is already the correct aspect ratio and is pixel-perfect.
//      Social platforms handle minor size differences gracefully.

@MainActor
final class CaptureService {

    private static let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true
    ])

    static func capture(rect: CGRect, preset: PlatformPreset, screen: NSScreen? = nil) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )

            let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
            guard let targetScreen else {
                print("SnipTease: No screen available"); return
            }

            // Match NSScreen to SCDisplay via CGDirectDisplayID.
            let screenDisplayID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            let display = content.displays.first(where: { $0.displayID == screenDisplayID })
                ?? content.displays.first
            guard let display else {
                print("SnipTease: No display found"); return
            }

            let backingScale = targetScreen.backingScaleFactor   // 2.0 on Retina

            // Snap sourceRect to pixel boundaries in POINT space.
            // On a 2× display, each pixel = 0.5pt, so we round to 0.5pt steps.
            let pixelPt = 1.0 / backingScale               // 0.5pt on 2× Retina
            let x0 = (rect.origin.x / pixelPt).rounded(.down) * pixelPt
            let y0 = (rect.origin.y / pixelPt).rounded(.down) * pixelPt
            let x1 = ((rect.origin.x + rect.width) / pixelPt).rounded(.up) * pixelPt
            let y1 = ((rect.origin.y + rect.height) / pixelPt).rounded(.up) * pixelPt

            let sourceRect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)

            // Output in full Retina pixels
            let nativeW = Int((sourceRect.width * backingScale).rounded())
            let nativeH = Int((sourceRect.height * backingScale).rounded())

            // Exclude SnipTease's own windows so we never accidentally
            // capture the overlay, even if it hasn't fully disappeared.
            let myBundleID = Bundle.main.bundleIdentifier ?? ""
            let myWindows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == myBundleID
            }

            let filter = SCContentFilter(display: display, excludingWindows: myWindows)
            let config = SCStreamConfiguration()
            config.sourceRect = sourceRect
            config.width = nativeW
            config.height = nativeH
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            // Use the display's native color space (Display P3 on modern Macs)
            // instead of forcing sRGB, which would cause a color-space conversion
            // and potential resampling. The PNG will embed the correct profile.
            config.colorSpaceName = CGColorSpace.displayP3

            let nativeImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            print("SnipTease: Captured \(nativeImage.width)×\(nativeImage.height) Retina pixels (backing scale \(backingScale)×)")

            // Determine export dimensions
            let exportW = max(Int(preset.exportWidth.rounded()), 1)
            let exportH = max(Int((preset.exportWidth / preset.aspectRatio).rounded()), 1)

            let finalImage: CGImage

            if nativeImage.width >= exportW && nativeImage.height >= exportH {
                // Native is bigger — downscale with Lanczos (sharp result)
                if nativeImage.width == exportW && nativeImage.height == exportH {
                    finalImage = nativeImage
                } else {
                    finalImage = lanczosDownscale(nativeImage, toWidth: exportW, height: exportH)
                }
                print("SnipTease: Downscaled to \(finalImage.width)×\(finalImage.height)")
            } else {
                // Native is smaller than export — keep native resolution.
                // Upscaling would only make it blurry. The native capture is
                // already the correct aspect ratio and is the sharpest output
                // we can produce from this screen region.
                finalImage = nativeImage
                print("SnipTease: Keeping native \(nativeImage.width)×\(nativeImage.height) " +
                      "(sharper than upscaling to \(exportW)×\(exportH))")
            }

            // Encode to PNG with correct DPI (72 × backingScale = 144 on Retina)
            let dpi = 72.0 * backingScale
            guard let pngData = encodePNG(finalImage, dpi: dpi) else {
                print("SnipTease: Failed to encode PNG"); return
            }

            // Save to Desktop
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            let filename = "SnipTease_\(preset.id)_\(timestamp).png"
            let desktopURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
                .appendingPathComponent(filename)

            try pngData.write(to: desktopURL)

            // Copy to clipboard — use point size (pixels / backingScale)
            // so paste targets display the image at the correct dimensions
            let nsImage = NSImage(
                cgImage: finalImage,
                size: NSSize(
                    width: CGFloat(finalImage.width) / backingScale,
                    height: CGFloat(finalImage.height) / backingScale
                )
            )
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([nsImage])

            print("SnipTease: Saved \(pngData.count / 1024)KB → \(desktopURL.lastPathComponent) + clipboard")
            NSSound(named: "Tink")?.play()

        } catch {
            print("SnipTease: Capture error — \(error.localizedDescription)")
        }
    }

    // MARK: - Lanczos Downscale via Core Image

    private static func lanczosDownscale(_ image: CGImage, toWidth targetW: Int, height targetH: Int) -> CGImage {
        let ciImage = CIImage(cgImage: image)
        let scaleX = CGFloat(targetW) / CGFloat(image.width)
        let scaleY = CGFloat(targetH) / CGFloat(image.height)

        // CILanczosScaleTransform is purpose-built for high-quality downscaling
        guard let lanczos = CIFilter(name: "CILanczosScaleTransform") else {
            return cgContextDownscale(image, toWidth: targetW, height: targetH)
        }

        // Use uniform scale (the aspect ratios should match, but use the
        // smaller factor to guarantee we fit, then crop if needed)
        let uniformScale = min(scaleX, scaleY)

        lanczos.setValue(ciImage, forKey: kCIInputImageKey)
        lanczos.setValue(uniformScale, forKey: kCIInputScaleKey)
        lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let output = lanczos.outputImage else {
            return cgContextDownscale(image, toWidth: targetW, height: targetH)
        }

        // Crop to exact export dimensions (handles any sub-pixel overshoot)
        let cropped = output.cropped(to: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? image.colorSpace
            ?? CGColorSpaceCreateDeviceRGB()

        if let result = ciContext.createCGImage(
            cropped,
            from: cropped.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ) {
            return result
        }

        return cgContextDownscale(image, toWidth: targetW, height: targetH)
    }

    // MARK: - CGContext Fallback

    private static func cgContextDownscale(_ image: CGImage, toWidth targetW: Int, height targetH: Int) -> CGImage {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: targetW,
                height: targetH,
                bitsPerComponent: image.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        return ctx.makeImage() ?? image
    }

    // MARK: - PNG Encoding

    private static func encodePNG(_ image: CGImage, dpi: Double = 144.0) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1, nil
        ) else { return nil }

        // Embed DPI so Preview and other apps display at the correct size.
        // Native macOS screenshots use 144 DPI on Retina (72 × 2).
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi
        ]
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(dest) else { return nil }

        // Modern macOS ImageIO writes a cICP chunk (ITU-T H.273 color coding points)
        // alongside the iCCP chunk for P3 images. Finder's Quick Look doesn't understand
        // cICP yet and falls back to a generic PNG placeholder. Strip it from the stream.
        return stripPNGChunk("cICP", from: data as Data) ?? (data as Data)
    }

    // Rebuilds a PNG byte stream with all chunks of the given type removed.
    private static func stripPNGChunk(_ chunkType: String, from data: Data) -> Data? {
        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        guard data.prefix(8) == pngSignature else { return nil }

        var result = Data(pngSignature)
        var offset = 8
        let typeBytes = Array(chunkType.utf8)

        while offset + 8 <= data.count {
            let length = Int(data[offset...offset+3].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            let type = Array(data[offset+4..<offset+8])
            let chunkEnd = offset + 8 + length + 4
            guard chunkEnd <= data.count else { break }

            if type != typeBytes {
                result.append(data[offset..<chunkEnd])
            }
            offset = chunkEnd
        }
        return result
    }
}
