import SwiftUI

/// The overlay's floating instrument panel. Three distinct clusters, not a flat
/// strip: the window's native traffic lights (drawn by the system in the
/// reserved left inset), a primary "Change" chip-button, and an isolated Opacity
/// module that reads as its own instrument. Pure presentation over
/// `OverlayControlsViewModel`.
struct OverlayControlBar: View {

    @ObservedObject var viewModel: OverlayControlsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var changeHovering = false

    private var opacityAnimation: Animation? {
        // A touch of resistance so the value settles rather than snaps — like an
        // aperture ring. Skipped under Reduce Motion.
        reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.9)
    }

    /// Left inset that clears the window's native traffic-light control so the
    /// bar's own controls never sit underneath it.
    private let trafficLightInset: CGFloat = 56

    var body: some View {
        HStack(spacing: DesignTokens.Space.md) {
            changeButton
            Spacer(minLength: DesignTokens.Space.md)
            opacityModule
        }
        .padding(.leading, trafficLightInset)
        .padding(.trailing, DesignTokens.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        // A hairline seam separating this chrome from the canvas below. The
        // ribbon behind this view already supplies the vibrant material
        // "elevation"; this just sharpens the boundary.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
        }
        // The window is titled + full-size-content, so SwiftUI would otherwise
        // inset this hosted bar downward by the titlebar height and clip it
        // inside the ribbon. We reserve the traffic-light space ourselves via
        // `trafficLightInset`, so ignore the titlebar safe area and fill it.
        .ignoresSafeArea()
    }

    // MARK: Change — primary action, a real chip-button

    // Closing is handled by the window's native red traffic light; the bar owns
    // "Clear" — drop the current reference and return to the "Add a reference"
    // start screen.
    private var changeButton: some View {
        Button(action: viewModel.requestRemove) {
            Label("Clear", systemImage: "trash")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                        .fill(Color.primary.opacity(changeHovering ? 0.12 : 0.06))
                )
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                changeHovering = hovering
            }
        }
        .help("Clear the current reference image")
        .accessibilityLabel("Clear reference image")
        .accessibilityHint("Removes the current image and returns to the start screen")
    }

    // MARK: Opacity — treated as an instrument, not inline text

    private var opacityModule: some View {
        HStack(spacing: DesignTokens.Space.sm) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Slider(
                value: $viewModel.opacity,
                in: OverlayControlsViewModel.range,
                step: OverlayControlsViewModel.nudgeStep
            )
            .controlSize(.small)
            .frame(minWidth: 100, maxWidth: 150)
            .tint(DesignTokens.accent)
            .animation(opacityAnimation, value: viewModel.opacity)
            .accessibilityLabel("Opacity")
            .accessibilityValue(viewModel.accessibilityOpacityValue)

            // Fixed width + monospaced digits so the toolbar never shifts as the
            // number goes 9% → 100%.
            Text("\(viewModel.opacityPercent)%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(opacityAnimation, value: viewModel.opacity)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DesignTokens.Space.md)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
