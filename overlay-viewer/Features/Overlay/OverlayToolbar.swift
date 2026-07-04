import SwiftUI

/// The overlay's floating instrument panel — a single, self-contained,
/// reusable component. It owns everything the toolbar needs: its vibrant
/// material background, its fixed height, the hairline seam to the canvas, and
/// visually distinct clusters (the window's native traffic lights in the
/// reserved left inset, a primary "Clear" chip, a size-settings gear, and an
/// isolated Opacity module).
///
/// Drop it in with a single line — `NSHostingView(rootView: OverlayToolbar(...))`
/// — with no surrounding AppKit wrapper view. Pure presentation over
/// `OverlayControlsViewModel`.
struct OverlayToolbar: View {

    /// The toolbar's height and the single source of truth a host window uses to
    /// size content beneath it and place its resize chrome.
    static let height: CGFloat = 44

    @ObservedObject var viewModel: OverlayControlsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var clearHovering = false
    @State private var showingSizeSettings = false

    private var opacityAnimation: Animation? {
        // A touch of resistance so the value settles rather than snaps — like an
        // aperture ring. Skipped under Reduce Motion.
        reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.9)
    }

    /// Left inset that clears the window's native (red) traffic-light control so
    /// the bar's own controls never sit underneath it.
    private let trafficLightInset: CGFloat = 44

    var body: some View {
        HStack(spacing: DesignTokens.Space.sm) {
            clearButton
            sizeButton
            Spacer(minLength: DesignTokens.Space.sm)
            opacityModule
        }
        .padding(.leading, trafficLightInset)
        .padding(.trailing, DesignTokens.Space.md)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        // The component carries its own vibrant material — no external AppKit
        // effect view required.
        .background(VisualEffectView(material: .menu))
        // A hairline seam separating this chrome from the canvas below.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
        }
        // The window is titled + full-size-content, so SwiftUI would otherwise
        // inset this hosted bar downward by the titlebar height and clip it. We
        // reserve the traffic-light space ourselves via `trafficLightInset`, so
        // ignore the titlebar safe area and fill the bar.
        .ignoresSafeArea()
    }

    // MARK: Clear — primary action, collapses to icon-only when space is tight

    private var clearButton: some View {
        Button(action: viewModel.requestRemove) {
            ViewThatFits(in: .horizontal) {
                clearChip(showTitle: true)
                clearChip(showTitle: false)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                clearHovering = hovering
            }
        }
        .help("Clear the current reference image")
        .accessibilityLabel("Clear reference image")
        .accessibilityHint("Removes the current image and returns to the start screen")
    }

    private func clearChip(showTitle: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "trash")
            if showTitle { Text("Clear") }
        }
        .font(.system(size: 13, weight: .medium))
        .fixedSize()
        .padding(.horizontal, showTitle ? 10 : 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(clearHovering ? 0.12 : 0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous))
    }

    // MARK: Size — custom width/height popover

    private var sizeButton: some View {
        Button {
            showingSizeSettings.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Set a custom width and height")
        .accessibilityLabel("Size settings")
        .popover(isPresented: $showingSizeSettings, arrowEdge: .bottom) {
            SizeSettingsForm(viewModel: viewModel, isPresented: $showingSizeSettings)
        }
    }

    // MARK: Opacity — treated as an instrument, not inline text

    // Widest variant that fits wins, so the module degrades cleanly as the
    // window shrinks: full → no icon → slider only. Fixed slider widths let
    // `ViewThatFits` measure reliably (a flexible slider can't be measured).
    private var opacityModule: some View {
        ViewThatFits(in: .horizontal) {
            opacityVariant(sliderWidth: 130, showExtras: true)
            opacityVariant(sliderWidth: 90, showExtras: true)
            opacityVariant(sliderWidth: 56, showExtras: false)
        }
        .padding(.horizontal, DesignTokens.Space.md)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func opacityVariant(sliderWidth: CGFloat, showExtras: Bool) -> some View {
        HStack(spacing: DesignTokens.Space.sm) {
            if showExtras {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Slider(
                value: $viewModel.opacity,
                in: OverlayControlsViewModel.range,
                step: OverlayControlsViewModel.nudgeStep
            )
            .controlSize(.small)
            .frame(width: sliderWidth)
            .tint(DesignTokens.accent)
            .animation(opacityAnimation, value: viewModel.opacity)
            .accessibilityLabel("Opacity")
            .accessibilityValue(viewModel.accessibilityOpacityValue)

            if showExtras {
                // Fixed width + monospaced digits so the toolbar never shifts as
                // the number goes 9% → 100%.
                Text("\(viewModel.opacityPercent)%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                    .contentTransition(.numericText())
                    .animation(opacityAnimation, value: viewModel.opacity)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - SizeSettingsForm

/// The gear popover: type an exact width/height, apply, or reset back to the
/// image's natural fit. Purely a view over `OverlayControlsViewModel` intents.
private struct SizeSettingsForm: View {
    @ObservedObject var viewModel: OverlayControlsViewModel
    @Binding var isPresented: Bool

    @State private var widthText = ""
    @State private var heightText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.md) {
            Text("Custom Size")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: DesignTokens.Space.sm, verticalSpacing: DesignTokens.Space.sm) {
                GridRow {
                    Text("Width").foregroundStyle(.secondary)
                    numberField("Width", text: $widthText)
                }
                GridRow {
                    Text("Height").foregroundStyle(.secondary)
                    numberField("Height", text: $heightText)
                }
            }

            Text("Tip: you can also drag the window edges.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack {
                Button("Reset to Fit") {
                    viewModel.resetSize()
                    isPresented = false
                }
                Spacer()
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Space.lg)
        .frame(width: 230)
        .onAppear {
            widthText = String(Int(viewModel.contentSize.width.rounded()))
            heightText = String(Int(viewModel.contentSize.height.rounded()))
        }
    }

    private func numberField(_ label: String, text: Binding<String>) -> some View {
        TextField("px", text: text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 90)
            .multilineTextAlignment(.trailing)
            .onSubmit(apply)
            .accessibilityLabel(label)
    }

    private func apply() {
        guard let w = Double(widthText), let h = Double(heightText) else { return }
        viewModel.applyCustomSize(width: CGFloat(w), height: CGFloat(h))
        isPresented = false
    }
}
