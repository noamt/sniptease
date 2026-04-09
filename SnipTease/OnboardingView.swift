import SwiftUI
import AppKit

// MARK: - Onboarding Window Controller
// Presents a centered, dark-themed onboarding window on first launch.

@MainActor
final class OnboardingWindowController {

    private var window: NSWindow?
    private let appState: AppState
    private let onComplete: () -> Void

    init(appState: AppState, onComplete: @escaping () -> Void) {
        self.appState = appState
        self.onComplete = onComplete
    }

    func show() {
        guard window == nil else { return }

        let onboardingView = OnboardingView(
            onComplete: { [weak self] in
                self?.appState.hasCompletedOnboarding = true
                UserDefaults.standard.removeObject(forKey: "onboardingStep")
                self?.dismiss()
                self?.onComplete()
            }
        )

        let hostingController = NSHostingController(rootView: onboardingView)
        hostingController.sizingOptions = [.preferredContentSize]

        let w = NSWindow(contentViewController: hostingController)
        w.title = "Welcome to SnipTease"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        w.setContentSize(NSSize(width: 480, height: 560))
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .normal

        // Fade in
        w.alphaValue = 0
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            w.animator().alphaValue = 1
        }

        window = w
    }

    private func dismiss() {
        guard let w = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            w.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            w.orderOut(nil)
            self?.window = nil
        })
    }
}

// MARK: - Onboarding View
// 4-step flow: Welcome → Screen Recording → Accessibility → Ready

struct OnboardingView: View {

    let onComplete: () -> Void

    // Persist the current step so relaunch resumes where we left off
    @State private var currentStep = UserDefaults.standard.integer(forKey: "onboardingStep")
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false
    @State private var checkingPermission = false
    @State private var pollingAccessibility = false
    @State private var pollingScreenRecording = false

