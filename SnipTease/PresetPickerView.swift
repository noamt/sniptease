import SwiftUI
import AppKit

// MARK: - Preset Picker (Raycast-style)
// Command-palette-style mode selector that slides down over the capture
// overlay. Arrow keys navigate, Enter selects, Esc dismisses.

struct PresetPickerView: View {
    let presets: [PlatformPreset]
    let currentPresetID: String
    @Binding var selectedIndex: Int
    let onSelect: (PlatformPreset) -> Void

    @State private var isVisible = false
    private let accent = Color(red: 0.38, green: 0.56, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(accent.opacity(0.85))

                Text("Switch Mode")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .tracking(0.3)

                Spacer()

                HStack(spacing: 10) {
                    pickerShortcut("↑↓", "Navigate")
                    pickerShortcut("↵", "Select")
                    pickerShortcut("Esc", "Close")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            // ── Preset list ────────────────────────────────────
            VStack(spacing: 2) {
                ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                    presetRow(preset, index: index)
                }
            }
            .padding(6)
        }
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .scaleEffect(isVisible ? 1 : 0.96)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                isVisible = true
            }
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: PlatformPreset, index: Int) -> some View {
        let isSelected = selectedIndex == index
        let isCurrent = preset.id == currentPresetID
        let exportH = Int(preset.exportWidth / preset.aspectRatio)

        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.25) : Color.white.opacity(0.06))
                    .frame(width: 30, height: 30)
                Image(systemName: preset.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preset.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white.opacity(isSelected ? 1.0 : 0.88))
                    if isCurrent {
                        Text("CURRENT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(accent)
                            .tracking(0.8)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(accent.opacity(0.15))
                            )
                    }
                }
                Text("\(preset.ratioLabel)  ·  \(Int(preset.exportWidth)) × \(exportH) px")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.42))
            }

            Spacer()

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.07) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(preset)
        }
        .onHover { hovering in
            if hovering {
                selectedIndex = index
            }
        }
    }

    private func pickerShortcut(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, 3.5)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(.white.opacity(0.38))
        }
    }
}
