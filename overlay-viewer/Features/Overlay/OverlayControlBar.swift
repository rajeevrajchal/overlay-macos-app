import SwiftUI

/// The overlay's floating instrument panel. Not a flat strip: a left cluster of
/// window actions (close · remove) and an isolated, labelled Opacity module with
/// a live percent readout and an arrow-key-nudgeable slider — the "focus ring"
/// of this app. Pure presentation over `OverlayControlsViewModel`.
struct OverlayControlBar: View {

    @ObservedObject var viewModel: OverlayControlsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var opacityAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85)
    }

    var body: some View {
        HStack(spacing: DesignTokens.Space.md) {
            actionCluster
            Spacer(minLength: DesignTokens.Space.sm)
            opacityModule
        }
        .padding(.horizontal, DesignTokens.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: Window actions

    private var actionCluster: some View {
        HStack(spacing: DesignTokens.Space.sm) {
            Button(action: viewModel.requestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close overlay")
            .accessibilityLabel("Close overlay")

            Button("Remove", action: viewModel.requestRemove)
                .buttonStyle(.plain)
                .font(.callout)
                .help("Remove image and return to the start screen")
                .accessibilityLabel("Remove image")
        }
        .foregroundStyle(.primary)
    }

    // MARK: Opacity module

    private var opacityModule: some View {
        HStack(spacing: DesignTokens.Space.sm) {
            Text("Opacity")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()

            Slider(
                value: $viewModel.opacity,
                in: OverlayControlsViewModel.range,
                step: OverlayControlsViewModel.nudgeStep
            )
            .controlSize(.small)
            .frame(minWidth: 90, maxWidth: 150)
            .tint(DesignTokens.accent)
            .animation(opacityAnimation, value: viewModel.opacity)
            .accessibilityLabel("Opacity")
            .accessibilityValue(viewModel.accessibilityOpacityValue)

            Text("\(viewModel.opacityPercent)%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: 40, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(opacityAnimation, value: viewModel.opacity)
                .accessibilityHidden(true)
        }
    }
}
