import Foundation
import SwiftUI
import Combine

// MARK: - App State
// Central observable state shared between the menu bar UI and the overlay.
// Persists user preferences (selected preset, margin toggle) via UserDefaults.

@MainActor
final class AppState: ObservableObject {

    private enum Keys {
        static let selectedPresetID = "selectedPresetID"
        static let showMargins = "showMargins"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    // Currently selected platform preset — restored from UserDefaults on init
    @Published var selectedPreset: PlatformPreset {
        didSet {
            UserDefaults.standard.set(selectedPreset.id, forKey: Keys.selectedPresetID)
        }
    }

    // Whether the overlay guide is currently visible on screen
    @Published var isOverlayActive: Bool = false

    // Frame of the guide rectangle in screen coordinates
    @Published var guideFrame: CGRect = .zero

    // Show/hide margin guides — restored from UserDefaults on init
    @Published var showMargins: Bool {
        didSet {
            UserDefaults.standard.set(showMargins, forKey: Keys.showMargins)
        }
    }

    // Most recent captured image
    @Published var lastCapture: NSImage? = nil

    // Status message shown briefly in the menu
    @Published var statusMessage: String? = nil

    // Whether onboarding has been completed
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    // ── Init (restore persisted preferences) ──────────────────

    init() {
        // Restore last selected preset, falling back to default
        let savedID = UserDefaults.standard.string(forKey: Keys.selectedPresetID)
        let allPresets = PlatformPreset.allPresets.flatMap { $0.presets }
        self.selectedPreset = allPresets.first { $0.id == savedID } ?? .defaultPreset

        // Restore margins toggle (default: true)
        if UserDefaults.standard.object(forKey: Keys.showMargins) != nil {
            self.showMargins = UserDefaults.standard.bool(forKey: Keys.showMargins)
        } else {
            self.showMargins = true
        }
    }

    // ── Actions ────────────────────────────────────────────────

    func activateOverlay() {
        isOverlayActive = true
    }

    func dismissOverlay() {
        isOverlayActive = false
    }

    func toggleOverlay() {
        isOverlayActive.toggle()
    }

    func selectPreset(_ preset: PlatformPreset) {
        selectedPreset = preset
    }

    func flashStatus(_ message: String) {
        statusMessage = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.statusMessage == message {
                self?.statusMessage = nil
            }
        }
    }
}
