import SwiftUI
import AppKit

// MARK: - Overlay Content View
// Full-screen overlay with Raycast-level polish: glass morphism bars,
// refined resize handles, smooth spring animations, and subtle visual cues.

struct OverlayContentView: View {
    @ObservedObject var appState: AppState

    // Drag state
    @State private var frameOrigin: CGPoint = .zero
    @State private var frameSize: CGSize = CGSize(width: 400, height: 500)
    @State private var isDragging = false
    @State private var isResizing = false
    @State private var dragOffset: CGSize = .zero
    @State private var initialSize: CGSize = .zero
    @State private var hasInitialized = false
    @State private var isVisible = false

    // Keyboard monitor
    @State private var keyMonitor: Any?

    // Preset picker (Raycast-style mode switcher)
    @State private var showingPresetPicker = false
    @State private var pickerSelection = 0

    private var flatPresets: [PlatformPreset] {
        PlatformPreset.allPresets.flatMap(\.presets)
    }

    private let handleSize: CGFloat = 10
    private let handleTapSize: CGFloat = 24       // Larger tap target
    private let minFrameSize: CGFloat = 100
    private let accent = Color(red: 0.38, green: 0.56, blue: 1.0)

    /// Top inset to clear the notch/menu bar area
    private var topSafeInset: CGFloat {
        if let screen = NSScreen.main {
            let inset = screen.safeAreaInsets.top
            return max(inset, 30)
        }
        return 38
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let rect = guideRect

                // ── Dimmed backdrop with cutout ───────────────────
                CutoutShape(cutout: rect)
                    .fill(Color.black.opacity(isVisible ? 0.5 : 0), style: FillStyle(eoFill: true))
                    .animation(.easeOut(duration: 0.25), value: isVisible)

                // ── Guide frame border — double stroke ────────────
                guideFrameBorder(rect)

                // ── Margin guides ─────────────────────────────────
                if appState.showMargins {
                    marginGuides(rect)
                }

                // ── Center crosshair ──────────────────────────────
                centerCrosshair(rect)

                // ── Rule of thirds ────────────────────────────────
                ruleOfThirds(rect)

                // ── Dimension badge ───────────────────────────────
                dimensionBadge(rect)

                // ── Drag surface ──────────────────────────────────
                Color.clear
                    .frame(width: max(1, rect.width - handleTapSize * 2), height: max(1, rect.height - handleTapSize * 2))
                    .position(x: rect.midX, y: rect.midY)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(in: geo.size))

                // ── Corner handles ────────────────────────────────
                ForEach(Corner.allCases, id: \.self) { corner in
                    resizeHandle(corner: corner, in: geo.size)
                }

                // ── Edge midpoint marks ───────────────────────────
                edgeMarks(rect)

                // ── Top instruction bar ───────────────────────────
                VStack {
                    Spacer().frame(height: topSafeInset + 8)
                    instructionBar
                    Spacer()
                }
                .zIndex(10)

