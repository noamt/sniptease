import Foundation

// MARK: - Platform Presets
// Defines aspect ratios and recommended content margins for each social platform.

struct PlatformPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String            // SF Symbol name
    let aspectWidth: CGFloat
    let aspectHeight: CGFloat
    /// Fraction of the frame to keep as "safe zone" margin on each side (0.0–0.5)
    let marginFraction: CGFloat
    /// Recommended export pixel width
    let exportWidth: CGFloat

    var aspectRatio: CGFloat { aspectWidth / aspectHeight }

    // Human-readable ratio label
    var ratioLabel: String {
        let w = Int(aspectWidth)
        let h = Int(aspectHeight)
        return "\(w):\(h)"
    }
}

// MARK: - Built-in Presets

extension PlatformPreset {

    // ── LinkedIn ────────────────────────────────────────────────
    static let linkedInFeed = PlatformPreset(
        id: "linkedin-feed",
        name: "LinkedIn Feed",
        icon: "briefcase.fill",
        aspectWidth: 1200,
        aspectHeight: 1200,
        marginFraction: 0.08,
        exportWidth: 1200
    )

    static let linkedInLandscape = PlatformPreset(
        id: "linkedin-landscape",
        name: "LinkedIn Landscape",
        icon: "briefcase",
        aspectWidth: 1200,
        aspectHeight: 627,
        marginFraction: 0.06,
        exportWidth: 1200
    )

    // ── X (Twitter) ────────────────────────────────────────────
    static let xSquare = PlatformPreset(
        id: "x-square",
        name: "X Square",
        icon: "bubble.left.fill",
        aspectWidth: 1,
        aspectHeight: 1,
        marginFraction: 0.07,
        exportWidth: 1080
    )

    static let xLandscape = PlatformPreset(
        id: "x-landscape",
        name: "X Landscape",
        icon: "bubble.left",
        aspectWidth: 16,
        aspectHeight: 9,
        marginFraction: 0.06,
        exportWidth: 1200
    )

    // ── Instagram ──────────────────────────────────────────────
    static let instagramSquare = PlatformPreset(
        id: "ig-square",
        name: "Instagram Square",
        icon: "camera.fill",
        aspectWidth: 1,
        aspectHeight: 1,
        marginFraction: 0.08,
        exportWidth: 1080
    )

    static let instagramPortrait = PlatformPreset(
        id: "ig-portrait",
        name: "Instagram Portrait",
        icon: "camera",
        aspectWidth: 4,
        aspectHeight: 5,
        marginFraction: 0.08,
        exportWidth: 1080
    )

    static let instagramStory = PlatformPreset(
        id: "ig-story",
        name: "Instagram Story",
        icon: "camera.badge.clock",
        aspectWidth: 9,
        aspectHeight: 16,
        marginFraction: 0.10,
        exportWidth: 1080
    )

    // ── OG / Meta Tags ──────────────────────────────────────────
    static let ogStandard = PlatformPreset(
        id: "og-standard",
        name: "OG Image",
        icon: "globe",
        aspectWidth: 1200,
        aspectHeight: 630,
        marginFraction: 0.06,
        exportWidth: 1200
    )

    static let ogRetina = PlatformPreset(
        id: "og-retina",
        name: "OG Image @2x",
        icon: "globe.badge.chevron.backward",
        aspectWidth: 1200,
        aspectHeight: 630,
        marginFraction: 0.06,
        exportWidth: 2400
    )

    static let twitterCard = PlatformPreset(
        id: "twitter-card",
        name: "X / Twitter Card",
        icon: "rectangle.landscape.rotate",
        aspectWidth: 2,
        aspectHeight: 1,
        marginFraction: 0.06,
        exportWidth: 1600
    )

    // ── All presets, grouped ───────────────────────────────────
    static let allPresets: [(platform: String, presets: [PlatformPreset])] = [
        ("OG / Meta", [ogStandard, ogRetina, twitterCard]),
        ("LinkedIn", [linkedInFeed, linkedInLandscape]),
        ("X", [xSquare, xLandscape]),
        ("Instagram", [instagramSquare, instagramPortrait, instagramStory])
    ]

    static let defaultPreset = instagramPortrait
}
