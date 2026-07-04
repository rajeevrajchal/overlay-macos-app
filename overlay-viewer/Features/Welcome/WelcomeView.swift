import SwiftUI
import UniformTypeIdentifiers

/// The redesigned empty state. Three *co-equal* ways in — drag, browse, Figma —
/// each its own card with the same visual weight, instead of one giant CTA with
/// the alternatives buried under a divider. Pure presentation: every decision
/// and side effect is delegated to `WelcomeViewModel`.
struct WelcomeView: View {

    @ObservedObject var viewModel: WelcomeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDropTargeted = false
    @FocusState private var figmaFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
        }
        .background(Color.clear)
        // Titled + full-size-content window: don't let SwiftUI add its own
        // titlebar safe-area inset on top of our explicit 36pt `titleBar`
        // spacer (which already reserves room for the traffic lights).
        .ignoresSafeArea()
    }

    // MARK: Title bar

    /// Reserves the top strip for the window's native traffic lights (drawn by
    /// the system over the full-size content view). The real red close button
    /// replaces the old hand-drawn "X".
    private var titleBar: some View {
        Color.clear
            .frame(height: 36)
            .accessibilityHidden(true)
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Space.lg) {
                header
                dragCard
                browseCard
                if viewModel.isFigmaConfigured {
                    figmaCard
                }
                if let message = viewModel.errorMessage {
                    errorBanner(message)
                }
            }
            .padding(.horizontal, DesignTokens.Space.xl)
            .padding(.bottom, DesignTokens.Space.xl)
        }
    }

    // MARK: Header — three-level typographic hierarchy

    private var header: some View {
        VStack(spacing: DesignTokens.Space.sm) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text("Add a reference")
                .font(.title3.weight(.semibold))          // headline
                .foregroundStyle(.primary)

            Text("Overlay any image on your screen to compare it pixel-by-pixel.")
                .font(.callout)                             // supporting
                .foregroundStyle(.secondary)                // secondary color
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DesignTokens.Space.sm)
        .accessibilityElement(children: .combine)
    }

    // MARK: Entry point 1 — drag & drop

    private var dragCard: some View {
        VStack(spacing: DesignTokens.Space.xs) {
            Image(systemName: "square.and.arrow.down")
                .font(.title2)
                .foregroundStyle(isDropTargeted ? DesignTokens.accent : .secondary)
            Text("Drag an image here")
                .font(.callout.weight(.medium))
            Text("or click to browse — PNG, JPG, any image")
                .font(.caption)                             // tertiary hint
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Space.lg)
        .background(cardBackground(active: isDropTargeted, dashed: true))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.requestBrowse() }
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { NSImage(contentsOf: $0) != nil }) else { return false }
            viewModel.handleDroppedFile(url)
            return true
        } isTargeted: { targeted in
            if reduceMotion {
                isDropTargeted = targeted
            } else {
                withAnimation(.easeOut(duration: 0.15)) { isDropTargeted = targeted }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drag an image here, or click to browse")
        .accessibilityHint("Opens a file picker to choose an image")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Entry point 2 — browse

    private var browseCard: some View {
        Button(action: viewModel.requestBrowse) {
            HStack(spacing: DesignTokens.Space.sm) {
                Image(systemName: "folder")
                Text("Browse Files…")
                    .font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Space.md)
            .foregroundStyle(.white)
            .background(DesignTokens.accentGradient)       // accent: primary action
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse files")
        .accessibilityHint("Opens a file picker to choose an image")
    }

    // MARK: Entry point 3 — Figma

    private var figmaCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.md) {
            connectionRow

            switch viewModel.connection {
            case .connected:
                figmaURLRow
            case .connecting:
                EmptyView()
            case .disconnected, .failed:
                connectButton
            }
        }
        .padding(DesignTokens.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(active: false, dashed: false))
    }

    private var connectionRow: some View {
        HStack(spacing: DesignTokens.Space.sm) {
            Image(systemName: "hand.draw")
                .foregroundStyle(.secondary)
            Text("Figma")
                .font(.callout.weight(.semibold))
            Spacer()
            // State via icon + text, never color alone.
            Label {
                Text(viewModel.connection.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                stateIcon
            }
            .labelStyle(.titleAndIcon)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Figma. \(viewModel.connection.label)")
    }

    @ViewBuilder
    private var stateIcon: some View {
        if viewModel.connection.isConnecting {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: viewModel.connection.symbolName)
                .foregroundStyle(viewModel.connection.isConnected ? DesignTokens.accent : .secondary)
        }
    }

    private var connectButton: some View {
        Button(action: viewModel.connect) {
            Text("Connect Figma")
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Space.sm)
        }
        .controlSize(.large)
        .accessibilityLabel("Connect Figma account")
    }

    private var figmaURLRow: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.sm) {
            HStack(spacing: DesignTokens.Space.sm) {
                TextField("https://figma.com/design/…", text: $viewModel.figmaURLText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($figmaFieldFocused)
                    .onSubmit(viewModel.openFigmaURL)
                    .accessibilityLabel("Figma file URL")

                Button(action: viewModel.openFigmaURL) {
                    if viewModel.isFetchingImage {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Open")
                    }
                }
                .disabled(viewModel.isFetchingImage)
                .accessibilityLabel("Open Figma URL")
            }

            Button("Disconnect", action: viewModel.disconnect)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Disconnect Figma")
        }
    }

    // MARK: Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Shared card chrome

    private func cardBackground(active: Bool, dashed: Bool) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
            .fill(DesignTokens.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .strokeBorder(
                        active ? DesignTokens.accent : DesignTokens.cardStroke,
                        style: StrokeStyle(lineWidth: active ? 1.5 : 1,
                                           dash: dashed ? [5, 4] : [])
                    )
            )
    }
}