    private let accent = Color(red: 0.38, green: 0.56, blue: 1.0)
    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // ── Step content ──────────────────────────────────────
            ZStack {
                if currentStep == 0 { welcomeStep.transition(stepTransition) }
                if currentStep == 1 { screenRecordingStep.transition(stepTransition) }
                if currentStep == 2 { accessibilityStep.transition(stepTransition) }
                if currentStep == 3 { readyStep.transition(stepTransition) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentStep)

            // ── Bottom bar ────────────────────────────────────────
            bottomBar
        }
        .frame(width: 480, height: 560)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
        .preferredColorScheme(.dark)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.14, green: 0.14, blue: 0.18),
                                Color(red: 0.10, green: 0.10, blue: 0.14)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: accent.opacity(0.2), radius: 20, y: 4)

                Image(systemName: "crop")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(accent)
            }

            VStack(spacing: 10) {
                Text("Welcome to SnipTease")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("Pixel-perfect screenshots sized for\nLinkedIn, X, and Instagram — in one click.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()

            // Feature highlights
            VStack(spacing: 12) {
                featureRow(icon: "aspectratio", text: "Live aspect ratio guides on your screen")
                featureRow(icon: "square.dashed.inset.filled", text: "Content-safe margin zones built in")
                featureRow(icon: "keyboard", text: "Global hotkey — capture without switching apps")
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding(.top, 20)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accent.opacity(0.1))
                )
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
        }
    }

    // MARK: - Step 2: Screen Recording Permission

    private var screenRecordingStep: some View {
        VStack(spacing: 24) {
            Spacer()

            permissionIcon(
                symbol: "record.circle",
                tint: accent
            )

            VStack(spacing: 10) {
                Text("Screen Recording Access")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                Text("SnipTease captures a region of your screen to create\nscreenshots. macOS requires your permission for this.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()

            if screenRecordingGranted {
                grantedBadge("Screen Recording enabled")
            } else {
                VStack(spacing: 12) {
                    permissionButton(
                        label: "Grant Access",
                        icon: "lock.shield",
                        isLoading: checkingPermission,
                        action: requestScreenRecording
                    )

                    Text("A system dialog will appear. Click Allow, then\nreturn here if needed.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            privacyNote("SnipTease never records video or sends data off your Mac.")

            Spacer().frame(height: 8)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: screenRecordingGranted)
        .onAppear {
            // Silent check — CGPreflightScreenCaptureAccess doesn't prompt
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        }
    }

    // MARK: - Step 3: Accessibility Permission

    private var accessibilityStep: some View {
        VStack(spacing: 24) {
            Spacer()

            permissionIcon(
                symbol: "hand.raised.fill",
                tint: Color.orange
            )

            VStack(spacing: 10) {
                Text("Accessibility Access")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                Text("SnipTease uses a global hotkey (⌃⇧S) so you can\nstart a capture from any app. macOS requires\nAccessibility permission to register this.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()

            if accessibilityGranted {
                grantedBadge("Accessibility enabled")
            } else {
                VStack(spacing: 12) {
                    permissionButton(
                        label: "Open Settings",
                        icon: "gearshape",
                        isLoading: false,
                        action: requestAccessibility
                    )

                    Text("Toggle SnipTease on in the list, then come back here.\nThe button below will light up automatically.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }

            Spacer()

            privacyNote("Only used for the global hotkey — nothing else is monitored.")

            Spacer().frame(height: 8)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: accessibilityGranted)
        .onAppear { startPollingAccessibility() }
        .onDisappear { pollingAccessibility = false }
    }

    // MARK: - Step 4: Ready

    private var readyStep: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.green)
            }

            VStack(spacing: 10) {
                Text("You're all set!")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                Text("SnipTease lives in your menu bar.\nHere's how to use it:")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()

            VStack(spacing: 14) {
                tipRow(
                    step: "1",
                    title: "Click the crop icon in your menu bar",
                    subtitle: "Pick a platform and aspect ratio"
                )
                tipRow(
                    step: "2",
                    title: "Hit Start Capture or press ⌃⇧S",
                    subtitle: "A guide frame appears on your screen"
                )
                tipRow(
                    step: "3",
                    title: "Position the frame and press Return",
                    subtitle: "Screenshot saved to Desktop + clipboard"
                )
            }
            .padding(.horizontal, 36)

            Spacer()
        }
    }

    private func tipRow(step: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(accent)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.35))
            }
            Spacer()
        }
    }

    // MARK: - Shared Components

    private func permissionIcon(symbol: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.1))
                .frame(width: 72, height: 72)
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(tint)
        }
    }

    private func grantedBadge(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.green)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(
            Capsule().fill(Color.green.opacity(0.1))
        )
        .transition(.scale.combined(with: .opacity))
    }

    private func permissionButton(
        label: String,
        icon: String,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                }
                Text(isLoading ? "Checking…" : label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func privacyNote(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundColor(.white.opacity(0.25))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            HStack {
                // Step indicators
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Capsule()
                            .fill(index == currentStep ? accent : Color.white.opacity(0.15))
                            .frame(width: index == currentStep ? 20 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStep)
                    }
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    // Skip on welcome and permission steps
                    if currentStep == 0 || currentStep == 2 {
                        Button("Skip") { advanceStep() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12.5))
                            .foregroundColor(.white.opacity(0.35))
                            .padding(.trailing, 12)
                    }

                    Button(action: advanceStep) {
                        HStack(spacing: 4) {
                            Text(nextButtonLabel)
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(accent)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { onComplete() }) {
                        HStack(spacing: 4) {
                            Text("Start Using SnipTease")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(accent)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private var nextButtonLabel: String {
        switch currentStep {
        case 0: return "Get Started"
        case 1: return screenRecordingGranted ? "Continue" : "Continue Anyway"
        case 2: return accessibilityGranted ? "Continue" : "Skip for Now"
        default: return "Continue"
        }
    }

    // MARK: - Actions

    private func advanceStep() {
        withAnimation {
            currentStep = min(currentStep + 1, totalSteps - 1)
            UserDefaults.standard.set(currentStep, forKey: "onboardingStep")
        }
    }

    private func requestScreenRecording() {
        // CGRequestScreenCaptureAccess triggers the system dialog
        // and returns immediately (true if already granted).
        let alreadyGranted = CGRequestScreenCaptureAccess()
        if alreadyGranted {
            screenRecordingGranted = true
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                advanceStep()
            }
        } else {
            // System dialog is now showing — poll silently until
            // the user grants it (may require app relaunch).
            startPollingScreenRecording()
        }
    }

    private func startPollingScreenRecording() {
        guard !pollingScreenRecording else { return }
        pollingScreenRecording = true
        Task {
            while pollingScreenRecording && !screenRecordingGranted {
                try? await Task.sleep(for: .seconds(1))
                let granted = CGPreflightScreenCaptureAccess()
                if granted {
                    await MainActor.run {
                        screenRecordingGranted = true
                        pollingScreenRecording = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(800))
                            advanceStep()
                        }
                    }
                }
            }
        }
    }

    private func requestAccessibility() {
        // This opens System Settings → Accessibility and shows SnipTease in the list
        HotkeyManager.requestAccessibility()
        // Start polling if not already
        if !pollingAccessibility {
            startPollingAccessibility()
        }
    }

    private func startPollingAccessibility() {
        // Check immediately
        accessibilityGranted = HotkeyManager.checkAccessibilitySilently()
        guard !accessibilityGranted else { return }

        pollingAccessibility = true
        Task {
            while pollingAccessibility && !accessibilityGranted {
                try? await Task.sleep(for: .seconds(1))
                let granted = HotkeyManager.checkAccessibilitySilently()
                await MainActor.run {
                    if granted && !accessibilityGranted {
                        accessibilityGranted = true
                        pollingAccessibility = false
                        // Auto-advance
                        Task {
                            try? await Task.sleep(for: .milliseconds(800))
                            advanceStep()
                        }
                    }
                }
            }
        }
    }
}