                // ── Preset picker (mode switcher) ─────────────────
                if showingPresetPicker {
                    VStack {
                        Spacer().frame(height: topSafeInset + 70)
                        PresetPickerView(
                            presets: flatPresets,
                            currentPresetID: appState.selectedPreset.id,
                            selectedIndex: $pickerSelection,
                            onSelect: { preset in
                                appState.selectPreset(preset)
                                closePresetPicker()
                            }
                        )
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(20)
                }
            }
            .onAppear {
                if !hasInitialized {
                    initializeFrame(in: geo.size)
                    hasInitialized = true
                }
                installKeyMonitor()
                withAnimation(.easeOut(duration: 0.3)) {
                    isVisible = true
                }
            }
            .onDisappear {
                removeKeyMonitor()
            }
            .onChange(of: appState.selectedPreset) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    recalculateSize(in: geo.size)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissOverlay)) { _ in
                appState.dismissOverlay()
            }
            .onReceive(NotificationCenter.default.publisher(for: .captureRequested)) { _ in
                performCapture()
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Guide Frame Border

    private func guideFrameBorder(_ rect: CGRect) -> some View {
        ZStack {
            // Outer glow
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(accent.opacity(0.25), lineWidth: 3)
                .frame(width: rect.width + 4, height: rect.height + 4)
                .position(x: rect.midX, y: rect.midY)
                .blur(radius: 2)

            // Main border
            Rectangle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Corner accent brackets
            ForEach(Corner.allCases, id: \.self) { corner in
                cornerBracket(corner: corner, in: rect)
            }
        }
    }

    private func cornerBracket(corner: Corner, in rect: CGRect) -> some View {
        let pos = corner.position(in: rect)
        let armLen: CGFloat = 20

        return Path { path in
            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: pos.x, y: pos.y + armLen))
                path.addLine(to: pos)
                path.addLine(to: CGPoint(x: pos.x + armLen, y: pos.y))
            case .topRight:
                path.move(to: CGPoint(x: pos.x - armLen, y: pos.y))
                path.addLine(to: pos)
                path.addLine(to: CGPoint(x: pos.x, y: pos.y + armLen))
            case .bottomLeft:
                path.move(to: CGPoint(x: pos.x, y: pos.y - armLen))
                path.addLine(to: pos)
                path.addLine(to: CGPoint(x: pos.x + armLen, y: pos.y))
            case .bottomRight:
                path.move(to: CGPoint(x: pos.x - armLen, y: pos.y))
                path.addLine(to: pos)
                path.addLine(to: CGPoint(x: pos.x, y: pos.y - armLen))
            }
        }
        .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Margin Guides

    private func marginGuides(_ rect: CGRect) -> some View {
        let margin = appState.selectedPreset.marginFraction
        let insetX = rect.width * margin
        let insetY = rect.height * margin
        let marginRect = rect.insetBy(dx: insetX, dy: insetY)

        return ZStack {
            // Dashed margin rectangle
            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 0.8, dash: [5, 4]))
                .foregroundColor(accent.opacity(0.4))
                .frame(width: marginRect.width, height: marginRect.height)
                .position(x: marginRect.midX, y: marginRect.midY)

            // Corner ticks on the margin box
            ForEach(Corner.allCases, id: \.self) { corner in
                let pos = corner.position(in: marginRect)
                Circle()
                    .fill(accent.opacity(0.35))
                    .frame(width: 4, height: 4)
                    .position(x: pos.x, y: pos.y)
            }

            // "SAFE" label
            Text("SAFE ZONE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(accent.opacity(0.35))
                .tracking(1.5)
                .position(x: marginRect.midX, y: marginRect.minY - 10)
        }
    }

    // MARK: - Center Crosshair

    private func centerCrosshair(_ rect: CGRect) -> some View {
        let cx = rect.midX
        let cy = rect.midY
        let gap: CGFloat = 6   // breathing room around the center point

        let crossPath = Path { path in
            // horizontal
            path.move(to: CGPoint(x: rect.minX, y: cy))
            path.addLine(to: CGPoint(x: cx - gap, y: cy))
            path.move(to: CGPoint(x: cx + gap, y: cy))
            path.addLine(to: CGPoint(x: rect.maxX, y: cy))
            // vertical
            path.move(to: CGPoint(x: cx, y: rect.minY))
            path.addLine(to: CGPoint(x: cx, y: cy - gap))
            path.move(to: CGPoint(x: cx, y: cy + gap))
            path.addLine(to: CGPoint(x: cx, y: rect.maxY))
        }
        let dash = StrokeStyle(lineWidth: 0.7, dash: [4, 4])

        return ZStack {
            // dark shadow for contrast on light backgrounds
            crossPath.stroke(Color.black.opacity(0.2), style: dash)
            // white line for contrast on dark backgrounds
            crossPath.stroke(Color.white.opacity(0.3), style: dash)

            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 5, height: 5)
                .position(x: cx, y: cy)
        }
    }

    // MARK: - Rule of Thirds

    private func ruleOfThirds(_ rect: CGRect) -> some View {
        let gridPath = Path { path in
            for i in 1...2 {
                let x = rect.minX + rect.width / 3 * CGFloat(i)
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            for i in 1...2 {
                let y = rect.minY + rect.height / 3 * CGFloat(i)
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }

        return ZStack {
            gridPath.stroke(Color.black.opacity(0.1), lineWidth: 0.5)
            gridPath.stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        }
    }

    // MARK: - Edge Midpoint Marks

    private func edgeMarks(_ rect: CGRect) -> some View {
        let markLen: CGFloat = 6
        return Path { path in
            // Top
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + markLen))
            // Bottom
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - markLen))
            // Left
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + markLen, y: rect.midY))
            // Right
            path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - markLen, y: rect.midY))
        }
        .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
    }

    // MARK: - Dimension Badge

    private func dimensionBadge(_ rect: CGRect) -> some View {
        let preset = appState.selectedPreset
        let exportH = preset.exportWidth / preset.aspectRatio

        return HStack(spacing: 6) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9))
                .foregroundColor(accent.opacity(0.8))
            Text("\(Int(preset.exportWidth)) × \(Int(exportH))")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .position(x: rect.midX, y: rect.maxY + 22)
    }

    // MARK: - Instruction Bar

    private var instructionBar: some View {
        HStack(spacing: 0) {
            // Platform badge — clickable to open mode switcher
            Button(action: {
                if showingPresetPicker {
                    closePresetPicker()
                } else {
                    openPresetPicker()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: appState.selectedPreset.icon)
                        .font(.system(size: 11))
                    Text(appState.selectedPreset.name)
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(0.7)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(accent.opacity(showingPresetPicker ? 0.45 : 0.25))
                )
            }
            .buttonStyle(.plain)

            Spacer().frame(width: 12)

            Text(appState.selectedPreset.ratioLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            Spacer()

            // Shortcut hints
            HStack(spacing: 12) {
                shortcutHint("Tab", "Mode")
                shortcutHint("⏎", "Capture")
                shortcutHint("Esc", "Cancel")
            }

            Spacer().frame(width: 16)

            // Margin toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    appState.showMargins.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: appState.showMargins ? "square.dashed.inset.filled" : "square.dashed")
                        .font(.system(size: 11))
                    Text("Margins")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(appState.showMargins ? 0.9 : 0.45))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(appState.showMargins ? accent.opacity(0.2) : Color.white.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 4)
        .padding(.horizontal, 40)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -8)
        .animation(.easeOut(duration: 0.3).delay(0.1), value: isVisible)
    }

    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    // MARK: - Keyboard Handling

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = CGKeyCode(event.keyCode)

            // ── Picker is open: route keys to the picker ──────
            if showingPresetPicker {
                switch code {
                case KeyCode.escape:
                    closePresetPicker()
                    return nil
                case KeyCode.returnKey:
                    let preset = flatPresets[pickerSelection]
                    appState.selectPreset(preset)
                    closePresetPicker()
                    return nil
                case KeyCode.downArrow:
                    pickerSelection = min(pickerSelection + 1, flatPresets.count - 1)
                    return nil
                case KeyCode.upArrow:
                    pickerSelection = max(pickerSelection - 1, 0)
                    return nil
                case KeyCode.tab:
                    closePresetPicker()
                    return nil
                default:
                    // Swallow all other keys while picker is open
                    return nil
                }
            }

            // ── Picker is closed: normal overlay keys ─────────
            switch code {
            case KeyCode.returnKey:
                performCapture()
                return nil
            case KeyCode.escape:
                appState.dismissOverlay()
                return nil
            case KeyCode.tab:
                openPresetPicker()
                return nil
            default:
                return event
            }
        }
    }

    private func openPresetPicker() {
        if let idx = flatPresets.firstIndex(where: { $0.id == appState.selectedPreset.id }) {
            pickerSelection = idx
        } else {
            pickerSelection = 0
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showingPresetPicker = true
        }
    }

    private func closePresetPicker() {
        withAnimation(.easeOut(duration: 0.18)) {
            showingPresetPicker = false
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Computed

    private var guideRect: CGRect {
        CGRect(origin: frameOrigin, size: frameSize)
    }

    // MARK: - Frame Initialization

    private func initializeFrame(in screenSize: CGSize) {
        let guide = suggestedGuideRect(in: screenSize)
        frameSize = guide.size
        frameOrigin = guide.origin
    }

    private func recalculateSize(in screenSize: CGSize) {
        let guide = suggestedGuideRect(in: screenSize, fallbackCenter: guideRect.center)
        frameSize = guide.size
        frameOrigin = guide.origin
    }

    private func suggestedGuideRect(
        in screenSize: CGSize,
        fallbackCenter: CGPoint? = nil
    ) -> CGRect {
        let usableBounds = usableGuideBounds(in: screenSize)

        if let screen = NSScreen.main,
           let subjectRect = WindowSubjectDetector.frontmostWindowRect(
                on: screen,
                excludingBundleID: Bundle.main.bundleIdentifier
           ) {
            return fitGuideRect(
                around: subjectRect,
                in: usableBounds,
                preset: appState.selectedPreset
            )
        }

        return defaultGuideRect(in: usableBounds, center: fallbackCenter)
    }

    private func usableGuideBounds(in screenSize: CGSize) -> CGRect {
        let usableTop = topSafeInset + 52    // Room for instruction bar
        return CGRect(
            x: 20,
            y: usableTop + 20,
            width: screenSize.width - 40,
            height: screenSize.height - usableTop - 40
        )
    }

    private func defaultGuideRect(in usableBounds: CGRect, center: CGPoint? = nil) -> CGRect {
        let preset = appState.selectedPreset
        let maxHeight = usableBounds.height * 0.72
        let maxWidth = usableBounds.width * 0.72

        var height = maxHeight
        var width = height * preset.aspectRatio

        if width > maxWidth {
            width = maxWidth
            height = width / preset.aspectRatio
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        return place(rect, inside: usableBounds, centeredAt: center ?? usableBounds.center)
    }

    private func fitGuideRect(
        around subjectRect: CGRect,
        in usableBounds: CGRect,
        preset: PlatformPreset
    ) -> CGRect {
        let subject = subjectRect
            .intersection(usableBounds)
            .insetBy(dx: -12, dy: -12)

        guard !subject.isNull, subject.width > 0, subject.height > 0 else {
            return defaultGuideRect(in: usableBounds)
        }

        let safeScale = max(1 - (preset.marginFraction * 2), 0.4)
        let minimumWidth = subject.width / safeScale
        let minimumHeight = subject.height / safeScale

        var width = max(minimumWidth, minimumHeight * preset.aspectRatio)
        var height = width / preset.aspectRatio

        if height < minimumHeight {
            height = minimumHeight
            width = height * preset.aspectRatio
        }

        let maxWidth = usableBounds.width
        let maxHeight = usableBounds.height
        if width > maxWidth || height > maxHeight {
            let fitScale = min(maxWidth / width, maxHeight / height)
            width *= fitScale
            height *= fitScale
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        return place(rect, inside: usableBounds, centeredAt: subject.center)
    }

    private func place(_ rect: CGRect, inside bounds: CGRect, centeredAt center: CGPoint) -> CGRect {
        var origin = CGPoint(
            x: center.x - rect.width / 2,
            y: center.y - rect.height / 2
        )
        origin.x = max(bounds.minX, min(origin.x, bounds.maxX - rect.width))
        origin.y = max(bounds.minY, min(origin.y, bounds.maxY - rect.height))
        return CGRect(origin: origin, size: rect.size)
    }

    // MARK: - Gestures

    private func dragGesture(in screenSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragOffset = .zero
                }
                let newX = frameOrigin.x + value.translation.width - dragOffset.width
                let newY = frameOrigin.y + value.translation.height - dragOffset.height
                frameOrigin.x = max(0, min(newX, screenSize.width - frameSize.width))
                frameOrigin.y = max(0, min(newY, screenSize.height - frameSize.height))
                dragOffset = value.translation
            }
            .onEnded { _ in
                isDragging = false
                dragOffset = .zero
            }
    }

    private func resizeHandle(corner: Corner, in screenSize: CGSize) -> some View {
        let rect = guideRect
        let pos = corner.position(in: rect)

        return ZStack {
            // Glow
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent.opacity(0.3))
                .frame(width: handleSize + 4, height: handleSize + 4)
                .blur(radius: 3)

            // Handle
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white)
                .frame(width: handleSize, height: handleSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(accent.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        }
        .frame(width: handleTapSize, height: handleTapSize)
        .contentShape(Rectangle())
        .position(x: pos.x, y: pos.y)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isResizing {
                        isResizing = true
                        initialSize = frameSize
                    }
                    let ratio = appState.selectedPreset.aspectRatio
                    let delta = value.translation

                    var newW = initialSize.width
                    var newH = initialSize.height

                    switch corner {
                    case .bottomRight:
                        newW = max(minFrameSize, min(initialSize.width + delta.width, screenSize.width - frameOrigin.x))
                        newH = newW / ratio
                    case .bottomLeft:
                        newW = max(minFrameSize, min(initialSize.width - delta.width, rect.maxX))
                        newH = newW / ratio
                        frameOrigin.x = frameOrigin.x + (frameSize.width - newW)
                    case .topRight:
                        newW = max(minFrameSize, min(initialSize.width + delta.width, screenSize.width - frameOrigin.x))
                        newH = newW / ratio
                        frameOrigin.y = frameOrigin.y + (frameSize.height - newH)
                    case .topLeft:
                        newW = max(minFrameSize, min(initialSize.width - delta.width, rect.maxX))
                        newH = newW / ratio
                        frameOrigin.x = frameOrigin.x + (frameSize.width - newW)
                        frameOrigin.y = frameOrigin.y + (frameSize.height - newH)
                    }

                    let maxOriginX = max(0, screenSize.width - newW)
                    let maxOriginY = max(0, screenSize.height - newH)
                    frameOrigin.x = max(0, min(frameOrigin.x, maxOriginX))
                    frameOrigin.y = max(0, min(frameOrigin.y, maxOriginY))
                    frameSize = CGSize(width: newW, height: newH)
                }
                .onEnded { _ in
                    isResizing = false
                }
        )
    }

    // MARK: - Capture

    private func performCapture() {
        let rect = guideRect
        let preset = appState.selectedPreset
        appState.dismissOverlay()

        Task {
            // Wait for the overlay panel to fully fade out before capturing
            try? await Task.sleep(for: .milliseconds(300))
            await CaptureService.capture(rect: rect, preset: preset)
            appState.flashStatus("Screenshot saved!")
        }
    }
}

// MARK: - Corner Enum

enum Corner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

// MARK: - Cutout Shape

struct CutoutShape: Shape {
    let cutout: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(cutout)
        return path
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
